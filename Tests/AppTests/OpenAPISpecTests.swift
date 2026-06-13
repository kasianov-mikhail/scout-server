//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import XCTVapor

@testable import App

final class OpenAPISpecTests: XCTestCase {
    /// The OpenAPI document is served verbatim, unauthenticated, so tooling and
    /// generated clients can fetch the contract without a key.
    func testServesOpenAPIDocumentUnauthenticated() async throws {
        try await withApp { app in
            try await app.test(.GET, "openapi.yaml") { res async in
                XCTAssertEqual(res.status, .ok)
                XCTAssertTrue(res.body.string.contains("openapi:"), res.body.string)
                XCTAssertTrue(res.headers.contentType?.description.contains("yaml") ?? false)
            }
        }
    }
}
