//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import XCTVapor

@testable import App

/// PeriodMatrix semantics mirror the client: an install active on day A is
/// daily-active on A, weekly-active on `[A, A+1w)`, and monthly-active on
/// `[A, A+1m)`. Cells are `cell_<period>_<day-of-month>` (1-based, padded),
/// one matrix per month.
///
final class ActiveUserTests: XCTestCase {
    let june = utcDate(2026, 6, 1)
    let july = utcDate(2026, 7, 1)

    func juneQuery() -> QueryRequest {
        QueryRequest(
            recordType: "PeriodMatrix",
            filters: [
                QueryFilter(field: "name", op: .equals, value: .string("ActiveUser")),
                QueryFilter(field: "date", op: .greaterThanOrEquals, value: .date(june)),
                QueryFilter(field: "date", op: .lessThan, value: .date(july)),
            ]
        )
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

            let response = try await query(juneQuery(), on: app)

            XCTAssertEqual(response.records.count, 1)
            let matrix = response.records[0]
            XCTAssertEqual(matrix.fields["name"], .string("ActiveUser"))
            XCTAssertEqual(matrix.fields["date"], .date(june))

            // DAU: both installs on the 10th, only "a" on the 11th.
            XCTAssertEqual(matrix.fields["cell_d_10"], .int(2))
            XCTAssertEqual(matrix.fields["cell_d_11"], .int(1))
            XCTAssertNil(matrix.fields["cell_d_12"])

            // WAU: the 10th's activity marks a week forward; "a" extends
            // one extra day via the 11th.
            XCTAssertEqual(matrix.fields["cell_w_10"], .int(2))
            XCTAssertEqual(matrix.fields["cell_w_16"], .int(2))
            XCTAssertEqual(matrix.fields["cell_w_17"], .int(1))
            XCTAssertNil(matrix.fields["cell_w_18"])

            // MAU: marks run to July, but July cells live in July's matrix,
            // which the date filter excludes.
            XCTAssertEqual(matrix.fields["cell_m_10"], .int(2))
            XCTAssertEqual(matrix.fields["cell_m_30"], .int(2))
        }
    }

    func testActivityFromPreviousMonthReachesIntoRange() async throws {
        try await withApp { app in
            // Active on May 25: monthly-active through June 24.
            try await write(
                [makeSession(start: utcDate(2026, 5, 25, 12), installID: "a")],
                to: app
            )

            let response = try await query(juneQuery(), on: app)

            XCTAssertEqual(response.records.count, 1)
            let matrix = response.records[0]
            XCTAssertNil(matrix.fields["cell_d_01"])
            XCTAssertEqual(matrix.fields["cell_m_24"], .int(1))
            XCTAssertNil(matrix.fields["cell_m_25"])
        }
    }

    func testOtherNamesReturnNothing() async throws {
        try await withApp { app in
            try await write(
                [makeSession(start: utcDate(2026, 6, 10, 9), installID: "a")],
                to: app
            )

            let response = try await query(
                QueryRequest(
                    recordType: "PeriodMatrix",
                    filters: [QueryFilter(field: "name", op: .equals, value: .string("Other"))]
                ),
                on: app
            )

            XCTAssertEqual(response.records, [])
        }
    }
}
