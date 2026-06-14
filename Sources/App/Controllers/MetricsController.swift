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
/// counts and flat value-per-bucket series grouped by name.
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

    /// `GET /metrics/series?name=<name>&category=<cat>&values=int|double&bucket=hour|day|week&from=<ms>&to=<ms>`
    /// — flat, dense value-per-bucket series grouped by name, the time-axis
    /// counterpart of the matrix grid. `name` and `category` filter the result
    /// (omit `name` to get every name at once); `values` forces the flavor and
    /// is inferred when omitted; `bucket` defaults to `day`; the range defaults
    /// to the trailing 90 days, like `activeUsers`.
    ///
    func series(req: Request) async throws -> MetricSeriesResponse {
        let name = req.query[String.self, at: "name"].flatMap { $0.isEmpty ? nil : $0 }
        let category = req.query[String.self, at: "category"].flatMap { $0.isEmpty ? nil : $0 }

        var values: MetricSeriesService.Flavor?
        if let raw = req.query[String.self, at: "values"] {
            guard let flavor = MetricSeriesService.Flavor(rawValue: raw) else {
                throw Abort(.badRequest, reason: "Unknown values '\(raw)'; expected int or double")
            }
            values = flavor
        }

        let bucketName = req.query[String.self, at: "bucket"] ?? MetricSeriesService.Bucket.day.rawValue
        guard let bucket = MetricSeriesService.Bucket(rawValue: bucketName) else {
            throw Abort(.badRequest, reason: "Unknown bucket '\(bucketName)'; expected hour, day, or week")
        }

        let to = req.query[Int64.self, at: "to"].map(Self.date(ms:)) ?? Date()
        let from = req.query[Int64.self, at: "from"].map(Self.date(ms:)) ?? to.addingTimeInterval(-Self.defaultSpan)

        guard from < to else {
            throw Abort(.badRequest, reason: "Empty range: 'from' must be before 'to'")
        }

        let series = try await MetricSeriesService.series(name: name, category: category, values: values, bucket: bucket, from: from, to: to, on: req.db)
        return MetricSeriesResponse(series: series)
    }

    private static func date(ms: Int64) -> Date {
        Date(timeIntervalSince1970: Double(ms) / 1000)
    }
}
