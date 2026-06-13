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

/// Guards against schema drift between a model and its migration.
///
/// Fluent never links a model's `@Field`s to the `.field(...)` calls in its
/// migration: adding a property without a matching migration compiles, passes
/// any test that doesn't touch the new column, and only fails at runtime once a
/// row is written. This test boots the app (running every migration, exactly as
/// `withApp` does), then asserts the columns a model declares match the columns
/// the migrations actually created — turning a forgotten migration into a red
/// CI run instead. It introspects whichever database backs the run, so it holds
/// on both the fast SQLite suite and the Postgres CI job.
final class SchemaConsistencyTests: XCTestCase {

    /// Every model whose columns a migration is expected to cover. Add new
    /// models here so they are held to the same check.
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

    /// The names of the columns that physically exist in `table`, read through
    /// each backend's own catalog: `PRAGMA` on SQLite, `information_schema` on
    /// Postgres.
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
