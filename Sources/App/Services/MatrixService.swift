//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Fluent
import SQLKit
import Vapor

/// Synthesizes CloudKit-style matrix records from raw data.
///
/// CloudKit cannot aggregate, so the Scout client maintains `DateIntMatrix`
/// and `DateDoubleMatrix` records by hand. This server aggregates natively:
/// clients only upload raw records, and queries for those matrix record types
/// are answered by GROUP BY over the rows, shaped exactly like the records the
/// client would have written. (Active users are aggregated natively too, but
/// served as a flat series — see `ActiveUserService` / `MetricsController`.)
///
enum MatrixService {
    static let matrixTypes: Set<String> = [
        intMatrixType, doubleMatrixType,
    ]

    static let intMatrixType = "DateIntMatrix"
    static let doubleMatrixType = "DateDoubleMatrix"

    /// Lifecycle record types whose weekly `DateIntMatrix` is named after
    /// the record type itself, mirroring `LifecycleMatrix.names` in Scout.
    ///
    static let lifecycleTypes = ["Crash", "Device", "Install", "Launch", "Session", "Version"]

    /// Raw metric record types uploaded by HTTP backends in place of the
    /// metric matrices the client maintains on CloudKit.
    ///
    static let intMetricType = "IntMetric"
    static let doubleMetricType = "DoubleMetric"

    static func run(_ request: QueryRequest, on database: any Database) async throws -> QueryResponse {
        guard let recordType = request.recordType else {
            throw Abort(.badRequest, reason: "Query must specify a recordType")
        }

        let constraints = try MatrixConstraints(filters: request.filters ?? [])

        let records: [RecordDTO] =
            switch recordType {
            case intMatrixType:
                try await intMatrices(constraints, on: database)
            case doubleMatrixType:
                try await doubleMatrices(constraints, on: database)
            default:
                throw Abort(.badRequest, reason: "Unknown matrix type '\(recordType)'")
            }

        let sorted = records.sorted { $0.recordName < $1.recordName }

        return QueryResponse(
            records: sorted.map { $0.keeping(fields: request.fields) },
            cursor: nil
        )
    }

    // MARK: - DateIntMatrix / DateDoubleMatrix

    private static func intMatrices(_ constraints: MatrixConstraints, on database: any Database) async throws -> [RecordDTO] {
        var buckets: [MatrixBucket] = []

        if constraints.category == nil {
            for type in lifecycleTypes where constraints.name == nil || constraints.name == type {
                buckets += try await countBuckets(recordType: type, named: type, constraints: constraints, on: database)
            }
            buckets += try await countBuckets(recordType: "Event", named: nil, constraints: constraints, on: database)
        }

        buckets += try await sumBuckets(recordType: intMetricType, constraints: constraints, on: database)

        return assemble(buckets, recordType: intMatrixType, constraints: constraints) { .int($0.totalInt ?? 0) }
    }

    private static func doubleMatrices(_ constraints: MatrixConstraints, on database: any Database) async throws -> [RecordDTO] {
        let buckets = try await sumBuckets(recordType: doubleMetricType, constraints: constraints, on: database)

        return assemble(buckets, recordType: doubleMatrixType, constraints: constraints) { .double($0.totalDouble ?? 0) }
    }

    /// Per-hour record counts; `named` overrides the matrix name for
    /// lifecycle types, events group by their own `name` column.
    ///
    private static func countBuckets(recordType: String, named: String?, constraints: MatrixConstraints, on database: any Database) async throws -> [MatrixBucket] {
        let sql = try sqlDatabase(database)
        let range = constraints.hourRange

        let rows: [MatrixBucket]
        if let named {
            rows = try await sql.raw(
                """
                SELECT hour_epoch AS hour, COUNT(*) AS total_int
                FROM records
                WHERE record_type = \(bind: recordType)
                  AND hour_epoch >= \(bind: range.lowerBound) AND hour_epoch < \(bind: range.upperBound)
                GROUP BY hour_epoch
                """
            ).all(decoding: MatrixBucket.self).map { bucket in
                var bucket = bucket
                bucket.name = named
                return bucket
            }
        } else {
            rows = try await sql.raw(
                """
                SELECT name, hour_epoch AS hour, COUNT(*) AS total_int
                FROM records
                WHERE record_type = \(bind: recordType) AND name IS NOT NULL
                  AND hour_epoch >= \(bind: range.lowerBound) AND hour_epoch < \(bind: range.upperBound)
                GROUP BY name, hour_epoch
                """
            ).all(decoding: MatrixBucket.self)
        }

        return rows.filter(constraints.matches)
    }

    /// Per-hour metric value sums, grouped by metric name and telemetry
    /// category — the server-side equivalent of the client's metric matrices.
    ///
    private static func sumBuckets(recordType: String, constraints: MatrixConstraints, on database: any Database) async throws -> [MatrixBucket] {
        let sql = try sqlDatabase(database)
        let range = constraints.hourRange

        let total =
            recordType == intMetricType
            ? "CAST(SUM(value_int) AS BIGINT) AS total_int"
            : "SUM(value_double) AS total_double"

        let rows = try await sql.raw(
            """
            SELECT name, category, hour_epoch AS hour, \(unsafeRaw: total)
            FROM records
            WHERE record_type = \(bind: recordType) AND name IS NOT NULL
              AND hour_epoch >= \(bind: range.lowerBound) AND hour_epoch < \(bind: range.upperBound)
            GROUP BY name, category, hour_epoch
            """
        ).all(decoding: MatrixBucket.self)

        return rows.filter(constraints.matches)
    }

