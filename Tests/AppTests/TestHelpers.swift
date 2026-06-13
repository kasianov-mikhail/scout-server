//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import XCTVapor

@testable import App

let testAPIKey = "test-key"

/// Boots an app against the test database, runs the test body, and shuts the
/// app down even when the body throws.
///
/// The database is in-memory SQLite by default; setting `DATABASE_URL` points
/// the suite at a real Postgres instead (see `configure`).
///
func withApp(_ body: (Application) async throws -> Void) async throws {
    let app = try await Application.make(.testing)
    do {
        try await configure(app)
        app.apiKeys = APIKeys(keys: [testAPIKey], environment: .testing)
        // Revert first so each test starts from a clean schema. A fresh
        // in-memory SQLite makes this a no-op, but a Postgres run shares one
        // database across tests, so the previous test's tables and rows must be
        // dropped to keep cases isolated.
        try await app.autoRevert()
        try await app.autoMigrate()
        try await body(app)
    } catch {
        try await app.asyncShutdown()
        throw error
    }
    try await app.asyncShutdown()
}

extension HTTPHeaders {
    static var authorized: HTTPHeaders {
        var headers = HTTPHeaders()
        headers.add(name: "X-API-Key", value: testAPIKey)
        headers.contentType = .json
        return headers
    }
}

// MARK: - Record Factories

func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    DateComponents(
        calendar: Calendar.utc,
        year: year, month: month, day: day, hour: hour, minute: minute
    ).date!
}

func makeRecord(type: String, name recordName: String = UUID().uuidString, fields: [String: FieldValue]) -> RecordDTO {
    RecordDTO(recordType: type, recordName: recordName, fields: fields)
}

func makeEvent(name: String, date: Date, level: String = "info", sessionID: String = UUID().uuidString, installID: String = UUID().uuidString) -> RecordDTO {
    makeRecord(
        type: "Event",
        fields: [
            "name": .string(name),
            "level": .string(level),
            "date": .date(date),
            "hour": .date(date.startOfHour),
            "day": .date(date.startOfDay),
            "week": .date(date.startOfWeek),
            "month": .date(date.startOfMonth),
            "uuid": .string(UUID().uuidString),
            "session_id": .string(sessionID),
            "install_id": .string(installID),
            "device_id": .string(UUID().uuidString),
            "launch_id": .string(UUID().uuidString),
            "param_count": .int(0),
            "version": .int(1),
        ]
    )
}

func makeSession(start: Date, installID: String, sessionID: String = UUID().uuidString) -> RecordDTO {
    makeRecord(
        type: "Session",
        name: sessionID,
        fields: [
            "start_date": .date(start),
            "session_id": .string(sessionID),
            "install_id": .string(installID),
            "device_id": .string(installID),
            "launch_id": .string(UUID().uuidString),
            "hour": .date(start.startOfHour),
            "day": .date(start.startOfDay),
            "week": .date(start.startOfWeek),
            "month": .date(start.startOfMonth),
            "version": .int(1),
        ]
    )
}

func makeMetric(type: String = "IntMetric", name: String, category: String, date: Date, value: FieldValue) -> RecordDTO {
    makeRecord(
        type: type,
        fields: [
            "name": .string(name),
            "category": .string(category),
            "date": .date(date),
            "hour": .date(date.startOfHour),
            "day": .date(date.startOfDay),
            "week": .date(date.startOfWeek),
            "month": .date(date.startOfMonth),
            "value": value,
            "uuid": .string(UUID().uuidString),
            "version": .int(1),
        ]
    )
}

// MARK: - Requests

func write(_ records: [RecordDTO], to app: Application) async throws {
    try await app.test(
        .POST, "api/v1/records",
        headers: .authorized,
        beforeRequest: { req in
            try req.content.encode(WriteRequest(records: records))
        },
        afterResponse: { res async in
            XCTAssertEqual(res.status, .ok, res.body.string)
        }
    )
}

func query(_ request: QueryRequest, on app: Application) async throws -> QueryResponse {
    var response: QueryResponse?
    try await app.test(
        .POST, "api/v1/records/query",
        headers: .authorized,
        beforeRequest: { req in
            try req.content.encode(request)
        },
        afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok, res.body.string)
            response = try res.content.decode(QueryResponse.self)
        }
    )
    return response!
}

func activeUsers(from: Date, to: Date, on app: Application) async throws -> [ActiveUserPoint] {
    let fromMs = Int64((from.timeIntervalSince1970 * 1000).rounded())
    let toMs = Int64((to.timeIntervalSince1970 * 1000).rounded())
    var response: ActiveUsersResponse?
    try await app.test(
        .GET, "api/v1/metrics/active-users?from=\(fromMs)&to=\(toMs)",
        headers: .authorized,
        afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok, res.body.string)
            response = try res.content.decode(ActiveUsersResponse.self)
        }
    )
    return response!.series
}
