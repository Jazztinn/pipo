# Sidecar Security Boundaries

- The only permitted remote origin is `https://lms.lpucavite.edu.ph`.
- Redirects and user destinations must remain on that origin.
- Requests are read-only Moodle web-service calls. Pipo does not upload, submit, send, mark read, or host a listener.
- Passwords exist only during token exchange. LMS tokens are kept in the macOS Keychain.
- Dashboard cache payloads are encrypted with CryptoKit before GRDB stores them locally.
- Sidecar error messages redact token and password fragments. Fixtures and logs must not contain credentials.
- JSON-line requests and responses are capped at 2 MiB; token responses use a smaller cap.
- Cached dashboards remain available when a refresh fails. Sign-out removes the token and the encrypted dashboard payload.
- Notification, message, and grade-feedback projections retain course and title only; message bodies, notification bodies, feedback text, and grade detail are excluded.
