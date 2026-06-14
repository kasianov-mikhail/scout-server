//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Fluent
import Vapor

/// Computes flat, dense value-per-bucket series grouped by name.
///
/// The same raw records that feed the `DateIntMatrix` / `DateDoubleMatrix`
/// grid feed this — record counts for lifecycle and event names, `IntMetric` /
/// `DoubleMetric` value sums for metric names — but folded onto a single time
/// axis instead of a weekday-by-hour grid. The hourly buckets `MatrixService`
/// already produces are grouped by name, rolled up into the requested
/// granularity, and zero-filled across the range, giving directly chartable
/// series like `GET /api/v1/metrics/active-users`.
///
enum MetricSeriesService {
    /// Which value flavor to serve, mirroring the `DateIntMatrix` /
    /// `DateDoubleMatrix` split.
    ///
    enum Flavor: String {
        case int
        case double
    }

    /// The granularity of a series point. `week` starts on Sunday, matching
    /// the rest of the date bucketing.
    ///
    enum Bucket: String {
        case hour
        case day
        case week

        var component: Calendar.Component {
            switch self {
            case .hour: .hour
            case .day: .day
            case .week: .weekOfYear
            }
        }

        func start(of date: Date) -> Date {
            switch self {
            case .hour: date.startOfHour
            case .day: date.startOfDay
            case .week: date.startOfWeek
            }
        }
    }

    /// One `MetricSeries` per name matching the `name` / `category` filters,
    /// each a dense point-per-bucket series over the half-open `[from, to)`
    /// range. The range snaps down to the bucket containing `from`, so the
    /// first bucket is whole. `values` forces the flavor; when omitted it is
    /// inferred, with integer counts/sums taking precedence (matching
    /// `DateIntMatrix`).
    ///
    static func series(name: String?, category: String?, values: Flavor?, bucket: Bucket, from: Date, to: Date, on database: any Database) async throws -> [MetricSeries] {
        let start = bucket.start(of: from)

        var constraints = MatrixConstraints(dateRange: start..<to)
        constraints.name = name
        constraints.category = category

        // The hourly buckets over-fetch a week past `to` for grid alignment,
        // so drop anything at or after the range's upper bound here.
        let upper = Int64(to.timeIntervalSince1970)
        let (flavor, buckets) = try await resolve(values, constraints: constraints, before: upper, on: database)

        var grouped: [GroupKey: [MatrixBucket]] = [:]
        for row in buckets where row.hour < upper {
            guard let name = row.name else { continue }
            grouped[GroupKey(name: name, category: row.category), default: []].append(row)
        }

        return
            grouped
            .map { key, rows in
                MetricSeries(
                    name: key.name,
                    category: key.category,
                    points: densePoints(rows, flavor: flavor, bucket: bucket, from: start, to: to)
                )
            }
            .sorted { ($0.name, $0.category ?? "") < ($1.name, $1.category ?? "") }
    }

    private struct GroupKey: Hashable {
        let name: String
        let category: String?
    }

    /// Picks the value flavor and the buckets that back it. An explicit
    /// `values` wins; otherwise integer sources are tried first and the double
    /// side is read only when they carry nothing in range.
    ///
    private static func resolve(_ values: Flavor?, constraints: MatrixConstraints, before upper: Int64, on database: any Database) async throws -> (Flavor, [MatrixBucket]) {
        switch values {
        case .int:
            return (.int, try await MatrixService.intBuckets(constraints, on: database))
        case .double:
            return (.double, try await MatrixService.doubleBuckets(constraints, on: database))
        case nil:
            let ints = try await MatrixService.intBuckets(constraints, on: database)
            if ints.contains(where: { $0.hour < upper }) {
                return (.int, ints)
            }
            return (.double, try await MatrixService.doubleBuckets(constraints, on: database))
        }
    }

    /// Folds one name's hourly buckets into the requested granularity and
    /// zero-fills every bucket across the range.
    ///
    private static func densePoints(_ rows: [MatrixBucket], flavor: Flavor, bucket: Bucket, from start: Date, to: Date) -> [MetricSeriesPoint] {
        var ints: [Date: Int64] = [:]
        var doubles: [Date: Double] = [:]
        for row in rows {
            let key = bucket.start(of: Date(timeIntervalSince1970: Double(row.hour)))
            switch flavor {
            case .int: ints[key, default: 0] += row.totalInt ?? 0
            case .double: doubles[key, default: 0] += row.totalDouble ?? 0
            }
        }

        var points: [MetricSeriesPoint] = []
        var cursor = start
        while cursor < to {
            let value: FieldValue =
                flavor == .int ? .int(ints[cursor] ?? 0) : .double(doubles[cursor] ?? 0)
            points.append(
                MetricSeriesPoint(date: Int64((cursor.timeIntervalSince1970 * 1000).rounded()), value: value)
            )
            cursor = Calendar.utc.date(byAdding: bucket.component, value: 1, to: cursor)!
        }
        return points
    }
}
