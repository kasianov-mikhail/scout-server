//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Fluent
import SQLKit
import Vapor

/// Computes a DAU/WAU/MAU time series from the raw records that signal
/// activity.
///
/// The Scout client marks activity forward: a device active on day A counts
/// as weekly-active for every day in `[A, A + 7 days)` and monthly-active
/// for `[A, A + 30 days)`, summing 0/1 flags per device across all clients.
/// The server mirrors that exact algorithm over the distinct (device, day)
/// pairs derived from raw records and serves the result as a flat series
/// from `GET /api/v1/metrics/active-users`.
///
/// Activity is counted per device, not per install, so reinstalling stays
/// one active user rather than becoming two. Retention counts installs
/// instead — a cohort is an acquisition, so `RetentionService` keys on
/// `install_id`.
///
enum ActiveUserService {
    /// The marker the client writes once per device per day: its explicit
    /// activity heartbeat.
    ///
    static let visitSource = "Visit"

    /// Every app foreground creates a session, so sessions signal activity
    /// too. The client counts both sources, and a device that produced
    /// either on a day is active that day.
    ///
    static let sessionSource = "Session"

    private enum Period: CaseIterable {
        case daily
        case weekly
        case monthly

        /// The length of the trailing window, in days. The month is a fixed
        /// 30 days rather than a calendar month, matching the client — a
        /// calendar month would stretch and shrink the window with the
        /// month's length.
        ///
        var days: Int {
            switch self {
            case .daily: 1
            case .weekly: 7
            case .monthly: 30
            }
        }
    }

    /// A flat DAU/WAU/MAU series — the aggregation-native shape the server
    /// serves directly. One point per UTC day in
    /// the half-open `[from, to)` range, each an as-of trailing distinct-device
    /// count (1, 7, and 30 days). Zero-activity days are included so the
    /// result is a dense, directly chartable series.
    ///
    static func series(from: Date, to: Date, on database: any Database) async throws -> [ActiveUserPoint] {
        let active = try await activeDevices(in: from..<to, on: database)

        var points: [ActiveUserPoint] = []
        var day = from.startOfDay

        while day < to {
            points.append(
                ActiveUserPoint(
                    date: Int64((day.timeIntervalSince1970 * 1000).rounded()),
                    dau: active[.daily]?[day]?.count ?? 0,
                    wau: active[.weekly]?[day]?.count ?? 0,
                    mau: active[.monthly]?[day]?.count ?? 0
                )
            )
            day = Calendar.utc.date(byAdding: .day, value: 1, to: day)!
        }

        return points
    }

    /// For each period, the set of devices counted active on each day. A
    /// device active on day A is marked forward across `[A, A + period)`, so
    /// a day's set is exactly the distinct devices active in the trailing
    /// window ending that day. Days at or after the range's upper bound are
    /// skipped, matching the half-open query semantics.
    ///
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

    /// Distinct (device, day) activity pairs. The lower bound backs off far
    /// enough that a 30-day forward mark still reaches the range.
    ///
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
