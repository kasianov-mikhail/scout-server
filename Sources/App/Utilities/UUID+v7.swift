//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Foundation

extension UUID {
    /// Creates a version 7 UUID (RFC 9562): a 48-bit big-endian Unix
    /// millisecond timestamp followed by random bits.
    ///
    /// Where the random version 4 that `UUID()` produces scatters inserts
    /// across a primary-key index, the timestamp prefix makes successive
    /// values sort in creation order, so new rows land at the right edge of
    /// the B-tree. That keeps the hot pages packed and avoids the page splits
    /// and index bloat random keys cause once a table grows large. The trade
    /// is that the creation time is now readable from the id; `records` keeps
    /// `id` server-internal (the DTO never exposes it), so nothing leaks.
    ///
    /// `now` is injectable so tests can pin the timestamp; callers take the
    /// default.
    ///
    static func v7(now: Date = Date()) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)

        // Bytes 0–5: milliseconds since the Unix epoch, big-endian.
        let milliseconds = UInt64(now.timeIntervalSince1970 * 1000)
        for offset in 0..<6 {
            bytes[offset] = UInt8(truncatingIfNeeded: milliseconds >> (8 * (5 - offset)))
        }

        // Bytes 6–15: random, then stamp the version and variant bits.
        for offset in 6..<16 {
            bytes[offset] = UInt8.random(in: .min ... .max)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x70  // version 7 in the high nibble
        bytes[8] = (bytes[8] & 0x3F) | 0x80  // variant 0b10 in the high bits

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
