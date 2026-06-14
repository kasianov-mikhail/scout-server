//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Vapor

func routes(_ app: Application) throws {
    app.get("healthz") { _ in
        HTTPStatus.ok
    }

    let api = app.grouped("api", "v1").grouped(APIKeyMiddleware())

    try api.register(collection: RecordController())
    try api.register(collection: MetricsController())
}
