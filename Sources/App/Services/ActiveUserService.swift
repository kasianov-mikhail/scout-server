//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Fluent
import SQLKit
import Vapor

enum ActiveUserService {
    static let visitSource = "Visit"

    static let sessionSource = "Session"

    private enum Period: CaseIterable {
        case daily
        case weekly
        case monthly

        var days: Int {
            switch self {
            case .daily: 1
            case .weekly: 7
            case .monthly: 30
            }
        }
    }

    static func series(from: Date, to: Date, on database: any Database) async throws -> [ActiveUserPoint] {
        let active = try await activeDevices(in: from..<to, on: database)

        var points: [ActiveUserPoint] = []
        var day = from.startOfDay

        while day < to {
            points.append(
                ActiveUserPoint(
                    date: day.milliseconds,
                    dau: active[.daily]?[day]?.count ?? 0,
                    wau: active[.weekly]?[day]?.count ?? 0,
                    mau: active[.monthly]?[day]?.count ?? 0
                )
            )
            day = Calendar.utc.date(byAdding: .day, value: 1, to: day)!
        }

        return points
    }

    private static func activeDevices(in range: Range<Date>, on database: any Database) async throws -> [Period: [Date: Set<String>]] {
        let pairs = try await activity(in: range, on: database)

        var active: [Period: [Date: Set<String>]] = [:]
        let calendar = Calendar.utc

        for pair in pairs {
            let day = Date(timeIntervalSince1970: Double(pair.day))

            for period in Period.allCases {
                for offset in 0..<period.days {
                    let marked = calendar.date(byAdding: .day, value: offset, to: day)!

                    guard marked < range.upperBound else {
                        break
                    }
                    active[period, default: [:]][marked, default: []].insert(pair.device)
                }
            }
        }

        return active
    }

    private struct ActivityPair: Decodable {
        let device: String
        let day: Int64
    }

    private static func activity(in range: Range<Date>, on database: any Database) async throws -> [ActivityPair] {
        let sql = try database.sql()

        let lower = Int64(range.lowerBound.timeIntervalSince1970) - 30 * 86_400
        let upper = Int64(range.upperBound.timeIntervalSince1970)

        return try await sql.raw(
            """
            SELECT DISTINCT device_id AS device, day_epoch AS day
            FROM records
            WHERE record_type IN (\(bind: visitSource), \(bind: sessionSource))
              AND device_id IS NOT NULL
              AND day_epoch >= \(bind: lower) AND day_epoch < \(bind: upper)
            """
        ).all(decoding: ActivityPair.self)
    }
}
