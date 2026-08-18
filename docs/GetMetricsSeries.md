# `GET /api/v1/metrics/series`

A name-grouped, pre-aggregated value-per-bucket series: record counts for lifecycle types (`Device`, `Install`, `Launch`, `Session`, `Version`, `Crash`, `Hang`) and event names, value sums for `IntMetric` / `DoubleMetric` names, and first-crash-per-install counts under the `VersionCrash` pseudo-name. One group per name, so a single request can carry a whole telemetry category — or, with no filters at all, the entire record stream.

| Parameter | Meaning |
| --- | --- |
| `name` | Optional. A single lifecycle type, event name, or metric name. Omitting it returns every name the range carries. |
| `category` | Optional. Narrows to one telemetry category and returns every metric name in it. |
| `values` | `int` or `double` — the value flavor. Inferred per name when omitted. |
| `bucket` | `hour`, `day`, or `week` (default `day`). `week` starts on Sunday. |
| `by` | Optional. `version` splits each name into one group per `app_version` and sets `version` on the group. Omitted, every version folds into a single group per name. |
| `source` | Optional. `event`, `lifecycle`, or `metric`. Pins the namespace a `name` resolves against so a name shared across namespaces isn't guessed. Omitted, the server infers from the name — counting a lifecycle type and any same-named event into one group. |
| `reduce` | `sum` or `last` (default `sum`). How a bucket folds its observations: `sum` accumulates, which suits counters and timers; `last` keeps the newest value in the bucket, which is what a gauge needs. |
| `from` / `to` | Half-open `[from, to)` range in milliseconds since the Unix epoch; `to` defaults to now and `from` to 90 days earlier. |

Both filters are optional and independent: `name` alone narrows to one series, `category` alone returns a whole telemetry category, and omitting both returns every series the raw records carry — which is how the client fills its log and search surfaces.

Each group carries one point per non-empty bucket over the range (empty buckets are omitted, so the series is sparse), each a typed `value` — `int` for counts and `IntMetric` sums, `double` for `DoubleMetric` sums. A `category` filter excludes lifecycle and event names, which carry no category. The range snaps down to the bucket containing `from`, so the first bucket is whole.

A `reduce=last` request spans metric records only, since record counts have no "latest" value, and it keeps zero readings rather than dropping them — zero is a legitimate gauge value. Records without a `date` carry no ordering and so are never the latest.

```json
{
  "series": [
    {"name": "api_calls", "category": "counter", "points": [{"date": 1780272000000, "value": {"int": 42}}]}
  ]
}
```

With `by=version`, each group also carries the version it was split on:

```json
{
  "series": [
    {"name": "Session", "version": "1.4.0", "points": [{"date": 1780272000000, "value": {"int": 118}}]},
    {"name": "Session", "version": "1.5.0", "points": [{"date": 1780272000000, "value": {"int": 512}}]}
  ]
}
```
