//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Fluent
import SQLKit
import Vapor

/// Computes name-grouped, value-per-bucket series natively from raw records.
///
/// Clients upload only raw records; GROUP BY aggregation folds them into
/// hourly rows — record counts for lifecycle and event names, `IntMetric` /
/// `DoubleMetric` value sums for metric names — which are rolled up into the
/// requested granularity and grouped by name. One request can carry a whole
/// telemetry category, or the entire record stream when both filters are
/// omitted.
///
enum MetricSeriesService {
    /// Lifecycle record types counted under their own name.
    static let lifecycleTypes = ["Crash", "Device", "Hang", "Install", "Launch", "Session", "Version"]

    /// The first `Crash` of each (install, app version) pair within the
    /// range — the crashed-installs series behind release health.
    ///
    static let versionCrashName = "VersionCrash"

    /// Raw metric record types clients upload; the server sums their values.
    static let intMetricType = "IntMetric"
    static let doubleMetricType = "DoubleMetric"

    /// The granularity of a series point. `week` starts on Sunday, matching
    /// the rest of the date bucketing.
    ///
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

    /// One group per name over the half-open `[from, to)` range, each a sparse
    /// list of `bucket`-aligned points. `name` and `category` narrow the
    /// result; omitting both returns every series the raw records carry.
    /// `values` picks the flavor — `int` for counts and `IntMetric` sums,
    /// `double` for `DoubleMetric` sums — and is inferred per name when
    /// omitted, the integer side winning a collision. `byVersion` splits the
    /// groups by the records' `app_version`.
    ///
    /// Empty buckets are dropped, so every point is a real observation and a
    /// year-wide category stays compact. The range snaps down to the bucket
    /// containing `from`, so the first bucket is whole.
    ///
    static func series(name: String?, category: String?, values: String?, bucket: Bucket, byVersion: Bool, from: Date, to: Date, on database: any Database) async throws -> [MetricSeriesGroup] {
        let constraints = Constraints(name: name, category: category, dateRange: bucket.start(of: from)..<to)

        var intTotals: [GroupKey: [Date: Int64]] = [:]
        if values != "double" {
            intTotals = fold(try await intRows(constraints, on: database), bucket: bucket, byVersion: byVersion) { $0.totalInt ?? 0 }
        }

        var doubleTotals: [GroupKey: [Date: Double]] = [:]
        if values != "int" {
            doubleTotals = fold(try await doubleRows(constraints, on: database), bucket: bucket, byVersion: byVersion) { $0.totalDouble ?? 0 }
        }

        var groups: [MetricSeriesGroup] = []

        for (key, totals) in intTotals {
            let points = sparsePoints(totals) { .int($0) }
            if points.count > 0 {
                groups.append(MetricSeriesGroup(name: key.name, category: key.category, version: key.version, points: points))
            }
        }

        for (key, totals) in doubleTotals {
            if values == nil, intTotals[key] != nil {
                continue
            }
            let points = sparsePoints(totals) { .double($0) }
            if points.count > 0 {
                groups.append(MetricSeriesGroup(name: key.name, category: key.category, version: key.version, points: points))
            }
        }

        return groups.sorted { ($0.name, $0.category ?? "", $0.version ?? "") < ($1.name, $1.category ?? "", $1.version ?? "") }
    }

    /// Hourly integer rows: lifecycle and event record counts, first-crash
    /// counts for `VersionCrash`, and `IntMetric` value sums, honoring the
    /// name/category constraints.
    ///
    private static func intRows(_ constraints: Constraints, on database: any Database) async throws -> [HourRow] {
        var rows: [HourRow] = []

        if constraints.category == nil {
            for type in lifecycleTypes where constraints.name == nil || constraints.name == type {
                rows += try await countRows(recordType: type, named: type, constraints: constraints, on: database)
            }
            if constraints.name == nil || constraints.name == versionCrashName {
                rows += try await firstCrashRows(constraints, on: database)
            }
            rows += try await countRows(recordType: "Event", named: nil, constraints: constraints, on: database)
        }

        rows += try await sumRows(recordType: intMetricType, constraints: constraints, on: database)

        return rows
    }

