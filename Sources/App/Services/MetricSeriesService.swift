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

    /// Which namespace a `name` resolves against. Absent, the server infers it
    /// from the name — counting a lifecycle type and any same-named event into
    /// one group. An explicit source keeps the two namespaces apart, so a
    /// custom event named like a lifecycle counter (e.g. "Session") is neither
    /// shadowed nor conflated.
    ///
    enum Source: String {
        case event, lifecycle, metric
    }

    /// How a bucket folds the observations inside it. `sum` accumulates, which
    /// suits counters and timers; `last` keeps the newest observation, which is
    /// what a gauge — a point-in-time value — needs.
    ///
    enum Reduce: String {
        case sum, last
    }

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
            if points.count > 0 {
                groups.append(MetricSeriesGroup(name: key.name, category: key.category, version: key.version, points: points))
            }
        }

        for (key, totals) in doubleTotals {
            if values == nil, intTotals[key] != nil {
                continue
            }
            let points = points(totals, reduce: reduce) { .double($0) }
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
    private static func intRows(_ constraints: Constraints, source: Source?, reduce: Reduce, on database: any Database) async throws -> [HourRow] {
        var rows: [HourRow] = []

        // Record counts have no "latest" value, so a last reduce only spans metrics.
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

    /// Per-hour lifecycle-type record counts plus the `VersionCrash`
    /// first-crash counts, honoring the name constraint.
    ///
    private static func lifecycleRows(_ constraints: Constraints, on database: any Database) async throws -> [HourRow] {
        var rows: [HourRow] = []
        for type in lifecycleTypes where constraints.name == nil || constraints.name == type {
            rows += try await countRows(recordType: type, named: type, constraints: constraints, on: database)
        }
        if constraints.name == nil || constraints.name == versionCrashName {
            rows += try await firstCrashRows(constraints, on: database)
        }
        return rows
    }

    /// Hourly double rows: `DoubleMetric` value sums. Only the metric-bearing
    /// sources carry them; an explicit event or lifecycle source has none.
    ///
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

    /// The newest value in each hour, per metric name and telemetry category —
    /// the gauge counterpart of `sumRows`. Rows without a date carry no
    /// ordering, so they cannot be "latest" and are skipped.
    ///
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

    /// Folds the hourly rows into the requested granularity, keyed by name,
    /// category, bucket start, and — when `byVersion` — app version. A `sum`
    /// reduce accumulates; a `last` reduce keeps the value of the newest hour
    /// in each bucket.
    ///
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

    /// The buckets of one group as wire points, sorted by date. A `sum` reduce
    /// drops empty buckets so a year-wide category stays compact; a `last`
    /// reduce keeps zeros, since zero is a legitimate gauge reading.
    ///
    private static func points<T: AdditiveArithmetic & Equatable>(_ totals: [Date: T], reduce: Reduce, value: (T) -> FieldValue) -> [MetricSeriesPoint] {
        totals
            .filter { reduce == .last || $0.value != .zero }
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
