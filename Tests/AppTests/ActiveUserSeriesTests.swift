//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import XCTVapor

@testable import App

/// The native `/metrics/active-users` series is the flat DAU/WAU/MAU shape
/// the server serves directly. Each point is an as-of trailing distinct-device
/// count over the 1, 7, and 30 days ending that UTC day, with zero-activity
/// days included.
///
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
            // May 25 plus the 29 following days is June 23, the last day the
            // 30-day window still holds that session.
            XCTAssertEqual(point(series, utcDate(2026, 6, 23))?.mau, 1)
            XCTAssertEqual(point(series, utcDate(2026, 6, 24))?.mau, 0)
        }
    }

    /// The monthly window is a fixed 30 days, as on the client. A calendar
    /// month would run 31 days out of January and 28 out of February, so the
    /// same activity would age differently depending on when it happened.
    ///
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

    /// A `Visit` is the marker the client writes once per device per day
    /// precisely to signal activity, so it counts on its own — a device that
    /// produced one but no session is still active.
    ///
    func testVisitMarkerCountsAsActivity() async throws {
        try await withApp { app in
            try await write([makeVisit(date: utcDate(2026, 6, 10, 9), deviceID: "a")], to: app)

            let series = try await activeUsers(from: utcDate(2026, 6, 1), to: utcDate(2026, 7, 1), on: app)

            XCTAssertEqual(point(series, utcDate(2026, 6, 10))?.dau, 1)
            XCTAssertEqual(point(series, utcDate(2026, 6, 11))?.wau, 1)
        }
    }

    /// The two sources describe the same device on the same day, so it counts
    /// once rather than twice.
    ///
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

    /// Users are counted per device, so reinstalling — a second install id on
    /// the same device — stays one active user.
    ///
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
