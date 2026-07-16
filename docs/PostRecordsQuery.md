# `POST /api/v1/records/query`

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

Aggregations over raw records are served separately as name-grouped flat time series — see [`GET /api/v1/metrics/series`](GetMetricsSeries.md) and [`GET /api/v1/metrics/active-users`](GetMetricsActiveUsers.md).

`IntMetric` and `DoubleMetric` are the raw metric record types clients upload (`name`, `category`, `date`, `value` + the usual id metadata); the server sums their values into the metric series.
