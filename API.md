# API

All endpoints sit under `/api/v1` and require an API key, passed either as an `X-API-Key` header or a bearer token. Keys are configured with the `SCOUT_API_KEYS` environment variable (comma-separated). Without keys the API is open only in the `development` environment.

## Endpoints
- [`POST /api/v1/records`](docs/post-records.md)
- [`POST /api/v1/records/query`](docs/post-records-query.md)
- [`GET /api/v1/records/:recordName`](docs/get-records-recordname.md)
- [`GET /api/v1/metrics/active-users`](docs/get-metrics-active-users.md)
- [`GET /api/v1/metrics/series`](docs/get-metrics-series.md)
- [`GET /healthz`](docs/get-healthz.md)
