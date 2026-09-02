# Usage tracking

Pipo measures three different things:

- `website visits`: homepage visits recorded in a shared Redis counter across Pipo domains and devices. The counter starts from the existing baseline of 82 and survives website deployments. It stores only the aggregate total.
- `download starts`: website requests that reach `/api/download`. This counts a request before the DMG is served; it does not prove a completed download or installation.
- `active use`: Pipo app launches and 15-minute heartbeats from enabled installations. The server stores HMAC-hashed random install IDs in daily Redis sets.

No LMS content, account identity, tokens, grades, messages, student IDs, IP addresses, or user-agent values are sent in the app event payload. Users can disable future app events in **Settings → Advanced → Usage data**.

## Vercel setup

Create an Upstash Redis database, then add these Vercel Production environment variables:

```text
UPSTASH_REDIS_REST_URL=...
UPSTASH_REDIS_REST_TOKEN=...
PIPO_USAGE_SALT=long-random-secret
PIPO_STATS_TOKEN=long-random-report-token
```

Redeploy website after setting variables. Keep `PIPO_USAGE_SALT` and `PIPO_STATS_TOKEN` private. Missing Redis configuration does not block the DMG redirect, but website visits and app usage counters will not persist.

## Read report

Use private bearer auth from a machine that has the report token:

```sh
curl -H "Authorization: Bearer $PIPO_STATS_TOKEN" https://pipo.jazztinn.me/api/usage
```

Update `DOWNLOAD_TARGET` and `RELEASE_VERSION` in `website/api/download.js` whenever website’s public DMG version changes. Keep website link `download` filename aligned with that release.

## Metric limits

Counts are directional. Download starts can include repeat clicks, failed transfers, bots, and retries. Active use represents installs that report successfully; offline launches and users with reporting disabled are absent. Redis daily active sets expire after 370 days; all-time install count does not expire.
