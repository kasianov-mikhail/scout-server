//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Vapor

struct IncidentsResponse: Content, Equatable {
    let tallies: [IncidentTally]
    let unkeyed: IncidentRange?
}

struct IncidentTally: Content, Equatable {
    let fingerprint: String
    let name: String
    let count: Int
    let firstHour: Int64
}

struct IncidentRange: Content, Equatable {
    let from: Int64
    let to: Int64
}

extension IncidentRange {
    init(range: Range<Date>) {
        self.init(from: range.lowerBound.milliseconds, to: range.upperBound.milliseconds)
    }
}
