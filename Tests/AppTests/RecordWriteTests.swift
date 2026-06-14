//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import XCTVapor

@testable import App

final class RecordWriteTests: XCTestCase {
    func testRejectsMissingAPIKey() async throws {
        try await withApp { app in
            try await app.test(.POST, "api/v1/records") { res async in
                XCTAssertEqual(res.status, .unauthorized)
            }
            try await app.test(.GET, "healthz") { res async in
                XCTAssertEqual(res.status, .ok)
            }
        }
    }

    func testAcceptsBearerToken() async throws {
        try await withApp { app in
            var headers = HTTPHeaders()
            headers.bearerAuthorization = BearerAuthorization(token: testAPIKey)
            headers.contentType = .json

            try await app.test(
                .POST, "api/v1/records/query",
                headers: headers,
                beforeRequest: { req in
                    try req.content.encode(QueryRequest(recordType: "Event"))
                },
                afterResponse: { res async in
                    XCTAssertEqual(res.status, .ok)
                }
            )
        }
    }

    func testWriteAndLookup() async throws {
        try await withApp { app in
            let date = utcDate(2026, 6, 10, 14, 30)
            let event = makeEvent(name: "login", date: date)
            try await write([event], to: app)

            try await app.test(.GET, "api/v1/records/\(event.recordName)", headers: .authorized) { res async throws in
                XCTAssertEqual(res.status, .ok)
                let fetched = try res.content.decode(Record.self)
                XCTAssertEqual(fetched, event)
            }
        }
    }

    func testLookupHonorsDesiredFields() async throws {
        try await withApp { app in
            let event = makeEvent(name: "login", date: utcDate(2026, 6, 10))
            try await write([event], to: app)

            try await app.test(
                .GET, "api/v1/records/\(event.recordName)?fields=name,level", headers: .authorized
            ) { res async throws in
                let fetched = try res.content.decode(Record.self)
                XCTAssertEqual(Set(fetched.fields.keys), ["name", "level"])
            }
        }
    }

    func testLookupUnknownRecordReturns404() async throws {
        try await withApp { app in
            try await app.test(.GET, "api/v1/records/missing", headers: .authorized) { res async in
                XCTAssertEqual(res.status, .notFound)
            }
        }
    }

    func testRecordNameIsGlobalIdentityAcrossTypes() async throws {
        try await withApp { app in
            // The unique constraint is on `record_name` alone, mirroring a
            // CloudKit record name: reusing a name under a different type
            // updates the existing record in place — it keeps its original
            // type and takes the new fields — rather than creating a second
            // row. This pins that intent so the global scope stays a deliberate
            // choice, not something a later change can quietly undo.
            let name = "shared-id"
            try await write([makeRecord(type: "Alpha", name: name, fields: ["level": .string("info")])], to: app)
            try await write([makeRecord(type: "Beta", name: name, fields: ["level": .string("warn")])], to: app)

            try await app.test(.GET, "api/v1/records/\(name)", headers: .authorized) { res async throws in
                XCTAssertEqual(res.status, .ok)
                let fetched = try res.content.decode(Record.self)
                XCTAssertEqual(fetched.recordType, "Alpha")
                XCTAssertEqual(fetched.fields["level"], .string("warn"))
            }

            // The second write did not spawn a row under the new type.
            let beta = try await query(QueryRequest(recordType: "Beta"), on: app)
            XCTAssertTrue(beta.records.isEmpty)
        }
    }

    func testUpsertReplacesFields() async throws {
        try await withApp { app in
            let start = utcDate(2026, 6, 10, 9)
            var session = makeSession(start: start, installID: "install-1", sessionID: "session-1")
            try await write([session], to: app)

            // The client re-sends sessions until synced; the second write
            // carries the end date and must replace the stored fields.
            session.fields["end_date"] = .date(utcDate(2026, 6, 10, 10))
            try await write([session], to: app)

            let response = try await query(QueryRequest(recordType: "Session"), on: app)
            XCTAssertEqual(response.records.count, 1)
            XCTAssertEqual(response.records[0].fields["end_date"], session.fields["end_date"])
        }
    }

    func testDuplicateNamesInOneBatch() async throws {
        try await withApp { app in
            let session = makeSession(start: utcDate(2026, 6, 10, 9), installID: "i", sessionID: "s")
            var updated = session
            updated.fields["end_date"] = .date(utcDate(2026, 6, 10, 11))

            try await write([session, updated], to: app)

            let response = try await query(QueryRequest(recordType: "Session"), on: app)
            XCTAssertEqual(response.records.count, 1)
            XCTAssertEqual(response.records[0].fields["end_date"], updated.fields["end_date"])
        }
    }

    func testRejectsMatrixWrites() async throws {
        try await withApp { app in
            let matrix = makeRecord(type: "DateIntMatrix", fields: ["name": .string("Session")])

            try await app.test(
                .POST, "api/v1/records",
                headers: .authorized,
                beforeRequest: { req in
                    try req.content.encode(WriteRequest(records: [matrix]))
                },
                afterResponse: { res async in
                    XCTAssertEqual(res.status, .badRequest)
                }
            )
        }
    }

    func testFieldValueRoundTrip() throws {
        let values: [String: FieldValue] = [
            "string": .string("hello"),
            "int": .int(42),
            "double": .double(1.5),
            "date": .date(utcDate(2026, 6, 12, 18, 45)),
            "bytes": .bytes(Data([1, 2, 3])),
            "strings": .strings(["a", "b"]),
        ]

        let data = try JSONEncoder().encode(values)
        let decoded = try JSONDecoder().decode([String: FieldValue].self, from: data)

        XCTAssertEqual(decoded, values)
    }
}
