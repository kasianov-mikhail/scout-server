//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Fluent
import SQLKit
import Vapor

/// Computes a DAU/WAU/MAU time series from raw `Session` records.
///
/// The Scout client marks activity forward: an install active on day A
/// counts as weekly-active for every day in `[A, A + 1 week)` and
/// monthly-active for `[A, A + 1 month)`, summing 0/1 flags per install
/// across all clients. The server mirrors that exact algorithm over the
/// distinct (install, day) pairs derived from raw Session records and serves
/// the result as a flat series from `GET /api/v1/metrics/active-users`.
///
enum ActiveUserService {
    /// The record type whose rows signal user activity. Every app
    /// foreground creates a Session, making it the activity heartbeat.
    ///
    static let activitySource = "Session"

    private enum Period: String, CaseIterable {
        case daily = "d"
        case weekly = "w"
        case monthly = "m"

        var component: Calendar.Component {
            switch self {
            case .daily: .day
            case .weekly: .weekOfYear
            case .monthly: .month
            }
        }
    }

    /// A flat DAU/WAU/MAU series — the aggregation-native shape the server
    /// serves directly. One point per UTC day in
    /// the half-open `[from, to)` range, each an as-of trailing distinct-install
    /// count (daily, 7-day, calendar-month). Zero-activity days are included so
    /// the result is a dense, directly chartable series.
    ///
    static func series(from: Date, to: Date, on database: any Database) async throws -> [ActiveUserPoint] {
        let constraints = MatrixConstraints(dateRange: from..<to)
        let active = try await activeInstalls(constraints, on: database)

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

    /// For each period, the set of installs counted active on each day. An
    /// install active on day A is marked forward across `[A, A + 1 period)`,
    /// so a day's set is exactly the distinct installs active in the trailing
    /// window ending that day. Days at or after the range's upper bound are
    /// skipped, matching the half-open query semantics.
    ///
    private static func activeInstalls(_ constraints: MatrixConstraints, on database: any Database) async throws -> [Period: [Date: Set<String>]] {
        let pairs = try await activity(constraints, on: database)

        var active: [Period: [Date: Set<String>]] = [:]
        let calendar = Calendar.utc

        for pair in pairs {
            let day = Date(timeIntervalSince1970: Double(pair.day))

            for period in Period.allCases {
                let limit = calendar.date(byAdding: period.component, value: 1, to: day)!
                var marked = day

                while marked < limit {
                    if constraints.dateRange.upperBound > marked {
                        active[period, default: [:]][marked, default: []].insert(pair.install)
                    }
                    marked = calendar.date(byAdding: .day, value: 1, to: marked)!
                }
            }
        }

        return active
    }

    private struct ActivityPair: Decodable {
        let install: String
        let day: Int64
    }

    /// Distinct (install, day) activity pairs. The lower bound backs off
    /// far enough that a month-long forward mark still reaches the range.
    ///
    private static func activity(_ constraints: MatrixConstraints, on database: any Database) async throws -> [ActivityPair] {
        let sql = try MatrixService.sqlDatabase(database)

        let lower =
            constraints.dateRange.lowerBound == .distantPast
            ? Int64.min / 2
            : Int64(constraints.dateRange.lowerBound.timeIntervalSince1970) - 32 * 86_400
        let upper =
            constraints.dateRange.upperBound == .distantFuture
            ? Int64.max / 2
            : Int64(constraints.dateRange.upperBound.timeIntervalSince1970)

        return try await sql.raw(
            """
            SELECT DISTINCT install_id AS install, day_epoch AS day
            FROM records
            WHERE record_type = \(bind: activitySource)
              AND install_id IS NOT NULL
              AND day_epoch >= \(bind: lower) AND day_epoch < \(bind: upper)
            """
        ).all(decoding: ActivityPair.self)
    }
}
