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
import hashlib, hmac, json, os, re, shutil, sys, threading, time, tempfile
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


def gc(root, ttl, active=()):
    wall = time.time()
    for name in os.listdir(root):
        p = os.path.join(root, name)
        try:
            if name not in active and not os.path.islink(p) and os.path.isdir(p) and wall - os.path.getmtime(p) > ttl:
                shutil.rmtree(p, ignore_errors=True)
        except OSError:
            pass


def find_by_hash(root, sha, active=()):
    """Only a cache record bound to the current published inode may identify an IPA.

    A crash between the IPA and cache renames produces a cache miss, never a false hit.
    Old plain-text cache records are intentionally misses until that session is uploaded again.
    """
    for name in os.listdir(root):
        d = os.path.join(root, name)
        try:
            if name in active or not ID_RE.fullmatch(name) or os.path.islink(d): continue
            path = os.path.join(d, "app.ipa")
            if os.path.islink(path): continue
            stat = os.stat(path)
            with open(os.path.join(d, ".sha256")) as f:
                record = json.loads(f.read(1024))
            if record == {"sha256": sha, "inode": stat.st_ino, "size": stat.st_size, "mtime_ns": stat.st_mtime_ns}:
                return name
        except (OSError, ValueError):
            pass
    return None


def client_identity(peer, headers):
    """The identity a peer is throttled by.

    X-Forwarded-For is trusted only from a loopback peer: that is the shipped Caddyfile shape, a local
    reverse proxy which overwrites the header (see Caddyfile.example). No proxy, no claim: a direct
    peer is identified by the connection itself, so it cannot forge (un)lockable identities by hand.
    """
    if peer not in ("127.0.0.1", "::1", "::ffff:127.0.0.1"):
        return peer
    fwd = [p.strip() for p in (headers.get("X-Forwarded-For") or "").split(",") if p.strip()]
    return fwd[-1] if fwd else peer


