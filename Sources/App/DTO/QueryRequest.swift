//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Vapor

/// A record query, the server-side counterpart of a `CKQuery`.
///
/// Either `recordType` (a fresh query) or `cursor` (continuation of a
/// previous one) must be present.
///
struct QueryRequest: Content, Equatable {
    var recordType: String?
    var filters: [QueryFilter]?
    var sort: [QuerySort]?
    var limit: Int?
    var fields: [String]?
    var cursor: String?
}

/// A single comparison against a queryable record field.
struct QueryFilter: Codable, Equatable, Sendable {
    enum Operator: String, Codable, Sendable {
        case equals
        case notEquals
        case greaterThan
        case greaterThanOrEquals
        case lessThan
        case lessThanOrEquals
        case `in`
        case beginsWith
    }

    let field: String
    let op: Operator
    let value: FieldValue
}

struct QuerySort: Codable, Equatable, Sendable {
    let field: String
    var ascending: Bool = true
}

struct QueryResponse: Content {
    let records: [RecordDTO]
    let cursor: String?
}
