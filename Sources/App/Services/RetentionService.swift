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
/// installs answered yes. Each cohort is also split into segments by the OS
/// major version of the install's first session, and each segment counts the
/// installs that crashed or hung soon after install. The result is served
/// directly from `GET /api/v1/metrics/retention`.
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

    /// The incident record types a segment counts affected installs for.
    static let crashSource = "Crash"
    static let hangSource = "Hang"

    /// Day-since-install milestones, in days, at which bounded retention is
    /// reported. Must stay in lockstep with the client's
    /// `RetentionCohort.dayOffsets`.
    ///
    static let dayOffsets = [0, 1, 3, 7, 14, 30]

    /// Days after install within which a crash or hang marks an install as
    /// affected: every day up to the last milestone.
    ///
    static let horizon = (dayOffsets.last ?? 0) + 1

    /// One weekly cohort per install week in the half-open `[from, to)` range,
    /// each carrying its install count, the retained count at every milestone,
    /// and its OS segments. A milestone that has not fully elapsed for the
    /// whole cohort by `to` is reported as `nil`, leaving the cohort table's
    /// triangular gap.
    ///
    static func cohorts(from: Date, to: Date, on database: any Database) async throws -> [RetentionCohortPoint] {
        let rows = try await activity(from: from, to: to, on: database)
        let systems = try await systems(from: from, to: to, on: database)
        let incidents = try await incidents(from: from, to: to, on: database)

        var installs: [String: InstallActivity] = [:]

        for row in rows {
            let installDay = Date(timeIntervalSince1970: Double(row.installDay))
            var entry = installs[row.install] ?? InstallActivity(day: installDay)
            if let active = row.activeDay {
                entry.offsets.insert(Int((active - row.installDay) / 86_400))
            }
            installs[row.install] = entry
        }

        var cohorts: [Date: Tally] = [:]
        var segments: [Date: [String: Tally]] = [:]

        for (install, entry) in installs {
            let week = entry.day.startOfWeek
            let crashed = incidents.contains(Incident(install: install, kind: crashSource))
            let hung = incidents.contains(Incident(install: install, kind: hangSource))

            cohorts[week, default: Tally()].add(entry, crashed: crashed, hung: hung)

            if let system = systems[install] {
                segments[week, default: [:]][system, default: Tally()].add(entry, crashed: crashed, hung: hung)
            }
        }

        return cohorts.keys.sorted().map { week in
            let cohort = cohorts[week] ?? Tally()

            return RetentionCohortPoint(
                date: Int64((week.timeIntervalSince1970 * 1000).rounded()),
                size: cohort.size,
                retained: cohort.cells(week: week, to: to),
                segments: (segments[week] ?? [:]).sorted { $0.key < $1.key }.map { name, segment in
                    RetentionSegmentPoint(
                        name: name,
                        size: segment.size,
                        retained: segment.cells(week: week, to: to),
                        crashes: segment.crashes,
                        hangs: segment.hangs
                    )
                }
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
        let sql = try database.sql()

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

    private struct SystemRow: Decodable {
        let install: String
        let os: String
    }

    /// The OS major version of each install's earliest session in range that
    /// carries one, such as "iOS 18" for "iOS 18.2".
    ///
    private static func systems(from: Date, to: Date, on database: any Database) async throws -> [String: String] {
        let sql = try database.sql()

        let lower = Int64(from.timeIntervalSince1970)
        let upper = Int64(to.timeIntervalSince1970)

        let rows = try await sql.raw(
            """
            SELECT install, os
            FROM (
                SELECT install_id AS install, os_version AS os,
                       ROW_NUMBER() OVER (PARTITION BY install_id ORDER BY start_date, id) AS rn
                FROM records
                WHERE record_type = \(bind: activitySource)
                  AND install_id IS NOT NULL AND os_version IS NOT NULL AND start_date IS NOT NULL
                  AND day_epoch >= \(bind: lower) AND day_epoch < \(bind: upper)
            ) AS ranked
            WHERE rn = 1
            """
        ).all(decoding: SystemRow.self)

        return Dictionary(rows.map { ($0.install, String($0.os.prefix { $0 != "." })) }) { first, _ in first }
    }

    private struct Incident: Decodable, Hashable {
        let install: String
        let kind: String
    }

    /// Every (install, incident type) pair where the install crashed or hung
    /// within `horizon` days of its install day.
    ///
    private static func incidents(from: Date, to: Date, on database: any Database) async throws -> Set<Incident> {
        let sql = try database.sql()

        let lower = Int64(from.timeIntervalSince1970)
        let upper = Int64(to.timeIntervalSince1970)
        let span = Int64(horizon * 86_400)

        let rows = try await sql.raw(
            """
            WITH installs AS (
                SELECT install_id, MIN(day_epoch) AS install_day
                FROM records
                WHERE record_type = \(bind: installSource)
                  AND install_id IS NOT NULL AND day_epoch IS NOT NULL
                GROUP BY install_id
            )
            SELECT DISTINCT r.install_id AS install, r.record_type AS kind
            FROM records r
            JOIN installs i ON r.install_id = i.install_id
            WHERE r.record_type IN (\(bind: crashSource), \(bind: hangSource))
              AND r.day_epoch >= i.install_day
              AND r.day_epoch < i.install_day + \(bind: span)
              AND r.day_epoch < \(bind: upper)
              AND i.install_day >= \(bind: lower) AND i.install_day < \(bind: upper)
            """
        ).all(decoding: Incident.self)

        return Set(rows)
    }
}

/// One install's day and the day offsets on which it was active.
private struct InstallActivity {
    let day: Date
    var offsets: Set<Int> = []
}

/// The running counts of a cohort or a segment.
private struct Tally {
    var size = 0
    var retained: [Int: Int] = [:]
    var crashes = 0
    var hangs = 0

    mutating func add(_ install: InstallActivity, crashed: Bool, hung: Bool) {
        size += 1

        for (index, offset) in RetentionService.dayOffsets.enumerated() where install.offsets.contains(offset) {
            retained[index, default: 0] += 1
        }

        if crashed {
            crashes += 1
        }
        if hung {
            hangs += 1
        }
    }

    /// The retained count at each milestone, or `nil` when the milestone has
    /// not fully elapsed for the whole cohort week by `to`.
    ///
    func cells(week: Date, to: Date) -> [Int?] {
        RetentionService.dayOffsets.enumerated().map { index, offset in
            let matured = Calendar.utc.date(byAdding: .day, value: 7 + offset, to: week)!
            guard matured < to else {
                return nil
            }
            return retained[index] ?? 0
        }
    }
}
