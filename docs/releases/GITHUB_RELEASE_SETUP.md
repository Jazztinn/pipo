# GitHub Release Setup

The GitHub `release` environment requires these Actions secrets:

- `SPARKLE_PRIVATE_KEY`: raw EdDSA private key matching `SUPublicEDKey`.
- `DEVELOPER_ID_CERT_P12_BASE64`: base64-encoded Developer ID certificate.
- `DEVELOPER_ID_CERT_PASSWORD`: password for the certificate archive.
- `DEVELOPER_ID_APPLICATION`: exact Developer ID Application identity.
- `NOTARY_API_KEY_P8_BASE64`: base64-encoded App Store Connect API key.
- `NOTARY_KEY_ID`: API key identifier.
- `NOTARY_ISSUER_ID`: App Store Connect issuer identifier.

Never place this value in the repository, workflow inputs, logs, or release
notes. Protect the `release` environment with required reviewers when desired.

To publish, open **Actions > Release > Run workflow**, choose a version and
channel, then approve the environment. The workflow builds the app and DMG,
signs the Sparkle appcast, creates the GitHub release, and pushes the updated
feed. Existing users update in place through Pipo's **Check for Updates**
control. The job stops before publication when signing or notary configuration
is absent.
