# R19 research checkpoint — Private user-owned loopback TLS

Status: **research partly completed; product implementation and device acceptance not completed**. No domain/CA account/DNS credentials or physical iPhone are available for the required authorized lab. No certificate issued/imported/revoked, no DNS changed, no production code or installation security policy changed.

## Primary-source evidence retrieved 2026-10-19

- [Let's Encrypt: Certificates for localhost](https://letsencrypt.org/docs/certificates-for-localhost/) (page says updated July31,2025): localhost itself is not uniquely owned. The page explicitly says a user-owned public domain resolving to127.0.0.1 can obtain a certificate via DNS validation. It also explicitly warns against distributing a native app's certificate **private key**, describing DNS substitution/impersonation and required revocation on known compromise. This is directly relevant to SECURITY.md's shared public TLS identity; feed integrity alone cannot restore private-key secrecy or availability.
- [Let's Encrypt: Challenge types / DNS-01](https://letsencrypt.org/docs/challenge-types/): DNS TXT proof can work without the local HTTPS endpoint being internet reachable. Automation requires appropriate DNS control; use narrowly scoped API credentials or a delegated validation zone, not full registrar/DNS-account credentials. Issuer/API terms must be reviewed for the actual domain/provider before product support is promised.
- [Apple Platform Deployment: Distribute proprietary in-house apps](https://support.apple.com/guide/deployment/distribute-proprietary-in-house-apps-depce7cefc4d/web) (page says published September17,2026): wireless distribution uses a manifest and HTTPS-accessible IPA with a device-trusted site certificate. App signing/provisioning and server TLS are separate. This enterprise-distribution guide **does not independently prove** arbitrary personal/ad-hoc/loopback installations on all modern iOS releases. Its iOS18+ enterprise trust/restart requirements are not universal claims about every credential type.

These are documented policy/transport prerequisites, not a successful Wax experiment. Browser treatment of localhost as potentially trustworthy does not establish acceptance by iOS's installation service.

## Candidate and boundaries

Evaluate an **optional** exact user-owned public hostname with a private per-device key, issuer-permitted certificate and loopback-only Network listener. DNS-01 can demonstrate domain ownership without exposing the listener. A DNS-only attacker lacking that private key should fail trusted TLS; test the actual installer rather than assuming URLSession behavior proves it. The certificate must remain genuinely secret and never enter the public installation feed, repository, diagnostics or distributed IPA.

Do not require domain ownership, a new account, subscriptions or hosting for ordinary local signing/export. Advanced users may already own a suitable domain; a domain is an operational cost/ownership requirement, not free infrastructure that Wax can promise universally. Importing a legitimately issued identity could be the first laboratory path; fully on-device CSR/ACME/DNS automation is a separate larger implementation, not an existing capability. TLS certificate algorithms and code-signing algorithms are different and must not be coupled unnecessarily.

Keychain custody/rotation, accessibility after lock, iOS17 PKCS#12 import side effects, backup exclusion and cancellation need R14/R8 work first. OS scheduling cannot guarantee renewal while the app remains unused; expiry warnings, explicit renewal and server/bucket/export fallback are necessary. Prefer an exact SAN and narrowly scoped DNS challenge delegation; do not store broad account credentials merely to simplify renewal. No issuer lifetime/renewal policy is assumed stable indefinitely.

## Alternatives assessed

| Approach | Technical/operational assessment |
|---|---|
| Current public shared identity/feed | Existing implementation; key disclosure enables impersonation if DNS is substituted and creates issuer revocation/availability risk. A signed feed cannot make the public key material private. Existing loopback/DNS validation is useful but not a proof of the installer's later DNS/TLS peer. |
| Optional private user-owned public-domain identity | Documented DNS-validation route is plausible and avoids intentional shared private-key disclosure. Requires owner authorization, actual issuer/provider decision, safe private storage/renewal and physical OTA evidence; not yet validated as a product. |
| Owner's existing HTTPS server/private bucket | Already implemented fallback; moves artifact delivery off-device and requires owner configuration/retention/credentials. No mandatory hosted signing proposed. R5/R14 improvements reduce relevant risks but do not remove external-host trust. |
| Export to owner-controlled tooling | Reliable architectural fallback without claiming direct install. Still needs legitimate signing/provisioning and independent device acceptance. |
| Plain HTTP or custom in-app TLS validation | Does not satisfy Apple's documented trusted-HTTPS requirement. App URLSession trust callbacks cannot be assumed to control the separate system installer. Not proposed as a bypass. |
| Self-signed root, VPN/DNS manipulation | Not a general private-key/trusted-HTTPS replacement. Managed-device trust may be a separately authorized lab configuration; ordinary users should not be asked to weaken trust or install broad roots to make this experiment work. No security bypass proposed. |

## Authorized lab protocol still required

1. Owner supplies a controlled test domain, DNS challenge scope and issuer-policy authorization; record only public policy/date/hostname-free fingerprints in review artifacts. No real secrets in Git.
2. Establish unchanged export/server/bucket controls with the same authorized signed fixture. Distinguish final-byte signature checks, OS provisioning/trust acceptance, delivery, installation observation and actual launch.
3. Generate/import a unique private transport identity; verify certificate chain, SAN/EKU/validity and private-key match. Confirm Keychain persistence/rotation/remove/failure handling without disclosing material.
4. Run on at least oldest supported iOS and current iOS, real iPhone models, Wi-Fi/cellular, foreground/background/locked state. Include DNS resolvers that rewrite/refuse loopback answers. Success on a browser, Simulator or URLSession is insufficient.
5. Controlled DNS substitution to an attacker endpoint **without** the key must fail the system installer's TLS. Test wrong-host, untrusted/expired/incomplete-chain identities; no trust-all fallback.
6. Exercise expiry/renewal/offline/DNS failure, cancellation during preparation/transfer, restart and low storage. Confirm original IPA/export survives and the UI never claims installation/launch from delivery alone.
7. Record exact Wax/iOS/build/cert public fingerprints and redacted outcomes. Adopt only after independent policy/security review and successful device controls. If gates fail, reject the design rather than marketing it as functional.

All experiment rows are **NOT RUN**. Exact blockers: no authorized domain/DNS/issuer context, no physical iPhone/system-installer observations, and unmerged R8/R14 prerequisites. Unmerged dependencies are not a permanent external blocker; they can be stacked once their contracts are reviewed. No production issuance is authorized by this research checkpoint.
