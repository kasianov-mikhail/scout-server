//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Fluent
import SQLKit
import Vapor

enum DeviceService {
    static let sessionSource = "Session"
    static let crashSource = "Crash"
    static let deviceSource = "Device"

    private static let modelBatch = 500

    static func devices(from: Date, to: Date, on database: any Database) async throws -> [DevicePoint] {
        let sessions = try await latestSessions(from: from, to: to, on: database)
        let crashes = try await crashCounts(from: from, to: to, on: database)
        let models = try await models(devices: sessions.map(\.device), on: database)

        return sessions.map { session in
            DevicePoint(
                deviceID: session.device,
                model: models[session.device],
                osVersion: session.os,
                lastSeen: session.lastSeen.milliseconds,
                sessions: session.sessions,
                crashes: crashes[session.device] ?? 0
            )
        }
        .sorted { $0.deviceID < $1.deviceID }
    }

    static func counts(ranges: [Range<Date>], on database: any Database) async throws -> [Int] {
        let sql = try database.sql()
        var counts: [Int] = []

        for range in ranges {
            let row = try await sql.raw(
                """
                SELECT COUNT(DISTINCT device_id) AS devices
                FROM records
                WHERE record_type = \(bind: sessionSource)
                  AND device_id IS NOT NULL
                  AND start_date >= \(bind: range.lowerBound) AND start_date < \(bind: range.upperBound)
                """
            ).first(decoding: DeviceCount.self)

            counts.append(row?.devices ?? 0)
        }

        return counts
    }

    private struct DeviceCount: Decodable {
        let devices: Int
    }

    private struct LatestSession: Decodable {
        let device: String
        let os: String?
        let lastSeen: Date
        let sessions: Int

        enum CodingKeys: String, CodingKey {
            case device
            case os
            case lastSeen = "last_seen"
            case sessions
        }
    }

    private static func latestSessions(from: Date, to: Date, on database: any Database) async throws -> [LatestSession] {
        let sql = try database.sql()

        return try await sql.raw(
            """
            WITH ranked AS (
                SELECT device_id, os_version, start_date,
                       ROW_NUMBER() OVER (PARTITION BY device_id ORDER BY start_date DESC) AS position,
                       COUNT(*) OVER (PARTITION BY device_id) AS sessions
                FROM records
                WHERE record_type = \(bind: sessionSource)
                  AND device_id IS NOT NULL
                  AND start_date >= \(bind: from) AND start_date < \(bind: to)
            )
            SELECT device_id AS device, os_version AS os, start_date AS last_seen, sessions
            FROM ranked
            WHERE position = 1
            """
        ).all(decoding: LatestSession.self)
    }

    private struct CrashCount: Decodable {
        let device: String
        let crashes: Int
    }

    private static func crashCounts(from: Date, to: Date, on database: any Database) async throws -> [String: Int] {
        let sql = try database.sql()

        let rows = try await sql.raw(
            """
            SELECT device_id AS device, COUNT(*) AS crashes
            FROM records
            WHERE record_type = \(bind: crashSource)
              AND device_id IS NOT NULL
              AND date >= \(bind: from) AND date < \(bind: to)
            GROUP BY device_id
            """
        ).all(decoding: CrashCount.self)

        return Dictionary(uniqueKeysWithValues: rows.map { ($0.device, $0.crashes) })
    }

    private static func models(devices: [String], on database: any Database) async throws -> [String: String] {
        var models: [String: String] = [:]

        for start in stride(from: 0, to: devices.count, by: modelBatch) {
            let batch = Array(devices[start..<min(start + modelBatch, devices.count)])

            let records = try await RecordModel.query(on: database)
                .filter(\.$recordType == deviceSource)
                .filter(\.$deviceID ~~ batch)
                .all()

            for record in records {
                guard let device = record.deviceID else {
                    continue
                }
                guard let model = record.payload["model"]?.stringValue else {
                    continue
                }
                models[device] = model
            }
        }

        return models
    }
}
