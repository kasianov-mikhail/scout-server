//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import OpenAPIRuntime
import Vapor

/// Unwraps the `ServerError` the OpenAPI runtime throws around a handler error.
///
/// The runtime wraps anything a handler throws in a `ServerError`, which Vapor's
/// error middleware does not recognize as an `AbortError` — so a thrown
/// `Abort(.badRequest)` would otherwise surface as a 500. Rethrowing the
/// `underlyingError` lets Vapor render the intended status and reason.
///
struct ServerErrorUnwrappingMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch let error as ServerError {
            throw error.underlyingError
        }
    }
}
