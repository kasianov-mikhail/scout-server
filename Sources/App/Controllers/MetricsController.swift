//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Fluent
import Vapor

/// Serves pre-aggregated metric series natively: the server aggregates raw
/// records and answers with finished series — the DAU/WAU/MAU active-user
/// counts and a name-grouped, value-per-bucket series for a telemetry category.
///
struct MetricsController: RouteCollection {
    /// Span used when the caller omits `from`: the trailing 90 days.
    static let defaultSpan: TimeInterval = 90 * 86_400

    func boot(routes: any RoutesBuilder) throws {
        let metrics = routes.grouped("metrics")
        metrics.get("active-users", use: activeUsers)
        metrics.get("retention", use: retention)
        metrics.get("series", use: series)
    }

    /// `GET /metrics/active-users?from=<ms>&to=<ms>` — one DAU/WAU/MAU point per
    /// UTC day over the half-open `[from, to)` range. Both bounds are
    /// milliseconds since the Unix epoch; `to` defaults to now and `from` to
    /// 90 days before `to`.
    ///
    func activeUsers(req: Request) async throws -> ActiveUsersResponse {
        let to = req.query[Int64.self, at: "to"].map(Self.date(ms:)) ?? Date()
        let from = req.query[Int64.self, at: "from"].map(Self.date(ms:)) ?? to.addingTimeInterval(-Self.defaultSpan)

        guard from < to else {
            throw Abort(.badRequest, reason: "Empty range: 'from' must be before 'to'")
        }

        let series = try await ActiveUserService.series(from: from, to: to, on: req.db)
        return ActiveUsersResponse(series: series)
    }

    /// `GET /metrics/retention?from=<ms>&to=<ms>` — a weekly retention-cohort
    /// table over the half-open `[from, to)` range of install weeks. Both
    /// bounds are milliseconds since the Unix epoch; `to` defaults to now and
    /// `from` to 90 days before `to`, like `activeUsers`.
    ///
    func retention(req: Request) async throws -> RetentionResponse {
        let to = req.query[Int64.self, at: "to"].map(Self.date(ms:)) ?? Date()
        let from = req.query[Int64.self, at: "from"].map(Self.date(ms:)) ?? to.addingTimeInterval(-Self.defaultSpan)

        guard from < to else {
            throw Abort(.badRequest, reason: "Empty range: 'from' must be before 'to'")
        }

        let cohorts = try await RetentionService.cohorts(from: from, to: to, on: req.db)
        return RetentionResponse(cohorts: cohorts)
    }

    /// `GET /metrics/series?name=<name>&category=<cat>&values=int|double&bucket=hour|day|week&by=version&from=<ms>&to=<ms>`
    /// — a name-grouped, value-per-bucket series for metric, event, or
    /// lifecycle names. `name` and `category` are optional filters; omitting
    /// both returns every series the raw records carry. `values` picks the
    /// flavor (inferred when omitted), `bucket` defaults to `day`,
    /// `by=version` splits the groups by app version, and the range defaults
    /// to the trailing 90 days, like `activeUsers`.
    ///
    func series(req: Request) async throws -> MetricSeriesResponse {
        let name = req.query[String.self, at: "name"].flatMap { $0.isEmpty ? nil : $0 }
        let category = req.query[String.self, at: "category"].flatMap { $0.isEmpty ? nil : $0 }

        let values = req.query[String.self, at: "values"].flatMap { $0.isEmpty ? nil : $0 }
        if let values, values != "int", values != "double" {
            throw Abort(.badRequest, reason: "Unknown values '\(values)'; expected int or double")
        }

        let bucketName = req.query[String.self, at: "bucket"] ?? MetricSeriesService.Bucket.day.rawValue
        guard let bucket = MetricSeriesService.Bucket(rawValue: bucketName) else {
            throw Abort(.badRequest, reason: "Unknown bucket '\(bucketName)'; expected hour, day, or week")
        }

        let by = req.query[String.self, at: "by"].flatMap { $0.isEmpty ? nil : $0 }
        if let by, by != "version" {
            throw Abort(.badRequest, reason: "Unknown grouping '\(by)'; expected version")
        }

        let to = req.query[Int64.self, at: "to"].map(Self.date(ms:)) ?? Date()
        let from = req.query[Int64.self, at: "from"].map(Self.date(ms:)) ?? to.addingTimeInterval(-Self.defaultSpan)

        guard from < to else {
            throw Abort(.badRequest, reason: "Empty range: 'from' must be before 'to'")
        }

        let series = try await MetricSeriesService.series(name: name, category: category, values: values, bucket: bucket, byVersion: by == "version", from: from, to: to, on: req.db)
        return MetricSeriesResponse(series: series)
    }

    private static func date(ms: Int64) -> Date {
        Date(timeIntervalSince1970: Double(ms) / 1000)
    }
}
