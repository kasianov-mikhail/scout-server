//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Fluent
import SQLKit
import Vapor

/// Computes DAU/WAU/MAU and shapes the result as the client's monthly
/// `PeriodMatrix` records named "ActiveUser".
///
/// The Scout client marks activity forward: an install active on day A
/// counts as weekly-active for every day in `[A, A + 1 week)` and
/// monthly-active for `[A, A + 1 month)`, summing 0/1 flags per install
/// across all clients. The server mirrors that exact algorithm over the
/// distinct (install, day) pairs derived from raw Session records.
///
enum ActiveUserService {
    static let matrixName = "ActiveUser"

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

    static func matrices(_ constraints: MatrixConstraints, on database: any Database) async throws -> [RecordDTO] {
        if let name = constraints.name, name != matrixName {
            return []
        }

        let pairs = try await activity(constraints, on: database)

        // For each period, the set of installs counted active on each day.
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

        // Fold day counts into monthly matrices: cell_<period>_<day-of-month>.
        var matrices: [Date: [String: FieldValue]] = [:]

        for (period, days) in active {
            for (day, installs) in days {
                let month = day.startOfMonth

                guard constraints.dateRange.contains(month) else {
                    continue
                }

                let index = calendar.dateComponents([.day], from: month, to: day).day ?? 0
                let cell = "cell_\(period.rawValue)_\(String(format: "%02d", index + 1))"

                matrices[month, default: [:]][cell] = .int(Int64(installs.count))
            }
        }

        return matrices.map { month, cells in
            var fields = cells
            fields["date"] = .date(month)
            fields["name"] = .string(matrixName)
            fields["version"] = .int(1)
            return RecordDTO(
                recordType: MatrixService.periodMatrixType,
                recordName: MatrixService.recordName(
                    type: MatrixService.periodMatrixType,
                    name: matrixName,
                    category: nil,
                    date: month
                ),
                fields: fields
            )
        }
    }

    // MARK: - Activity Pairs

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
