# Scout Server

[![CI](https://github.com/kasianov-mikhail/scout-server/actions/workflows/ci.yml/badge.svg)](https://github.com/kasianov-mikhail/scout-server/actions/workflows/ci.yml) [![Docker](https://github.com/kasianov-mikhail/scout-server/actions/workflows/docker.yml/badge.svg)](https://github.com/kasianov-mikhail/scout-server/actions/workflows/docker.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE) ![Swift](https://img.shields.io/badge/Swift-6.0-orange)


A Vapor backend for the [Scout](https://github.com/kasianov-mikhail/scout) package. The server aggregates analytics data natively: clients upload only raw records, and the matrix record types Scout's UI reads (`DateIntMatrix`, `DateDoubleMatrix`) are synthesized on the fly with SQL aggregation. Active users (DAU/WAU/MAU) are aggregated the same way and served as a flat series.

## Table of Contents
- [Features](#features)
- [Running](#running)
- [Configuration](#configuration)
- [API](#api)
- [Development](#development)
- [License](#license)

## Features

| | | |
|:-:|-|-|
| 📊 | **Native Aggregation** | The matrix record types Scout's UI reads (`DateIntMatrix`, `DateDoubleMatrix`), the DAU/WAU/MAU active-user series, and flat per-name metric series are synthesized on the fly with SQL — clients upload only raw records. |
| 🔁 | **Idempotent Upserts** | Records are upserted by `recordName`, so re-sent batches overwrite in place and sync retries stay safe. The [Scout](https://github.com/kasianov-mikhail/scout) dashboard queries the API directly. |
| 🔑 | **API Keys** | Endpoints are guarded by API keys, passed via an `X-API-Key` header or a bearer token. |
| 🐘 | **Postgres** | Records persist in Postgres with migrations run automatically on boot; tests run against in-memory SQLite. |
| 🐳 | **Docker** | Ships as a container image on the [GitHub Container Registry](https://github.com/kasianov-mikhail/scout-server/pkgs/container/scout-server). |

## Running

```sh
docker compose up
```

brings up the server with Postgres on `localhost:8080`. Images are published to GitHub Container Registry as [`ghcr.io/kasianov-mikhail/scout-server`](https://github.com/kasianov-mikhail/scout-server/pkgs/container/scout-server).

## Configuration

| Variable | Meaning |
| --- | --- |
| `SCOUT_API_KEYS` | Comma-separated list of accepted API keys |
| `DATABASE_URL` | Postgres connection string (takes precedence) |
| `DATABASE_HOST` / `DATABASE_PORT` / `DATABASE_USERNAME` / `DATABASE_PASSWORD` / `DATABASE_NAME` | Component-wise Postgres configuration |

Migrations run automatically on boot.

## API

The server exposes a small HTTP API under `/api/v1` for uploading and querying records. See [API.md](API.md) for the full reference.

## Development

```sh
swift test
```

Tests run against an in-memory SQLite database; the aggregation SQL is portable across both drivers (grouping happens on epoch-second bucket columns).

## License
Scout Server is released under the MIT License. See [LICENSE](LICENSE) for details.
