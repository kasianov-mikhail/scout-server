# `GET /api/v1/metrics/active-users`

The native, pre-aggregated DAU/WAU/MAU series. The server derives active-user counts from the raw records that signal activity — the `Visit` marker a client writes once per device per day, and every `Session` — and returns the finished series directly.

`from` and `to` bound a half-open `[from, to)` range as milliseconds since the Unix epoch; `to` defaults to now and `from` to 90 days earlier. The response carries one point per UTC day (zero-activity days included), each an as-of trailing distinct-device count over the day (`dau`), 7 days (`wau`), and 30 days (`mau`).

Users are counted per device, so a reinstall stays one active user. `GET /api/v1/metrics/retention` counts installs instead, since a cohort is an acquisition rather than a person.

```json
{
  "series": [
    {"date": 1780272000000, "dau": 1, "wau": 1, "mau": 1}
  ]
}
```
