//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Vapor

/// A flat, dense value-per-bucket series for a single metric, event, or
/// lifecycle name — the time-axis counterpart of the `DateIntMatrix` /
/// `DateDoubleMatrix` grid, aggregated natively from raw records.
///
struct MetricSeriesResponse: Content, Equatable {
    let series: [MetricSeriesPoint]
}

/// One bucket of the series: the aggregate `value` over the half-open window
/// starting at `date`.
///
/// `date` is milliseconds since the Unix epoch at the UTC bucket start. `value`
/// is `.int` for record counts and `IntMetric` sums, `.double` for
/// `DoubleMetric` sums. Empty buckets are still emitted (as a zero value) so
/// the series is dense and directly chartable.
///
struct MetricSeriesPoint: Content, Equatable {
    let date: Int64
    let value: FieldValue
}
