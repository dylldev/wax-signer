# Security

Wax signs apps on your own iPhone with your own certificate and profile, and installs them from an HTTPS server
you control. This page says what protects what, and how to report a problem.

## What stays private
- Your certificate, its key and your profiles are kept in the iPhone Keychain, this device only. They are not
  synced, not in backups, and never leave the phone.
- The install server token and any cloud bucket keys are kept the same way. Wax never writes them to a log or an
  error message.
- Wax has no built-in server, source or account. The address you enter is the only place it sends signed apps.

## How the install server is protected (`Server/wax-ota`)
- Uploads and deletes need `Authorization: Bearer <token>`. The token is 32 or more random characters, compared in
  constant time.
- Five wrong tokens from one address lock that address out for 15 minutes.
- Each upload goes to an unguessable folder (128 random bits). That folder name is what protects a download link,
  so it is never written to a log. Files are deleted after 6 hours by default.
- The service listens on 127.0.0.1 only; a reverse proxy (Caddy, set up by `install.sh`) is the only thing facing
  the internet, and it serves nothing except `/ota-up/*` and `/ota/*`.
- Size limits apply per file and in total, including uploads still in progress.

## Cloud bucket option
The bucket stays private. iOS receives links that name one file and stop working after 6 hours. Use a key that can
only touch that bucket, and add a one-day expiry rule on the bucket.

## "This iPhone" install host
- Wax opens a listener on the loopback interface only, for the one app being installed. It uses a random path, a
  15-minute lifetime, and is closed once iOS has taken the whole file or after 10 minutes of waiting.
- The name it uses (`waxspike123.duckdns.org`) resolves to `127.0.0.1`, and Wax refuses to start unless the name
  resolves only to loopback. The official feed may publish only that name.
- **The certificate's private key is public on purpose.** It ships in a public file so every install of Wax can use
  it. On its own it does not read your files, your Keychain or your signing certificate, and Wax signs nothing with it.
  Two real exposures remain:
  - *Availability.* Anyone holding the key can ask Let's Encrypt to revoke the certificate, which is in tension with
    Let's Encrypt's Subscriber Agreement. If that happens, "This iPhone" stops working until a new certificate is
    published; the other hosts are unaffected.
  - *Redirection.* Wax checks that the name resolves only to this phone before it starts, but iOS looks the name up
    again when you tap Install. Whoever controls the name's DNS record (the maintainer's DuckDNS account) or a hostile
    network resolver could point it elsewhere and, holding the public key, answer as the install server and offer a
    different app. You would still see iOS's install prompt with the app's name, and the app still has to be signed
    for your device. Install only apps you chose, watch the prompt, and prefer "My server" if you do not trust the
    network.
- The certificate file is checked before use: it must open, chain to a root iOS trusts, be valid now and match the
  name, and the official feed may publish only the official name. Phones ask the feed again once a day, so a re-issued
  certificate reaches them within a day.
- Outage runbook (maintainer): run the "Renew install certificate" workflow with *force* to issue a new certificate
  within the hour, with no app update. Phones pick it up within a day; until then they use their cached copy.
- Not built yet (v2): a signature on the certificate file by a key held off GitHub, and a second fallback name.

## What is not protected
- Anyone who holds a download link can fetch that one app until it expires. Do not share install links.
- If your server's token leaks, change it in `/etc/wax-ota.env` (then `sudo systemctl restart wax-ota`) and paste
  the new setup line into Wax.
- Wax signs whatever IPA you give it. It cannot tell whether an app is safe.

## Reporting a problem
Please report security problems privately, not in a public issue: use GitHub's "Report a vulnerability" on this
repository's Security tab. Include what you did, what happened, and which version of Wax. Expect an answer within
a week.
