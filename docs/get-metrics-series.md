# `GET /api/v1/metrics/series`

A name-grouped, pre-aggregated value-per-bucket series — the time-axis counterpart of the `DateIntMatrix` / `DateDoubleMatrix` grid. The same raw records feed both: record counts for lifecycle types (`Device`, `Install`, `Launch`, `Session`, `Version`, `Crash`) and event names, value sums for `IntMetric` / `DoubleMetric` names. One group per name, so a single request can carry a whole telemetry category.

| Parameter | Meaning |
| --- | --- |
| `name` | Optional. A single lifecycle type, event name, or metric name. At least one of `name` or `category` is required. |
| `category` | Optional. Narrows to one telemetry category and returns every metric name in it. At least one of `name` or `category` is required. |
| `values` | `int` or `double` — the value flavor. Inferred per name when omitted. |
| `bucket` | `hour`, `day`, or `week` (default `day`). `week` starts on Sunday. |
| `from` / `to` | Half-open `[from, to)` range in milliseconds since the Unix epoch; `to` defaults to now and `from` to 90 days earlier. |

Each group carries one point per non-empty bucket over the range (empty buckets are omitted, so the series is sparse), each a typed `value` — `int` for counts and `IntMetric` sums, `double` for `DoubleMetric` sums. A `category` filter excludes lifecycle and event names, which carry no category. The range snaps down to the bucket containing `from`, so the first bucket is whole.

```json
{
  "series": [
    {"name": "api_calls", "category": "counter", "points": [{"date": 1780272000000, "value": {"int": 42}}]}
  ]
}
```
