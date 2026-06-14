//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Fluent
import Vapor

struct RecordController: RouteCollection {
    /// Largest accepted write batch; the Scout client chunks at 400.
    static let maxBatchSize = 1000

    func boot(routes: any RoutesBuilder) throws {
        let records = routes.grouped("records")
        records.post(use: write)
        records.post("query", use: query)
        records.get(":recordName", use: lookup)
    }

    /// Upserts a batch of records by `recordName` — re-sent records overwrite
    /// their fields, so sync retries stay idempotent.
    ///
    func write(req: Request) async throws -> WriteResponse {
        let body = try req.content.decode(WriteRequest.self)

        guard body.records.count <= Self.maxBatchSize else {
            throw Abort(.payloadTooLarge, reason: "At most \(Self.maxBatchSize) records per request")
        }
        for record in body.records {
            guard MatrixService.matrixTypes.contains(record.recordType) == false else {
                throw Abort(.badRequest, reason: "Matrix records are aggregated server-side and cannot be written")
            }
            guard !record.recordType.isEmpty, !record.recordName.isEmpty else {
                throw Abort(.badRequest, reason: "Records require a recordType and recordName")
            }
        }

        try await req.db.transaction { db in
            let names = body.records.map(\.recordName)
            let existing = try await RecordModel.query(on: db)
                .filter(\.$recordName ~~ names)
                .all()
            let byName = Dictionary(existing.map { ($0.recordName, $0) }) { first, _ in first }

            var fresh: [String: RecordModel] = [:]

            for record in body.records {
                if let model = byName[record.recordName] {
                    model.apply(fields: record.fields)
                    try await model.save(on: db)
                } else if let model = fresh[record.recordName] {
                    model.apply(fields: record.fields)
                } else {
                    fresh[record.recordName] = RecordModel(record)
                }
            }

            try await Array(fresh.values).create(on: db)
        }

        return WriteResponse(saved: body.records.count)
    }

    func query(req: Request) async throws -> QueryResponse {
        let query = try req.content.decode(QueryRequest.self)

        if let recordType = query.recordType, MatrixService.matrixTypes.contains(recordType) {
            return try await MatrixService.run(query, on: req.db)
        }

        return try await RecordQueryService.run(query, on: req.db)
    }

    func lookup(req: Request) async throws -> Record {
        guard let recordName = req.parameters.get("recordName") else {
            throw Abort(.badRequest)
        }

        guard let model = try await RecordModel.query(on: req.db).filter(\.$recordName == recordName).first() else {
            throw Abort(.notFound, reason: "No record named '\(recordName)'")
        }

        let fields = req.query[String.self, at: "fields"].map { $0.split(separator: ",").map(String.init) }

        return model.wire.keeping(fields: fields)
    }
}
