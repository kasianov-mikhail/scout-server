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

Queries for `DateIntMatrix` and `DateDoubleMatrix` are answered by aggregation over raw records:

- `DateIntMatrix` — weekly hour-bucket counts of lifecycle records (`Device`, `Install`, `Launch`, `Session`, `Version`, `Crash`), of events grouped by event name, and hour-bucket sums of `IntMetric` values grouped by metric name and category.
- `DateDoubleMatrix` — hour-bucket sums of `DoubleMetric` values.

The same aggregation is also available as a name-grouped flat time series — see [`GET /api/v1/metrics/series`](get-metrics-series.md).

Active users (DAU/WAU/MAU) are aggregated natively too, but served as a flat series from [`GET /api/v1/metrics/active-users`](get-metrics-active-users.md).

`IntMetric` and `DoubleMetric` are the raw metric record types clients upload (`name`, `category`, `date`, `value` + the usual id metadata); the server aggregates them into the matrix records above.
