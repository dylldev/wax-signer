# Wax Installability Passport

**Status:** Draft for review  
**Scope:** First implementation stage of the Wax reliability roadmap  
**Date:** 2026-10-18

## The problem

Wax can inspect an IPA and check the signature it creates, but those checks do not prove that Apple or a particular iPhone will accept an installation. Today, the user can mistake “Wax's signature self-check passed” for “this app will install.” That distinction matters: installation also depends on certificate and profile trust, device eligibility, iOS compatibility, and the installation route.

## Proposal

Before signing, show a local **Installability Passport** for the selected IPA, identity, provisioning profile, signing options, and installation route. It is a concise, evidence-backed preflight report: what Wax checked, what needs attention, and what Wax cannot determine.

It is a diagnostic, not a guarantee, score, or safety certification. It must never show an unknown as a pass.

## First release scope

The first version is read-only and runs before signing. It will reuse the existing IPA inspection, profile parsing, certificate validity, profile fitness, and signing preflight logic wherever possible.

It will report:

- **IPA:** archive structure, app identifier, minimum iOS version when present, embedded signature/profile presence, and architectures Wax can actually process.
- **Signing identity:** certificate date validity and whether its fingerprint is listed in the selected profile.
- **Profile:** parse result, expiry, iOS platform eligibility, profile kind, and whether the app identifier fits the profile's application-identifier pattern.
- **Entitlements:** requested keys and which are present in the profile. Explain dropped or unsupported requests instead of silently describing them as granted.
- **Install route:** whether the selected Wax route is configured and reachable when Wax can check it. A reachable server is not proof that iOS will accept the IPA.

Each row has one of four results:

- **Pass:** Wax directly checked the fact with local data.
- **Warning:** a known condition may cause an install or behavior problem.
- **Blocked:** Wax already knows signing cannot proceed with these inputs.
- **Unknown:** Wax cannot establish the fact from available information.

Every row includes a short reason and, where useful, the next safe action. The summary uses the strongest applicable status and never collapses warnings or unknowns into “ready.”

## Explicit limits

Wax cannot ask iOS for a general, public-API install-acceptance verdict. On an ordinary iPhone app, it also cannot reliably obtain the phone's UDID to compare with a development or Ad Hoc profile. Certificate/profile revocation and Apple's current trust decision may be unavailable offline. These checks must say **Unknown** unless Wax has direct, current evidence. A profile's device count is not proof that this user's device is included.

Wax's existing signature verifier remains a self-check. It checks its own signature structures and file hashes; it does not replace Apple's verifier, prove certificate trust, or predict `installd` acceptance. The Passport must say this in plain language near its summary.

## User flow

1. User selects an IPA and the signing inputs as today.
2. Wax presents the Passport before the signing action.
3. User can expand a row to see evidence and limitations.
4. If blocked, Wax explains what input must change. If warning or unknown, Wax allows the user to continue after seeing the caveat.
5. Signing and the current post-sign self-check continue unchanged. Their results remain separate from preflight results.

No automatic bundle-ID rewrite, entitlement removal, credential upload, or install attempt is triggered by viewing the Passport.

## Architecture

- Keep the report model with existing signing logic unless implementation proves a separate package boundary is needed.
- Build rows from the same inputs used by `SigningModel` and `SigningOptions`; avoid a second, divergent signing-eligibility implementation.
- Reuse `IPAInspector`, `ProfileFitness`, certificate validity helpers, and profile metadata. Surface limits where existing APIs only parse structure or metadata.
- Keep the first UI entry in the Sign flow. Do not add a new tab or an account/cloud service.
- No external dependency, telemetry, or upload. IPA contents, credentials, private keys, profiles, and device identifiers stay on-device.
- Do not log passwords, private-key material, or raw profile contents.

## Acceptance criteria

- A user can distinguish “Wax checked this and it passed” from “Wax cannot know.”
- Expired certificates/profiles, an unlisted signing certificate, a mismatched application identifier, unsupported IPA structure, and incompatible known iOS minimum are not presented as ready.
- Unknown device eligibility, revocation, and Apple's final acceptance are explicitly labeled unknown, never green.
- The report explains that Wax's post-sign check is not Apple's install decision.
- Viewing the report does not modify the IPA, credentials, profile, or signing options.
- The existing signing flow remains available after a warning or unknown result, with its current blocking behavior preserved for definite preflight failures.

## Not in this stage

The following remain candidates for later, separately scoped work: a verifiable signing receipt; measured performance improvements to ZIP extraction and repacking; stronger transfer and install-route diagnostics; library update provenance; and opt-in sharing of a redacted diagnostic report. No new installation bypass or unsupported Apple behavior is proposed.

## Risks and open design questions

- Some checks may need to be moved or exposed from internal APIs. Keep that change small and avoid duplicating policy.
- Profile kind is inferred from profile contents in Wax; present it as Wax's classification, not an Apple guarantee.
- Server reachability checks can be transient and should not be cached as proof of later install success.
- The exact handling of warnings should remain clear and accessible at larger text sizes; the Passport must not become a long technical wall before signing.

## Verification approach

Implementation should use existing test fixtures and checks for deterministic local facts, plus simulator review for the report's wording and accessibility. A real-device install remains the only way to establish acceptance for a specific phone and route. The 0.14.1 release remains gated on the phone test already recorded in the project handoff.
