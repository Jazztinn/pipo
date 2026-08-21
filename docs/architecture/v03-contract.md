# Pipo v0.3 contract

Protocol version is `2`. Version 1 snapshots must continue decoding with empty
defaults for all new fields.

`refresh_dashboard` accepts optional `sections: [String]`. Supported names are
`schedule`, `due_soon`, `assignments`, `announcements`, `messages`, `grades`,
and `resources`. Omitted means full refresh. Each returned section has a
timestamp; failed requested sections retain cached Swift values.

Dashboard adds `next_up`, `schedule`, `announcements`, and `resources` arrays.
Dashboard items add optional `excerpt`, `submission_status`, `resource_kind`,
and `section`. Course summaries add `upcoming_count`. Capability support adds
`submission_status`, `announcements`, and `resources`.

Assignment statuses are `not_submitted`, `submitted`, `graded`, `reopened`, or
`unknown`. Status calls cover at most 30 relevant assignments with concurrency
4. Announcements cap at 20, resources at 30, calendar events at 30.

AppCore owns ranking, smart date groups, encrypted local state, reminders,
EventKit, diagnostics, and partial cache merging. PipoUI only renders mapped
state and invokes AppCore actions. Message bodies and OS notification bodies
remain metadata-only. Announcement and assignment excerpts may enter encrypted
cache. All URLs retain fixed LPU origin enforcement.
