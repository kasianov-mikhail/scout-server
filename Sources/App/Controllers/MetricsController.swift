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
/// counts and a flat value-per-bucket series for any single name.
///
struct MetricsController: RouteCollection {
    /// Span used when the caller omits `from`: the trailing 90 days.
    static let defaultSpan: TimeInterval = 90 * 86_400

    func boot(routes: any RoutesBuilder) throws {
        let metrics = routes.grouped("metrics")
        metrics.get("active-users", use: activeUsers)
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

    /// `GET /metrics/series?name=<name>&category=<cat>&bucket=hour|day|week&from=<ms>&to=<ms>`
    /// — a flat, dense value-per-bucket series for one metric, event, or
    /// lifecycle name, the time-axis counterpart of the matrix grid. `name` is
    /// required, `category` and `bucket` (default `day`) optional; the range
    /// defaults to the trailing 90 days, like `activeUsers`.
    ///
    func series(req: Request) async throws -> MetricSeriesResponse {
        guard let name = req.query[String.self, at: "name"], !name.isEmpty else {
            throw Abort(.badRequest, reason: "Query parameter 'name' is required")
        }
        let category = req.query[String.self, at: "category"].flatMap { $0.isEmpty ? nil : $0 }

        let bucketName = req.query[String.self, at: "bucket"] ?? MetricSeriesService.Bucket.day.rawValue
        guard let bucket = MetricSeriesService.Bucket(rawValue: bucketName) else {
            throw Abort(.badRequest, reason: "Unknown bucket '\(bucketName)'; expected hour, day, or week")
        }

        let to = req.query[Int64.self, at: "to"].map(Self.date(ms:)) ?? Date()
        let from = req.query[Int64.self, at: "from"].map(Self.date(ms:)) ?? to.addingTimeInterval(-Self.defaultSpan)

        guard from < to else {
            throw Abort(.badRequest, reason: "Empty range: 'from' must be before 'to'")
        }

        let series = try await MetricSeriesService.series(name: name, category: category, bucket: bucket, from: from, to: to, on: req.db)
        return MetricSeriesResponse(series: series)
    }

    private static func date(ms: Int64) -> Date {
        Date(timeIntervalSince1970: Double(ms) / 1000)
    }
}
