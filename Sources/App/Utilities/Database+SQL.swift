//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Fluent
import SQLKit
import Vapor

extension Database {
    /// The SQL face of this database, for raw GROUP BY aggregation.
    func sql() throws -> any SQLDatabase {
        guard let sql = self as? any SQLDatabase else {
            throw Abort(.internalServerError, reason: "Database does not support SQL aggregation")
        }
        return sql
    }
}
