//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Fluent
import Vapor

/// Executes record queries against the generic `records` table.
enum RecordQueryService {
    static let defaultLimit = 200
    static let maxLimit = 1000

    /// Fields a query may filter or sort on; each maps to a dedicated column.
    static let queryableFields: Set<String> = [
        "name", "category", "level", "uuid",
        "device_id", "install_id", "launch_id", "session_id",
        "date", "start_date", "end_date", "param_count",
    ]

    static func run(_ request: QueryRequest, on database: any Database) async throws -> QueryResponse {
        let cursor: QueryCursor
        if let token = request.cursor {
            cursor = try QueryCursor(token: token)
        } else {
            cursor = QueryCursor(query: request, offset: 0)
        }

        let query = cursor.query

        guard let recordType = query.recordType, !recordType.isEmpty else {
            throw Abort(.badRequest, reason: "Query must specify a recordType")
        }

        let limit = min(max(query.limit ?? defaultLimit, 1), maxLimit)

        let builder = RecordModel.query(on: database).filter(\.$recordType == recordType)

        for filter in query.filters ?? [] {
            try apply(filter, to: builder)
        }

        for sort in query.sort ?? [] {
            guard queryableFields.contains(sort.field) else {
                throw Abort(.badRequest, reason: "Cannot sort by field '\(sort.field)'")
            }
            builder.sort(field(sort.field), sort.ascending ? .ascending : .descending)
        }

        // A deterministic tiebreak so offset pagination never skips or
        // repeats rows between pages.
        builder.sort(\.$id)

        let models = try await builder.range(cursor.offset..<(cursor.offset + limit + 1)).all()

        let hasMore = models.count > limit
        let page = models.prefix(limit).map { $0.dto.keeping(fields: query.fields) }

        return QueryResponse(
            records: Array(page),
            cursor: hasMore ? QueryCursor(query: query, offset: cursor.offset + limit).token : nil
        )
    }

    private static func apply(_ filter: QueryFilter, to builder: QueryBuilder<RecordModel>) throws {
        guard queryableFields.contains(filter.field) else {
            throw Abort(.badRequest, reason: "Cannot filter by field '\(filter.field)'")
        }

        let field = field(filter.field)
        let value = try bind(filter.value, for: filter)

        switch filter.op {
        case .equals:
            builder.filter(field, .equal, value)
        case .notEquals:
            builder.filter(field, .notEqual, value)
        case .greaterThan:
            builder.filter(field, .greaterThan, value)
        case .greaterThanOrEquals:
            builder.filter(field, .greaterThanOrEqual, value)
        case .lessThan:
            builder.filter(field, .lessThan, value)
        case .lessThanOrEquals:
            builder.filter(field, .lessThanOrEqual, value)
        case .in:
            guard case .strings(let values) = filter.value else {
                throw Abort(.badRequest, reason: "Filter 'in' on '\(filter.field)' requires a string list")
            }
            builder.filter(field, .subset(inverse: false), .array(values.map { .bind($0) }))
        case .beginsWith:
            guard case .string = filter.value else {
                throw Abort(.badRequest, reason: "Filter 'beginsWith' on '\(filter.field)' requires a string")
            }
            builder.filter(field, .contains(inverse: false, .prefix), value)
        }
    }

    private static func field(_ name: String) -> DatabaseQuery.Field {
        .path([FieldKey(stringLiteral: name)], schema: RecordModel.schema)
    }

    private static func bind(_ value: FieldValue, for filter: QueryFilter) throws -> DatabaseQuery.Value {
        switch value {
        case .string(let value):
            .bind(value)
        case .int(let value):
            .bind(value)
        case .double(let value):
            .bind(value)
        case .date(let value):
            .bind(value)
        case .strings(let values):
            .array(values.map { .bind($0) })
        case .bytes:
            throw Abort(.badRequest, reason: "Cannot filter '\(filter.field)' by a bytes value")
        }
    }
}
