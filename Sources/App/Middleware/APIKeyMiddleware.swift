//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Vapor

/// The set of API keys the server accepts, parsed from `SCOUT_API_KEYS`.
///
/// An empty key set rejects every request except in the `.development`
/// environment, where the API stays open for local experimentation.
///
struct APIKeys: Sendable {
    let keys: Set<String>
    let environment: Environment

    static func parse(_ raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    func allows(_ key: String?) -> Bool {
        if keys.isEmpty {
            return environment == .development
        }
        guard let key else {
            return false
        }
        return keys.contains(key)
    }
}

extension Application {
    private struct APIKeysStorage: StorageKey {
        typealias Value = APIKeys
    }

    var apiKeys: APIKeys {
        get {
            storage[APIKeysStorage.self] ?? APIKeys(keys: [], environment: environment)
        }
        set {
            storage[APIKeysStorage.self] = newValue
        }
    }
}

/// Authenticates requests by the `X-API-Key` header or a bearer token.
struct APIKeyMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let key = request.headers.first(name: "X-API-Key") ?? request.headers.bearerAuthorization?.token

        guard request.application.apiKeys.allows(key) else {
            throw Abort(.unauthorized, reason: "Missing or invalid API key")
        }

        return try await next.respond(to: request)
    }
}
