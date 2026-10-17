//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import XCTVapor

@testable import App

final class DateBucketTests: XCTestCase {
    func testWeekStartsOnSunday() {
        XCTAssertEqual(Calendar.utc.firstWeekday, 1)

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
