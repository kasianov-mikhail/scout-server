# API

All endpoints sit under `/api/v1` and require an API key, passed either as an `X-API-Key` header or a bearer token. Keys are configured with the `SCOUT_API_KEYS` environment variable (comma-separated). Without keys the API is open only in the `development` environment.

## Table of Contents
- [`POST /api/v1/records`](#post-apiv1records)
- [`POST /api/v1/records/query`](#post-apiv1recordsquery)
- [`GET /api/v1/records/:recordName`](#get-apiv1recordsrecordname)
- [`GET /api/v1/metrics/active-users`](#get-apiv1metricsactive-users)
- [`GET /api/v1/metrics/series`](#get-apiv1metricsseries)
- [`GET /healthz`](#get-healthz)

## `POST /api/v1/records`

Upserts a batch of records (at most 1000 per request) keyed by `recordName`: re-sent records overwrite their fields, so sync retries stay idempotent. Matrix record types are rejected — they are derived, not stored.

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

## `POST /api/v1/records/query`

Filters and sorts run against the queryable fields (`name`, `category`, `level`, `uuid`, `device_id`, `install_id`, `launch_id`, `session_id`, `date`, `start_date`, `end_date`, `param_count`). Operators: `equals`, `notEquals`, `greaterThan`, `greaterThanOrEquals`, `lessThan`, `lessThanOrEquals`, `in`, `beginsWith`.

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

Queries for `DateIntMatrix` and `DateDoubleMatrix` are answered by aggregation over raw records:

- `DateIntMatrix` — weekly hour-bucket counts of lifecycle records (`Device`, `Install`, `Launch`, `Session`, `Version`, `Crash`), of events grouped by event name, and hour-bucket sums of `IntMetric` values grouped by metric name and category.
- `DateDoubleMatrix` — hour-bucket sums of `DoubleMetric` values.

The same aggregation is also available for a single name as a flat time series — see [`GET /api/v1/metrics/series`](#get-apiv1metricsseries).

Active users (DAU/WAU/MAU) are aggregated natively too, but served as a flat series from [`GET /api/v1/metrics/active-users`](#get-apiv1metricsactive-users).

`IntMetric` and `DoubleMetric` are the raw metric record types clients upload (`name`, `category`, `date`, `value` + the usual id metadata); the server aggregates them into the matrix records above.

## `GET /api/v1/records/:recordName`

Fetches a single record by `recordName`, with an optional `?fields=a,b,c` projection. Returns 404 when missing.

## `GET /api/v1/metrics/active-users`

The native, pre-aggregated DAU/WAU/MAU series. The server derives active-user counts from raw `Session` records and returns the finished series directly.

`from` and `to` bound a half-open `[from, to)` range as milliseconds since the Unix epoch; `to` defaults to now and `from` to 90 days earlier. The response carries one point per UTC day (zero-activity days included), each an as-of trailing distinct-install count over the day (`dau`), 7 days (`wau`), and calendar month (`mau`).

```json
{
  "series": [
    {"date": 1780272000000, "dau": 1, "wau": 1, "mau": 1}
  ]
}
```

## `GET /api/v1/metrics/series`

A flat, pre-aggregated value-per-bucket series for a single name — the time-axis counterpart of the `DateIntMatrix` / `DateDoubleMatrix` grid. The same raw records feed both: record counts for lifecycle types (`Device`, `Install`, `Launch`, `Session`, `Version`, `Crash`) and event names, value sums for `IntMetric` / `DoubleMetric` names.

| Parameter | Meaning |
| --- | --- |
| `name` | Required. The lifecycle type, event name, or metric name to aggregate. |
| `category` | Optional. Narrows metric names to one telemetry category. |
| `bucket` | `hour`, `day`, or `week` (default `day`). `week` starts on Sunday. |
| `from` / `to` | Half-open `[from, to)` range in milliseconds since the Unix epoch; `to` defaults to now and `from` to 90 days earlier. |

The response carries one point per bucket over the range (empty buckets included, so the series is dense), each a typed `value` — `int` for counts and `IntMetric` sums, `double` for `DoubleMetric` sums. The range snaps down to the bucket containing `from`, so the first bucket is whole.

```json
{
  "series": [
    {"date": 1780272000000, "value": {"int": 42}}
  ]
}
```

## `GET /healthz`

Unauthenticated liveness probe.
