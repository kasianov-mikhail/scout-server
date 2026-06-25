# `POST /api/v1/records`

Upserts a batch of records (at most 1000 per request) keyed by `recordID`: re-sent records overwrite their fields, so sync retries stay idempotent. Matrix record types are rejected — they are derived, not stored.

```json
{
  "records": [
    {
      "recordType": "Event",
      "recordID": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
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
