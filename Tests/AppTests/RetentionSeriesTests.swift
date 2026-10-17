//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import XCTVapor

@testable import App

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
                    makeSession(start: installDay.addingTimeInterval(3600), installID: "a"),
                    makeSession(start: utcDate(2026, 6, 2, 10), installID: "a"),
                    makeSession(start: utcDate(2026, 6, 8, 9), installID: "a"),
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

    func testMaturityRequiresFullCohortWeek() async throws {
        try await withApp { app in
            let installDay = utcDate(2026, 7, 20)

            try await write(
                [
                    makeInstall(date: installDay, installID: "a"),
                    makeSession(start: installDay.addingTimeInterval(3600), installID: "a"),
                ],
                to: app
            )

            let week = installDay.startOfWeek
            let from = utcDate(2026, 5, 1)

            let atBoundary = try await retention(from: from, to: week.addingTimeInterval(7 * 86_400), on: app)
            XCTAssertNil(retained(try XCTUnwrap(cohort(atBoundary, week: week)), offset: 0))

            let pastBoundary = try await retention(from: from, to: week.addingTimeInterval(7 * 86_400 + 1), on: app)
            XCTAssertEqual(retained(try XCTUnwrap(cohort(pastBoundary, week: week)), offset: 0), 1)
        }
    }

    func testSegmentsSplitByFirstSessionOSMajor() async throws {
        try await withApp { app in
            let installDay = utcDate(2026, 6, 1)

            try await write(
                [
                    makeInstall(date: installDay, installID: "a"),
                    makeInstall(date: installDay, installID: "b"),
                    makeInstall(date: installDay, installID: "c"),
                    makeInstall(date: installDay, installID: "d"),
                    makeSession(start: installDay.addingTimeInterval(3600), installID: "a", osVersion: "iOS 18.2"),
                    makeSession(start: utcDate(2026, 6, 2, 10), installID: "a", osVersion: "iOS 19.0"),
                    makeSession(start: installDay.addingTimeInterval(7200), installID: "b", osVersion: "iOS 18.1"),
                    makeSession(start: installDay.addingTimeInterval(7200), installID: "c", osVersion: "iOS 17.5"),
                    makeSession(start: installDay.addingTimeInterval(7200), installID: "d"),
                ],
                to: app
            )

            let cohorts = try await retention(from: utcDate(2026, 5, 1), to: utcDate(2026, 8, 1), on: app)
            let point = try XCTUnwrap(cohort(cohorts, week: installDay.startOfWeek))

            XCTAssertEqual(point.size, 4)
            XCTAssertEqual(point.segments.map(\.name), ["iOS 17", "iOS 18"])

            let recent = try XCTUnwrap(point.segments.first { $0.name == "iOS 18" })
            XCTAssertEqual(recent.size, 2)
            XCTAssertEqual(recent.retained.first, 2)
            XCTAssertEqual(recent.retained[1], 1)

            let older = try XCTUnwrap(point.segments.first { $0.name == "iOS 17" })
            XCTAssertEqual(older.size, 1)
            XCTAssertEqual(older.retained[1], 0)
        }
    }

    func testSegmentsCountInstallsAffectedByIncidents() async throws {
        try await withApp { app in
            let installDay = utcDate(2026, 6, 1)

            try await write(
                [
                    makeInstall(date: installDay, installID: "a"),
                    makeInstall(date: installDay, installID: "b"),
                    makeInstall(date: installDay, installID: "c"),
                    makeSession(start: installDay.addingTimeInterval(3600), installID: "a", osVersion: "iOS 18.2"),
                    makeSession(start: installDay.addingTimeInterval(3600), installID: "b", osVersion: "iOS 18.2"),
                    makeSession(start: installDay.addingTimeInterval(3600), installID: "c", osVersion: "iOS 18.2"),
                    makeCrash(date: utcDate(2026, 6, 3), installID: "a"),
                    makeCrash(date: utcDate(2026, 6, 20), installID: "a"),
                    makeHang(date: utcDate(2026, 7, 1, 23), installID: "a"),
                    makeCrash(date: utcDate(2026, 7, 2), installID: "b"),
                    makeHang(date: utcDate(2026, 6, 1, 5), installID: "c"),
                ],
                to: app
            )

            let cohorts = try await retention(from: utcDate(2026, 5, 1), to: utcDate(2026, 8, 1), on: app)
            let point = try XCTUnwrap(cohort(cohorts, week: installDay.startOfWeek))
            let segment = try XCTUnwrap(point.segments.first)

            XCTAssertEqual(segment.size, 3)
            XCTAssertEqual(segment.crashes, 1)
            XCTAssertEqual(segment.hangs, 2)
        }
    }

    func testSegmentMilestonesMatureWithTheCohort() async throws {
        try await withApp { app in
            let installDay = utcDate(2026, 7, 20)

            try await write(
                [
                    makeInstall(date: installDay, installID: "a"),
                    makeSession(start: installDay.addingTimeInterval(3600), installID: "a", osVersion: "iOS 18.2"),
                ],
                to: app
            )

            let cohorts = try await retention(from: utcDate(2026, 7, 1), to: utcDate(2026, 8, 1), on: app)
            let point = try XCTUnwrap(cohort(cohorts, week: installDay.startOfWeek))
            let segment = try XCTUnwrap(point.segments.first)

            XCTAssertEqual(segment.retained.map { $0 == nil }, point.retained.map { $0 == nil })
        }
    }

    func testMigrationBackfillsOSVersionOfStoredSessions() async throws {
        try await withApp { app in
            let installDay = utcDate(2026, 6, 1)

            try await write(
                [
                    makeInstall(date: installDay, installID: "a"),
                    makeSession(start: installDay.addingTimeInterval(3600), installID: "a", osVersion: "iOS 18.2"),
                ],
                to: app
            )

            try await AddOSVersionField().revert(on: app.db)
            try await AddOSVersionField().prepare(on: app.db)

            let cohorts = try await retention(from: utcDate(2026, 5, 1), to: utcDate(2026, 8, 1), on: app)
            let point = try XCTUnwrap(cohort(cohorts, week: installDay.startOfWeek))

            XCTAssertEqual(point.segments.map(\.name), ["iOS 18"])
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
