#!/usr/bin/env python3
"""Wax OTA upload endpoint. Stdlib only.

Accepts an IPA and a manifest from the Wax app and stores them under an unguessable id; a static file server
(Caddy) serves them back to iOS for `itms-services://`. Files are short-lived.

    PUT    /u/<id>/app.ipa | /u/<id>/manifest.plist   (Authorization: Bearer <token>)  -> 201
           app.ipa may carry X-Wax-SHA256; the body must match it (else 400) and is then findable by hash
    GET    /has/<sha256>                              -> 200 {"id": ...} if that IPA is stored, else 404
    DELETE /u/<id>                                                                      -> 200

Never logs tokens or ids. Listens on loopback only; put it behind Caddy.
"""
import hashlib, hmac, json, os, re, shutil, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ID_RE = re.compile(r"^[A-Za-z0-9_-]{22,64}$")
NAMES = {"app.ipa", "manifest.plist"}
CHUNK = 1 << 20
LOCK_AFTER = 5            # wrong tokens from one address before it is locked out
LOCK_SECS = 15 * 60
now = time.monotonic      # tests move this clock
SHA_RE = re.compile(r"^[0-9a-f]{64}$")


def dir_size(root):
    total = 0
    for base, _, files in os.walk(root):
        for f in files:
            try: total += os.path.getsize(os.path.join(base, f))
            except OSError: pass
    return total


def gc(root, ttl):
    now = time.time()
    for name in os.listdir(root):
        p = os.path.join(root, name)
        try:
            if os.path.isdir(p) and now - os.path.getmtime(p) > ttl:
                shutil.rmtree(p, ignore_errors=True)
        except OSError:
            pass


def find_by_hash(root, sha):
    """Id of a stored IPA whose verified hash is `sha`, or None."""
    for name in os.listdir(root):
        d = os.path.join(root, name)
        try:
            if ID_RE.match(name) and os.path.isfile(os.path.join(d, "app.ipa")):
                with open(os.path.join(d, ".sha256")) as f:
                    if f.read() == sha:
                        return name
        except OSError:
            pass
    return None


