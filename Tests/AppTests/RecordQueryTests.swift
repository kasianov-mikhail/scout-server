//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import XCTVapor

@testable import App

final class RecordQueryTests: XCTestCase {
    func testFiltersByEquality() async throws {
        try await withApp { app in
            try await write(
                [
                    makeEvent(name: "login", date: utcDate(2026, 6, 10, 9)),
                    makeEvent(name: "logout", date: utcDate(2026, 6, 10, 10)),
                ],
                to: app
            )

            let response = try await query(
                QueryRequest(
                    recordType: "Event",
                    filters: [QueryFilter(field: "name", op: .equals, value: .string("login"))]
                ),
                on: app
            )

            XCTAssertEqual(response.records.count, 1)
            XCTAssertEqual(response.records[0].fields["name"], .string("login"))
        }
    }

    func testFiltersByDateRangeAndInList() async throws {
        try await withApp { app in
            try await write(
                [
                    makeSession(start: utcDate(2026, 6, 1, 8), installID: "a"),
                    makeSession(start: utcDate(2026, 6, 5, 8), installID: "b"),
                    makeSession(start: utcDate(2026, 6, 9, 8), installID: "c"),
                ],
                to: app
            )

            let response = try await query(
                QueryRequest(
                    recordType: "Session",
                    filters: [
                        QueryFilter(field: "install_id", op: .in, value: .strings(["a", "b"])),
                        QueryFilter(field: "start_date", op: .greaterThan, value: .date(utcDate(2026, 6, 2))),
                    ]
                ),
                on: app
            )

            XCTAssertEqual(response.records.count, 1)
            XCTAssertEqual(response.records[0].fields["install_id"], .string("b"))
        }
    }

    func testFiltersByPrefix() async throws {
        try await withApp { app in
            try await write(
                [
                    makeEvent(name: "cart_add", date: utcDate(2026, 6, 10, 9)),
                    makeEvent(name: "cart_remove", date: utcDate(2026, 6, 10, 9)),
                    makeEvent(name: "login", date: utcDate(2026, 6, 10, 9)),
                ],
                to: app
            )

            let response = try await query(
                QueryRequest(
                    recordType: "Event",
                    filters: [QueryFilter(field: "name", op: .beginsWith, value: .string("cart_"))]
                ),
                on: app
            )

            XCTAssertEqual(response.records.count, 2)
        }
    }

    func testSortsAndLimitsWithDesiredFields() async throws {
        try await withApp { app in
            try await write(
                [
                    makeEvent(name: "first", date: utcDate(2026, 6, 10, 9)),
                    makeEvent(name: "second", date: utcDate(2026, 6, 10, 10)),
                    makeEvent(name: "third", date: utcDate(2026, 6, 10, 11)),
                ],
                to: app
            )

            let response = try await query(
                QueryRequest(
                    recordType: "Event",
                    sort: [QuerySort(field: "date", ascending: false)],
                    limit: 2,
                    fields: ["name"]
                ),
                on: app
            )

            XCTAssertEqual(response.records.map { $0.fields["name"] }, [.string("third"), .string("second")])
            XCTAssertEqual(response.records[0].fields.keys.sorted(), ["name"])
            XCTAssertNotNil(response.cursor)
        }
    }

    func testCursorWalksAllPages() async throws {
        try await withApp { app in
            let events = (0..<7).map { hour in
                makeEvent(name: "tick", date: utcDate(2026, 6, 10, 9, hour))
            }
            try await write(events, to: app)

            var collected: [Record] = []
            var request = QueryRequest(recordType: "Event", sort: [QuerySort(field: "date")], limit: 3)

            for _ in 0..<5 {
                let response = try await query(request, on: app)
                collected += response.records
                guard let cursor = response.cursor else {
                    break
                }
                request = QueryRequest(cursor: cursor)
            }

            XCTAssertEqual(collected.count, 7)
            XCTAssertEqual(Set(collected.map(\.recordID)).count, 7)
        }
    }

    func testCursorIsStableWhenSortKeysTie() async throws {
        try await withApp { app in
            let sameInstant = utcDate(2026, 6, 10, 9)
            let events = (0..<10).map { _ in makeEvent(name: "tick", date: sameInstant) }
            try await write(events, to: app)

            var collected: [Record] = []
            var request = QueryRequest(recordType: "Event", sort: [QuerySort(field: "date")], limit: 3)

            for _ in 0..<10 {
                let response = try await query(request, on: app)
                collected += response.records
                guard let cursor = response.cursor else {
                    break
                }
                request = QueryRequest(cursor: cursor)
            }

            XCTAssertEqual(collected.count, 10)
            XCTAssertEqual(Set(collected.map(\.recordID)).count, 10)
        }
    }

    func testRejectsUnknownFilterField() async throws {
        try await withApp { app in
            try await app.test(
                .POST, "api/v1/records/query",
                headers: .authorized,
                beforeRequest: { req in
                    try req.content.encode(
                        QueryRequest(
                            recordType: "Event",
                            filters: [QueryFilter(field: "payload", op: .equals, value: .string("x"))]
                        )
                    )
                },
                afterResponse: { res async in
                    XCTAssertEqual(res.status, .badRequest)
                }
            )
        }
    }

    func testQueryDoesNotLeakAcrossRecordTypes() async throws {
        try await withApp { app in
            try await write(
                [
                    makeEvent(name: "login", date: utcDate(2026, 6, 10, 9)),
                    makeSession(start: utcDate(2026, 6, 10, 9), installID: "a"),
                ],
                to: app
            )

            let response = try await query(QueryRequest(recordType: "Session"), on: app)
            XCTAssertEqual(response.records.map(\.recordType), ["Session"])
        }
    }
}
