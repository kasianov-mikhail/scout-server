//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Fluent
import Vapor

/// Computes a flat, dense value-per-bucket series for one name.
///
/// The same raw records that feed the `DateIntMatrix` / `DateDoubleMatrix`
/// grid also feed this series — record counts for lifecycle and event names,
/// `IntMetric` / `DoubleMetric` value sums for metric names — but folded onto
/// a single time axis instead of a weekday-by-hour grid. The hourly buckets
/// `MatrixService` already produces are rolled up into the requested
/// granularity and zero-filled across the range, giving a directly chartable
/// series like `GET /api/v1/metrics/active-users`.
///
enum MetricSeriesService {
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

    /// One dense point per `bucket` over the half-open `[from, to)` range. The
    /// range snaps down to the bucket start containing `from`, so the first
    /// bucket is whole; values are `.int` for counts and `IntMetric` sums,
    /// `.double` for `DoubleMetric` sums. When a name carries both (an unusual
    /// collision), the integer side wins, matching `DateIntMatrix` precedence.
    ///
    static func series(name: String, category: String?, bucket: Bucket, from: Date, to: Date, on database: any Database) async throws -> [MetricSeriesPoint] {
        let start = bucket.start(of: from)

        var constraints = MatrixConstraints(dateRange: start..<to)
        constraints.name = name
        constraints.category = category

        // The hourly buckets over-fetch a week past `to` for grid alignment,
        // so drop anything at or after the range's upper bound here.
        let upper = Int64(to.timeIntervalSince1970)
        let ints = try await MatrixService.intBuckets(constraints, on: database)
        let doubles = try await MatrixService.doubleBuckets(constraints, on: database)

        let intTotals = fold(ints, before: upper, bucket: bucket) { $0.totalInt ?? 0 }
        let doubleTotals = fold(doubles, before: upper, bucket: bucket) { $0.totalDouble ?? 0 }

        let useDouble = intTotals.isEmpty && !doubleTotals.isEmpty

        var points: [MetricSeriesPoint] = []
        var cursor = start
        while cursor < to {
            let value: FieldValue =
                useDouble
                ? .double(doubleTotals[cursor] ?? 0)
                : .int(intTotals[cursor] ?? 0)
            points.append(
                MetricSeriesPoint(date: Int64((cursor.timeIntervalSince1970 * 1000).rounded()), value: value)
            )
            cursor = Calendar.utc.date(byAdding: bucket.component, value: 1, to: cursor)!
        }

        return points
    }

    /// Sums the hourly buckets into the requested granularity, keyed by the
    /// bucket start, discarding hours at or after `before`.
    ///
    private static func fold<T: AdditiveArithmetic>(_ buckets: [MatrixBucket], before: Int64, bucket: Bucket, value: (MatrixBucket) -> T) -> [Date: T] {
        var totals: [Date: T] = [:]
        for row in buckets where row.hour < before {
            let key = bucket.start(of: Date(timeIntervalSince1970: Double(row.hour)))
            totals[key, default: .zero] += value(row)
        }
        return totals
    }
}
