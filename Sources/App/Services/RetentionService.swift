//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Fluent
import SQLKit
import Vapor

/// Builds a weekly retention-cohort table from raw `Install` and `Session`
/// records.
///
/// Installs are grouped into acquisition cohorts by the UTC week of their
/// install day. For each install and each milestone in `dayOffsets`, bounded
/// day-N retention asks a single yes/no question: was the install active on
/// exactly `install day + N`? A cohort's `retained[N]` is how many of its
/// installs answered yes. The result is served directly from
/// `GET /api/v1/metrics/retention`.
///
enum RetentionService {
    /// The record type that anchors a cohort: one per install, carrying the
    /// install day.
    ///
    static let installSource = "Install"

    /// The record type that signals activity. Every app foreground creates a
    /// Session, making it the return-visit heartbeat.
    ///
    static let activitySource = "Session"

    /// Day-since-install milestones, in days, at which bounded retention is
    /// reported. Must stay in lockstep with the client's
    /// `RetentionCohort.dayOffsets`.
    ///
    static let dayOffsets = [0, 1, 3, 7, 14, 30]

    /// One weekly cohort per install week in the half-open `[from, to)` range,
    /// each carrying its install count and the retained count at every
    /// milestone. A milestone that has not fully elapsed for the whole cohort
    /// by `to` is reported as `nil`, leaving the cohort table's triangular gap.
    ///
    static func cohorts(from: Date, to: Date, on database: any Database) async throws -> [RetentionCohortPoint] {
        let rows = try await activity(from: from, to: to, on: database)
        let calendar = Calendar.utc

        var installs: [String: (day: Date, offsets: Set<Int>)] = [:]

        for row in rows {
            let installDay = Date(timeIntervalSince1970: Double(row.installDay))
            var entry = installs[row.install] ?? (day: installDay, offsets: [])
            if let active = row.activeDay {
                entry.offsets.insert(Int((active - row.installDay) / 86_400))
            }
            installs[row.install] = entry
        }

        var sizes: [Date: Int] = [:]
        var retained: [Date: [Int: Int]] = [:]

        for (_, entry) in installs {
            let week = entry.day.startOfWeek
            sizes[week, default: 0] += 1

            for (index, offset) in dayOffsets.enumerated() where entry.offsets.contains(offset) {
                retained[week, default: [:]][index, default: 0] += 1
            }
        }

        return sizes.keys.sorted().map { week in
            let counts = retained[week] ?? [:]

            let cells = dayOffsets.enumerated().map { index, offset -> Int? in
                let matured = calendar.date(byAdding: .day, value: 6 + offset, to: week)!
                guard matured < to else {
                    return nil
                }
                return counts[index] ?? 0
            }

            return RetentionCohortPoint(
                date: Int64((week.timeIntervalSince1970 * 1000).rounded()),
                size: sizes[week] ?? 0,
                retained: cells
            )
        }
    }

    private struct RetentionRow: Decodable {
        let install: String
        let installDay: Int64
        let activeDay: Int64?

        enum CodingKeys: String, CodingKey {
            case install
            case installDay = "install_day"
            case activeDay = "active_day"
        }
    }

    /// Each install in range paired with every distinct day it was active
    /// within its first 30 days (offset 0…30). Installs with no activity still
    /// appear once with a `nil` active day, so cohort sizes count every
    /// acquired install, not just the returning ones.
    ///
    private static func activity(from: Date, to: Date, on database: any Database) async throws -> [RetentionRow] {
        let sql = try MatrixService.sqlDatabase(database)

        let lower = Int64(from.timeIntervalSince1970)
        let upper = Int64(to.timeIntervalSince1970)
        let maxOffset = Int64((dayOffsets.max() ?? 0) * 86_400)

        return try await sql.raw(
            """
            WITH installs AS (
                SELECT install_id, MIN(day_epoch) AS install_day
                FROM records
                WHERE record_type = \(bind: installSource)
                  AND install_id IS NOT NULL AND day_epoch IS NOT NULL
                GROUP BY install_id
            ),
            activity AS (
                SELECT DISTINCT install_id, day_epoch
                FROM records
                WHERE record_type = \(bind: activitySource)
                  AND install_id IS NOT NULL AND day_epoch IS NOT NULL
            )
            SELECT i.install_id AS install, i.install_day AS install_day, a.day_epoch AS active_day
            FROM installs i
            LEFT JOIN activity a
              ON a.install_id = i.install_id
              AND a.day_epoch >= i.install_day
              AND a.day_epoch <= i.install_day + \(bind: maxOffset)
              AND a.day_epoch < \(bind: upper)
            WHERE i.install_day >= \(bind: lower) AND i.install_day < \(bind: upper)
            """
        ).all(decoding: RetentionRow.self)
    }
}
