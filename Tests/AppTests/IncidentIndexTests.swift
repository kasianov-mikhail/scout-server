//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import XCTVapor

@testable import App

final class IncidentIndexTests: XCTestCase {
    func testTalliesCountIncidentsPerFingerprint() async throws {
        try await withApp { app in
            try await write(
                [
                    makeIncident(fingerprint: "f1", date: utcDate(2026, 6, 10, 9, 15)),
                    makeIncident(fingerprint: "f1", date: utcDate(2026, 6, 11, 14)),
                    makeIncident(name: "SIGABRT", fingerprint: "f2", date: utcDate(2026, 6, 12, 8)),
                    makeIncident(fingerprint: "f1", date: utcDate(2026, 7, 2)),
                    makeIncident(type: "Hang", fingerprint: "f1", date: utcDate(2026, 6, 10)),
                ],
                to: app
            )

            let index = try await incidents(type: "Crash", from: utcDate(2026, 6, 1), to: utcDate(2026, 7, 1), on: app)

            XCTAssertEqual(
                index,
                IncidentsResponse(
                    tallies: [
                        IncidentTally(fingerprint: "f1", name: "SIGSEGV", count: 2, firstHour: utcDate(2026, 6, 10, 9).milliseconds),
                        IncidentTally(fingerprint: "f2", name: "SIGABRT", count: 1, firstHour: utcDate(2026, 6, 12, 8).milliseconds),
                    ],
                    unkeyed: nil
                )
            )
        }
    }

    func testUnkeyedIncidentsLeaveTheirRangeToARawRead() async throws {
        try await withApp { app in
            try await write(
                [
                    makeIncident(fingerprint: "f1", date: utcDate(2026, 6, 10, 9)),
                    makeIncident(fingerprint: nil, date: utcDate(2026, 6, 11, 14, 20)),
                    makeIncident(fingerprint: "", date: utcDate(2026, 6, 11, 10, 5)),
                    makeIncident(fingerprint: "f2", date: utcDate(2026, 6, 11, 12)),
                    makeIncident(fingerprint: "f1", date: utcDate(2026, 6, 12, 8)),
                ],
                to: app
            )

            let index = try await incidents(type: "Crash", from: utcDate(2026, 6, 1), to: utcDate(2026, 7, 1), on: app)

            XCTAssertEqual(
                index,
                IncidentsResponse(
                    tallies: [
                        IncidentTally(fingerprint: "f1", name: "SIGSEGV", count: 1, firstHour: utcDate(2026, 6, 12, 8).milliseconds)
                    ],
                    unkeyed: IncidentRange(from: utcDate(2026, 6, 11, 10).milliseconds, to: utcDate(2026, 6, 11, 15).milliseconds)
                )
            )
        }
    }

    func testMigrationBackfillsStoredFingerprints() async throws {
        try await withApp { app in
            try await write([makeIncident(type: "Hang", fingerprint: "f1", date: utcDate(2026, 6, 10, 9))], to: app)

            try await AddFingerprintField().revert(on: app.db)
            try await AddFingerprintField().prepare(on: app.db)

            let index = try await incidents(type: "Hang", from: utcDate(2026, 6, 1), to: utcDate(2026, 7, 1), on: app)

            XCTAssertEqual(index.tallies.map(\.fingerprint), ["f1"])
            XCTAssertNil(index.unkeyed)
        }
    }

    func testIncidentsRejectUnknownTypes() async throws {
        try await withApp { app in
            for path in ["api/v1/metrics/incidents", "api/v1/metrics/incidents?type=Event", "api/v1/metrics/incidents?type=crash"] {
                try await app.test(
                    .GET, path,
                    headers: .authorized,
                    afterResponse: { res async in
                        XCTAssertEqual(res.status, .badRequest, path)
                    }
                )
            }
        }
    }
}

private func makeIncident(type: String = "Crash", name: String = "SIGSEGV", fingerprint: String?, date: Date) -> Record {
    var record = makeIncident(type: type, date: date)
    record.fields["name"] = .string(name)
    record.fields["fingerprint"] = fingerprint.map(FieldValue.string)
    return record
}
