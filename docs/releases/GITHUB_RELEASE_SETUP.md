# GitHub Release Setup

Pipo currently publishes ad-hoc signed builds while Developer ID enrollment is
deferred. Sparkle still verifies every in-app update with Pipo's EdDSA key.

The GitHub `release` environment requires one Actions secret:

- `SPARKLE_PRIVATE_KEY`: raw EdDSA private key matching `SUPublicEDKey`.

Never place this value in the repository, workflow inputs, logs, or release
notes. Protect the `release` environment with required reviewers when desired.

To publish, open **Actions > Release > Run workflow**, choose a version and
channel, then approve the environment. The workflow builds the app and DMG,
signs the Sparkle appcast, creates the GitHub release, and pushes the updated
feed. Existing users update in place through Pipo's **Check for Updates**
control.

## Current limitation

Without Developer ID signing and notarization, first-time users may need to
approve Pipo in **System Settings > Privacy & Security**. A future Developer ID
release can restore the certificate import, hardened runtime, notarization, and
stapling stages without changing the Sparkle key.
