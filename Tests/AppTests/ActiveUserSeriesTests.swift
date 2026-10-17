//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import XCTVapor

@testable import App

final class ActiveUserSeriesTests: XCTestCase {
    func point(_ series: [ActiveUserPoint], _ date: Date) -> ActiveUserPoint? {
        let ms = Int64((date.timeIntervalSince1970 * 1000).rounded())
        return series.first { $0.date == ms }
    }

    func testDailyWeeklyMonthlyCounts() async throws {
        try await withApp { app in
            try await write(
                [
                    makeSession(start: utcDate(2026, 6, 10, 9), installID: "a"),
                    makeSession(start: utcDate(2026, 6, 10, 20), installID: "a"),
                    makeSession(start: utcDate(2026, 6, 10, 11), installID: "b"),
                    makeSession(start: utcDate(2026, 6, 11, 8), installID: "a"),
                ],
                to: app
            )

            let series = try await activeUsers(from: utcDate(2026, 6, 1), to: utcDate(2026, 7, 1), on: app)

            XCTAssertEqual(series.count, 30)

            XCTAssertEqual(point(series, utcDate(2026, 6, 10))?.dau, 2)
            XCTAssertEqual(point(series, utcDate(2026, 6, 11))?.dau, 1)
            XCTAssertEqual(point(series, utcDate(2026, 6, 12))?.dau, 0)

            XCTAssertEqual(point(series, utcDate(2026, 6, 10))?.wau, 2)
            XCTAssertEqual(point(series, utcDate(2026, 6, 16))?.wau, 2)
            XCTAssertEqual(point(series, utcDate(2026, 6, 17))?.wau, 1)
            XCTAssertEqual(point(series, utcDate(2026, 6, 18))?.wau, 0)

            XCTAssertEqual(point(series, utcDate(2026, 6, 10))?.mau, 2)
            XCTAssertEqual(point(series, utcDate(2026, 6, 30))?.mau, 2)
        }
    }

    func testActivityFromPreviousMonthReachesIntoRange() async throws {
        try await withApp { app in
            try await write(
                [makeSession(start: utcDate(2026, 5, 25, 12), installID: "a")],
                to: app
            )

            let series = try await activeUsers(from: utcDate(2026, 6, 1), to: utcDate(2026, 7, 1), on: app)

            XCTAssertEqual(point(series, utcDate(2026, 6, 1))?.dau, 0)
            XCTAssertEqual(point(series, utcDate(2026, 6, 1))?.wau, 0)
            XCTAssertEqual(point(series, utcDate(2026, 6, 23))?.mau, 1)
            XCTAssertEqual(point(series, utcDate(2026, 6, 24))?.mau, 0)
        }
    }

    func testMonthlyWindowIsThirtyDaysWhateverTheMonth() async throws {
        try await withApp { app in
            try await write(
                [
                    makeSession(start: utcDate(2026, 1, 1, 9), installID: "a"),
                    makeSession(start: utcDate(2026, 2, 1, 9), installID: "b"),
                ],
                to: app
            )

            let series = try await activeUsers(from: utcDate(2026, 1, 1), to: utcDate(2026, 4, 1), on: app)

            XCTAssertEqual(point(series, utcDate(2026, 1, 30))?.mau, 1)
            XCTAssertEqual(point(series, utcDate(2026, 1, 31))?.mau, 0)

            XCTAssertEqual(point(series, utcDate(2026, 3, 2))?.mau, 1)
            XCTAssertEqual(point(series, utcDate(2026, 3, 3))?.mau, 0)
        }
    }

    func testVisitMarkerCountsAsActivity() async throws {
        try await withApp { app in
            try await write([makeVisit(date: utcDate(2026, 6, 10, 9), deviceID: "a")], to: app)

            let series = try await activeUsers(from: utcDate(2026, 6, 1), to: utcDate(2026, 7, 1), on: app)

            XCTAssertEqual(point(series, utcDate(2026, 6, 10))?.dau, 1)
            XCTAssertEqual(point(series, utcDate(2026, 6, 11))?.wau, 1)
        }
    }

    func testVisitAndSessionOfOneDeviceCountOnce() async throws {
        try await withApp { app in
            try await write(
                [
                    makeVisit(date: utcDate(2026, 6, 10, 9), deviceID: "a"),
                    makeSession(start: utcDate(2026, 6, 10, 20), installID: "install-1", deviceID: "a"),
                ],
                to: app
            )

            let series = try await activeUsers(from: utcDate(2026, 6, 1), to: utcDate(2026, 7, 1), on: app)

            XCTAssertEqual(point(series, utcDate(2026, 6, 10))?.dau, 1)
        }
    }

    func testReinstallOnOneDeviceIsOneUser() async throws {
        try await withApp { app in
            try await write(
                [
                    makeSession(start: utcDate(2026, 6, 10, 9), installID: "install-1", deviceID: "a"),
                    makeSession(start: utcDate(2026, 6, 10, 20), installID: "install-2", deviceID: "a"),
                ],
                to: app
            )

            let series = try await activeUsers(from: utcDate(2026, 6, 1), to: utcDate(2026, 7, 1), on: app)

            XCTAssertEqual(point(series, utcDate(2026, 6, 10))?.dau, 1)
        }
    }

    func testEmptyRangeIsRejected() async throws {
        try await withApp { app in
            let to = utcDate(2026, 6, 1)
            let ms = Int64((to.timeIntervalSince1970 * 1000).rounded())
            try await app.test(
                .GET, "api/v1/metrics/active-users?from=\(ms)&to=\(ms)",
                headers: .authorized,
                afterResponse: { res async in
                    XCTAssertEqual(res.status, .badRequest)
                }
            )
        }
    }
}
