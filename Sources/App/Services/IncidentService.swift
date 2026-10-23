//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Fluent
import SQLKit
import Vapor

enum IncidentService {
    static let recordTypes = ["Crash", "Hang"]

    static func index(recordType: String, from: Date, to: Date, on database: any Database) async throws -> IncidentsResponse {
        let sql = try database.sql()

        let unkeyed = try await sql.raw(
            """
            SELECT MIN(date) AS first_date, MAX(date) AS last_date
            FROM records
            WHERE record_type = \(bind: recordType)
              AND (fingerprint IS NULL OR fingerprint = '')
              AND date >= \(bind: from) AND date < \(bind: to)
            """
        ).first(decoding: DateSpan.self)?.hours

        let keyedFrom = unkeyed.map { max(from, $0.upperBound) } ?? from

        let tallies = try await sql.raw(
            """
            SELECT fingerprint, MIN(name) AS name, COUNT(*) AS count, MIN(date) AS first_date
            FROM records
            WHERE record_type = \(bind: recordType)
              AND fingerprint IS NOT NULL AND fingerprint <> ''
              AND date >= \(bind: keyedFrom) AND date < \(bind: to)
            GROUP BY fingerprint
            ORDER BY fingerprint
            """
        ).all(decoding: TallyRow.self)

        return IncidentsResponse(
            tallies: tallies.map(\.tally),
            unkeyed: unkeyed.map(IncidentRange.init(range:))
        )
    }

    private struct DateSpan: Decodable {
        let firstDate: Date?
        let lastDate: Date?

        enum CodingKeys: String, CodingKey {
            case firstDate = "first_date"
            case lastDate = "last_date"
        }

        var hours: Range<Date>? {
            guard let firstDate, let lastDate else {
                return nil
            }
            return firstDate.startOfHour..<lastDate.startOfHour.addingTimeInterval(3600)
        }
    }

    private struct TallyRow: Decodable {
        let fingerprint: String
        let name: String?
        let count: Int
        let firstDate: Date

        enum CodingKeys: String, CodingKey {
            case fingerprint
            case name
            case count
            case firstDate = "first_date"
        }

        var tally: IncidentTally {
            IncidentTally(
                fingerprint: fingerprint,
                name: name ?? "",
                count: count,
                firstHour: firstDate.startOfHour.milliseconds
            )
        }
    }
}
