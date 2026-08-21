# Upstream

Pipo adapts the Moodle client design and selected read-only behavior from
[`ALinuxPerson/openlms-mcp`](https://github.com/ALinuxPerson/openlms-mcp).

- Pinned commit: `c5a09e9f70d56def5e26acea425d1a7dfd514503`
- Retrieved: 2026-08-21
- License: MIT
- Upstream copyright: Copyright (c) 2026 ALinuxPerson

Adapted upstream paths:

- `src/moodle.rs`: request encoding, response limits, same-origin handling,
  secret sanitization, and HTML-to-text conversion.
- `src/server.rs`: read-only Moodle function choices and parameter shapes for
  courses, assignments, notifications, messages, and grades.

Pipo excludes MCP transports, HTTP listeners, upload support, and write tools.

The upstream repository remains available locally as the
`openlms-upstream` Git remote for review and security updates.
