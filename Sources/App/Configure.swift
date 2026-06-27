//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Fluent
import FluentPostgresDriver
import FluentSQLiteDriver
import Vapor

public func configure(_ app: Application) async throws {
    if let url = Environment.get("DATABASE_URL") {
        try app.databases.use(.postgres(url: url), as: .psql)
    } else if app.environment == .testing {
        app.databases.use(.sqlite(.memory), as: .sqlite)
    } else {
        app.databases.use(
            .postgres(
                configuration: SQLPostgresConfiguration(
                    hostname: Environment.get("DATABASE_HOST") ?? "localhost",
                    port: Environment.get("DATABASE_PORT").flatMap(Int.init) ?? SQLPostgresConfiguration.ianaPortNumber,
                    username: Environment.get("DATABASE_USERNAME") ?? "scout",
                    password: Environment.get("DATABASE_PASSWORD") ?? "scout",
                    database: Environment.get("DATABASE_NAME") ?? "scout",
                    tls: .prefer(try .init(configuration: .clientDefault))
                )
            ),
            as: .psql
        )
    }

    app.migrations.add(CreateRecord())

    app.apiKeys = APIKeys(
        keys: Environment.get("SCOUT_API_KEYS").map(APIKeys.parse) ?? [],
        environment: app.environment
    )

    try routes(app)

    if app.environment != .testing {
        try await app.autoMigrate()
    }
}
