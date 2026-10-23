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
    static let maxSpan: TimeInterval = 5 * 366 * 86_400
    static let maxRanges = 32

    func boot(routes: any RoutesBuilder) throws {
        let metrics = routes.grouped("metrics")
        metrics.get("active-users", use: activeUsers)
        metrics.get("retention", use: retention)
        metrics.get("series", use: series)
        metrics.get("devices", use: devices)
        metrics.get("device-counts", use: deviceCounts)
        metrics.get("incidents", use: incidents)
    }

    func activeUsers(req: Request) async throws -> ActiveUsersResponse {
        let range = try Self.range(of: req)

        let series = try await ActiveUserService.series(from: range.lowerBound, to: range.upperBound, on: req.db)
        return ActiveUsersResponse(series: series)
    }

    func retention(req: Request) async throws -> RetentionResponse {
        let range = try Self.range(of: req)

        let cohorts = try await RetentionService.cohorts(from: range.lowerBound, to: range.upperBound, on: req.db)
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

        let range = try Self.range(of: req)

        let series = try await MetricSeriesService.series(name: name, category: category, values: values, bucket: bucket, byVersion: by == "version", source: source, reduce: reduce, from: range.lowerBound, to: range.upperBound, on: req.db)
        return MetricSeriesResponse(series: series)
    }

    func devices(req: Request) async throws -> DevicesResponse {
        let range = try Self.range(of: req)

        let devices = try await DeviceService.devices(from: range.lowerBound, to: range.upperBound, on: req.db)
        return DevicesResponse(devices: devices)
    }

    func deviceCounts(req: Request) async throws -> DeviceCountsResponse {
        guard let list = req.query[String.self, at: "ranges"].flatMap({ $0.isEmpty ? nil : $0 }) else {
            throw Abort(.badRequest, reason: "Missing 'ranges': expected from-to pairs in milliseconds, comma-separated")
        }

        let pairs = list.split(separator: ",")

        guard pairs.count <= Self.maxRanges else {
            throw Abort(.badRequest, reason: "Too many ranges: at most \(Self.maxRanges)")
        }

        let ranges = try pairs.map(Self.range(pair:))

        let counts = try await DeviceService.counts(ranges: ranges, on: req.db)
        return DeviceCountsResponse(counts: counts)
    }

    func incidents(req: Request) async throws -> IncidentsResponse {
        let type = req.query[String.self, at: "type"] ?? ""
        guard IncidentService.recordTypes.contains(type) else {
            throw Abort(.badRequest, reason: "Unknown type '\(type)'; expected \(IncidentService.recordTypes.joined(separator: " or "))")
        }

        let range = try Self.range(of: req)

        return try await IncidentService.index(recordType: type, from: range.lowerBound, to: range.upperBound, on: req.db)
    }

    private static func range(pair: Substring) throws -> Range<Date> {
        let bounds = pair.split(separator: "-").compactMap { Int64($0) }

        guard bounds.count == 2 else {
            throw Abort(.badRequest, reason: "Malformed range '\(pair)': expected from-to in milliseconds")
        }

        return try range(from: date(ms: bounds[0]), to: date(ms: bounds[1]))
    }

    private static func range(of req: Request) throws -> Range<Date> {
        let to = try req.query[Int64.self, at: "to"].map(date(ms:)) ?? Date()
        let from = try req.query[Int64.self, at: "from"].map(date(ms:)) ?? to.addingTimeInterval(-defaultSpan)

        return try range(from: from, to: to)
    }

    private static func range(from: Date, to: Date) throws -> Range<Date> {
        guard from < to else {
            throw Abort(.badRequest, reason: "Empty range: 'from' must be before 'to'")
        }

        guard to.timeIntervalSince(from) <= maxSpan else {
            throw Abort(.badRequest, reason: "Range too long: at most \(Int(maxSpan / 86_400)) days")
        }

        return from..<to
    }

    private static func date(ms: Int64) throws -> Date {
        guard let date = Date(milliseconds: ms) else {
            throw Abort(.badRequest, reason: "Date \(ms) is out of range")
        }
        return date
    }
}
