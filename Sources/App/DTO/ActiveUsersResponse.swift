//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Vapor

/// The native active-user series an HTTP backend serves directly, without the
/// CloudKit `PeriodMatrix` forward-mark bookkeeping the client maintains by hand.
///
struct ActiveUsersResponse: Content, Equatable {
    let series: [ActiveUserPoint]
}

/// One day of the series: distinct active installs as of `date`, counted over
/// the trailing day (`dau`), 7 days (`wau`), and calendar month (`mau`).
///
/// `date` is milliseconds since the Unix epoch at UTC midnight, matching the
/// rest of the wire format.
///
struct ActiveUserPoint: Content, Equatable {
    let date: Int64
    let dau: Int
    let wau: Int
    let mau: Int
}
