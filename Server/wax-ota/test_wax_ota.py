"""Run: python3 -m unittest -v Server/wax-ota/test_wax_ota.py (no network, no VM)."""
import http.client, json, os, shutil, sys, tempfile, threading, time, unittest
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

if __name__ == "__main__":
    unittest.main()
