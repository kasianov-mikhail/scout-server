//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import XCTVapor

@testable import App

/// Guards the one calendar property the wire format depends on: weeks start
/// on Sunday.
///
/// `week` buckets and every retention cohort are keyed by `startOfWeek`, and
/// the client keys them the same way. A calendar that quietly refuses
/// `firstWeekday = 1` — which is what the `iso8601` identifier does on some
/// platforms — shifts every one of those keys by a day without failing
/// anything else, so the invariant is asserted rather than assumed.
///
final class DateBucketTests: XCTestCase {
    func testWeekStartsOnSunday() {
        XCTAssertEqual(Calendar.utc.firstWeekday, 1)

        // A midweek day whose week reaches back into the previous month, so a
        // Monday start would land on a different date and month.
        XCTAssertEqual(utcDate(2026, 6, 3).startOfWeek, utcDate(2026, 5, 31))
    }

    func testEveryWeekBucketIsTheSundayOnOrBeforeItsDay() {
        var day = utcDate(2024, 1, 1)
        let end = utcDate(2028, 1, 1)

        while day < end {
            let week = day.startOfWeek

            XCTAssertEqual(Calendar.utc.component(.weekday, from: week), 1, "\(week) is not a Sunday")
            XCTAssertLessThanOrEqual(week, day)
            XCTAssertLessThan(day.timeIntervalSince(week), 7 * 86_400)

            day = Calendar.utc.date(byAdding: .day, value: 1, to: day)!
        }
    }
}
