//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Fluent
import SQLKit
import Vapor

enum MetricSeriesService {
    static let lifecycleTypes = ["Condition", "Crash", "Device", "Hang", "Install", "Launch", "ResourceException", "Screen", "Session", "Version"]

    private static let firstSeenTypes = ["VersionCrash": "Crash", "VersionInstall": "Version"]

    static let dailyMetricType = "DailyMetric"

    static let intMetricType = "IntMetric"
    static let doubleMetricType = "DoubleMetric"

    enum Source: String {
        case event, lifecycle, metric
    }

    enum Reduce: String {
        case sum, last
    }

    enum Bucket: String {
        case hour
        case day
        case week

        func start(of date: Date) -> Date {
            switch self {
            case .hour: date.startOfHour
            case .day: date.startOfDay
            case .week: date.startOfWeek
            }
        }
    }

    static func series(name: String?, category: String?, values: String?, bucket: Bucket, byVersion: Bool, source: Source?, reduce: Reduce = .sum, from: Date, to: Date, on database: any Database) async throws -> [MetricSeriesGroup] {
        let constraints = Constraints(name: name, category: category, dateRange: bucket.start(of: from)..<to)

        var intTotals: [GroupKey: [Date: Int64]] = [:]
        if values != "double" {
            let rows = try await intRows(constraints, source: source, reduce: reduce, on: database)
            intTotals = fold(rows, bucket: bucket, byVersion: byVersion, reduce: reduce) { $0.totalInt ?? 0 }
        }

        var doubleTotals: [GroupKey: [Date: Double]] = [:]
        if values != "int" {
            let rows = try await doubleRows(constraints, source: source, reduce: reduce, on: database)
            doubleTotals = fold(rows, bucket: bucket, byVersion: byVersion, reduce: reduce) { $0.totalDouble ?? 0 }
        }

        var groups: [MetricSeriesGroup] = []

        for (key, totals) in intTotals {
            let points = points(totals, reduce: reduce) { .int($0) }
            if !points.isEmpty {
                groups.append(MetricSeriesGroup(name: key.name, category: key.category, version: key.version, points: points))
            }
        }

        for (key, totals) in doubleTotals {
            if values == nil, intTotals[key] != nil {
                continue
            }
            let points = points(totals, reduce: reduce) { .double($0) }
            if !points.isEmpty {
                groups.append(MetricSeriesGroup(name: key.name, category: key.category, version: key.version, points: points))
            }
        }

        return groups.sorted { ($0.name, $0.category ?? "", $0.version ?? "") < ($1.name, $1.category ?? "", $1.version ?? "") }
    }

    private static func intRows(_ constraints: Constraints, source: Source?, reduce: Reduce, on database: any Database) async throws -> [HourRow] {
        var rows: [HourRow] = []

        guard reduce == .sum else {
            return try await lastRows(recordType: intMetricType, constraints: constraints, on: database)
        }

        switch source {
        case .event:
            rows += try await countRows(recordType: "Event", named: nil, constraints: constraints, on: database)
        case .lifecycle:
            rows += try await lifecycleRows(constraints, on: database)
        case .metric:
            rows += try await sumRows(recordType: intMetricType, constraints: constraints, on: database)
        case nil:
            if constraints.category == nil {
                rows += try await lifecycleRows(constraints, on: database)
                rows += try await countRows(recordType: "Event", named: nil, constraints: constraints, on: database)
            }
            rows += try await sumRows(recordType: intMetricType, constraints: constraints, on: database)
        }

        return rows
    }

    private static func lifecycleRows(_ constraints: Constraints, on database: any Database) async throws -> [HourRow] {
        var rows: [HourRow] = []
        for type in lifecycleTypes where constraints.name == nil || constraints.name == type {
            rows += try await countRows(recordType: type, named: type, constraints: constraints, on: database)
        }
        for (name, type) in firstSeenTypes where constraints.name == nil || constraints.name == name {
            rows += try await firstSeenRows(recordType: type, named: name, constraints: constraints, on: database)
        }
        rows += try await dailyMetricRows(constraints, on: database)
        return rows
    }

    private static func doubleRows(_ constraints: Constraints, source: Source?, reduce: Reduce, on database: any Database) async throws -> [HourRow] {
        switch source {
        case .event, .lifecycle:
            []
        case .metric, nil:
            reduce == .last
                ? try await lastRows(recordType: doubleMetricType, constraints: constraints, on: database)
                : try await sumRows(recordType: doubleMetricType, constraints: constraints, on: database)
        }
    }

    private static func countRows(recordType: String, named: String?, constraints: Constraints, on database: any Database) async throws -> [HourRow] {
        let sql = try database.sql()
        let range = constraints.hourRange

        let rows: [HourRow]
        if let named {
            rows = try await sql.raw(
                """
                SELECT category, app_version, hour_epoch AS hour, COUNT(*) AS total_int
                FROM records
                WHERE record_type = \(bind: recordType)
                  AND hour_epoch >= \(bind: range.lowerBound) AND hour_epoch < \(bind: range.upperBound)
                GROUP BY category, app_version, hour_epoch
                """
            ).all(decoding: HourRow.self).map { row in
                var row = row
                row.name = named
                return row
            }
        } else {
            rows = try await sql.raw(
                """
                SELECT name, app_version, hour_epoch AS hour, COUNT(*) AS total_int
                FROM records
                WHERE record_type = \(bind: recordType) AND name IS NOT NULL
                  AND hour_epoch >= \(bind: range.lowerBound) AND hour_epoch < \(bind: range.upperBound)
                GROUP BY name, app_version, hour_epoch
                """
            ).all(decoding: HourRow.self)
        }

        return rows.filter(constraints.matches)
    }

