//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import XCTVapor

@testable import App

/// Scout's calendar is ISO 8601 with `firstWeekday = 1` in UTC, so weeks
/// run Sunday through Saturday and `weekday` is 1 for Sunday. 2026-06-10
/// is a Wednesday: weekday 4, week start Sunday 2026-06-07.
///
final class MatrixAggregationTests: XCTestCase {
    let wednesday = utcDate(2026, 6, 10, 9, 15)
    let weekStart = utcDate(2026, 6, 7)

    func testEventCountsBecomeIntMatrix() async throws {
        try await withApp { app in
            try await write(
                [
                    makeEvent(name: "login", date: utcDate(2026, 6, 10, 9, 5)),
                    makeEvent(name: "login", date: utcDate(2026, 6, 10, 9, 55)),
                    makeEvent(name: "login", date: utcDate(2026, 6, 10, 10, 0)),
                    makeEvent(name: "logout", date: utcDate(2026, 6, 10, 9, 30)),
                ],
                to: app
            )

            let response = try await query(
                QueryRequest(
                    recordType: "DateIntMatrix",
                    filters: [QueryFilter(field: "name", op: .equals, value: .string("login"))]
                ),
                on: app
            )

            XCTAssertEqual(response.records.count, 1)
            let matrix = response.records[0]
            XCTAssertEqual(matrix.fields["name"], .string("login"))
            XCTAssertEqual(matrix.fields["date"], .date(weekStart))
            XCTAssertEqual(matrix.fields["cell_4_09"], .int(2))
            XCTAssertEqual(matrix.fields["cell_4_10"], .int(1))
            XCTAssertNil(matrix.fields["cell_4_11"])
            XCTAssertNil(response.cursor)
        }
    }

    func testLifecycleCountsAppearUnderRecordTypeName() async throws {
        try await withApp { app in
            try await write(
                [
                    makeSession(start: utcDate(2026, 6, 10, 9), installID: "a"),
                    makeSession(start: utcDate(2026, 6, 10, 9, 20), installID: "b"),
                ],
                to: app
            )

            let response = try await query(
                QueryRequest(
                    recordType: "DateIntMatrix",
                    filters: [QueryFilter(field: "name", op: .equals, value: .string("Session"))]
                ),
                on: app
            )

            XCTAssertEqual(response.records.count, 1)
            XCTAssertEqual(response.records[0].fields["cell_4_09"], .int(2))
        }
    }

    func testUnfilteredIntMatrixSpansAllSources() async throws {
        try await withApp { app in
            try await write(
                [
                    makeEvent(name: "login", date: wednesday),
                    makeSession(start: wednesday, installID: "a"),
                    makeMetric(name: "requests", category: "counter", date: wednesday, value: .int(5)),
                ],
                to: app
            )

            let response = try await query(QueryRequest(recordType: "DateIntMatrix"), on: app)

            let names = Set(response.records.map { $0.fields["name"]?.stringValue })
            XCTAssertEqual(names, ["login", "Session", "requests"])
        }
    }

    func testMetricValuesAreSummedPerHourAndFilteredByCategory() async throws {
        try await withApp { app in
            try await write(
                [
                    makeMetric(name: "requests", category: "counter", date: utcDate(2026, 6, 10, 9, 1), value: .int(5)),
                    makeMetric(name: "requests", category: "counter", date: utcDate(2026, 6, 10, 9, 59), value: .int(7)),
                    makeMetric(name: "errors", category: "meter_increment", date: utcDate(2026, 6, 10, 9, 30), value: .int(1)),
                ],
                to: app
            )

            let response = try await query(
                QueryRequest(
                    recordType: "DateIntMatrix",
                    filters: [QueryFilter(field: "category", op: .equals, value: .string("counter"))]
                ),
                on: app
            )

            XCTAssertEqual(response.records.count, 1)
            let matrix = response.records[0]
            XCTAssertEqual(matrix.fields["name"], .string("requests"))
            XCTAssertEqual(matrix.fields["category"], .string("counter"))
            XCTAssertEqual(matrix.fields["cell_4_09"], .int(12))
        }
    }

    func testDoubleMatrixComesFromDoubleMetrics() async throws {
        try await withApp { app in
            try await write(
                [
                    makeMetric(type: "DoubleMetric", name: "duration", category: "timer", date: wednesday, value: .double(0.5)),
                    makeMetric(type: "DoubleMetric", name: "duration", category: "timer", date: wednesday, value: .double(1.25)),
                ],
                to: app
            )

            let response = try await query(QueryRequest(recordType: "DateDoubleMatrix"), on: app)

            XCTAssertEqual(response.records.count, 1)
            let matrix = response.records[0]
            XCTAssertEqual(matrix.fields["date"], .date(weekStart))
            XCTAssertEqual(matrix.fields["cell_4_09"], .double(1.75))
        }
    }

    func testDateRangeFilterCutsWholeWeeks() async throws {
        try await withApp { app in
            try await write(
                [
                    makeEvent(name: "login", date: utcDate(2026, 6, 3, 12)),
                    makeEvent(name: "login", date: utcDate(2026, 6, 10, 12)),
                ],
                to: app
            )

            let response = try await query(
                QueryRequest(
                    recordType: "DateIntMatrix",
                    filters: [
                        QueryFilter(field: "date", op: .greaterThanOrEquals, value: .date(weekStart)),
                        QueryFilter(field: "date", op: .lessThan, value: .date(utcDate(2026, 6, 14))),
                    ]
                ),
                on: app
            )

            XCTAssertEqual(response.records.count, 1)
            XCTAssertEqual(response.records[0].fields["date"], .date(weekStart))
        }
    }

    func testEventNamedLikeLifecycleTypeMergesIntoOneMatrix() async throws {
        try await withApp { app in
            try await write(
                [
                    makeSession(start: wednesday, installID: "a"),
                    makeEvent(name: "Session", date: wednesday),
                ],
                to: app
            )

            let response = try await query(
                QueryRequest(
                    recordType: "DateIntMatrix",
                    filters: [QueryFilter(field: "name", op: .equals, value: .string("Session"))]
                ),
                on: app
            )

            XCTAssertEqual(response.records.count, 1)
            XCTAssertEqual(response.records[0].fields["cell_4_09"], .int(2))
        }
    }
}
