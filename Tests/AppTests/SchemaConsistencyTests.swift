//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Fluent
import SQLKit
import XCTVapor

@testable import App

final class SchemaConsistencyTests: XCTestCase {

    static let models: [(schema: String, keys: [FieldKey])] = [
        (RecordModel.schema, RecordModel.keys)
    ]

    func testModelColumnsMatchMigratedSchema() async throws {
        try await withApp { app in
            let sql = try XCTUnwrap(app.db as? any SQLDatabase)

            for model in Self.models {
                let expected = Set(model.keys.map(\.description))
                let actual = try await Self.columns(of: model.schema, in: sql)

                XCTAssertEqual(
                    expected,
                    actual,
                    """
                    Schema drift in '\(model.schema)'.
                    On the model but not in the DB (missing migration?): \(expected.subtracting(actual).sorted())
                    In the DB but not on the model (stale field?):       \(actual.subtracting(expected).sorted())
                    """
                )
            }
        }
    }

    private static func columns(of table: String, in sql: any SQLDatabase) async throws -> Set<String> {
        if sql.dialect.name == "sqlite" {
            let rows = try await sql.raw("PRAGMA table_info(\(unsafeRaw: table))").all()
            return Set(try rows.map { try $0.decode(column: "name", as: String.self) })
        } else {
            let rows = try await sql.raw(
                "SELECT column_name FROM information_schema.columns WHERE table_name = \(bind: table)"
            ).all()
            return Set(try rows.map { try $0.decode(column: "column_name", as: String.self) })
        }
    }
}
