//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import XCTVapor

@testable import App

/// `reduce=last` folds a bucket to its newest observation instead of summing,
/// which is what a gauge needs. 2026-06-10 is a Wednesday.
///
final class MetricSeriesReduceTests: XCTestCase {
    private func value(_ groups: [MetricSeriesGroup], _ name: String, _ date: Date) -> FieldValue? {
        let ms = Int64((date.timeIntervalSince1970 * 1000).rounded())
        return groups.first { $0.name == name }?.points.first { $0.date == ms }?.value
    }

    private func gauge(_ value: Double, at date: Date) -> Record {
        makeMetric(type: "DoubleMetric", name: "queue_depth", category: "meter", date: date, value: .double(value))
    }

    func testLastKeepsTheNewestValueInTheBucket() async throws {
        try await withApp { app in
            try await write(
                [
                    gauge(5, at: utcDate(2026, 6, 10, 9, 10)),
                    gauge(8, at: utcDate(2026, 6, 10, 9, 40)),
                    gauge(3, at: utcDate(2026, 6, 10, 9, 55)),
                ],
                to: app
            )

            let groups = try await metricSeries(
                category: "meter", values: "double", bucket: "hour", reduce: "last",
                from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            XCTAssertEqual(value(groups, "queue_depth", utcDate(2026, 6, 10, 9)), .double(3))
        }
    }

    func testSumRemainsTheDefault() async throws {
        try await withApp { app in
            try await write(
                [gauge(5, at: utcDate(2026, 6, 10, 9, 10)), gauge(8, at: utcDate(2026, 6, 10, 9, 40))],
                to: app
            )

            let groups = try await metricSeries(
                category: "meter", values: "double", bucket: "hour",
                from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            XCTAssertEqual(value(groups, "queue_depth", utcDate(2026, 6, 10, 9)), .double(13))
        }
    }

    func testLastResolvesEachBucketIndependently() async throws {
        try await withApp { app in
            try await write(
                [
                    gauge(5, at: utcDate(2026, 6, 10, 9, 10)),
                    gauge(2, at: utcDate(2026, 6, 10, 9, 50)),
                    gauge(9, at: utcDate(2026, 6, 10, 10, 5)),
                ],
                to: app
            )

            let groups = try await metricSeries(
                category: "meter", values: "double", bucket: "hour", reduce: "last",
                from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            XCTAssertEqual(value(groups, "queue_depth", utcDate(2026, 6, 10, 9)), .double(2))
            XCTAssertEqual(value(groups, "queue_depth", utcDate(2026, 6, 10, 10)), .double(9))
        }
    }

    func testLastFoldsHoursIntoTheNewestOfADayBucket() async throws {
        try await withApp { app in
            try await write(
                [
                    gauge(5, at: utcDate(2026, 6, 10, 9, 10)),
                    gauge(7, at: utcDate(2026, 6, 10, 23, 30)),
                ],
                to: app
            )

            let groups = try await metricSeries(
                category: "meter", values: "double", bucket: "day", reduce: "last",
                from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            XCTAssertEqual(value(groups, "queue_depth", utcDate(2026, 6, 10)), .double(7))
        }
    }

    func testLastKeepsAZeroReading() async throws {
        try await withApp { app in
            try await write(
                [gauge(7, at: utcDate(2026, 6, 10, 9, 10)), gauge(0, at: utcDate(2026, 6, 10, 9, 40))],
                to: app
            )

            let groups = try await metricSeries(
                category: "meter", values: "double", bucket: "hour", reduce: "last",
                from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            XCTAssertEqual(value(groups, "queue_depth", utcDate(2026, 6, 10, 9)), .double(0))
        }
    }

    func testUnknownReduceIsRejected() async throws {
        try await withApp { app in
            let from = Int64(utcDate(2026, 6, 10).timeIntervalSince1970 * 1000)
            let to = Int64(utcDate(2026, 6, 11).timeIntervalSince1970 * 1000)

            try await app.test(
                .GET, "api/v1/metrics/series?category=meter&reduce=median&from=\(from)&to=\(to)",
                headers: .authorized,
                afterResponse: { res async in
                    XCTAssertEqual(res.status, .badRequest)
                }
            )
        }
    }
}
