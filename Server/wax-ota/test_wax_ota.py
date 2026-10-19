"""Run: python3 -m unittest -v Server/wax-ota/test_wax_ota.py (no network, no VM)."""
import http.client, json, os, shutil, socket, sys, tempfile, threading, time, unittest
sys.path.insert(0, os.path.dirname(__file__))
import wax_ota

TOKEN = "t" * 40
ID = "A" * 22

class Base(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.srv = wax_ota.make_server(("127.0.0.1", 0), self.root, TOKEN, max_bytes=1000, max_total=2500, ttl=60)
        self.port = self.srv.server_address[1]
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
    def tearDown(self):
        self.srv.shutdown(); self.srv.server_close(); shutil.rmtree(self.root, ignore_errors=True)
    def req(self, method, path, body=None, token=TOKEN, headers=None):
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        h = dict(headers or {})
        if token is not None: h["Authorization"] = "Bearer " + token
        c.request(method, path, body=body, headers=h)
        r = c.getresponse(); data = r.read(); c.close()
        return r.status, data

class Auth(Base):
    def test_missing_or_wrong_token_is_401_and_nothing_is_written(self):
        self.assertEqual(self.req("PUT", f"/u/{ID}/app.ipa", b"x", token=None)[0], 401)
        self.assertEqual(self.req("PUT", f"/u/{ID}/app.ipa", b"x", token="wrong")[0], 401)
        self.assertEqual(os.listdir(self.root), [])

class InFlight(Base):
    def _stall(self, id_, declared, sent):
        import socket
        c = socket.create_connection(("127.0.0.1", self.port), timeout=5)
        c.sendall((f"PUT /u/{id_}/app.ipa HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer {TOKEN}\r\n"
                   f"Content-Length: {declared}\r\n\r\n").encode() + b"x" * sent)
        time.sleep(0.3)
        return c
    def test_a_stalled_upload_does_not_block_another(self):
        c = self._stall("B" * 22, 900, 10)
        try: self.assertEqual(self.req("PUT", f"/u/{ID}/app.ipa", b"hello")[0], 201)
        finally: c.close()
    def test_bytes_promised_to_in_flight_uploads_count_against_the_quota(self):
        a = self._stall("B" * 22, 1000, 10); b = self._stall("C" * 22, 1000, 10)
        try: self.assertEqual(self.req("PUT", f"/u/{ID}/app.ipa", b"x" * 1000)[0], 507)  # 2500 total, 2000 promised
        finally: a.close(); b.close()
    def test_partial_upload_bytes_are_not_counted_twice_against_the_quota(self):
        a = self._stall("B" * 22, 1000, 10); b = self._stall("C" * 22, 1000, 10)
        try: self.assertEqual(self.req("PUT", f"/u/{ID}/app.ipa", b"x" * 500)[0], 201)  # 20 written + 1980 reserved + 500
        finally: a.close(); b.close()

class Upload(Base):
    def test_put_stores_file_atomically(self):
        s, _ = self.req("PUT", f"/u/{ID}/app.ipa", b"hello")
        self.assertEqual(s, 201)
        with open(os.path.join(self.root, ID, "app.ipa"), "rb") as f: self.assertEqual(f.read(), b"hello")
        self.assertEqual(sorted(os.listdir(os.path.join(self.root, ID))), ["app.ipa"])  # no temp leftovers
    def test_both_allowed_names(self):
        for n in ("app.ipa", "manifest.plist"):
            self.assertEqual(self.req("PUT", f"/u/{ID}/{n}", b"x")[0], 201)
    def test_bad_ids_and_names_rejected(self):
        for p in ["/u/short/app.ipa", f"/u/{ID}/evil.sh", f"/u/{ID}/../app.ipa", "/u/../../etc/passwd/app.ipa",
                  f"/u/{ID}/app.ipa/x", "/x", "/u//app.ipa", f"/u/{'a/b'*8}/app.ipa"]:
            self.assertIn(self.req("PUT", p, b"x")[0], (400, 404), p)
        self.assertEqual(os.listdir(self.root), [])
    def test_too_large_is_413_and_not_stored(self):
        self.assertEqual(self.req("PUT", f"/u/{ID}/app.ipa", b"x" * 1001)[0], 413)
        self.assertEqual(os.listdir(self.root), [])
    def test_total_quota_is_507(self):
        for i, c in enumerate("BCD"):
            self.assertEqual(self.req("PUT", f"/u/{c*22}/app.ipa", b"y" * 900)[0], 201 if i < 2 else 507)
    def test_get_is_not_served_here(self):
        self.req("PUT", f"/u/{ID}/app.ipa", b"x")
        self.assertIn(self.req("GET", f"/u/{ID}/app.ipa")[0], (404, 405))

import hashlib
HASH = hashlib.sha256(b"hello").hexdigest()

class HashSkip(Base):
    def put_hashed(self, id_=ID, body=b"hello", digest=HASH):
        return self.req("PUT", f"/u/{id_}/app.ipa", body, headers={"X-Wax-SHA256": digest})
    def test_has_returns_the_id_of_a_stored_ipa(self):
        self.assertEqual(self.put_hashed()[0], 201)
        s, data = self.req("GET", f"/has/{HASH}")
        self.assertEqual((s, json.loads(data)), (200, {"id": ID}))
    def test_has_404_for_unknown_hash(self):
        self.assertEqual(self.req("GET", f"/has/{'0'*64}")[0], 404)
        self.assertEqual(self.req("GET", "/has/not-a-hash")[0], 404)
    def test_has_needs_token(self):
        self.put_hashed()
        self.assertEqual(self.req("GET", f"/has/{HASH}", token=None)[0], 401)
    def test_wrong_hash_header_is_rejected_400(self):
        self.assertEqual(self.put_hashed(digest="0" * 64)[0], 400)
        self.assertEqual(os.listdir(os.path.join(self.root, ID)), [])   # nothing stored, no leftovers
        self.assertEqual(self.req("GET", f"/has/{'0'*64}")[0], 404)
    def test_a_malformed_hash_header_does_not_leak_quota(self):
        for _ in range(3):   # 3 x 1000 would exceed max_total=2500 if each refusal kept its reservation
            self.assertEqual(self.req("PUT", f"/u/{ID}/app.ipa", b"x" * 1000, headers={"X-Wax-SHA256": "nothex"})[0], 400)
        self.assertEqual(self.req("PUT", f"/u/{ID}/app.ipa", b"x" * 1000)[0], 201)
    def test_an_upload_without_the_header_is_not_findable(self):
        self.req("PUT", f"/u/{ID}/app.ipa", b"hello")
        self.assertEqual(self.req("GET", f"/has/{HASH}")[0], 404)
    def test_replacing_the_ipa_without_a_hash_forgets_the_old_hash(self):
        self.put_hashed(); self.req("PUT", f"/u/{ID}/app.ipa", b"other")
        self.assertEqual(self.req("GET", f"/has/{HASH}")[0], 404)
    def test_deleted_or_expired_sessions_are_not_found(self):
        self.put_hashed(); self.req("DELETE", f"/u/{ID}")
        self.assertEqual(self.req("GET", f"/has/{HASH}")[0], 404)


class Cleanup(Base):
    def test_delete_removes_directory(self):
        self.req("PUT", f"/u/{ID}/app.ipa", b"x")
        self.assertEqual(self.req("DELETE", f"/u/{ID}")[0], 200)
        self.assertFalse(os.path.exists(os.path.join(self.root, ID)))
    def test_gc_removes_only_expired(self):
        self.req("PUT", f"/u/{ID}/app.ipa", b"x"); self.req("PUT", f"/u/{'E'*22}/app.ipa", b"x")
        old = time.time() - 120
        os.utime(os.path.join(self.root, ID), (old, old))
        wax_ota.gc(self.root, ttl=60)
        self.assertEqual(os.listdir(self.root), ["E" * 22])


class Health(Base):
    def test_health_requires_the_token(self):
        self.assertEqual(self.req("GET", "/health", token=None)[0], 401)
        self.assertEqual(self.req("GET", "/health", token="wrong")[0], 401)
        self.assertEqual(self.req("GET", "/health")[0], 204)

    def test_health_writes_nothing(self):
        self.req("GET", "/health"); self.assertEqual(os.listdir(self.root), [])


class ClientIdentity(unittest.TestCase):
    """Unit stubs for the identity decision; no network."""

    @staticmethod
    def fake(peer, headers):
        import email.message
        h = email.message.Message()
        for k, v in (headers or {}).items(): h[k] = v
        return wax_ota.client_identity(peer, h)

    def test_forged_header_from_a_direct_peer_is_ignored(self):
        self.assertEqual(self.fake("203.0.113.7", {"X-Forwarded-For": "1.2.3.4"}), "203.0.113.7")
        self.assertEqual(self.fake("203.0.113.7", {"X-Forwarded-For": "wax.example"}), "203.0.113.7")

    def test_no_header_from_a_direct_peer_uses_the_connection(self):
        self.assertEqual(self.fake("203.0.113.7", None), "203.0.113.7")

    def test_header_from_a_loopback_peer_is_trusted_last_entry(self):
        self.assertEqual(self.fake("127.0.0.1", {"X-Forwarded-For": "203.0.113.9, 203.0.113.8"}), "203.0.113.8")
        self.assertEqual(self.fake("::1", {"X-Forwarded-For": "203.0.113.8"}), "203.0.113.8")

    def test_empty_or_blank_header_from_a_loopback_peer_falls_back_to_the_peer(self):
        self.assertEqual(self.fake("127.0.0.1", {"X-Forwarded-For": " , ,"}), "127.0.0.1")
        self.assertEqual(self.fake("127.0.0.1", None), "127.0.0.1")


class ThrottleDirectPeer(unittest.TestCase):
    """The lockout keys on the connection, not a claim: a direct (non-loopback) peer with a forged
    X-Forwarded-For can neither share nor steal identities. Skips visibly when the machine has no
    routable non-loopback address to bind on."""

    def setUp(self):
        self.ip = self._direct_ip()
        if self.ip is None: self.skipTest("no non-loopback address to connect from")

    @staticmethod
    def _direct_ip():
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.connect(("8.8.8.8", 53))
            ip = s.getsockname()[0]; s.close()
            return None if ip.startswith("127.") else ip
        except OSError:
            return None

    def test_a_forged_forwarded_header_does_not_own_or_exploit_lockout(self):
        root = tempfile.mkdtemp()
        try:
            srv = wax_ota.make_server(("", 0), root, TOKEN, max_bytes=1000, max_total=2500, ttl=60)
            port = srv.server_address[1]
            threading.Thread(target=srv.serve_forever, daemon=True).start()
            def req(headers):
                c = http.client.HTTPConnection(self.ip, port, timeout=5)
                h = dict(headers); h["Authorization"] = "Bearer wrong"
                c.request("GET", "/health", headers=h)
                r = c.getresponse(); r.read(); c.close()
                return r.status
            for _ in range(5): self.assertEqual(req({"X-Forwarded-For": "203.0.113.77"}), 401)
            # Old behaviour keyed every forged claim on the header, so the peer itself never accumulated
            # five; the next two answers must be a lock keyed on the peer. Each request still sends a
            # different forged identity to show none of them created a counter of their own.
            self.assertEqual(req({"X-Forwarded-For": "198.51.100.2"}), 429)
            self.assertEqual(req({}), 429)
        finally:
            srv.shutdown(); srv.server_close(); shutil.rmtree(root, ignore_errors=True)


class Throttle(Base):
    def bad(self, n):
        return [self.req("GET", "/health", token="wrong")[0] for _ in range(n)]
    def test_five_bad_tokens_lock_the_ip_for_fifteen_minutes(self):
        self.assertEqual(self.bad(5), [401] * 5)
        self.assertEqual(self.req("GET", "/health")[0], 429)               # even the right token is refused now
        self.assertEqual(self.req("PUT", f"/u/{ID}/app.ipa", b"x")[0], 429)
        self.assertEqual(os.listdir(self.root), [])
    def test_lock_expires(self):
        self.bad(5)
        real = wax_ota.now
        wax_ota.now = lambda: real() + 15 * 60 + 1
        try: self.assertEqual(self.req("GET", "/health")[0], 204)
        finally: wax_ota.now = real
    def test_good_token_does_not_count(self):
        for _ in range(20): self.assertEqual(self.req("GET", "/health")[0], 204)
    def test_four_bad_then_a_good_one_resets_the_count(self):
        self.bad(4); self.assertEqual(self.req("GET", "/health")[0], 204)
        self.assertEqual(self.bad(4), [401] * 4)
    def test_the_proxy_header_names_the_client_so_one_attacker_does_not_lock_everyone(self):
        for _ in range(5): self.req("GET", "/health", token="wrong", headers={"X-Forwarded-For": "203.0.113.9"})
        self.assertEqual(self.req("GET", "/health", headers={"X-Forwarded-For": "203.0.113.9"})[0], 429)
        self.assertEqual(self.req("GET", "/health", headers={"X-Forwarded-For": "198.51.100.1"})[0], 204)


class Settings(unittest.TestCase):
    ENV = {"WAX_OTA_TOKEN": "t" * 40}

    def test_default_ttl_is_six_hours(self):
        self.assertEqual(wax_ota.settings_from_env(self.ENV)["ttl"], 21600)

    def test_ttl_below_a_minute_is_refused(self):
        for bad in ("0", "59", "-5", "abc"):
            with self.assertRaises(SystemExit): wax_ota.settings_from_env({**self.ENV, "WAX_OTA_TTL": bad})

    def test_non_positive_quotas_are_refused(self):
        with self.assertRaises(SystemExit): wax_ota.settings_from_env({**self.ENV, "WAX_OTA_MAX_BYTES": "0"})
        with self.assertRaises(SystemExit): wax_ota.settings_from_env({**self.ENV, "WAX_OTA_MAX_TOTAL": "-1"})

    def test_short_token_is_refused(self):
        with self.assertRaises(SystemExit): wax_ota.settings_from_env({"WAX_OTA_TOKEN": "short"})


class Gc(unittest.TestCase):
    def folder_aged(self, root, name, hours):
        p = os.path.join(root, name); os.makedirs(p)
        t = time.time() - hours * 3600; os.utime(p, (t, t)); return p

    def test_gc_keeps_a_five_hour_old_folder_and_removes_a_seven_hour_old_one(self):
        root = tempfile.mkdtemp()
        try:
            keep = self.folder_aged(root, "keep", 5); gone = self.folder_aged(root, "gone", 7)
            wax_ota.gc(root, 21600)
            self.assertTrue(os.path.isdir(keep)); self.assertFalse(os.path.exists(gone))
        finally: shutil.rmtree(root, ignore_errors=True)


class SessionTransactions(Base):
    def pause(self, session=ID):
        entered, release = threading.Event(), threading.Event()
        original = self.srv.RequestHandlerClass._store
        def paused(handler, parts, *args):
            if parts[1] == session:
                entered.set()
                if not release.wait(5): raise AssertionError("test request was not released")
            return original(handler, parts, *args)
        self.srv.RequestHandlerClass._store = paused
        return entered, release

    def open_body(self, session=ID, body=b"new", declared=None):
        conn = socket.create_connection(("127.0.0.1", self.port), timeout=5)
        conn.sendall((f"PUT /u/{session}/app.ipa HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer {TOKEN}\r\n"
                      f"Content-Length: {len(body) if declared is None else declared}\r\n\r\n").encode() + body)
        return conn

    def finish(self, conn):
        response = http.client.HTTPResponse(conn); response.begin()
        status = response.status; response.read(); conn.close(); return status

    def test_overlapping_same_session_put_manifest_and_delete_are_conflicts(self):
        entered, release = self.pause()
        conn = self.open_body(body=b"first")
        try:
            self.assertTrue(entered.wait(3))
            for name in ("app.ipa", "manifest.plist"):
                self.assertEqual(self.req("PUT", f"/u/{ID}/{name}", b"second")[0], 409)
            self.assertEqual(self.req("DELETE", f"/u/{ID}")[0], 409)
            release.set(); self.assertEqual(self.finish(conn), 201)
            with open(os.path.join(self.root, ID, "app.ipa"), "rb") as f: self.assertEqual(f.read(), b"first")
        finally: release.set(); conn.close()

    def test_other_sessions_continue_and_gc_cannot_remove_active_session(self):
        self.assertEqual(self.req("PUT", f"/u/{ID}/app.ipa", b"old")[0], 201)
        entered, release = self.pause(); conn = self.open_body()
        try:
            self.assertTrue(entered.wait(3))
            old = time.time() - 120; os.utime(os.path.join(self.root, ID), (old, old))
            self.srv.collect(); self.assertTrue(os.path.isfile(os.path.join(self.root, ID, "app.ipa")))
            self.assertEqual(self.req("PUT", f"/u/{'Z'*22}/app.ipa", b"other")[0], 201)
            release.set(); self.assertEqual(self.finish(conn), 201)
        finally: release.set(); conn.close()

    def test_aborted_replacement_and_hash_failure_preserve_existing_file(self):
        self.assertEqual(self.req("PUT", f"/u/{ID}/app.ipa", b"old")[0], 201)
        conn = self.open_body(body=b"partial", declared=100)
        conn.shutdown(socket.SHUT_WR)
        self.assertEqual(self.finish(conn), 400)
        self.assertEqual(self.req("PUT", f"/u/{ID}/app.ipa", b"bad", headers={"X-Wax-SHA256": "0"*64})[0], 400)
        with open(os.path.join(self.root, ID, "app.ipa"), "rb") as f: self.assertEqual(f.read(), b"old")
        self.assertEqual(os.listdir(os.path.join(self.root, ID)), ["app.ipa"])

    def test_publication_failure_preserves_file_and_hash(self):
        from unittest.mock import patch
        self.assertEqual(self.req("PUT", f"/u/{ID}/app.ipa", b"hello", headers={"X-Wax-SHA256": HASH})[0], 201)
        replace = os.replace
        def fail(source, destination):
            if destination.endswith("app.ipa"): raise OSError("injected publication failure")
            return replace(source, destination)
        with patch.object(wax_ota.os, 'replace', side_effect=fail):
            self.assertEqual(self.req("PUT", f"/u/{ID}/app.ipa", b"new")[0], 500)
        with open(os.path.join(self.root, ID, "app.ipa"), "rb") as f: self.assertEqual(f.read(), b"hello")
        self.assertEqual(self.req("GET", f"/has/{HASH}")[0], 200)

    def test_cache_publication_failure_is_a_real_upload_but_never_false_hash_hit(self):
        from unittest.mock import patch
        self.req("PUT", f"/u/{ID}/app.ipa", b"hello", headers={"X-Wax-SHA256": HASH})
        replace = os.replace
        def fail(source, destination):
            if destination.endswith(".sha256"): raise OSError("injected cache write failure")
            return replace(source, destination)
        new = b"new"; sha = hashlib.sha256(new).hexdigest()
        with patch.object(wax_ota.os, 'replace', side_effect=fail):
            status, data = self.req("PUT", f"/u/{ID}/app.ipa", new, headers={"X-Wax-SHA256": sha})
        self.assertEqual(status, 201); self.assertIn("warning", json.loads(data))
        self.assertEqual(self.req("GET", f"/has/{HASH}")[0], 404)
        self.assertEqual(self.req("GET", f"/has/{sha}")[0], 404)
        with open(os.path.join(self.root, ID, "app.ipa"), "rb") as f: self.assertEqual(f.read(), new)

    def test_failed_cleanup_is_hidden_counted_and_collectable(self):
        from unittest.mock import patch
        unlink = os.unlink
        def fail(path, *args, **kw):
            if str(path).endswith('.part'): raise OSError("injected cleanup failure")
            return unlink(path, *args, **kw)
        with patch.object(wax_ota.os, 'unlink', side_effect=fail):
            self.assertEqual(self.req("PUT", f"/u/{ID}/app.ipa", b"bad", headers={"X-Wax-SHA256": "0"*64})[0], 400)
        self.assertGreater(wax_ota.dir_size(self.root), 0)
        self.assertTrue(all(n.startswith('.') and n.endswith('.part') for n in os.listdir(os.path.join(self.root, ID))))
        old = time.time() - 120; os.utime(os.path.join(self.root, ID), (old, old)); self.srv.collect()
        self.assertFalse(os.path.exists(os.path.join(self.root, ID)))

    def test_symlinked_session_does_not_write_outside_root(self):
        outside = tempfile.mkdtemp()
        try:
            os.symlink(outside, os.path.join(self.root, ID))
            self.assertEqual(self.req("PUT", f"/u/{ID}/app.ipa", b"bad")[0], 400)
            self.assertEqual(os.listdir(outside), [])
        finally: shutil.rmtree(outside)

    def test_delete_cleanup_failure_is_not_false_success(self):
        from unittest.mock import patch
        self.req("PUT", f"/u/{ID}/app.ipa", b"old")
        with patch.object(wax_ota.shutil, 'rmtree', side_effect=OSError("injected delete failure")):
            self.assertEqual(self.req("DELETE", f"/u/{ID}")[0], 500)
        self.assertEqual(self.req("DELETE", f"/u/{ID}")[0], 200)



class HashIdentity(Base):
    def test_stat_metadata_is_not_accepted_as_content_identity(self):
        self.req("PUT", f"/u/{ID}/app.ipa", b"other")
        path = os.path.join(self.root, ID, "app.ipa"); info = os.stat(path)
        with open(os.path.join(self.root, ID, ".sha256"), "w") as cache:
            json.dump(dict(sha256=HASH, inode=info.st_ino, size=info.st_size, mtime_ns=info.st_mtime_ns),cache)
        self.assertEqual(self.req("GET", f"/has/{HASH}")[0],404)

    def test_hash_verification_owns_its_session_but_does_not_block_others(self):
        from unittest.mock import patch
        self.req("PUT", f"/u/{ID}/app.ipa", b"hello",headers={"X-Wax-SHA256":HASH})
        entered,release=threading.Event(),threading.Event();original=wax_ota.verified_file_hash
        def pause(path,limit):
            entered.set()
            if not release.wait(5): raise AssertionError("test did not release hash verification")
            return original(path,limit)
        answer=[]
        with patch.object(wax_ota,'verified_file_hash',side_effect=pause):
            request=threading.Thread(target=lambda:answer.append(self.req("GET",f"/has/{HASH}")[0]));request.start()
            try:
                self.assertTrue(entered.wait(3))
                self.assertEqual(self.req("DELETE",f"/u/{ID}")[0],409)
                self.assertEqual(self.req("PUT",f"/u/{ID}/app.ipa",b"replace")[0],409)
                self.assertEqual(self.req("PUT",f"/u/{'Z'*22}/app.ipa",b"other")[0],201)
            finally:release.set();request.join(5)
        self.assertEqual(answer,[200])

if __name__ == "__main__": unittest.main()
