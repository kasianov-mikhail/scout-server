# API

All endpoints sit under `/api/v1` and require an API key, passed either as an `X-API-Key` header or a bearer token. Keys are configured with the `SCOUT_API_KEYS` environment variable (comma-separated). Without keys the API is open only in the `development` environment.

## Endpoints
- [`POST /api/v1/records`](docs/PostRecords.md)
- [`POST /api/v1/records/query`](docs/PostRecordsQuery.md)
- [`GET /api/v1/records/:recordName`](docs/GetRecordsRecordName.md)
- [`GET /api/v1/metrics/active-users`](docs/GetMetricsActiveUsers.md)
- [`GET /api/v1/metrics/series`](docs/GetMetricsSeries.md)
- [`GET /healthz`](docs/GetHealthz.md)
