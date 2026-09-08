# Sidecar Security Boundaries

- The only permitted remote origin is `https://lms.lpucavite.edu.ph`.
- Redirects and user destinations must remain on that origin.
- Requests are read-only Moodle web-service calls. Pipo does not upload, submit, send, mark read, or host a listener.
- Passwords exist only during token exchange. LMS tokens are kept in the macOS Keychain.
- Dashboard cache payloads are encrypted with CryptoKit before GRDB stores them locally.
- Sidecar error messages redact token and password fragments. Fixtures and logs must not contain credentials.
- JSON-line requests and responses are capped at 2 MiB; token responses use a smaller cap.
- Cached dashboards remain available when a refresh fails. Sign-out removes the token and the encrypted dashboard payload.
- Notification, message, and grade-feedback cache projections retain identity, kind, title, course metadata, timestamp, unread/submission status and validated destination. Their detail and excerpt fields are excluded. Course grade totals and the derived next-up list are excluded from disk snapshots too.
- Private message and grade details may remain in signed-in memory; sign-out clears that memory. Disposable LMS cache clearing does not delete imported schedules.
- Confirmed schedules use an independent account key and encrypted store. Sign-out closes access and clears decrypted fields while retaining the encrypted schedule/key for the same authenticated account. Explicit schedule deletion removes both. Document previews and extraction text are transient; only confirmed schedule fields, local IDs and revision metadata enter schedule storage.
