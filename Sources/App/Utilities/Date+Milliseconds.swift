//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Foundation

private let maxMilliseconds: Int64 = 8_640_000_000_000_000

extension Date {
    init?(milliseconds: Int64) {
        guard (-maxMilliseconds...maxMilliseconds).contains(milliseconds) else {
            return nil
        }
        self.init(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    var milliseconds: Int64 {
        Int64((timeIntervalSince1970 * 1000).rounded())
    }
}
