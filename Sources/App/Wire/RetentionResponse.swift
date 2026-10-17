//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Vapor

struct RetentionResponse: Content, Equatable {
    let cohorts: [RetentionCohortPoint]
}

struct RetentionCohortPoint: Content, Equatable {
    let date: Int64
    let size: Int
    let retained: [Int?]
}
