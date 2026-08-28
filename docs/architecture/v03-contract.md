# Pipo v0.5 contract

Protocol version is `4`. Clients send `hello` before authenticated work and
require `protocol_version: 4`; snapshots remain version `3` and continue
decoding with version 1 and 2 compatibility defaults.

Authentication responses include `account_id` and safe site metadata. Core
caches that account's site capabilities and course index in memory for fifteen
minutes. Cache never crosses access-token fingerprints.

Dashboard work permits at most 32 LMS attempts and 45 seconds; course detail
permits 12 attempts and 30 seconds. Heavy course work uses at most 12 courses,
rotated deterministically across refreshes. Read-only LMS calls retry once for
transient network, timeout, 408, 429, and 5xx responses with bounded jitter or
`Retry-After` up to ten seconds. Authentication never retries.

Every `section_results` value can include `error_code`, `truncated`,
`available_count`, and `retry_after_seconds`. Truncated data reports `partial`.
Diagnostics include LMS attempts, retries, heavy-work truncation, and protocol
version. Responses clamp text and trim low-priority rows before 2 MiB cap.

Version 1 and 2 snapshots continue decoding with
compatibility defaults for all new fields.

`refresh_dashboard` accepts optional `sections: [String]`. Supported names are
`schedule`, `due_soon`, `assignments`, `announcements`, `notifications`,
`messages`, `grades`, and `resources`. Omitted means full refresh. Each returned
section has a structured status and timestamp; failed requested sections retain
cached Swift values.

Dashboard adds `next_up`, `schedule`, `announcements`, and `resources` arrays.
Dashboard items add stable `entity_key` plus optional `excerpt`,
`submission_status`, `resource_kind`, and `section`. Course summaries add
`upcoming_count`. Capability support adds `submission_status`, `announcements`,
and `resources`.

Assignment statuses are `not_submitted`, `submitted`, `graded`, `reopened`, or
`unknown`. Status calls cover at most 12 relevant assignments within the
seven-day window, with concurrency 4. Announcements cap at 20, resources at 30,
calendar events at 30.

AppCore owns ranking, smart date groups, encrypted local state, reminders,
EventKit, diagnostics, and partial cache merging. PipoUI only renders mapped
state and invokes AppCore actions. Message bodies and OS notification bodies
remain metadata-only. Announcement and assignment excerpts may enter encrypted
cache. All URLs retain fixed LPU origin enforcement.