def make_server(addr, root, token, max_bytes, max_total, ttl):
    quota_lock = threading.Lock()
    guard_lock = threading.Lock()
    fails = {}      # address -> wrong tokens since the last good one
    locked = {}     # address -> when the lock ends
    active = set()   # session IDs owned by a PUT or DELETE; guarded by quota_lock
    max_active = 16   # bounded body readers; overload is explicit, not an unbounded wait
    reserved = [0]   # bytes promised to uploads still in flight
    os.makedirs(root, exist_ok=True)

    class H(BaseHTTPRequestHandler):
        server_version = "wax-ota"
        def log_message(self, *a): pass                     # no access log: paths contain the secret id

        def setup(self):
            super().setup()
            self.connection.settimeout(30)   # bounded idle header read before body admission

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
            return client_identity(self.client_address[0], self.headers)

        def _authed(self):
            """True when the token is right. Otherwise answers 401, or 429 for an address locked out by wrong tokens."""
            who = self._client(); t = now()
            with guard_lock:
                if locked.get(who, 0) > t:
                    self._send(429, {"error": "too many wrong tokens"}); return False
                got = self.headers.get("Authorization", "")
                if hmac.compare_digest(got.encode(), ("Bearer " + token).encode()):
                    fails.pop(who, None); return True
                n = fails.pop(who, None)     # re-inserted so the map is touch-ordered
                fails[who] = (n or 0) + 1
                if fails[who] >= LOCK_AFTER:
                    locked[who] = t + LOCK_SECS; fails.pop(who, None)
                while len(fails) > 10000:    # bounded memory under a spray of addresses:
                    del fails[next(iter(fails))]   # evict the stalest counter, never the whole table
                if len(locked) > 10000:
                    for k in [k for k, v in locked.items() if v <= t]: del locked[k]
            self._send(401, {"error": "unauthorized"}); return False

        def _parts(self):
            return self.path.split("?")[0].strip("/").split("/")

        def do_GET(self):
            # Lets Wax check its token (and that this service is behind the proxy) before it signs anything.
            if not self._authed(): return
            p = self._parts()
            if len(p) == 2 and p[0] == "has" and SHA_RE.fullmatch(p[1]):
                with quota_lock: found = find_by_hash(root, p[1], active)
                return self._send(200, {"id": found}) if found else self._send(404, {"error": "not found"})
            if p != ["health"]: return self._send(404, {"error": "not found"})
            self.send_response(204); self.send_header("Content-Length", "0"); self.send_header("Connection", "close")
            self.end_headers()

        def do_PUT(self):
            if not self._authed(): return
            p = self._parts()
            if len(p) != 3 or p[0] != "u" or not ID_RE.fullmatch(p[1]) or p[2] not in NAMES:
                return self._send(400, {"error": "bad path"})
            if self.headers.get("Transfer-Encoding") or len(self.headers.get_all("Content-Length", [])) != 1:
                return self._send(400, {"error": "one Content-Length and no Transfer-Encoding required"})
            try: n = int(self.headers.get("Content-Length", ""))
            except ValueError: return self._send(411, {"error": "length required"})
            if n < 0 or n > max_bytes: return self._send(413, {"error": "too large"})
            want = self.headers.get("X-Wax-SHA256", "").lower() if p[2] == "app.ipa" else ""
            if want and not SHA_RE.fullmatch(want): return self._send(400, {"error": "bad hash"})
            reservation = [0]
            with quota_lock:
                if p[1] in active: return self._send(409, {"error": "session busy; retry after its current request completes"})
                if len(active) >= max_active: return self._send(503, {"error": "upload capacity busy; retry later"})
                gc(root, ttl, active | {p[1]})
                amount = n + (512 if want else 0)   # cache metadata plus the complete staged body
                if dir_size(root) + reserved[0] + amount > max_total: return self._send(507, {"error": "server full"})
                active.add(p[1]); reservation[0] = amount; reserved[0] += amount
            try: result = self._store(p, n, want, reservation)
            finally:
                with quota_lock:
                    reserved[0] -= reservation[0]; active.remove(p[1])
            return self._send(*result)

        def _store(self, p, n, want, reservation):
            deadline = time.monotonic() + 600 + n / 50_000
            d = os.path.join(root, p[1])
            tmp = cache_tmp = None
            published = False
            try:
                if os.path.islink(d): return 400, {"error": "unsafe session path"}
                os.makedirs(d, exist_ok=True); os.chmod(d, 0o755)
                target = os.path.join(d, p[2])
                if os.path.islink(target): return 400, {"error": "unsafe artifact path"}
                fd, tmp = tempfile.mkstemp(prefix="." + p[2] + ".", suffix=".part", dir=d)
                got = 0; digest = hashlib.sha256()
                with os.fdopen(fd, "wb") as f:
                    while got < n:
                        remaining = deadline - time.monotonic()
                        if remaining <= 0: break
                        self.connection.settimeout(min(60, remaining))
                        b = self.rfile.read1(min(CHUNK, n - got))
                        if not b: break
                        f.write(b); f.flush(); digest.update(b); got += len(b)
                        with quota_lock:
                            reservation[0] -= len(b); reserved[0] -= len(b)
                    f.flush(); os.fsync(f.fileno())
                if got != n: return 400, {"error": "short body; upload again"}
                if want and digest.hexdigest() != want: return 400, {"error": "hash mismatch; upload again"}
                os.chmod(tmp, 0o644)
                if want:
                    stat = os.stat(tmp)
                    record = {"sha256": want, "inode": stat.st_ino, "size": stat.st_size, "mtime_ns": stat.st_mtime_ns}
                    fd, cache_tmp = tempfile.mkstemp(prefix=".sha256.", suffix=".part", dir=d)
                    with os.fdopen(fd, "w") as cache:
                        json.dump(record, cache); cache.flush(); os.fsync(cache.fileno())
                # Only this rename publishes IPA bytes. Earlier failures leave the old artifact/cache intact.
                # Hash lookup and GC share this lock, and active sessions cannot be deleted or overlapped.
                with quota_lock:
                    os.replace(tmp, target); tmp = None; published = True
                    if p[2] == "app.ipa":
                        try:
                            if cache_tmp:
                                os.replace(cache_tmp, os.path.join(d, ".sha256")); cache_tmp = None
                            else: os.unlink(os.path.join(d, ".sha256"))
                        except OSError:
                            # The IPA commit already succeeded. A missing/stale inode-bound cache is safe:
                            # report a real upload success rather than a false failure after replacement.
                            return 201, {"ok": True, "warning": "uploaded; hash cache unavailable"}
                    os.utime(d)
                return 201, None
            except OSError:
                return (201 if published else 500), {"ok": published, "warning" if published else "error": "post-publication cleanup failed" if published else "write failed; previous artifact kept"}
            finally:
                for owned in (tmp, cache_tmp):
                    if owned:
                        try: os.unlink(owned)
                        except OSError: pass  # hidden, quota-counted orphan; GC retries after TTL

        def do_DELETE(self):
            if not self._authed(): return
            p = self._parts()
            if len(p) != 2 or p[0] != "u" or not ID_RE.fullmatch(p[1]): return self._send(400, {"error": "bad path"})
            with quota_lock:
                if p[1] in active: return self._send(409, {"error": "session busy; retry delete later"})
                active.add(p[1])
            try:
                path = os.path.join(root, p[1])
                if os.path.islink(path): result = 400, {"error": "unsafe session path"}
                else:
                    try: shutil.rmtree(path)
                    except FileNotFoundError: pass
                    result = 200, None
            except OSError: result = 500, {"error": "delete failed; retry cleanup"}
            finally:
                with quota_lock: active.remove(p[1])
            return self._send(*result)

    srv = ThreadingHTTPServer(addr, H)
    def collect():
        with quota_lock: gc(root, ttl, active)
    srv.collect = collect
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
            time.sleep(60); srv.collect()
    threading.Thread(target=sweeper, daemon=True).start()
    srv.serve_forever()


if __name__ == "__main__":
    main()
