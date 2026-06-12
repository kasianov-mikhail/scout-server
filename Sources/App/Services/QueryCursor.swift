//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Foundation
import Vapor

/// A stateless pagination cursor: the original query plus the next offset,
/// base64-encoded. The client treats it as an opaque token, so the query
/// can be replayed without any server-side cursor storage.
///
struct QueryCursor: Codable, Equatable {
    let query: QueryRequest
    let offset: Int

    var token: String {
        let data = try! JSONEncoder().encode(self)
        return data.base64EncodedString()
    }

    init(query: QueryRequest, offset: Int) {
        var query = query
        query.cursor = nil
        self.query = query
        self.offset = offset
    }

    init(token: String) throws {
        guard let data = Data(base64Encoded: token) else {
            throw Abort(.badRequest, reason: "Malformed cursor")
        }
        do {
            self = try JSONDecoder().decode(QueryCursor.self, from: data)
        } catch {
            throw Abort(.badRequest, reason: "Malformed cursor")
        }
    }
}
