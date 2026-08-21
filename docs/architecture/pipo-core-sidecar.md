# Pipo Core Sidecar

Pipo uses a versioned JSON-lines process named `pipo-core` in place of a UniFFI binding. Every request and response is one UTF-8 JSON object terminated by `\n` on standard input and standard output. The process has no HTTP listener, local socket, upload path, or mutation method.

The protocol version is `1`. Supported methods are `authenticate_with_password`, `authenticate_with_token`, `discover_capabilities`, `refresh_dashboard`, `load_course`, and `resolve_destination`.

`refresh_dashboard` treats courses as the required feed. Deadlines,
notifications, assignments, messages, and grades fail independently and
return section failures beside usable data. Assignment IDs remain in the
encrypted snapshot so Swift can label only first-observed assignments as new.

`authenticate_with_password` exchanges the supplied password with Moodle's token endpoint once. The password is not cached by Rust or Swift. Subsequent requests supply the Keychain-backed token. Pipo only contacts `https://lms.lpucavite.edu.ph`; redirects and destinations must retain that exact origin. Response decoding is capped at 2 MiB, with a smaller cap for token exchange responses.

The Moodle request design follows the read-only portions of `ALinuxPerson/openlms-mcp` at `c5a09e9f70d56def5e26acea425d1a7dfd514503`. Pipo removed its MCP server, write methods, file transfer support, confirmations, and listener configuration.

## Rejected UniFFI Spike

The initial UniFFI spike was rejected for the local beta. The available Swift command-line SDK and compiler do not match the full Xcode toolchain required for generated bindings, package integration, archive signing, and macOS app verification. A process boundary keeps the Rust protocol independently testable and gives the app a stable Codable contract while full Xcode is unavailable. Revisit UniFFI only after the full Xcode toolchain can compile and archive both sides.
