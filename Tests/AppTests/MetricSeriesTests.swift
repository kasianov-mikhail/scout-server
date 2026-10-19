//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import XCTVapor

@testable import App

final class MetricSeriesTests: XCTestCase {
    func value(_ groups: [MetricSeriesGroup], _ name: String, _ date: Date) -> FieldValue? {
        let ms = date.milliseconds
        return groups.first { $0.name == name }?.points.first { $0.date == ms }?.value
    }

    func points(_ groups: [MetricSeriesGroup], _ name: String) -> [MetricSeriesPoint] {
        groups.first { $0.name == name }?.points ?? []
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

            let groups = try await metricSeries(
                name: "login", from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            XCTAssertEqual(groups.map(\.name), ["login"])
            XCTAssertEqual(value(groups, "login", utcDate(2026, 6, 10)), .int(3))
        }
    }

    func testEmptyBucketsAreOmitted() async throws {
        try await withApp { app in
            try await write([makeEvent(name: "login", date: utcDate(2026, 6, 10, 9))], to: app)

            let groups = try await metricSeries(
                name: "login", from: utcDate(2026, 6, 9), to: utcDate(2026, 6, 12), on: app
            )

            XCTAssertEqual(points(groups, "login").count, 1)
            XCTAssertEqual(value(groups, "login", utcDate(2026, 6, 10)), .int(1))
            XCTAssertNil(value(groups, "login", utcDate(2026, 6, 9)))
            XCTAssertNil(value(groups, "login", utcDate(2026, 6, 11)))
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

            let groups = try await metricSeries(
                name: "login", bucket: "hour",
                from: utcDate(2026, 6, 10, 9), to: utcDate(2026, 6, 10, 11), on: app
            )

            XCTAssertEqual(points(groups, "login").count, 2)
            XCTAssertEqual(value(groups, "login", utcDate(2026, 6, 10, 9)), .int(2))
            XCTAssertEqual(value(groups, "login", utcDate(2026, 6, 10, 10)), .int(1))
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

            let groups = try await metricSeries(
                name: "login", bucket: "week",
                from: utcDate(2026, 6, 7), to: utcDate(2026, 6, 21), on: app
            )

            XCTAssertEqual(points(groups, "login").count, 2)
            XCTAssertEqual(value(groups, "login", utcDate(2026, 6, 7)), .int(1))
            XCTAssertEqual(value(groups, "login", utcDate(2026, 6, 14)), .int(1))
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

            let groups = try await metricSeries(
                name: "Session", from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            XCTAssertEqual(value(groups, "Session", utcDate(2026, 6, 10)), .int(2))
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

            let groups = try await metricSeries(
                name: "requests", category: "counter",
                from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            XCTAssertEqual(groups.map(\.name), ["requests"])
            XCTAssertEqual(value(groups, "requests", utcDate(2026, 6, 10)), .int(12))
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

            let groups = try await metricSeries(
                name: "duration", category: "timer",
                from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            XCTAssertEqual(value(groups, "duration", utcDate(2026, 6, 10)), .double(1.75))
        }
    }

    func testCategoryReturnsAllNamesGrouped() async throws {
        try await withApp { app in
            try await write(
                [
                    makeMetric(name: "requests", category: "counter", date: utcDate(2026, 6, 10, 9), value: .int(5)),
                    makeMetric(name: "requests", category: "counter", date: utcDate(2026, 6, 10, 15), value: .int(7)),
                    makeMetric(name: "errors", category: "counter", date: utcDate(2026, 6, 10, 9), value: .int(2)),
                    makeMetric(name: "ignored", category: "meter", date: utcDate(2026, 6, 10, 9), value: .int(99)),
                ],
                to: app
            )

            let groups = try await metricSeries(
                category: "counter", values: "int",
                from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            XCTAssertEqual(Set(groups.map(\.name)), ["requests", "errors"])
            XCTAssertEqual(value(groups, "requests", utcDate(2026, 6, 10)), .int(12))
            XCTAssertEqual(value(groups, "errors", utcDate(2026, 6, 10)), .int(2))
        }
    }

    func testSweepWithoutFiltersSpansAllSources() async throws {
        try await withApp { app in
            try await write(
                [
                    makeEvent(name: "login", date: utcDate(2026, 6, 10, 9)),
                    makeSession(start: utcDate(2026, 6, 10, 9), installID: "a"),
                    makeCrash(date: utcDate(2026, 6, 10, 10), installID: "a", appVersion: "1.0"),
                    makeHang(date: utcDate(2026, 6, 10, 11)),
                    makeMetric(name: "requests", category: "counter", date: utcDate(2026, 6, 10, 9), value: .int(5)),
                    makeMetric(type: "DoubleMetric", name: "duration", category: "timer", date: utcDate(2026, 6, 10, 9), value: .double(0.5)),
                ],
                to: app
            )

            let groups = try await metricSeries(from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app)

            let names = Set(groups.map(\.name))
            XCTAssertTrue(names.isSuperset(of: ["login", "Session", "Crash", "Hang", "VersionCrash", "requests", "duration"]), "\(names)")
            XCTAssertEqual(value(groups, "login", utcDate(2026, 6, 10)), .int(1))
            XCTAssertEqual(value(groups, "duration", utcDate(2026, 6, 10)), .double(0.5))
        }
    }

    func testHangCountsByType() async throws {
        try await withApp { app in
            try await write(
                [
                    makeHang(date: utcDate(2026, 6, 10, 9)),
                    makeHang(date: utcDate(2026, 6, 10, 14)),
                ],
                to: app
            )

            let groups = try await metricSeries(
                name: "Hang", from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            XCTAssertEqual(value(groups, "Hang", utcDate(2026, 6, 10)), .int(2))
        }
    }

    func testVersionGroupingSplitsLifecycleCounts() async throws {
        try await withApp { app in
            try await write(
                [
                    makeSession(start: utcDate(2026, 6, 10, 9), installID: "a", appVersion: "3.2.0"),
                    makeSession(start: utcDate(2026, 6, 10, 9, 30), installID: "a", appVersion: "3.2.0"),
                    makeSession(start: utcDate(2026, 6, 10, 9), installID: "b", appVersion: "3.1.4"),
                ],
                to: app
            )

            let groups = try await metricSeries(
                name: "Session", by: "version",
                from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            XCTAssertEqual(groups.map(\.version), ["3.1.4", "3.2.0"])
            XCTAssertEqual(groups.map { $0.points.first?.value }, [.int(1), .int(2)])
        }
    }

    func testUnversionedQueryKeepsTotalsAcrossVersions() async throws {
        try await withApp { app in
            try await write(
                [
                    makeSession(start: utcDate(2026, 6, 10, 9), installID: "a", appVersion: "3.2.0"),
                    makeSession(start: utcDate(2026, 6, 10, 9, 30), installID: "b", appVersion: "3.1.4"),
                ],
                to: app
            )

            let groups = try await metricSeries(
                name: "Session", from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            XCTAssertEqual(groups.map(\.version), [nil])
            XCTAssertEqual(value(groups, "Session", utcDate(2026, 6, 10)), .int(2))
        }
    }

    func testVersionCrashCountsFirstCrashPerInstall() async throws {
        try await withApp { app in
            try await write(
                [
                    makeCrash(date: utcDate(2026, 6, 10, 9), installID: "a", appVersion: "3.2.0"),
                    makeCrash(date: utcDate(2026, 6, 10, 15), installID: "a", appVersion: "3.2.0"),
                    makeCrash(date: utcDate(2026, 6, 10, 9), installID: "b", appVersion: "3.2.0"),
                    makeCrash(date: utcDate(2026, 6, 10, 9), installID: "a", appVersion: "3.1.4"),
                ],
                to: app
            )

            let groups = try await metricSeries(
                name: "VersionCrash", by: "version",
                from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            XCTAssertEqual(groups.map(\.version), ["3.1.4", "3.2.0"])
            XCTAssertEqual(groups.map { $0.points.reduce(0) { $0 + ($1.value.intValue ?? 0) } }, [1, 2])
        }
    }

    func testEventSourceReachesEventNamedLikeLifecycleCounter() async throws {
        try await withApp { app in
            try await write(
                [
                    makeEvent(name: "Session", date: utcDate(2026, 6, 10, 9)),
                    makeEvent(name: "Session", date: utcDate(2026, 6, 10, 9, 30)),
                    makeSession(start: utcDate(2026, 6, 10, 9), installID: "a"),
                ],
                to: app
            )

            let groups = try await metricSeries(
                name: "Session", source: "event",
                from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            XCTAssertEqual(groups.map(\.name), ["Session"])
            XCTAssertEqual(value(groups, "Session", utcDate(2026, 6, 10)), .int(2))
        }
    }

    func testLifecycleSourceIgnoresSameNamedEvent() async throws {
        try await withApp { app in
            try await write(
                [
                    makeEvent(name: "Session", date: utcDate(2026, 6, 10, 9)),
                    makeSession(start: utcDate(2026, 6, 10, 9), installID: "a"),
                    makeSession(start: utcDate(2026, 6, 10, 14), installID: "b"),
                ],
                to: app
            )

            let groups = try await metricSeries(
                name: "Session", source: "lifecycle",
                from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            XCTAssertEqual(value(groups, "Session", utcDate(2026, 6, 10)), .int(2))
        }
    }

    func testMetricSourceExcludesLifecycleAndEvents() async throws {
        try await withApp { app in
            try await write(
                [
                    makeEvent(name: "requests", date: utcDate(2026, 6, 10, 9)),
                    makeMetric(name: "requests", category: "counter", date: utcDate(2026, 6, 10, 9), value: .int(5)),
                    makeMetric(name: "requests", category: "counter", date: utcDate(2026, 6, 10, 15), value: .int(7)),
                ],
                to: app
            )

            let groups = try await metricSeries(
                name: "requests", source: "metric",
                from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            XCTAssertEqual(value(groups, "requests", utcDate(2026, 6, 10)), .int(12))
        }
    }

    func testResourceExceptionsCountByKindAndVersion() async throws {
        try await withApp { app in
            try await write(
                [
                    makeResourceException(kind: "cpu", date: utcDate(2026, 6, 10, 9), appVersion: "3.2.0"),
                    makeResourceException(kind: "cpu", date: utcDate(2026, 6, 10, 15), appVersion: "3.2.0"),
                    makeResourceException(kind: "disk_write", date: utcDate(2026, 6, 10, 9), appVersion: "3.2.0"),
                    makeResourceException(kind: "cpu", date: utcDate(2026, 6, 10, 9), appVersion: "3.1.4"),
                ],
                to: app
            )

            let groups = try await metricSeries(
                name: "ResourceException", by: "version", source: "lifecycle",
                from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            let totals = groups.map { "\($0.category ?? "-") \($0.version ?? "") \($0.points.first?.value.intValue ?? 0)" }
            XCTAssertEqual(totals, ["cpu 3.1.4 1", "cpu 3.2.0 2", "disk_write 3.2.0 1"])
        }
    }

    func testScreenViewsCountByScreenAndVersion() async throws {
        try await withApp { app in
            try await write(
                [
                    makeScreen(name: "Feed", date: utcDate(2026, 6, 10, 9), appVersion: "3.2.0"),
                    makeScreen(name: "Feed", date: utcDate(2026, 6, 10, 15), appVersion: "3.2.0"),
                    makeScreen(name: "Profile", date: utcDate(2026, 6, 10, 9), appVersion: "3.2.0"),
                    makeScreen(name: "Feed", date: utcDate(2026, 6, 10, 9), appVersion: "3.1.4"),
                ],
                to: app
            )

            let groups = try await metricSeries(
                name: "Screen", by: "version", source: "lifecycle",
                from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            let totals = groups.map { "\($0.category ?? "-") \($0.version ?? "") \($0.points.first?.value.intValue ?? 0)" }
            XCTAssertEqual(totals, ["Feed 3.1.4 1", "Feed 3.2.0 2", "Profile 3.2.0 1"])
        }
    }

    func testConditionsCountByKindAndVersion() async throws {
        try await withApp { app in
            try await write(
                [
                    makeCondition(kind: "memory_warning", date: utcDate(2026, 6, 10, 9), appVersion: "3.2.0"),
                    makeCondition(kind: "memory_warning", date: utcDate(2026, 6, 10, 15), appVersion: "3.2.0"),
                    makeCondition(kind: "thermal_serious", date: utcDate(2026, 6, 10, 9), appVersion: "3.2.0"),
                    makeCondition(kind: "memory_warning", date: utcDate(2026, 6, 10, 9), appVersion: "3.1.4"),
                ],
                to: app
            )

            let groups = try await metricSeries(
                name: "Condition", by: "version", source: "lifecycle",
                from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            let totals = groups.map { "\($0.category ?? "-") \($0.version ?? "") \($0.points.first?.value.intValue ?? 0)" }
            XCTAssertEqual(totals, ["memory_warning 3.1.4 1", "memory_warning 3.2.0 2", "thermal_serious 3.2.0 1"])
        }
    }

    func testLifecycleCountsWithoutCategoryStayWhole() async throws {
        try await withApp { app in
            try await write(
                [
                    makeCrash(date: utcDate(2026, 6, 10, 9), appVersion: "3.2.0"),
                    makeCrash(date: utcDate(2026, 6, 10, 15), appVersion: "3.2.0"),
                ],
                to: app
            )

            let groups = try await metricSeries(
                name: "Crash", by: "version", source: "lifecycle",
                from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            XCTAssertEqual(groups.map(\.category), [nil])
            XCTAssertEqual(value(groups, "Crash", utcDate(2026, 6, 10)), .int(2))
        }
    }

    func testDailyMetricCategoryNarrowsToOneCategory() async throws {
        try await withApp { app in
            try await write(
                [
                    makeDailyMetric(name: "exit", category: "watchdog", value: 2, date: utcDate(2026, 6, 10, 9), appVersion: "3.2.0"),
                    makeDailyMetric(name: "exit", category: "normal", value: 40, date: utcDate(2026, 6, 10, 9), appVersion: "3.2.0"),
                ],
                to: app
            )

            let groups = try await metricSeries(
                name: "exit", category: "watchdog", source: "lifecycle",
                from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            XCTAssertEqual(groups.map(\.category), ["watchdog"])
            XCTAssertEqual(value(groups, "exit", utcDate(2026, 6, 10)), .int(2))
        }
    }

    func testDailyMetricSumsSplitByNameCategoryAndVersion() async throws {
        try await withApp { app in
            try await write(
                [
                    makeDailyMetric(name: "launch_time", category: "100", value: 4, date: utcDate(2026, 6, 10, 9), appVersion: "3.2.0"),
                    makeDailyMetric(name: "launch_time", category: "100", value: 6, date: utcDate(2026, 6, 10, 15), appVersion: "3.2.0"),
                    makeDailyMetric(name: "launch_time", category: "200", value: 1, date: utcDate(2026, 6, 10, 9), appVersion: "3.2.0"),
                    makeDailyMetric(name: "launch_time", category: "100", value: 3, date: utcDate(2026, 6, 10, 9), appVersion: "3.1.4"),
                    makeDailyMetric(name: "foreground_time", value: 3600, date: utcDate(2026, 6, 10, 9), appVersion: "3.2.0"),
                ],
                to: app
            )

            let groups = try await metricSeries(
                by: "version", source: "lifecycle",
                from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            let totals = groups.map { "\($0.name) \($0.category ?? "-") \($0.version ?? "") \($0.points.first?.value.intValue ?? 0)" }
            XCTAssertEqual(
                totals,
                [
                    "foreground_time - 3.2.0 3600",
                    "launch_time 100 3.1.4 3",
                    "launch_time 100 3.2.0 10",
                    "launch_time 200 3.2.0 1",
                ]
            )
        }
    }

    func testDailyMetricNameNarrowsToOneMetric() async throws {
        try await withApp { app in
            try await write(
                [
                    makeDailyMetric(name: "launch_time", category: "100", value: 4, date: utcDate(2026, 6, 10, 9), appVersion: "3.2.0"),
                    makeDailyMetric(name: "peak_memory", category: "150", value: 1, date: utcDate(2026, 6, 10, 9), appVersion: "3.2.0"),
                    makeDailyMetric(name: "exit", category: "normal", value: 40, date: utcDate(2026, 6, 10, 9), appVersion: "3.2.0"),
                ],
                to: app
            )

            let groups = try await metricSeries(
                name: "peak_memory", source: "lifecycle",
                from: utcDate(2026, 6, 10), to: utcDate(2026, 6, 11), on: app
            )

            XCTAssertEqual(groups.map(\.category), ["150"])
            XCTAssertEqual(value(groups, "peak_memory", utcDate(2026, 6, 10)), .int(1))
        }
    }

    func testUnknownSourceIsRejected() async throws {
        try await withApp { app in
            try await app.test(
                .GET, "api/v1/metrics/series?name=login&source=widget&from=0&to=1",
                headers: .authorized,
                afterResponse: { res async in
                    XCTAssertEqual(res.status, .badRequest)
                }
            )
        }
    }

    func testUnknownByIsRejected() async throws {
        try await withApp { app in
            try await app.test(
                .GET, "api/v1/metrics/series?name=login&by=device&from=0&to=1",
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

    func testUnknownValuesIsRejected() async throws {
        try await withApp { app in
            try await app.test(
                .GET, "api/v1/metrics/series?name=login&values=triple&from=0&to=1",
                headers: .authorized,
                afterResponse: { res async in
                    XCTAssertEqual(res.status, .badRequest)
                }
            )
        }
    }
}
