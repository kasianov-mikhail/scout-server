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

    func testFiltersIncidentsByFingerprint() async throws {
        try await withApp { app in
            try await write(
                [
                    makeCrash(fingerprint: "f1", date: utcDate(2026, 6, 10, 9)),
                    makeCrash(fingerprint: "f2", date: utcDate(2026, 6, 10, 10)),
                    makeCrash(fingerprint: "f3", date: utcDate(2026, 6, 10, 11)),
                ],
                to: app
            )

            let response = try await query(
                QueryRequest(
                    recordType: "Crash",
                    filters: [QueryFilter(field: "fingerprint", op: .in, value: .strings(["f1", "f2"]))],
                    sort: [QuerySort(field: "date", ascending: true)]
                ),
                on: app
            )

            XCTAssertEqual(response.records.map { $0.fields["fingerprint"] }, [.string("f1"), .string("f2")])
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

    func testPrefixMatchesWildcardCharactersLiterally() async throws {
        try await withApp { app in
            try await write(
                [
                    makeEvent(name: "cart_add", date: utcDate(2026, 6, 10, 9)),
                    makeEvent(name: "cartXadd", date: utcDate(2026, 6, 10, 9)),
                    makeEvent(name: "100%_done", date: utcDate(2026, 6, 10, 9)),
                    makeEvent(name: "1000", date: utcDate(2026, 6, 10, 9)),
                ],
                to: app
            )

            let underscore = try await query(
                QueryRequest(
                    recordType: "Event",
                    filters: [QueryFilter(field: "name", op: .beginsWith, value: .string("cart_"))]
                ),
                on: app
            )
            XCTAssertEqual(underscore.records.compactMap { $0.fields["name"]?.stringValue }, ["cart_add"])

            let percent = try await query(
                QueryRequest(
                    recordType: "Event",
                    filters: [QueryFilter(field: "name", op: .beginsWith, value: .string("100%"))]
                ),
                on: app
            )
            XCTAssertEqual(percent.records.compactMap { $0.fields["name"]?.stringValue }, ["100%_done"])
        }
    }

    func testPrefixIsCaseSensitive() async throws {
        try await withApp { app in
            try await write(
                [
                    makeEvent(name: "Login", date: utcDate(2026, 6, 10, 9)),
                    makeEvent(name: "login", date: utcDate(2026, 6, 10, 9)),
                ],
                to: app
            )

            let response = try await query(
                QueryRequest(
                    recordType: "Event",
                    filters: [QueryFilter(field: "name", op: .beginsWith, value: .string("log"))]
                ),
                on: app
            )

            XCTAssertEqual(response.records.compactMap { $0.fields["name"]?.stringValue }, ["login"])
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

    func testCursorWithHugeOffsetReturnsEmptyPage() async throws {
        try await withApp { app in
            try await write([makeEvent(name: "login", date: utcDate(2026, 6, 10, 9))], to: app)

            let cursor = QueryCursor(query: QueryRequest(recordType: "Event"), offset: .max)
            let response = try await query(QueryRequest(cursor: cursor.token), on: app)

            XCTAssertEqual(response.records, [])
            XCTAssertNil(response.cursor)
        }
    }

    func testRejectsCursorWithNegativeOffset() async throws {
        try await withApp { app in
            let cursor = QueryCursor(query: QueryRequest(recordType: "Event"), offset: -1)
            try await app.test(
                .POST, "api/v1/records/query",
                headers: .authorized,
                beforeRequest: { req in
                    try req.content.encode(QueryRequest(cursor: cursor.token))
                },
                afterResponse: { res async in
                    XCTAssertEqual(res.status, .badRequest)
                }
            )
        }
    }

    func testRejectsDateFilterOutOfRange() async throws {
        try await withApp { app in
            try await app.test(
                .POST, "api/v1/records/query",
                headers: .authorized,
                beforeRequest: { req in
                    req.body = ByteBuffer(string: #"{"recordType":"Event","filters":[{"field":"date","op":"lessThan","value":{"date":9223372036854775807}}]}"#)
                },
                afterResponse: { res async in
                    XCTAssertEqual(res.status, .badRequest)
                }
            )
        }
    }

    func testFiltersByDateAtRangeLimit() async throws {
        try await withApp { app in
            try await write([makeEvent(name: "login", date: utcDate(2026, 6, 10, 9))], to: app)

            let response = try await query(
                QueryRequest(
                    recordType: "Event",
                    filters: [QueryFilter(field: "date", op: .lessThan, value: .date(Date(milliseconds: 8_640_000_000_000_000)!))]
                ),
                on: app
            )

            XCTAssertEqual(response.records.count, 1)
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

private func makeCrash(fingerprint: String, date: Date) -> Record {
    var record = makeCrash(date: date)
    record.fields["fingerprint"] = .string(fingerprint)
    return record
}
