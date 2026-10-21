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
