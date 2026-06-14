//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Fluent
import Vapor

/// Serves pre-aggregated metric series natively, the simpler counterpart of
/// the CloudKit matrices Scout reconstructs by hand. Where CloudKit forces the
/// client to maintain `PeriodMatrix` records, an HTTP backend just answers with
/// the finished series.
///
struct MetricsController: RouteCollection {
    /// Span used when the caller omits `from`: the trailing 90 days.
    static let defaultSpan: TimeInterval = 90 * 86_400

    func boot(routes: any RoutesBuilder) throws {
        let metrics = routes.grouped("metrics")
        metrics.get("active-users", use: activeUsers)
    }

    /// `GET /metrics/active-users?from=<ms>&to=<ms>` — one DAU/WAU/MAU point per
    /// UTC day over the half-open `[from, to)` range. Both bounds are
    /// milliseconds since the Unix epoch; `to` defaults to now and `from` to
    /// 90 days before `to`.
    ///
    func activeUsers(req: Request) async throws -> ActiveUsersResponse {
        let to = req.query[Int64.self, at: "to"].map(Self.date(ms:)) ?? Date()
        let from = req.query[Int64.self, at: "from"].map(Self.date(ms:)) ?? to.addingTimeInterval(-Self.defaultSpan)

        guard from < to else {
            throw Abort(.badRequest, reason: "Empty range: 'from' must be before 'to'")
        }

        let series = try await ActiveUserService.series(from: from, to: to, on: req.db)
        return ActiveUsersResponse(series: series)
    }

    private static func date(ms: Int64) -> Date {
        Date(timeIntervalSince1970: Double(ms) / 1000)
    }
}
