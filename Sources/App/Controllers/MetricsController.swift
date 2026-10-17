//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Fluent
import Vapor

struct MetricsController: RouteCollection {
    static let defaultSpan: TimeInterval = 90 * 86_400

    func boot(routes: any RoutesBuilder) throws {
        let metrics = routes.grouped("metrics")
        metrics.get("active-users", use: activeUsers)
        metrics.get("retention", use: retention)
        metrics.get("series", use: series)
    }

    func activeUsers(req: Request) async throws -> ActiveUsersResponse {
        let to = req.query[Int64.self, at: "to"].map(Self.date(ms:)) ?? Date()
        let from = req.query[Int64.self, at: "from"].map(Self.date(ms:)) ?? to.addingTimeInterval(-Self.defaultSpan)

        guard from < to else {
            throw Abort(.badRequest, reason: "Empty range: 'from' must be before 'to'")
        }

        let series = try await ActiveUserService.series(from: from, to: to, on: req.db)
        return ActiveUsersResponse(series: series)
    }

    func retention(req: Request) async throws -> RetentionResponse {
        let to = req.query[Int64.self, at: "to"].map(Self.date(ms:)) ?? Date()
        let from = req.query[Int64.self, at: "from"].map(Self.date(ms:)) ?? to.addingTimeInterval(-Self.defaultSpan)

        guard from < to else {
            throw Abort(.badRequest, reason: "Empty range: 'from' must be before 'to'")
        }

        let cohorts = try await RetentionService.cohorts(from: from, to: to, on: req.db)
        return RetentionResponse(cohorts: cohorts)
    }

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

        let sourceName = req.query[String.self, at: "source"].flatMap { $0.isEmpty ? nil : $0 }
        let source = try sourceName.map { name -> MetricSeriesService.Source in
            guard let source = MetricSeriesService.Source(rawValue: name) else {
                throw Abort(.badRequest, reason: "Unknown source '\(name)'; expected event, lifecycle, or metric")
            }
            return source
        }

        let reduceName = req.query[String.self, at: "reduce"] ?? MetricSeriesService.Reduce.sum.rawValue
        guard let reduce = MetricSeriesService.Reduce(rawValue: reduceName) else {
            throw Abort(.badRequest, reason: "Unknown reduce '\(reduceName)'; expected sum or last")
        }

        let to = req.query[Int64.self, at: "to"].map(Self.date(ms:)) ?? Date()
        let from = req.query[Int64.self, at: "from"].map(Self.date(ms:)) ?? to.addingTimeInterval(-Self.defaultSpan)

        guard from < to else {
            throw Abort(.badRequest, reason: "Empty range: 'from' must be before 'to'")
        }

        let series = try await MetricSeriesService.series(name: name, category: category, values: values, bucket: bucket, byVersion: by == "version", source: source, reduce: reduce, from: from, to: to, on: req.db)
        return MetricSeriesResponse(series: series)
    }

    private static func date(ms: Int64) -> Date {
        Date(timeIntervalSince1970: Double(ms) / 1000)
    }
}
