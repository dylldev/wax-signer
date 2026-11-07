# Give people a signed app they can keep

Wax 1.0 should let an iPhone owner import an authorized app and their own signing credentials, see exactly what will change, sign once, and keep a verified IPA they can export or deliver through a qualified route. If delivery fails, the signed file stays on the shelf. The first release should serve someone who already has a compatible identity and profile. Wax can help that person understand what to fix before they spend time signing again. [Confirmation and execution](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/Sources/SigningKit/PreparedIPA.swift#L178-L219) · [Shelf recovery](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/Sources/InstallKit/IPALibrary.swift#L284-L417)

## Three journeys define the release

| Journey | Experience | Finish rule |
|---|---|---|
| First sign | Import an authorized, unencrypted IPA from Files, import the matching RSA identity and provisioning profile, inspect profile and entitlement changes, confirm and sign. | Original digest unchanged. Final archive passes an independent verifier and exports from the normal app. |
| Install a saved app | Select a retained signed item, inspect destination and expiry, send to a qualified user-owned HTTPS server, then open the iOS installation prompt. | Separate receipts for delivery, install observation and fresh launch. Restarting Wax or retrying delivery preserves the same signed bytes. |
| Renew or update | Pick the prior shelf record, compare profile, app ID, prefix and capability changes, then sign an update or choose a separately installed copy. | Matching update retains a seeded app value on the test device. An incompatible identity gets a warning before modification. |

## The support contract has boundaries

**Must ship.** Authorized, structurally supported classic ZIP IPAs with a supported arm64 device slice, an RSA certificate in a user-supplied P12, matching profile and supported entitlement grants. Claim development or Ad Hoc routes only for combinations that pass G2. Test simple apps and at least one extension-bearing fixture. Treat unsupported layouts, encryption, expired credentials, insufficient storage and unauthorized entitlements as actionable outcomes. Preserve originals and prior good outputs across cancellation, process death, duplicate import, failed shelf writes and unavailable networks. [ZipArchive.swift](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/Sources/IPAKit/ZipArchive.swift#L97-L148) · [ProfileSelection.swift](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/Sources/SigningKit/ProfileSelection.swift#L15-L126) · [FatMachO.swift](https://github.com/dylldev/wax-signer/blob/62ff68b72f27e9e33987a87a48f27765369e126f/Sources/SigningKit/FatMachO.swift#L1-L74)

**Stable delivery.** Offer signed-file export first and a user-controlled HTTPS server as the candidate supported install route. Name prerequisites before upload and disclose who receives the IPA. Qualify on two physical device/OS combinations, one at the claimed lower bound and one current supported combination. Narrow the published support range if the lower bound cannot be exercised. Keep shared-key loopback and bucket behind explicit experimental choice. A host outage leaves export available. [Delivery threat model](COMPETITIVE-LANDSCAPE.md#the-stable-route-needs-a-private-server-identity)

**Nice after launch.** Richer receipts, historical comparisons, evidence-based compression presets, source artwork and opt-in diagnostics can build on signed records. Keep source-built probes and raw developer controls in Wax Dev. [Idea register](INNOVATION-LAB.md)

**Outside 1.0.** Apple Account provisioning, public enterprise credential sharing, decrypting App Store apps, universal compatibility, injected-code guarantees, guaranteed unattended refresh, hosted key custody and container execution. Extension and service behavior needs an actual device observation. Enterprise distribution belongs to the eligible organization's own users. [Apple deployment](https://support.apple.com/en-euro/guide/deployment/depce7cefc4d/1/web/1.0) · [Apple background strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)

## Ship the premium core

| Strategy | Gain | Cost and release decision |
|---|---|---|
| Fast | Ship export and sign quickly on a narrow fixture. | Leaves the saved-install and continuity journeys without candidate proof. Suitable for a preview. |
| Premium core, recommended | Deliver the three journeys above, observable failure states, two-device conformance, accessibility and reproducible release bytes. | Requires device access, independent verification and an HTTPS operator. Cut unqualified combinations before changing the quality bar. |
| Maximum scope | Add remote provisioning, new formats, private TLS issuance, automation and broad injection. | Adds authentication, renewal, format and platform dependencies before demand or support budgets are known. Sequence through bounded experiments after 1.0. |

| Choice | Engineering effort and external waits | Risk / confidence | Proof, value and opportunity cost |
|---|---|---|---|
| Fast | Estimate 4–8 engineer-days plus one-device access for a preview | High support risk / medium preview confidence | Sign/export fixture and one device give early evidence. Gives up qualified delivery, updates and much of the distinction from other signers. |
| Premium core | 15–36 engineer-days across four stages before discovered repairs, with overlapping tasks. Device/operator/reviewer waits separate. | Medium delivery risk / medium confidence | Two-device suite, independent output, failure recovery and blind first-use walkthrough support the three journeys. Defers account provisioning and extra formats. |
| Maximum | At least several engineer-months if viable, plus issuer, pairing, multiple device and policy dependencies; estimate confidence low | High upkeep and compatibility risk / low confidence | Each new model needs its own adversarial and physical corpus. Broader feature coverage competes for the same reviewer and device time as signing correctness. |

Release a normal unsigned asset, a distinctly identified Dev asset and checksums consistent with the source feed. Require all eight [release gates](RELEASE-READINESS.md), including distribution rollback and first-use instructions. The release owner approves publication only after evidence matches the final candidate.
