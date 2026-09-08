# Stabilization rollout ledger

This ledger records current implementation evidence, verification completed in
this checkout, and gates that remain outside local source checks. It is not a
release approval or production-readiness claim.

## Scope and defaults

The Moodle path in this working tree remains protocol v4 with snapshot schema v3. Swift
uses JSON-line requests with numeric JSON projection in
[`PipoSidecar.swift`](../app/Sources/PipoAppCore/PipoSidecar.swift), and Rust
emits the corresponding v4 handshake in
[`rust/pipo-core/src/lib.rs`](../rust/pipo-core/src/lib.rs). Moodle remains the
only enabled school path. `SchoolRegistry` contains only LPU Cavite, and both
school selection and Canvas are disabled feature gates.

Schedule import and presentation are separately disabled by default. Their
only current switches are `UserDefaults` keys
`pipo.features.schedule-import` and `pipo.features.schedule-presentation` in
[`PipoFeatureGates.swift`](../app/Sources/PipoAppCore/PipoFeatureGates.swift).
Do not enable either during a stable rollout without the schedule acceptance
gate below.

Provider identities are domain-opaque: `AccountScope` combines provider,
school, origin, and opaque remote account identity into a deterministic hashed
storage ID in [`PipoProviders.swift`](../app/Sources/PipoAppCore/PipoProviders.swift).
Canvas support is fixture-only. `CanvasOAuthService` has no usable production
registry entry, and its internal `testSchool` seam exists solely for tests.
There is no live Canvas school, public PAT flow, or production OAuth entry.

## Migration and rollback safety

`PipoPersistenceManager` reopens encrypted dashboard storage when its vault
key changes and retains unsaved privacy-projected snapshots while secure
storage is unavailable. It does not convert a failed Keychain open into a
permanent memory-only dependency. `PipoEAFScheduleStore` backs up existing
schedule rows before its schema version changes, rejects newer schemas, and
retains unreadable encrypted data rather than deleting it. Recovery is to keep
the prior database and Keychain material, restore the previous app build, and
never delete an encrypted database merely because the replacement key cannot
open it.

## Acceptance ledger

| ID | Area | Current fact | State |
|---|---|---|---|
| STAB-01 / H1, M5 | Persistence | Key-sensitive reopen and retry, migration of known legacy account cache, no disk grade totals/message details, memory fallback with an explicit unsaved action result. | Regression tests pass in diagnostic harness |
| STAB-02 / H2, M1, M4 | Session and sync | Process generations, cancellation/drain before deletion, bounded partial retention, authoritative empty sections, derived next-up, offline notification reconciliation, preceding quiet-hour scheduling. | Regression tests pass in diagnostic harness; live race acceptance remains |
| STAB-03 / H3–H6, M2–M3 | Moodle | Complete enrollment retained while enrichment rotates; canonical submission merge and discussion identities; bounded requests and response bodies; server cooldown and school-day queries. | Rust fixture checks; live Moodle acceptance remains |
| STAB-04 / H7–H9, M6 | Menu and actions | Typed Retry targets, partial warnings beside rows, item kinds preserved, course-detail lookup, truthful open/Calendar/local-save outcomes, labels and keyboard menus, inspector history and preserved row state. | Website and native source tests pass; rendered/assistive checks remain |
| STAB-05 / H10–H11, M7–M8 | Release and services | Exact-SHA check/tag gates, artifact manifest/hash, verified download tooling, content secret scan; bounded telemetry/feedback inputs, deadlines, rate limits, retention and circuit breakers. | Local checks pass; production configuration and installed update remain unverified |
| STAB-06 | Schedule | Encrypted per-account confirmed storage, schema backup/refusal, local extraction, editable review, TBA, day/week/Today/search, local minute updates, overnight occurrence handling. | Synthetic PDF and schedule tests pass; feature gates remain off |
| STAB-07 | Canvas/provider | Moodle provider boundary, registry, opaque domain scopes, system-browser PKCE and rotating-token core, test-only Canvas transport. | Foundations and fixtures; full wire migration and live school acceptance remain |

