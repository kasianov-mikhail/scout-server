//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Vapor

@main
enum Entrypoint {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)

        let app = try await Application.make(env)

        do {
            try await configure(app)
            try await app.execute()
        } catch {
            app.logger.report(error: error)
            let notifier = app.telegramNotifier ?? .fromEnvironment(client: app.client, logger: app.logger)
            await notifier?.serverDidFail(error)
            try? await app.asyncShutdown()
            throw error
        }

        try await app.asyncShutdown()
    }
}
