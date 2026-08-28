# Releases

Pipo release automation requires a configured Developer ID identity, Apple
notary credentials, and the Sparkle EdDSA key. The public appcast is served from
the repository root. Publication remains a separate, reviewer-approved action.

When Developer ID/notary credentials are unavailable, the workflow can publish
an explicitly unnotarized, ad-hoc-signed universal build. Release notes must
retain the macOS first-launch warning. Sparkle EdDSA signing remains required.

Public release checklist:

- Build universal `arm64` and `x86_64` app and core helper.
- Sign Sparkle components and helpers inside-out before signing the app bundle.
- Enable hardened runtime.
- Sign, notarize, and staple the DMG.
- Run `scripts/verify-release.sh`.
- Generate checksums, SBOM, and dependency license report.
- Sign the Sparkle archive with the protected EdDSA key.
- Publish GitHub release before updating the public appcast.
- Install the previous version and verify the user-approved update path.

`app/Sources/PipoUI/Resources/WhatsNew.json` is the release manifest. Its
version, build, channel, importance, and short item list drive the bundled
What’s New view, Sparkle notes, rollout policy, and GitHub release notes.

Rollback uses a higher patch and build number containing the last known-good
code. Publish it as critical when immediate distribution is required. Never
replace a signed artifact or point the feed at a lower build.

The appcast URL is
`https://raw.githubusercontent.com/Jazztinn/pipo/main/appcast.xml`. Never export
or commit the private Sparkle key.
