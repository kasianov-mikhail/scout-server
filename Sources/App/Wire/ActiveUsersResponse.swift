//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Vapor

struct ActiveUsersResponse: Content, Equatable {
    let series: [ActiveUserPoint]
}

struct ActiveUserPoint: Content, Equatable {
    let date: Int64
    let dau: Int
    let wau: Int
    let mau: Int
}
