# Security

## Supported use

Pipo is read-only and accepts LMS data only from
`https://lms.lpucavite.edu.ph`. It does not submit assignments, send messages,
mark notifications read, bypass certificates, or scrape authenticated pages.

## Secrets

- LMS passwords are used only for a one-time token exchange.
- LMS tokens and local encryption keys belong in macOS Keychain.
- Logs must redact credentials, grades, message content, and student IDs.
- Test fixtures must contain synthetic data.

## Reporting

Do not include account data or credentials in a public report. Use GitHub's
private vulnerability reporting when enabled for the repository.