    /// Hourly double rows: `DoubleMetric` value sums.
    private static func doubleRows(_ constraints: Constraints, on database: any Database) async throws -> [HourRow] {
        try await sumRows(recordType: doubleMetricType, constraints: constraints, on: database)
    }

    /// Per-hour record counts; `named` overrides the series name for
    /// lifecycle types, events group by their own `name` column.
    ///
    private static func countRows(recordType: String, named: String?, constraints: Constraints, on database: any Database) async throws -> [HourRow] {
        let sql = try database.sql()
        let range = constraints.hourRange

        let rows: [HourRow]
        if let named {
            rows = try await sql.raw(
                """
                SELECT app_version, hour_epoch AS hour, COUNT(*) AS total_int
                FROM records
                WHERE record_type = \(bind: recordType)
                  AND hour_epoch >= \(bind: range.lowerBound) AND hour_epoch < \(bind: range.upperBound)
                GROUP BY app_version, hour_epoch
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

    /// Per-hour counts of each (install, app version) pair's first `Crash`
    /// within the range. Installs without an id collapse into one pair per
    /// version, matching the client-side aggregation.
    ///
    private static func firstCrashRows(_ constraints: Constraints, on database: any Database) async throws -> [HourRow] {
        let sql = try database.sql()
        let range = constraints.hourRange

        let rows = try await sql.raw(
            """
            SELECT app_version, hour_epoch AS hour, COUNT(*) AS total_int
            FROM (
                SELECT app_version, MIN(hour_epoch) AS hour_epoch
                FROM records
                WHERE record_type = \(bind: "Crash")
                  AND hour_epoch >= \(bind: range.lowerBound) AND hour_epoch < \(bind: range.upperBound)
                GROUP BY install_id, app_version
            ) AS firsts
            GROUP BY app_version, hour_epoch
            """
        ).all(decoding: HourRow.self).map { row in
            var row = row
            row.name = versionCrashName
            return row
        }

        return rows.filter(constraints.matches)
    }

    /// Per-hour metric value sums, grouped by metric name and telemetry
    /// category.
    ///
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

    /// Sums the hourly rows into the requested granularity, keyed by name,
    /// category, bucket start, and — when `byVersion` — app version.
    ///
    private static func fold<T: AdditiveArithmetic & Equatable>(_ rows: [HourRow], bucket: Bucket, byVersion: Bool, value: (HourRow) -> T) -> [GroupKey: [Date: T]] {
        var totals: [GroupKey: [Date: T]] = [:]
        for row in rows {
            guard let name = row.name else {
                continue
            }
            let key = GroupKey(name: name, category: row.category, version: byVersion ? row.appVersion : nil)
            let bucketStart = bucket.start(of: Date(timeIntervalSince1970: Double(row.hour)))
            totals[key, default: [:]][bucketStart, default: .zero] += value(row)
        }
        return totals
    }

    /// The non-zero buckets of one group as wire points, sorted by date.
    ///
    private static func sparsePoints<T: AdditiveArithmetic & Equatable>(_ totals: [Date: T], value: (T) -> FieldValue) -> [MetricSeriesPoint] {
        totals
            .filter { $0.value != .zero }
            .sorted { $0.key < $1.key }
            .map { MetricSeriesPoint(date: Int64(($0.key.timeIntervalSince1970 * 1000).rounded()), value: value($0.value)) }
    }
}

/// One GROUP BY row: a (name, category, app version, hour bucket) and its
/// aggregate.
///
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

/// The narrowing a series request carries: a half-open date range plus
/// optional `name` and `category` equality.
///
private struct Constraints {
    let name: String?
    let category: String?
    let dateRange: Range<Date>

    /// SQL prefilter on hour buckets: hours starting inside the date range.
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

/// A (name, category, app version) series identity.
private struct GroupKey: Hashable {
    let name: String
    let category: String?
    let version: String?
}