## Verification recorded in this checkout

- Native diagnostic harness: **114 tests passed**, covering AppCore plus PipoUI tests. Includes actual PDF text extraction, confirmed-value storage round trips, different-account isolation, key replacement, cancellation, unsaved action errors, OAuth fixtures, quiet hours, overnight boundaries, re-import change summaries and partial grade overlays.
- Website: **37 tests passed**; production build passed after canonical MenuWeb synchronization.
- Rust: **42 tests passed** with the lockfile enforced; formatting and Clippy with warnings denied passed. Dashboard retains a 32-attempt/45-second budget; heavy work rotates across six courses so section calls fit alongside status enrichment. Retries consume the same envelope and can make later optional work partial.
- Release shell syntax, Info.plist validation and `git diff --check` passed.
- Website production dependency advisory scan reported **0 vulnerabilities**. Cargo advisory tooling was unavailable; no Rust advisory clearance is claimed.

The temporary SDK 15.4 harness uses Observation and Sendable-metatype compatibility shims, an AppKit import compatibility adjustment, and a no-op replacement for newer glass rendering APIs. Test sources and AppCore behavior run locally, but this does not validate the production UI appearance, Sparkle executable, matching SDK build, or a packaged app. Project dependencies and installed SDKs were not patched.

## Remaining implementation and acceptance boundaries

The seven-phase roadmap is not fully complete. Stabilization changes are reviewable in this checkout, while schedule and provider expansion stay gated:

- Provider-neutral identity types exist, but the compatibility wire still uses Moodle's numeric course projection and some destination construction remains in Swift. A versioned wire/entity migration and complete provider-owned destinations are required before enabling Canvas. This is implementation work, not an external-access dependency.
- Canvas transport exists under Rust `cfg(test)` only. Its fixture success does not establish production mapping, permission coverage, OAuth registration, or live behavior. Canvas UI and school selection remain disabled.
- Text-PDF import supports explicit delimited tables; Vision contributes local text and geometry for review. Wrapped/irregular layouts and real school forms need a redacted corpus and parser refinement. Empty or uncertain extraction does not invent times or term dates; manual entry and correction remain available.
- One active term and weekly meetings are supported. Meeting-specific effective date ranges, irregular recurrence and a broader durable-schema migration history remain future work. Class reminders and recurring Calendar export are deliberately deferred by the approved scope.
- The current schedule window requires at least 920 × 640 points. Short displays, multiple screens, larger text, VoiceOver, contrast, reduced motion and Safari behavior require rendered acceptance before enablement.
- Coverage/truncation and cooldown metadata improve the existing snapshot contract; a provider-neutral per-entity coverage/continuation contract remains part of the wire migration. Unsupported feature gates do not remove retained authored schedules.

## Required external gates

1. Exercise schedule import against redacted real EAF files, including
   ambiguous rows, manual corrections, re-import, backup recovery, and a
   rejected or interrupted migration.
2. Before enabling Canvas, obtain a registered public-client configuration,
   validate registered callback behavior and rotating refresh tokens against a
   real approved school, then perform live acceptance without recording real
   credentials or student data.
3. Run the complete native suite with a matching full Xcode SDK/toolchain,
   then inspect rendered UI, VoiceOver navigation, packaged installer, and a
   real Sparkle update path.
4. Run fresh dependency advisory checks in the release environment. Do not
   infer advisory status from lockfiles or source inspection.

## Working-tree and release boundary

This worktree contains intentional user-owned modifications and untracked
implementation files, including release workflow, website telemetry, native
app, Rust, schedule, provider/OAuth, and test work. They remain preserved.
No commit, push, deployment, live OAuth, live telemetry, or release is implied
by this ledger. Syntax parsing or source inspection does not close any gate.
