//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Fluent
import Vapor

/// A stored analytics record.
///
/// The full typed payload lives in `payload`; the fields Scout queries or
/// aggregates on are mirrored into dedicated columns so they can be
/// filtered, sorted, and grouped in SQL. `hourEpoch`/`dayEpoch` duplicate
/// the `hour`/`day` buckets as Unix seconds, giving aggregation queries a
/// GROUP BY key that decodes identically on Postgres and SQLite.
///
final class RecordModel: Model, @unchecked Sendable {
    static let schema = "records"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "record_type")
    var recordType: String

    @Field(key: "record_name")
    var recordName: String

    @OptionalField(key: "name")
    var name: String?

    @OptionalField(key: "category")
    var category: String?

    @OptionalField(key: "level")
    var level: String?

    @OptionalField(key: "uuid")
    var uuid: String?

    @OptionalField(key: "device_id")
    var deviceID: String?

    @OptionalField(key: "install_id")
    var installID: String?

    @OptionalField(key: "launch_id")
    var launchID: String?

    @OptionalField(key: "session_id")
    var sessionID: String?

    @OptionalField(key: "date")
    var date: Date?

    @OptionalField(key: "start_date")
    var startDate: Date?

    @OptionalField(key: "end_date")
    var endDate: Date?

    @OptionalField(key: "hour_epoch")
    var hourEpoch: Int64?

    @OptionalField(key: "day_epoch")
    var dayEpoch: Int64?

    @OptionalField(key: "param_count")
    var paramCount: Int64?

    @OptionalField(key: "value_int")
    var valueInt: Int64?

    @OptionalField(key: "value_double")
    var valueDouble: Double?

    @Field(key: "payload")
    var payload: [String: FieldValue]

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}
}

// MARK: - DTO Mapping

extension RecordModel {
    convenience init(dto: RecordDTO) {
        self.init()
        recordType = dto.recordType
        recordName = dto.recordName
        apply(fields: dto.fields)
    }

    /// Replaces the payload and re-extracts the queryable columns.
    func apply(fields: [String: FieldValue]) {
        payload = fields

        name = fields["name"]?.stringValue
        category = fields["category"]?.stringValue
        level = fields["level"]?.stringValue
        uuid = fields["uuid"]?.stringValue
        deviceID = fields["device_id"]?.stringValue
        installID = fields["install_id"]?.stringValue
        launchID = fields["launch_id"]?.stringValue
        sessionID = fields["session_id"]?.stringValue
        date = fields["date"]?.dateValue
        startDate = fields["start_date"]?.dateValue
        endDate = fields["end_date"]?.dateValue
        paramCount = fields["param_count"]?.intValue

        let reference = fields["date"]?.dateValue ?? fields["start_date"]?.dateValue
        let hour = fields["hour"]?.dateValue ?? reference?.startOfHour
        let day = fields["day"]?.dateValue ?? reference?.startOfDay
        hourEpoch = hour.map { Int64($0.timeIntervalSince1970) }
        dayEpoch = day.map { Int64($0.timeIntervalSince1970) }

        switch fields["value"] {
        case .int(let value):
            valueInt = value
            valueDouble = nil
        case .double(let value):
            valueDouble = value
            valueInt = nil
        default:
            valueInt = nil
            valueDouble = nil
        }
    }

    var dto: RecordDTO {
        RecordDTO(recordType: recordType, recordName: recordName, fields: payload)
    }
}

// MARK: - Migration

struct CreateRecord: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(RecordModel.schema)
            .id()
            .field("record_type", .string, .required)
            .field("record_name", .string, .required)
            .field("name", .string)
            .field("category", .string)
            .field("level", .string)
            .field("uuid", .string)
            .field("device_id", .string)
            .field("install_id", .string)
            .field("launch_id", .string)
            .field("session_id", .string)
            .field("date", .datetime)
            .field("start_date", .datetime)
            .field("end_date", .datetime)
            .field("hour_epoch", .int64)
            .field("day_epoch", .int64)
            .field("param_count", .int64)
            .field("value_int", .int64)
            .field("value_double", .double)
            .field("payload", .json, .required)
            .field("created_at", .datetime)
            .field("ingest_source", .string)
            .unique(on: "record_name")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(RecordModel.schema).delete()
    }
}
