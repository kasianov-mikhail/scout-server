//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Foundation
import OpenAPIVapor
import Vapor

func routes(_ app: Application) throws {
    app.get("healthz") { _ in
        HTTPStatus.ok
    }

    // The OpenAPI document itself, served unauthenticated so tooling and
    // generated clients can fetch the contract. It is the same file the
    // generator consumes, bundled as a resource.
    app.get("openapi.yaml") { _ -> Response in
        guard let url = Bundle.module.url(forResource: "openapi", withExtension: "yaml"),
            let data = try? Data(contentsOf: url)
        else {
            throw Abort(.notFound)
        }
        var headers = HTTPHeaders()
        headers.contentType = HTTPMediaType(type: "application", subType: "yaml")
        return Response(status: .ok, headers: headers, body: .init(data: data))
    }

    // The OpenAPI document mounts its paths (`/records`, …) under this group, so
    // the spec's `/api/v1` server prefix and the API-key guard come from the
    // route group while `serverURL` stays at the default root. The unwrapping
    // middleware sits outside the API-key guard so a thrown `Abort` keeps its
    // status; see `ServerErrorUnwrappingMiddleware`.
    let secured = app.grouped("api", "v1")
        .grouped(ServerErrorUnwrappingMiddleware(), APIKeyMiddleware())

    let transport = VaporTransport(routesBuilder: secured)
    try ScoutAPIHandler(app: app).registerHandlers(on: transport)
}
