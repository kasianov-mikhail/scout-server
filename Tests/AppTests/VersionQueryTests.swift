//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import XCTVapor

@testable import App

final class VersionQueryTests: XCTestCase {
    func testFiltersVersionsByAppVersion() async throws {
        try await withApp { app in
            try await write(
                [
                    makeVersion(date: utcDate(2026, 6, 10), appVersion: "3.2.0", build: "412"),
                    makeVersion(date: utcDate(2026, 6, 9), appVersion: "3.1.4", build: "405"),
                ],
                to: app
            )

            let response = try await query(
                QueryRequest(
                    recordType: "Version",
                    filters: [QueryFilter(field: "app_version", op: .equals, value: .string("3.2.0"))]
                ),
                on: app
            )

            XCTAssertEqual(response.records.count, 1)
            XCTAssertEqual(response.records[0].fields["app_version"], .string("3.2.0"))
            XCTAssertEqual(response.records[0].fields["build_number"], .string("412"))
        }
    }
}
