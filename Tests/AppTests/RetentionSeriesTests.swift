//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import XCTVapor

@testable import App

/// The native `/metrics/retention` table groups installs into weekly
/// acquisition cohorts and reports bounded day-N retention: for each milestone
/// in `RetentionService.dayOffsets`, how many of a cohort's installs were
/// active on exactly `install day + N`. Milestones that have not fully elapsed
/// for a cohort come back `nil`.
///
final class RetentionSeriesTests: XCTestCase {
    func cohort(_ cohorts: [RetentionCohortPoint], week: Date) -> RetentionCohortPoint? {
        let ms = Int64((week.timeIntervalSince1970 * 1000).rounded())
        return cohorts.first { $0.date == ms }
    }

    func retained(_ point: RetentionCohortPoint, offset: Int) -> Int? {
        guard let index = RetentionService.dayOffsets.firstIndex(of: offset) else {
            return nil
        }
        return point.retained[index]
    }

    func testBoundedDayNCounts() async throws {
        try await withApp { app in
            let installDay = utcDate(2026, 6, 1)

            try await write(
                [
                    makeInstall(date: installDay, installID: "a"),
                    makeInstall(date: installDay, installID: "b"),
                    // Install "a" returns on D0, D1, D7.
                    makeSession(start: installDay.addingTimeInterval(3600), installID: "a"),
                    makeSession(start: utcDate(2026, 6, 2, 10), installID: "a"),
                    makeSession(start: utcDate(2026, 6, 8, 9), installID: "a"),
                    // Install "b" only opens on D0.
                    makeSession(start: installDay.addingTimeInterval(7200), installID: "b"),
                ],
                to: app
            )

            let cohorts = try await retention(from: utcDate(2026, 5, 1), to: utcDate(2026, 8, 1), on: app)
            let week = installDay.startOfWeek
            let point = try XCTUnwrap(cohort(cohorts, week: week))

            XCTAssertEqual(point.size, 2)
            XCTAssertEqual(retained(point, offset: 0), 2)
            XCTAssertEqual(retained(point, offset: 1), 1)
            XCTAssertEqual(retained(point, offset: 3), 0)
            XCTAssertEqual(retained(point, offset: 7), 1)
            XCTAssertEqual(retained(point, offset: 30), 0)
        }
    }

    func testInstallWithoutActivityStillCountsInSize() async throws {
        try await withApp { app in
            let installDay = utcDate(2026, 6, 1)

            try await write(
                [
                    makeInstall(date: installDay, installID: "a"),
                    makeSession(start: installDay.addingTimeInterval(3600), installID: "a"),
                    // Install "b" never opens the app again.
                    makeInstall(date: installDay, installID: "b"),
                ],
                to: app
            )

            let cohorts = try await retention(from: utcDate(2026, 5, 1), to: utcDate(2026, 8, 1), on: app)
            let point = try XCTUnwrap(cohort(cohorts, week: installDay.startOfWeek))

            XCTAssertEqual(point.size, 2)
            XCTAssertEqual(retained(point, offset: 0), 1)
        }
    }

    func testImmatureMilestonesAreNil() async throws {
        try await withApp { app in
            let installDay = utcDate(2026, 7, 20)

            try await write(
                [
                    makeInstall(date: installDay, installID: "a"),
                    makeSession(start: installDay.addingTimeInterval(3600), installID: "a"),
                ],
                to: app
            )

            let cohorts = try await retention(from: utcDate(2026, 7, 1), to: utcDate(2026, 8, 1), on: app)
            let point = try XCTUnwrap(cohort(cohorts, week: installDay.startOfWeek))

            XCTAssertEqual(retained(point, offset: 0), 1)
            XCTAssertNil(retained(point, offset: 30))
        }
    }

    func testEmptyRangeIsRejected() async throws {
        try await withApp { app in
            let to = utcDate(2026, 6, 1)
            let ms = Int64((to.timeIntervalSince1970 * 1000).rounded())
            try await app.test(
                .GET, "api/v1/metrics/retention?from=\(ms)&to=\(ms)",
                headers: .authorized,
                afterResponse: { res async in
                    XCTAssertEqual(res.status, .badRequest)
                }
            )
        }
    }
}