def make_server(addr, root, token, max_bytes, max_total, ttl):
    quota_lock = threading.Lock()
    guard_lock = threading.Lock()
    fails = {}      # address -> wrong tokens since the last good one
    locked = {}     # address -> when the lock ends
    reserved = [0]   # bytes promised to uploads still in flight
    os.makedirs(root, exist_ok=True)

    class H(BaseHTTPRequestHandler):
        server_version = "wax-ota"
        def log_message(self, *a): pass                     # no access log: paths contain the secret id

        def _send(self, code, obj=None):
            body = json.dumps(obj or {"ok": code < 400}).encode()
            try:
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Connection", "close")
                self.end_headers(); self.wfile.write(body)
            except OSError:
                pass  # The client may disconnect while an upload is in progress.

        def _client(self):
            # Behind Caddy every connection comes from loopback; Caddy sets X-Forwarded-For to the real address
            # (replacing anything the caller sent), so the last entry is the one to trust.
            fwd = self.headers.get("X-Forwarded-For", "").split(",")[-1].strip()
            return fwd or self.client_address[0]

        def _authed(self):
            """True when the token is right. Otherwise answers 401, or 429 for an address locked out by wrong tokens."""
            who = self._client(); t = now()
            with guard_lock:
                if locked.get(who, 0) > t:
                    self._send(429, {"error": "too many wrong tokens"}); return False
                got = self.headers.get("Authorization", "")
                if hmac.compare_digest(got.encode(), ("Bearer " + token).encode()):
                    fails.pop(who, None); return True
                fails[who] = fails.get(who, 0) + 1
                if fails[who] >= LOCK_AFTER:
                    locked[who] = t + LOCK_SECS; fails.pop(who, None)
                if len(fails) > 10000: fails.clear()      # bounded memory under a spray of addresses
                if len(locked) > 10000:
                    for k in [k for k, v in locked.items() if v <= t]: del locked[k]
            self._send(401, {"error": "unauthorized"}); return False

        def _parts(self):
            return self.path.split("?")[0].strip("/").split("/")

        def do_GET(self):
            # Lets Wax check its token (and that this service is behind the proxy) before it signs anything.
            if not self._authed(): return
            p = self._parts()
            if len(p) == 2 and p[0] == "has" and SHA_RE.match(p[1]):
                found = find_by_hash(root, p[1])
                return self._send(200, {"id": found}) if found else self._send(404, {"error": "not found"})
            if p != ["health"]: return self._send(404, {"error": "not found"})
            self.send_response(204); self.send_header("Content-Length", "0"); self.send_header("Connection", "close")
            self.end_headers()

        def do_PUT(self):
            if not self._authed(): return
            p = self._parts()
            if len(p) != 3 or p[0] != "u" or not ID_RE.match(p[1]) or p[2] not in NAMES:
                return self._send(400, {"error": "bad path"})
            try: n = int(self.headers.get("Content-Length", ""))
            except ValueError: return self._send(411, {"error": "length required"})
            if n < 0 or n > max_bytes: return self._send(413, {"error": "too large"})
            want = self.headers.get("X-Wax-SHA256", "").lower() if p[2] == "app.ipa" else ""
            if want and not SHA_RE.match(want): return self._send(400, {"error": "bad hash"})
            self.connection.settimeout(60)   # idle cap per read
            reservation = [n]
            with quota_lock:                 # lock covers only the accounting, never the body read
                gc(root, ttl)
                if dir_size(root) + reserved[0] + n > max_total: return self._send(507, {"error": "server full"})
                reserved[0] += n
            try: return self._store(p, n, want, reservation)
            finally:
                with quota_lock: reserved[0] -= reservation[0]

        def _store(self, p, n, want, reservation):
            deadline = time.monotonic() + 600 + n / 50_000   # total cap: a trickling client cannot hold quota forever
            d = os.path.join(root, p[1]); os.makedirs(d, exist_ok=True); os.chmod(d, 0o755)
            tmp = os.path.join(d, "." + p[2] + ".part")
            got = 0
            digest = hashlib.sha256()
            touched = time.monotonic()
            try:
                with open(tmp, "wb") as f:
                    while got < n:
                        b = self.rfile.read(min(CHUNK, n - got))
                        if not b or time.monotonic() > deadline: break
                        f.write(b); digest.update(b); got += len(b)
                        with quota_lock:
                            reservation[0] -= len(b); reserved[0] -= len(b)
                        if time.monotonic() - touched > 30:   # a slow upload is alive: keep gc() from sweeping its folder
                            os.utime(d); touched = time.monotonic()
                if got != n:
                    os.unlink(tmp); return self._send(400, {"error": "short body"})
                if want and digest.hexdigest() != want:
                    os.unlink(tmp); return self._send(400, {"error": "hash mismatch"})
                if p[2] == "app.ipa":
                    try: os.unlink(os.path.join(d, ".sha256"))   # a replaced IPA must not keep its old hash
                    except OSError: pass
                os.chmod(tmp, 0o644); os.replace(tmp, os.path.join(d, p[2]))
                if want:
                    with open(os.path.join(d, ".sha256"), "w") as h: h.write(want)
            except OSError:
                try: os.unlink(tmp)
                except OSError: pass
                return self._send(500, {"error": "write failed"})
            self._send(201)

        def do_DELETE(self):
            if not self._authed(): return
            p = self._parts()
            if len(p) != 2 or p[0] != "u" or not ID_RE.match(p[1]): return self._send(400, {"error": "bad path"})
            shutil.rmtree(os.path.join(root, p[1]), ignore_errors=True)
            self._send(200)

    srv = ThreadingHTTPServer(addr, H)
    srv.daemon_threads = True
    return srv


def settings_from_env(env):
    """Reads and checks every setting; exits with a clear message on nonsense so a typo cannot silently
    delete in-flight uploads (TTL 0) or accept everything (quota 0)."""
    def number(name, default, minimum):
        raw = env.get(name, str(default))
        try: value = int(raw)
        except ValueError: sys.exit(f"{name} must be a whole number, got {raw!r}")
        if value < minimum: sys.exit(f"{name} must be at least {minimum}, got {value}")
        return value
    token = env.get("WAX_OTA_TOKEN", "")
    if len(token) < 32: sys.exit("WAX_OTA_TOKEN must be set (32+ chars)")
    return {
        "token": token,
        "root": env.get("WAX_OTA_ROOT", "/var/www/signed-www/ota"),
        "ttl": number("WAX_OTA_TTL", 21600, 60),          # 6 hours: long enough to tap "Ready to install" later
        "port": number("WAX_OTA_PORT", 8091, 1),
        "max_bytes": number("WAX_OTA_MAX_BYTES", 2 << 30, 1),
        "max_total": number("WAX_OTA_MAX_TOTAL", 6 << 30, 1),
    }


def main():
    cfg = settings_from_env(os.environ)
    srv = make_server(("127.0.0.1", cfg["port"]), cfg["root"], cfg["token"], cfg["max_bytes"], cfg["max_total"], cfg["ttl"])
    def sweeper():
        while True:
            time.sleep(60); gc(cfg["root"], cfg["ttl"])
    threading.Thread(target=sweeper, daemon=True).start()
    srv.serve_forever()


if __name__ == "__main__":
    main()
