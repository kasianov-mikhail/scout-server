//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Vapor

/// A name-grouped, value-per-bucket series — the time-axis counterpart of the
/// `DateIntMatrix` / `DateDoubleMatrix` grid, aggregated natively from raw
/// records. One `MetricSeriesGroup` per metric, event, or lifecycle name, so a
/// single request can carry a whole telemetry category.
///
struct MetricSeriesResponse: Content, Equatable {
    let series: [MetricSeriesGroup]
}

/// One name's series over the requested range.
///
struct MetricSeriesGroup: Content, Equatable {
    let name: String
    let category: String?
    let points: [MetricSeriesPoint]
}

/// One bucket of a series: the aggregate `value` over the half-open window
/// starting at `date`.
///
/// `date` is milliseconds since the Unix epoch at the UTC bucket start. `value`
/// is `.int` for record counts and `IntMetric` sums, `.double` for
/// `DoubleMetric` sums. Empty buckets are omitted, so the series is sparse:
/// every point is a real, non-zero observation.
///
struct MetricSeriesPoint: Content, Equatable {
    let date: Int64
    let value: FieldValue
}
