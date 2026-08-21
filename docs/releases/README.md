# Releases

Pipo remains a local beta until a Developer ID identity and Sparkle signing key
are configured.

Public release checklist:

- Build universal `arm64` and `x86_64` app and core helper.
- Sign nested helper before signing the app bundle.
- Enable hardened runtime.
- Notarize and staple the app and DMG.
- Run `scripts/verify-release.sh`.
- Generate checksums, SBOM, and dependency license report.
- Sign the Sparkle archive with the protected EdDSA key.
- Publish GitHub release before updating the public appcast.
- Install the previous version and verify the user-approved update path.

The appcast URL is `https://jazztinn.github.io/pipo/appcast.xml`. Publishing it
stays disabled until the first signed release candidate.

