# GitHub Release Setup

Pipo's Release workflow keeps signing credentials in the GitHub `release`
environment. Routine releases run without local Keychain prompts.

Configure these GitHub Actions secrets once:

- `CERTIFICATE_P12_BASE64`: Developer ID Application certificate and private key exported as a password-protected `.p12`, then Base64 encoded.
- `CERTIFICATE_PASSWORD`: password used for the `.p12` export.
- `CI_KEYCHAIN_PASSWORD`: random password used only for the temporary runner Keychain.
- `DEVELOPER_ID_APPLICATION`: full `Developer ID Application: ... (TEAMID)` identity.
- `APPLE_ID`: Apple Account used for notarization.
- `APPLE_APP_PASSWORD`: app-specific password for notarization.
- `APPLE_TEAM_ID`: Apple Developer team identifier.
- `SPARKLE_PRIVATE_KEY`: raw EdDSA private key matching `SUPublicEDKey`.

Protect the `release` environment with required reviewers. Never place any of
these values in the repository, workflow inputs, logs, or release notes.

To publish, open **Actions > Release > Run workflow**, choose a version and
channel, then approve the protected environment. The workflow signs the app,
notarizes and staples the DMG, signs the Sparkle appcast, creates the GitHub
release, and pushes the updated feed. Existing users update in place through
Pipo's **Check for Updates** control.
