# wax-ota

Tiny upload endpoint for Wax's over-the-air install. Wax PUTs a signed IPA and a manifest here; iOS then fetches
them over HTTPS through `itms-services://`. Stdlib Python, no dependencies.

- Auth: `Authorization: Bearer <token>` on PUT/DELETE. Token is read from `WAX_OTA_TOKEN` (32+ characters).
- Paths: `PUT /u/<22+ char id>/app.ipa` and `/u/<id>/manifest.plist`. The id is 128 random bits chosen by the app;
  it is the only thing protecting a file from being fetched, so it must never appear in an access log.
- Files are deleted `WAX_OTA_TTL` seconds after upload (default 21600, six hours; minimum 60). Nothing is deleted when the install finishes.
- Limits: per-file size, total size (counting uploads still in flight), 60 s idle read, total time cap per upload.
- Listens on 127.0.0.1 only. Put it behind a TLS reverse proxy with a publicly trusted certificate.

- Wrong tokens: five from one address lock it out for 15 minutes (the address is the one Caddy reports).
- `GET /has/<sha256>` (token needed) tells Wax whether this exact IPA is already stored, so it is not uploaded twice.

Run the tests: `python3 -m unittest discover -s Server/wax-ota -p 'test_*.py' -v`

## Set up your own server (any Ubuntu VPS, Oracle Always Free works)

You need a small Ubuntu server with a public IP and a name that points at it. A free name works too: if the IP is
`1.2.3.4`, then `1-2-3-4.sslip.io` already points there.

1. **Get a server.** On Oracle Cloud's Always Free tier, create an Ubuntu VM (an Ampere A1 or the small AMD shape).
   Oracle may ask for a card at sign-up to verify you; it does not charge inside the free resources. Other VPS
   providers work the same way.
2. **Open the web ports in the cloud firewall.** In Oracle: the VM's subnet, Security List, add ingress rules for
   TCP 80 and 443 from 0.0.0.0/0 (22 is already there). Other providers have a similar firewall page.
3. **Log in and run the installer:**

   ```bash
   git clone <this repository> && cd <repository>/Server/wax-ota
   sudo ./install.sh 1-2-3-4.sslip.io      # your own name here
   ```

   Preview first with `./install.sh --dry-run <name>`: it prints every step and changes nothing.
4. **Paste the last line it prints** (`WAXINSTALL1 https://… <token>`) into Wax: Settings, Install host, Paste.
   The token lives only in `/etc/wax-ota.env` (readable by root) and in Wax's Keychain.

What the installer does: installs Caddy (HTTPS certificate included) and this service, makes a random 40-character
token, serves only `/ota-up/*` (uploads, needs the token) and `/ota/*` (downloads, needs the secret id) and answers
404 to everything else, opens only ports 22, 80 and 443, and turns on fail2ban. The upload service listens on
127.0.0.1 only. The firewall rules and the Oracle-specific steps above have not been run on a fresh Oracle VM by the
author of this guide; if a step differs on your image, the Caddyfile and service file the script writes are plain
files you can read and fix.

To update the service later, copy the new `wax_ota.py` over `/opt/wax-ota/wax_ota.py` and run
`sudo systemctl restart wax-ota`.

The Caddy settings the installer uses are in `Caddyfile.example`. Do not enable access logs for `/ota/*`:
paths contain the secret id. iOS needs the correct `Content-Type` for `.ipa` and `.plist`.

## Upload transaction guarantees (R5)

Each session admits one PUT or DELETE at a time; an overlapping request gets HTTP 409 and should retry after the current request finishes. Other sessions continue, up to 16 admitted body readers (503 when busy). Body idle timeout is 60 seconds; a total deadline applies to actual read chunks. Header reads have a 30-second idle timeout. Existing Caddy request-size limits and bearer-token checks remain mandatory. Reverse-proxy global header/connection limits should also be set for the operator's traffic; this stdlib service is not a general Internet edge.

Each request writes its own hidden, unpredictable `.part` file, verifies the complete declared body/hash, flushes it, then atomically renames to the requested artifact. Failures before publication preserve previous bytes. Responses follow owned-temporary cleanup and session release. Cleanup failures retain hidden quota-counted files for TTL collection; Caddy hides these files. Active sessions are excluded from GC and DELETE. GC never follows session symlinks.

The optional hash cache uses inode/size/mtime only as a candidate prefilter; a hit also requires streaming SHA-256 over the actual file while that session is protected from mutations/GC. Other sessions remain free to progress. The IPA and cache are two renames, not one transaction: a crash or cache-write failure yields a safe cache miss. Once IPA publication succeeds, a cache failure returns 201 with a warning because the requested IPA bytes really committed. Plain-text pre-R5 cache records become misses until uploaded again. Sequential replacement remains supported; callers must not treat a session as immutable across later explicit uploads. No power-loss or multiple backend-process coordination guarantee is claimed. Run exactly one backend process per storage root.

`python3 -m unittest discover -s Server/wax-ota -p 'test_*.py'` includes event-synchronized same-session conflicts, different-session progress, active GC/DELETE, aborted bodies, publication/cache/cleanup faults and containment. No server is deployed by these tests.
