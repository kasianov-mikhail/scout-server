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

    func testRangeQueriesUseRecordTypeIndexes() async throws {
        try await withApp { app in
            let sql = try XCTUnwrap(app.db as? any SQLDatabase)

            for column in AddRecordIndexes.rangeColumns {
                let index = AddRecordIndexes.indexName(column)

                if sql.dialect.name == "sqlite" {
                    let rows = try await sql.raw(
                        """
                        EXPLAIN QUERY PLAN SELECT COUNT(*) FROM records
                        WHERE record_type = 'Event' AND \(ident: column) >= 0 AND \(ident: column) < 1
                        """
                    ).all()
                    let plan = try rows.map { try $0.decode(column: "detail", as: String.self) }.joined(separator: "\n")
                    XCTAssertTrue(plan.contains(index), "Range on '\(column)' skips \(index):\n\(plan)")
                } else {
                    let rows = try await sql.raw(
                        "SELECT indexname FROM pg_indexes WHERE tablename = 'records' AND indexname = \(bind: index)"
                    ).all()
                    XCTAssertEqual(rows.count, 1, "Missing index \(index)")
                }
            }
        }
    }

    func testDeviceLookupUsesIndex() async throws {
        try await withApp { app in
            let sql = try XCTUnwrap(app.db as? any SQLDatabase)

            if sql.dialect.name == "sqlite" {
                let rows = try await sql.raw(
                    "EXPLAIN QUERY PLAN SELECT * FROM records WHERE record_type = 'Launch' AND device_id = 'a'"
                ).all()
                let plan = try rows.map { try $0.decode(column: "detail", as: String.self) }.joined(separator: "\n")
                XCTAssertTrue(plan.contains(AddDeviceIndex.index), "Lookup skips \(AddDeviceIndex.index):\n\(plan)")
            } else {
                let rows = try await sql.raw(
                    "SELECT indexname FROM pg_indexes WHERE tablename = 'records' AND indexname = \(bind: AddDeviceIndex.index)"
                ).all()
                XCTAssertEqual(rows.count, 1, "Missing index \(AddDeviceIndex.index)")
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