    private static func firstSeenRows(recordType: String, named: String, constraints: Constraints, on database: any Database) async throws -> [HourRow] {
        let sql = try database.sql()
        let range = constraints.hourRange

        let rows = try await sql.raw(
            """
            SELECT app_version, hour_epoch AS hour, COUNT(*) AS total_int
            FROM (
                SELECT app_version, MIN(hour_epoch) AS hour_epoch
                FROM records
                WHERE record_type = \(bind: recordType) AND hour_epoch < \(bind: range.upperBound)
                GROUP BY install_id, app_version
                HAVING MIN(hour_epoch) >= \(bind: range.lowerBound)
            ) AS firsts
            GROUP BY app_version, hour_epoch
            """
        ).all(decoding: HourRow.self).map { row in
            var row = row
            row.name = named
            return row
        }

        return rows.filter(constraints.matches)
    }

    private static func dailyMetricRows(_ constraints: Constraints, on database: any Database) async throws -> [HourRow] {
        let sql = try database.sql()
        let range = constraints.hourRange

        let rows = try await sql.raw(
            """
            SELECT name, category, app_version, hour_epoch AS hour, CAST(SUM(value_int) AS BIGINT) AS total_int
            FROM records
            WHERE record_type = \(bind: dailyMetricType) AND name IS NOT NULL
              AND hour_epoch >= \(bind: range.lowerBound) AND hour_epoch < \(bind: range.upperBound)
            GROUP BY name, category, app_version, hour_epoch
            """
        ).all(decoding: HourRow.self)

        return rows.filter(constraints.matches)
    }

    private static func sumRows(recordType: String, constraints: Constraints, on database: any Database) async throws -> [HourRow] {
        let sql = try database.sql()
        let range = constraints.hourRange

        let total =
            recordType == intMetricType
            ? "CAST(SUM(value_int) AS BIGINT) AS total_int"
            : "SUM(value_double) AS total_double"

        let rows = try await sql.raw(
            """
            SELECT name, category, hour_epoch AS hour, \(unsafeRaw: total)
            FROM records
            WHERE record_type = \(bind: recordType) AND name IS NOT NULL
              AND hour_epoch >= \(bind: range.lowerBound) AND hour_epoch < \(bind: range.upperBound)
            GROUP BY name, category, hour_epoch
            """
        ).all(decoding: HourRow.self)

        return rows.filter(constraints.matches)
    }

    private static func lastRows(recordType: String, constraints: Constraints, on database: any Database) async throws -> [HourRow] {
        let sql = try database.sql()
        let range = constraints.hourRange

        let isInt = recordType == intMetricType
        let projection = isInt ? "CAST(value_int AS BIGINT) AS total_int" : "value_double AS total_double"
        let column = isInt ? "total_int" : "total_double"

        let rows = try await sql.raw(
            """
            SELECT name, category, hour, \(unsafeRaw: column)
            FROM (
                SELECT name, category, hour_epoch AS hour, \(unsafeRaw: projection),
                       ROW_NUMBER() OVER (PARTITION BY name, category, hour_epoch ORDER BY date DESC) AS rn
                FROM records
                WHERE record_type = \(bind: recordType) AND name IS NOT NULL AND date IS NOT NULL
                  AND hour_epoch >= \(bind: range.lowerBound) AND hour_epoch < \(bind: range.upperBound)
            ) AS ranked
            WHERE rn = 1
            """
        ).all(decoding: HourRow.self)

        return rows.filter(constraints.matches)
    }

    private static func fold<T: AdditiveArithmetic & Equatable>(_ rows: [HourRow], bucket: Bucket, byVersion: Bool, reduce: Reduce, value: (HourRow) -> T) -> [GroupKey: [Date: T]] {
        var totals: [GroupKey: [Date: T]] = [:]
        var latestHour: [GroupKey: [Date: Int64]] = [:]

        for row in rows {
            guard let name = row.name else {
                continue
            }
            let key = GroupKey(name: name, category: row.category, version: byVersion ? row.appVersion : nil)
            let bucketStart = bucket.start(of: Date(timeIntervalSince1970: Double(row.hour)))

            switch reduce {
            case .sum:
                totals[key, default: [:]][bucketStart, default: .zero] += value(row)
            case .last:
                if let seen = latestHour[key]?[bucketStart], seen >= row.hour {
                    continue
                }
                latestHour[key, default: [:]][bucketStart] = row.hour
                totals[key, default: [:]][bucketStart] = value(row)
            }
        }

        return totals
    }

    private static func points<T: AdditiveArithmetic & Equatable>(_ totals: [Date: T], reduce: Reduce, value: (T) -> FieldValue) -> [MetricSeriesPoint] {
        totals
            .filter { reduce == .last || $0.value != .zero }
            .sorted { $0.key < $1.key }
            .map { MetricSeriesPoint(date: $0.key.milliseconds, value: value($0.value)) }
    }
}

private struct HourRow: Decodable {
    var name: String?
    var category: String?
    var appVersion: String?
    var hour: Int64
    var totalInt: Int64?
    var totalDouble: Double?

    enum CodingKeys: String, CodingKey {
        case name, category, hour
        case appVersion = "app_version"
        case totalInt = "total_int"
        case totalDouble = "total_double"
    }
}

private struct Constraints {
    let name: String?
    let category: String?
    let dateRange: Range<Date>

    var hourRange: Range<Int64> {
        Int64(dateRange.lowerBound.timeIntervalSince1970)..<Int64(dateRange.upperBound.timeIntervalSince1970)
    }

    func matches(_ row: HourRow) -> Bool {
        if let name, row.name != name {
            return false
        }
        if let category, row.category != category {
            return false
        }
        return true
    }
}

private struct GroupKey: Hashable {
    let name: String
    let category: String?
    let version: String?
}
