//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Vapor

/// Flat, pre-aggregated value-per-bucket series — the time-axis counterpart of
/// the `DateIntMatrix` / `DateDoubleMatrix` grid, aggregated natively from raw
/// records. One `MetricSeries` per name, so a single request can carry a whole
/// category at once.
///
struct MetricSeriesResponse: Content, Equatable {
    let series: [MetricSeries]
}

/// One name's dense series over the requested range.
///
struct MetricSeries: Content, Equatable {
    let name: String
    let category: String?
    let points: [MetricSeriesPoint]
}

/// One bucket of a series: the aggregate `value` over the half-open window
/// starting at `date`.
///
/// `date` is milliseconds since the Unix epoch at the UTC bucket start. `value`
/// is `.int` for record counts and `IntMetric` sums, `.double` for
/// `DoubleMetric` sums. Empty buckets are still emitted (as a zero value) so
/// each series is dense and directly chartable.
///
struct MetricSeriesPoint: Content, Equatable {
    let date: Int64
    let value: FieldValue
}
