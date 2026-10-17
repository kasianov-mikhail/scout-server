# `GET /api/v1/metrics/retention`

The native, pre-aggregated weekly retention-cohort table. The server groups raw `Install` records into acquisition cohorts by the UTC week of their install day, reads `Session` records as the return-visit heartbeat, splits each cohort by OS version, and returns the finished table directly.

`from` and `to` bound a half-open `[from, to)` range of install days as milliseconds since the Unix epoch; `to` defaults to now and `from` to 90 days earlier. Weeks start on Sunday, matching the rest of the date bucketing.

Each cohort carries its UTC week start (`date`), the number of installs acquired that week (`size`, the denominator — installs that never returned are counted too), and `retained`, aligned to the day-since-install milestones `[0, 1, 3, 7, 14, 30]`. Entry `i` is how many of the cohort's installs were active on exactly `install day + offset[i]` — bounded day-N retention, a single yes/no question per install rather than a running total. The milestones must stay in lockstep with the client's `RetentionCohort.dayOffsets`.

A milestone reads `null` until it has fully elapsed for every install in the cohort. A cohort's last install day is `week + 6`, so milestone `N` matures at `week + 7 + N` days; anything not yet matured by `to` is the triangular gap of a cohort table rather than a zero.

`segments` splits each cohort by the OS major version of the install's earliest `Session` in range that carries an `os_version`: `"iOS 18.2"` becomes `"iOS 18"`. Installs whose sessions carry no OS version belong to no segment, so segment sizes can add up to less than the cohort's. A segment's `size` and `retained` read like the cohort's own, with the same `null` gap. `crashes` and `hangs` count the segment's installs with at least one `Crash` or `Hang` record within 31 days of install (install day through day 30), each install counted once. Segments are sorted by name.

```json
{
  "cohorts": [
    {
      "date": 1780272000000,
      "size": 12,
      "retained": [12, 7, 4, 2, null, null],
      "segments": [
        {"name": "iOS 17", "size": 3, "retained": [3, 1, 1, 0, null, null], "crashes": 1, "hangs": 0},
        {"name": "iOS 18", "size": 9, "retained": [9, 6, 3, 2, null, null], "crashes": 0, "hangs": 2}
      ]
    }
  ]
}
```
