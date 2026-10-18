# Spike: installing from a name that resolves to 127.0.0.1 (result, 2026-10-17)

Question: can an iPhone install an app over the air from an HTTPS server running on the same phone, using a real
domain name that points at 127.0.0.1 and a publicly trusted certificate? If yes, nobody would need a host at all.

## Setup (throwaway, all deleted afterwards)
- A free DuckDNS name (`<name>.duckdns.org`) set to `127.0.0.1`.
- A Let's Encrypt certificate for that name, issued with `acme.sh` using the DNS challenge.
- A small test app that listens on `https://<name>:8443` with that certificate (Network.framework, TLS identity
  from the certificate and its chain) and serves `/manifest.plist` and `/app.ipa`. Signed with Wax and installed
  on an iPhone 17, iOS 27.2.
- The app opened `itms-services://?action=download-manifest&url=https://<name>:8443/manifest.plist`.

## Result: it works
- iOS (user agent `com.apple.appstored`) connected to the app's own loopback server, accepted the certificate, and
  fetched the manifest. The system prompt "<name> would like to install <app>" appeared.
- After Install, iOS sent `HEAD /app.ipa` and `GET /app.ipa`. With a real signed IPA (57,728 bytes) the whole file
  was delivered (`sent 57728 bytes err=nil`) and the app was then replaced by the served build. Proof: the replaced
  app's log lines lost the version tag the served-from copy carried.
- No server of any kind was involved.

## What it means
- A host-free install is possible: an app on the phone can serve the manifest and the IPA to iOS itself.
- It needs a name that resolves to 127.0.0.1 and a certificate that iOS trusts for that name. The certificate's
  private key has to ship inside the app (or be fetched by it), so it is effectively public. Let's Encrypt can
  revoke a publicly leaked key, which would break every install that relies on it until a new certificate is
  issued and shipped. A project-owned domain and a renewal routine (certificates last 90 days) would be needed.
- The app must stay running while iOS downloads (the test used a background task, about 30 seconds); a large IPA
  needs more thought (background audio or a continued processing task).
- Not tested: an IPA of several hundred MB, the Wax app serving instead of a separate test app, expiry of the
  certificate, and what Apple or Let's Encrypt do about a widely shared key.

## Recommendation
Worth a follow-up spec: "Install on this phone, no host" built into Wax, with the domain, certificate renewal and
revocation plan decided first. Until then the server and cloud-bucket options stay the supported routes.

## Cleanup done
Test app uninstalled from the phone, certificate and key deleted from the Mac, the downloaded `acme.sh` removed,
the test IPAs removed from iCloud Drive. The DuckDNS token appeared in a screenshot sent in chat: regenerate it or
delete the `<name>` domain on duckdns.org.
