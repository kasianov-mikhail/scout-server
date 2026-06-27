//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Fluent
import Vapor

/// Computes name-grouped, value-per-bucket series.
///
/// The same raw records that feed the `DateIntMatrix` / `DateDoubleMatrix`
/// grid also feed these series — record counts for lifecycle and event names,
/// `IntMetric` / `DoubleMetric` value sums for metric names — but folded onto
/// a single time axis instead of a weekday-by-hour grid. The hourly buckets
/// `MatrixService` already produces are rolled up into the requested
/// granularity and grouped by name, so one request can carry a whole telemetry
/// category.
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

    /// One group per name over the half-open `[from, to)` range, each a sparse
    /// list of `bucket`-aligned points. `name` and `category` narrow the result
    /// (the controller requires at least one); `values` picks the flavor —
    /// `int` for counts and `IntMetric` sums, `double` for `DoubleMetric` sums —
    /// and is inferred per name when omitted, the integer side winning a
    /// collision to match `DateIntMatrix` precedence.
    ///
    /// Empty buckets are dropped, so every point is a real observation and a
    /// year-wide category stays compact. The range snaps down to the bucket
    /// containing `from`, so the first bucket is whole.
    ///
    static func series(name: String?, category: String?, values: String?, bucket: Bucket, from: Date, to: Date, on database: any Database) async throws -> [MetricSeriesGroup] {
        let start = bucket.start(of: from)

        var constraints = MatrixConstraints(dateRange: start..<to)
        constraints.name = name
        constraints.category = category

        let upper = Int64(to.timeIntervalSince1970)

        var intTotals: [GroupKey: [Date: Int64]] = [:]
        if values != "double" {
            let buckets = try await MatrixService.intBuckets(constraints, on: database)
            intTotals = fold(buckets, before: upper, bucket: bucket) { $0.totalInt ?? 0 }
        }

        var doubleTotals: [GroupKey: [Date: Double]] = [:]
        if values != "int" {
            let buckets = try await MatrixService.doubleBuckets(constraints, on: database)
            doubleTotals = fold(buckets, before: upper, bucket: bucket) { $0.totalDouble ?? 0 }
        }

        var groups: [MetricSeriesGroup] = []

        for (key, totals) in intTotals {
            let points = sparsePoints(totals) { .int($0) }
            if points.count > 0 {
                groups.append(MetricSeriesGroup(name: key.name, category: key.category, points: points))
            }
        }

        for (key, totals) in doubleTotals {
            if values == nil, intTotals[key] != nil {
                continue
            }
            let points = sparsePoints(totals) { .double($0) }
            if points.count > 0 {
                groups.append(MetricSeriesGroup(name: key.name, category: key.category, points: points))
            }
        }

        return groups.sorted { ($0.name, $0.category ?? "") < ($1.name, $1.category ?? "") }
    }

    /// Sums the hourly buckets into the requested granularity, keyed by name,
    /// category, and bucket start, discarding hours at or after `before`.
    ///
    private static func fold<T: AdditiveArithmetic & Equatable>(_ buckets: [MatrixBucket], before: Int64, bucket: Bucket, value: (MatrixBucket) -> T) -> [GroupKey: [Date: T]] {
        var totals: [GroupKey: [Date: T]] = [:]
        for row in buckets where row.hour < before {
            guard let name = row.name else {
                continue
            }
            let key = GroupKey(name: name, category: row.category)
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

/// A (name, category) series identity.
private struct GroupKey: Hashable {
    let name: String
    let category: String?
}
