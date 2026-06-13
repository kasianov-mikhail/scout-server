//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Foundation

// Converts between the generated OpenAPI wire types and the internal domain
// types the services and tests are written against. The internal types stay
// the single source of truth for behavior; these bridges keep the generated
// layer a thin, mechanical translation at the HTTP boundary.

// MARK: - FieldValue

extension FieldValue {
    /// Builds an internal field value from its generated wire form.
    init(_ wire: Components.Schemas.FieldValue) {
        switch wire {
        case .StringValue(let value):
            self = .string(value.string)
        case .IntValue(let value):
            self = .int(value.int)
        case .DoubleValue(let value):
            self = .double(value.double)
        case .DateValue(let value):
            self = .date(Date(timeIntervalSince1970: Double(value.date) / 1000))
        case .BytesValue(let value):
            self = .bytes(Data(base64Encoded: value.bytes) ?? Data())
        case .StringsValue(let value):
            self = .strings(value.strings)
        }
    }

    /// The generated wire form of this field value.
    var wire: Components.Schemas.FieldValue {
        switch self {
        case .string(let value):
            return .StringValue(.init(string: value))
        case .int(let value):
            return .IntValue(.init(int: value))
        case .double(let value):
            return .DoubleValue(.init(double: value))
        case .date(let value):
            return .DateValue(.init(date: Int64((value.timeIntervalSince1970 * 1000).rounded())))
        case .bytes(let value):
            return .BytesValue(.init(bytes: value.base64EncodedString()))
        case .strings(let value):
            return .StringsValue(.init(strings: value))
        }
    }
}

// MARK: - Record

extension RecordDTO {
    init(_ wire: Components.Schemas.Record) {
        self.init(
            recordType: wire.recordType,
            recordName: wire.recordName,
            fields: wire.fields.additionalProperties.mapValues { FieldValue($0) }
        )
    }

    var wire: Components.Schemas.Record {
        .init(
            recordType: recordType,
            recordName: recordName,
            fields: .init(additionalProperties: fields.mapValues(\.wire))
        )
    }
}

// MARK: - Query

extension QueryRequest {
    init(_ wire: Components.Schemas.QueryRequest) {
        self.init(
            recordType: wire.recordType,
            filters: wire.filters?.map { QueryFilter($0) },
            sort: wire.sort?.map { QuerySort($0) },
            limit: wire.limit,
            fields: wire.fields,
            cursor: wire.cursor
        )
    }
}

extension QueryFilter {
    init(_ wire: Components.Schemas.QueryFilter) {
        self.init(field: wire.field, op: .init(wire.op), value: FieldValue(wire.value))
    }
}

extension QueryFilter.Operator {
    init(_ wire: Components.Schemas.QueryFilter.opPayload) {
        switch wire {
        case .equals: self = .equals
        case .notEquals: self = .notEquals
        case .greaterThan: self = .greaterThan
        case .greaterThanOrEquals: self = .greaterThanOrEquals
        case .lessThan: self = .lessThan
        case .lessThanOrEquals: self = .lessThanOrEquals
        case ._in: self = .in
        case .beginsWith: self = .beginsWith
        }
    }
}

extension QuerySort {
    init(_ wire: Components.Schemas.QuerySort) {
        self.init(field: wire.field, ascending: wire.ascending ?? true)
    }
}

extension Components.Schemas.QueryResponse {
    init(_ response: QueryResponse) {
        self.init(records: response.records.map(\.wire), cursor: response.cursor)
    }
}

// MARK: - Active users

extension Components.Schemas.ActiveUsersResponse {
    init(_ series: [ActiveUserPoint]) {
        self.init(
            series: series.map { point in
                .init(date: point.date, dau: point.dau, wau: point.wau, mau: point.mau)
            }
        )
    }
}
