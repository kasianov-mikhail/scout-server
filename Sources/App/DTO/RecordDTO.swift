//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Vapor

/// Wire representation of a single record.
struct RecordDTO: Content, Equatable {
    let recordType: String
    let recordName: String
    var fields: [String: FieldValue]
}

extension RecordDTO {
    /// Restricts the payload to the requested fields. A `nil` list keeps
    /// every field.
    ///
    func keeping(fields desired: [String]?) -> RecordDTO {
        guard let desired else {
            return self
        }
        let kept = Set(desired)
        var copy = self
        copy.fields = fields.filter { kept.contains($0.key) }
        return copy
    }
}

struct WriteRequest: Content {
    let records: [RecordDTO]
}

struct WriteResponse: Content {
    let saved: Int
}
