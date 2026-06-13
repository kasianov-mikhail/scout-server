//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Fluent
import OpenAPIRuntime
import Vapor

/// Implements the generated `APIProtocol` over the existing services. Validation
/// and matrix routing match the former controllers; errors are thrown as
/// `Abort` and surface with their intended status via the
/// `ServerErrorUnwrappingMiddleware`.
///
struct ScoutAPIHandler: APIProtocol {
    let app: Application

    /// Largest accepted write batch; the Scout client chunks at 400.
    static let maxBatchSize = 1000

    /// Span used when the caller omits `from`: the trailing 90 days.
    static let defaultSpan: TimeInterval = 90 * 86_400

    func createRecords(
        _ input: Operations.createRecords.Input
    ) async throws -> Operations.createRecords.Output {
        let records: [RecordDTO]
        switch input.body {
        case .json(let body):
            records = body.records.map { RecordDTO($0) }
        }

        guard records.count <= Self.maxBatchSize else {
            throw Abort(.payloadTooLarge, reason: "At most \(Self.maxBatchSize) records per request")
        }
        for record in records {
            guard MatrixService.matrixTypes.contains(record.recordType) == false else {
                throw Abort(.badRequest, reason: "Matrix records are aggregated server-side and cannot be written")
            }
            guard !record.recordType.isEmpty, !record.recordName.isEmpty else {
                throw Abort(.badRequest, reason: "Records require a recordType and recordName")
            }
        }

        try await app.db.transaction { db in
            let names = records.map(\.recordName)
            let existing = try await RecordModel.query(on: db)
                .filter(\.$recordName ~~ names)
                .all()
            let byName = Dictionary(existing.map { ($0.recordName, $0) }) { first, _ in first }

            var fresh: [String: RecordModel] = [:]

            for dto in records {
                if let model = byName[dto.recordName] {
                    model.apply(fields: dto.fields)
                    try await model.save(on: db)
                } else if let model = fresh[dto.recordName] {
                    model.apply(fields: dto.fields)
                } else {
                    fresh[dto.recordName] = RecordModel(dto: dto)
                }
            }

            try await Array(fresh.values).create(on: db)
        }

        return .ok(.init(body: .json(.init(saved: records.count))))
    }

    func queryRecords(
        _ input: Operations.queryRecords.Input
    ) async throws -> Operations.queryRecords.Output {
        let query: QueryRequest
        switch input.body {
        case .json(let body):
            query = QueryRequest(body)
        }

        let response: QueryResponse
        if let recordType = query.recordType, MatrixService.matrixTypes.contains(recordType) {
            response = try await MatrixService.run(query, on: app.db)
        } else {
            response = try await RecordQueryService.run(query, on: app.db)
        }

        return .ok(.init(body: .json(.init(response))))
    }

    func getRecord(
        _ input: Operations.getRecord.Input
    ) async throws -> Operations.getRecord.Output {
        let recordName = input.path.recordName

        guard let model = try await RecordModel.query(on: app.db).filter(\.$recordName == recordName).first() else {
            throw Abort(.notFound, reason: "No record named '\(recordName)'")
        }

        let fields = input.query.fields.map { $0.split(separator: ",").map(String.init) }
        return .ok(.init(body: .json(model.dto.keeping(fields: fields).wire)))
    }

    func getActiveUsers(
        _ input: Operations.getActiveUsers.Input
    ) async throws -> Operations.getActiveUsers.Output {
        let to = input.query.to.map(Self.date(ms:)) ?? Date()
        let from = input.query.from.map(Self.date(ms:)) ?? to.addingTimeInterval(-Self.defaultSpan)

        guard from < to else {
            throw Abort(.badRequest, reason: "Empty range: 'from' must be before 'to'")
        }

        let series = try await ActiveUserService.series(from: from, to: to, on: app.db)
        return .ok(.init(body: .json(.init(series))))
    }

    private static func date(ms: Int64) -> Date {
        Date(timeIntervalSince1970: Double(ms) / 1000)
    }
}