    /// Folds hour buckets into one record per (name, category, week), with
    /// `cell_<weekday>_<hour>` keys identical to the client's `GridCell`.
    ///
    private static func assemble(_ buckets: [MatrixBucket], recordType: String, constraints: MatrixConstraints, value: (MatrixBucket) -> FieldValue) -> [RecordDTO] {
        var matrices: [MatrixKey: [String: FieldValue]] = [:]

        for bucket in buckets {
            let hourDate = Date(timeIntervalSince1970: Double(bucket.hour))
            let week = hourDate.startOfWeek

            guard constraints.dateRange.contains(week), let name = bucket.name else {
                continue
            }

            let weekday = Calendar.utc.component(.weekday, from: hourDate)
            let hour = Calendar.utc.component(.hour, from: hourDate)
            let key = MatrixKey(name: name, category: bucket.category, week: week)
            let cell = "cell_\(weekday)_\(String(format: "%02d", hour))"

            // An event sharing a lifecycle type's name lands in the same
            // bucket; CloudKit would store two records that the client sums
            // on read, so summing here preserves the observable result.
            matrices[key, default: [:]][cell] = adding(matrices[key]?[cell], value(bucket))
        }

        return matrices.map { key, cells in
            var fields = cells
            fields["date"] = .date(key.week)
            fields["name"] = .string(key.name)
            fields["version"] = .int(1)
            if let category = key.category {
                fields["category"] = .string(category)
            }
            return RecordDTO(
                recordType: recordType,
                recordName: recordName(type: recordType, name: key.name, category: key.category, date: key.week),
                fields: fields
            )
        }
    }

    private static func adding(_ existing: FieldValue?, _ addition: FieldValue) -> FieldValue {
        switch (existing, addition) {
        case (.int(let lhs), .int(let rhs)):
            .int(lhs + rhs)
        case (.double(let lhs), .double(let rhs)):
            .double(lhs + rhs)
        default:
            addition
        }
    }

    static func recordName(type: String, name: String, category: String?, date: Date) -> String {
        "\(type)/\(name)/\(category ?? "-")/\(Int64(date.timeIntervalSince1970))"
    }

    static func sqlDatabase(_ database: any Database) throws -> any SQLDatabase {
        guard let sql = database as? any SQLDatabase else {
            throw Abort(.internalServerError, reason: "Database does not support SQL aggregation")
        }
        return sql
    }
}

// MARK: - Building Blocks

/// One GROUP BY row: a (name, category, hour bucket) and its aggregate.
struct MatrixBucket: Decodable {
    var name: String?
    var category: String?
    var hour: Int64
    var totalInt: Int64?
    var totalDouble: Double?

    enum CodingKeys: String, CodingKey {
        case name, category, hour
        case totalInt = "total_int"
        case totalDouble = "total_double"
    }
}

private struct MatrixKey: Hashable {
    let name: String
    let category: String?
    let week: Date
}

/// The filter shapes Scout sends for matrix queries: a half-open `date`
/// range plus optional `name` and `category` equality.
///
struct MatrixConstraints {
    var dateRange: Range<Date> = Date.distantPast..<Date.distantFuture
    var name: String?
    var category: String?

    init(dateRange: Range<Date>) {
        self.dateRange = dateRange
    }

    init(filters: [QueryFilter]) throws {
        var lower = Date.distantPast
        var upper = Date.distantFuture

        for filter in filters {
            switch (filter.field, filter.op, filter.value) {
            case ("date", .greaterThanOrEquals, .date(let date)):
                lower = max(lower, date)
            case ("date", .lessThan, .date(let date)):
                upper = min(upper, date)
            case ("name", .equals, .string(let value)):
                name = value
            case ("category", .equals, .string(let value)):
                category = value
            default:
                throw Abort(.badRequest, reason: "Unsupported matrix filter on '\(filter.field)'")
            }
        }

        guard lower < upper else {
            throw Abort(.badRequest, reason: "Empty date range")
        }

        dateRange = lower..<upper
    }

    /// SQL prefilter on hour buckets. A matrix week inside the date range
    /// only contains hours from its own week, so hours are bounded by
    /// `[lower, upper + 1 week)`; the exact per-week cut happens in Swift.
    ///
    var hourRange: Range<Int64> {
        let lower = dateRange.lowerBound == .distantPast ? Int64.min / 2 : Int64(dateRange.lowerBound.timeIntervalSince1970)
        let upper = dateRange.upperBound == .distantFuture ? Int64.max / 2 : Int64(dateRange.upperBound.timeIntervalSince1970) + 7 * 86_400
        return lower..<upper
    }

    func matches(_ bucket: MatrixBucket) -> Bool {
        if let name, bucket.name != name {
            return false
        }
        if let category, bucket.category != category {
            return false
        }
        return true
    }
}
