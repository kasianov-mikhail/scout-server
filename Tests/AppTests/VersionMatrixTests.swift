//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import XCTVapor

@testable import App

/// The server dimensions lifecycle matrices by `app_version`, so release
/// health reads per-version session and crash counts. 2026-06-10 is a
/// Wednesday: weekday 4, hour cells `cell_4_<hour>`.
///
final class VersionMatrixTests: XCTestCase {
    func testSessionMatrixIsDimensionedByAppVersion() async throws {
        try await withApp { app in
            try await write(
                [
                    session(start: utcDate(2026, 6, 10, 9), appVersion: "3.2.0"),
                    session(start: utcDate(2026, 6, 10, 9, 30), appVersion: "3.2.0"),
                    session(start: utcDate(2026, 6, 10, 9), appVersion: "3.1.4"),
                ],
                to: app
            )

            let response = try await query(
                QueryRequest(
                    recordType: "DateIntMatrix",
                    filters: [
                        QueryFilter(field: "name", op: .equals, value: .string("Session")),
                        QueryFilter(field: "app_version", op: .equals, value: .string("3.2.0")),
                    ]
                ),
                on: app
            )

            XCTAssertEqual(response.records.count, 1)
            let matrix = response.records[0]
            XCTAssertEqual(matrix.fields["name"], .string("Session"))
            XCTAssertEqual(matrix.fields["app_version"], .string("3.2.0"))
            XCTAssertEqual(matrix.fields["cell_4_09"], .int(2))
        }
    }

    func testUnversionedQueryKeepsTotalsAcrossVersions() async throws {
        try await withApp { app in
            try await write(
                [
                    session(start: utcDate(2026, 6, 10, 9), appVersion: "3.2.0"),
                    session(start: utcDate(2026, 6, 10, 9, 30), appVersion: "3.1.4"),
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

            let total = response.records.compactMap { record -> Int64? in
                if case .int(let count) = record.fields["cell_4_09"] { return count }
                return nil
            }
            .reduce(0, +)
            XCTAssertEqual(total, 2)
        }
    }

    private func session(start: Date, appVersion: String) -> Record {
        makeRecord(
            type: "Session",
            fields: [
                "start_date": .date(start),
                "session_id": .string(UUID().uuidString),
                "install_id": .string(UUID().uuidString),
                "device_id": .string(UUID().uuidString),
                "launch_id": .string(UUID().uuidString),
                "app_version": .string(appVersion),
                "hour": .date(start.startOfHour),
                "day": .date(start.startOfDay),
                "week": .date(start.startOfWeek),
                "month": .date(start.startOfMonth),
                "version": .int(1),
            ]
        )
    }
}
