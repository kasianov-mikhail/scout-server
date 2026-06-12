# Scout Server

Vapor backend for the [Scout](https://github.com/kasianov-mikhail/scout) package.

Scout clients can sync analytics to CloudKit, to one or more Scout servers, or to any combination of both. Unlike CloudKit, this server aggregates data natively: clients upload only raw records, and the matrix record types Scout's UI reads (`DateIntMatrix`, `DateDoubleMatrix`, `PeriodMatrix`) are synthesized on the fly with SQL aggregation — no client-side matrix bookkeeping required.

## API

All endpoints sit under `/api/v1` and require an API key, passed either as an `X-API-Key` header or a bearer token. Keys are configured with the `SCOUT_API_KEYS` environment variable (comma-separated). Without keys the API is open only in the `development` environment.

### `POST /api/v1/records`

Upserts a batch of records (at most 1000 per request) keyed by `recordName`, mirroring CloudKit's `savePolicy: .allKeys` so sync retries stay idempotent. Matrix record types are rejected — they are derived, not stored.

```json
{
  "records": [
    {
      "recordType": "Event",
      "recordName": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
      "fields": {
        "name": {"string": "login"},
        "date": {"date": 1718000000000},
        "param_count": {"int": 0}
      }
    }
  ]
}
```

Field values are typed, single-key objects: `string`, `int`, `double`, `date` (milliseconds since the Unix epoch), `bytes` (base64), or `strings` (a string list, used by `in` filters).

### `POST /api/v1/records/query`

The counterpart of `CKQuery`. Filters and sorts run against the queryable fields (`name`, `category`, `level`, `uuid`, `device_id`, `install_id`, `launch_id`, `session_id`, `date`, `start_date`, `end_date`, `param_count`). Operators: `equals`, `notEquals`, `greaterThan`, `greaterThanOrEquals`, `lessThan`, `lessThanOrEquals`, `in`, `beginsWith`.

```json
{
  "recordType": "Event",
  "filters": [
    {"field": "name", "op": "beginsWith", "value": {"string": "cart_"}}
  ],
  "sort": [{"field": "date", "ascending": false}],
  "limit": 200,
  "fields": ["name", "date", "level"]
}
```

The response carries `records` and an opaque `cursor` when more pages exist; pass `{"cursor": "..."}` to continue.

Queries for `DateIntMatrix`, `DateDoubleMatrix`, and `PeriodMatrix` are answered by aggregation over raw records, shaped exactly like the matrices a CloudKit client would have written:

- `DateIntMatrix` — weekly hour-bucket counts of lifecycle records (`Device`, `Install`, `Launch`, `Session`, `Version`, `Crash`), of events grouped by event name, and hour-bucket sums of `IntMetric` values grouped by metric name and category.
- `DateDoubleMatrix` — hour-bucket sums of `DoubleMetric` values.
- `PeriodMatrix` (`name == "ActiveUser"`) — monthly DAU/WAU/MAU matrices derived from distinct installs with `Session` activity.

`IntMetric` and `DoubleMetric` are raw record types Scout uploads to servers in place of the metric matrices it maintains on CloudKit (`name`, `category`, `date`, `value` + the usual id metadata).

### `GET /api/v1/records/:recordName`

Fetches a single record (CloudKit's `lookup`), with an optional `?fields=a,b,c` projection. Returns 404 when missing.

### `GET /healthz`

Unauthenticated liveness probe.

## Running

```sh
docker compose up
```

brings up the server with Postgres on `localhost:8080`. Images are published to GitHub Container Registry as [`ghcr.io/kasianov-mikhail/scout-server`](https://github.com/kasianov-mikhail/scout-server/pkgs/container/scout-server).

Configuration:

| Variable | Meaning |
| --- | --- |
| `SCOUT_API_KEYS` | Comma-separated list of accepted API keys |
| `DATABASE_URL` | Postgres connection string (takes precedence) |
| `DATABASE_HOST` / `DATABASE_PORT` / `DATABASE_USERNAME` / `DATABASE_PASSWORD` / `DATABASE_NAME` | Component-wise Postgres configuration |

Migrations run automatically on boot.

## Development

```sh
swift test
```

Tests run against an in-memory SQLite database; the aggregation SQL is portable across both drivers (grouping happens on epoch-second bucket columns).
