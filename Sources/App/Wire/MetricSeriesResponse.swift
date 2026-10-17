//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Vapor

struct MetricSeriesResponse: Content, Equatable {
    let series: [MetricSeriesGroup]
}

struct MetricSeriesGroup: Content, Equatable {
    let name: String
    let category: String?
    let version: String?
    let points: [MetricSeriesPoint]
}

struct MetricSeriesPoint: Content, Equatable {
    let date: Int64
    let value: FieldValue
}
