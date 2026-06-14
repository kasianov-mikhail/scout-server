//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import XCTVapor

@testable import App

/// `GET /metrics/series` flattens the same raw records that feed the
/// `DateIntMatrix` / `DateDoubleMatrix` grid onto a single time axis: one
/// dense point per bucket for a single name, counts as `.int` and metric sums
/// as `.double`. 2026-06-10 is a Wednesday; its week starts Sunday 2026-06-07.
///
final class MetricSeriesTests: XCTestCase {
    func value(_ series: [MetricSeriesPoint], _ date: Date) -> FieldValue? {
        let ms = Int64((date.timeIntervalSince1970 * 1000).rounded())
        return series.first { $0.date == ms }?.value
    }

    func testEventCountsBecomeDailySeries() async throws {
        try await withApp { app in
            try await write(
                [
                    makeEvent(name: "login", date: utcDate(2026, 6, 10, 9, 5)),
                    makeEvent(name: "login", date: utcDate(2026, 6, 10, 9, 55)),
                    makeEvent(name: "login", date: utcDate(2026, 6, 10, 23, 0)),
                    makeEvent(name: "logout", date: utcDate(2026, 6, 10, 10, 0)),
                ],
                to: app
            )

            let series = try await metricSeries(
                name: "login", from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            XCTAssertEqual(series.count, 1)
            XCTAssertEqual(value(series, utcDate(2026, 6, 10)), .int(3))
        }
    }

    func testEmptyBucketsAreZeroFilled() async throws {
        try await withApp { app in
            try await write([makeEvent(name: "login", date: utcDate(2026, 6, 10, 9))], to: app)

            let series = try await metricSeries(
                name: "login", from: utcDate(2026, 6, 9), to: utcDate(2026, 6, 12), on: app
            )

            XCTAssertEqual(series.count, 3)
            XCTAssertEqual(value(series, utcDate(2026, 6, 9)), .int(0))
            XCTAssertEqual(value(series, utcDate(2026, 6, 10)), .int(1))
            XCTAssertEqual(value(series, utcDate(2026, 6, 11)), .int(0))
        }
    }

    func testHourBucketResolution() async throws {
        try await withApp { app in
            try await write(
                [
                    makeEvent(name: "login", date: utcDate(2026, 6, 10, 9, 5)),
                    makeEvent(name: "login", date: utcDate(2026, 6, 10, 9, 55)),
                    makeEvent(name: "login", date: utcDate(2026, 6, 10, 10, 0)),
                ],
                to: app
            )

            let series = try await metricSeries(
                name: "login", bucket: "hour",
                from: utcDate(2026, 6, 10, 9), to: utcDate(2026, 6, 10, 11), on: app
            )

            XCTAssertEqual(series.count, 2)
            XCTAssertEqual(value(series, utcDate(2026, 6, 10, 9)), .int(2))
            XCTAssertEqual(value(series, utcDate(2026, 6, 10, 10)), .int(1))
        }
    }

    func testWeekBucketResolution() async throws {
        try await withApp { app in
            try await write(
                [
                    makeEvent(name: "login", date: utcDate(2026, 6, 10, 12)),
                    makeEvent(name: "login", date: utcDate(2026, 6, 17, 12)),
                ],
                to: app
            )

            let series = try await metricSeries(
                name: "login", bucket: "week",
                from: utcDate(2026, 6, 7), to: utcDate(2026, 6, 21), on: app
            )

            XCTAssertEqual(series.count, 2)
            XCTAssertEqual(value(series, utcDate(2026, 6, 7)), .int(1))
            XCTAssertEqual(value(series, utcDate(2026, 6, 14)), .int(1))
        }
    }

    func testLifecycleCountsByType() async throws {
        try await withApp { app in
            try await write(
                [
                    makeSession(start: utcDate(2026, 6, 10, 9), installID: "a"),
                    makeSession(start: utcDate(2026, 6, 10, 14), installID: "b"),
                ],
                to: app
            )

            let series = try await metricSeries(
                name: "Session", from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            XCTAssertEqual(value(series, utcDate(2026, 6, 10)), .int(2))
        }
    }

    func testIntMetricSumsFilteredByCategory() async throws {
        try await withApp { app in
            try await write(
                [
                    makeMetric(name: "requests", category: "counter", date: utcDate(2026, 6, 10, 9, 1), value: .int(5)),
                    makeMetric(name: "requests", category: "counter", date: utcDate(2026, 6, 10, 15, 0), value: .int(7)),
                    makeMetric(name: "requests", category: "meter", date: utcDate(2026, 6, 10, 9, 0), value: .int(99)),
                ],
                to: app
            )

            let series = try await metricSeries(
                name: "requests", category: "counter",
                from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            XCTAssertEqual(value(series, utcDate(2026, 6, 10)), .int(12))
        }
    }

    func testDoubleMetricBecomesDoubleSeries() async throws {
        try await withApp { app in
            try await write(
                [
                    makeMetric(type: "DoubleMetric", name: "duration", category: "timer", date: utcDate(2026, 6, 10, 9), value: .double(0.5)),
                    makeMetric(type: "DoubleMetric", name: "duration", category: "timer", date: utcDate(2026, 6, 10, 9, 30), value: .double(1.25)),
                ],
                to: app
            )

            let series = try await metricSeries(
                name: "duration", category: "timer",
                from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            XCTAssertEqual(value(series, utcDate(2026, 6, 10)), .double(1.75))
        }
    }

    func testMissingNameIsRejected() async throws {
        try await withApp { app in
            try await app.test(
                .GET, "api/v1/metrics/series?from=0&to=1",
                headers: .authorized,
                afterResponse: { res async in
                    XCTAssertEqual(res.status, .badRequest)
                }
            )
        }
    }

    func testUnknownBucketIsRejected() async throws {
        try await withApp { app in
            try await app.test(
                .GET, "api/v1/metrics/series?name=login&bucket=fortnight&from=0&to=1",
                headers: .authorized,
                afterResponse: { res async in
                    XCTAssertEqual(res.status, .badRequest)
                }
            )
        }
    }
}
