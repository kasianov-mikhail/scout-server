//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Foundation

extension UUID {
    static func v7(now: Date = Date()) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)

        let milliseconds = UInt64(now.timeIntervalSince1970 * 1000)
        for offset in 0..<6 {
            bytes[offset] = UInt8(truncatingIfNeeded: milliseconds >> (8 * (5 - offset)))
        }

        for offset in 6..<16 {
            bytes[offset] = UInt8.random(in: .min ... .max)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x70
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
