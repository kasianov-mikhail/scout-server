//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import XCTVapor

@testable import App

final class DeviceMetricsTests: XCTestCase {
    func testDevicesSummarizeSessionsCrashesAndModel() async throws {
        try await withApp { app in
            try await write(
                [
                    makeDevice(deviceID: "a", model: "iPhone15,3", date: utcDate(2026, 5, 1)),
                    makeSession(start: utcDate(2026, 6, 10, 9), installID: "ia", deviceID: "a", osVersion: "iOS 17.3"),
                    makeSession(start: utcDate(2026, 6, 12, 18, 30), installID: "ia", deviceID: "a", osVersion: "iOS 17.4"),
                    makeSession(start: utcDate(2026, 6, 11, 8), installID: "ib", deviceID: "b"),
                    makeCrash(date: utcDate(2026, 6, 12, 19), deviceID: "a"),
                    makeCrash(date: utcDate(2026, 6, 13, 7), deviceID: "a"),
                ],
                to: app
            )

            let summary = try await devices(from: utcDate(2026, 6, 1), to: utcDate(2026, 7, 1), on: app)

            XCTAssertEqual(
                summary,
                [
                    DevicePoint(
                        deviceID: "a",
                        model: "iPhone15,3",
                        osVersion: "iOS 17.4",
                        lastSeen: utcDate(2026, 6, 12, 18, 30).milliseconds,
                        sessions: 2,
                        crashes: 2
                    ),
                    DevicePoint(
                        deviceID: "b",
                        model: nil,
                        osVersion: nil,
                        lastSeen: utcDate(2026, 6, 11, 8).milliseconds,
                        sessions: 1,
                        crashes: 0
                    ),
                ]
            )
        }
    }

    func testDevicesCountOnlyTheRange() async throws {
        try await withApp { app in
            try await write(
                [
                    makeSession(start: utcDate(2026, 5, 31, 23), installID: "ia", deviceID: "a"),
                    makeSession(start: utcDate(2026, 6, 2, 9), installID: "ia", deviceID: "a"),
                    makeSession(start: utcDate(2026, 7, 1), installID: "ib", deviceID: "b"),
                    makeCrash(date: utcDate(2026, 5, 31, 23, 30), deviceID: "a"),
                ],
                to: app
            )

            let summary = try await devices(from: utcDate(2026, 6, 1), to: utcDate(2026, 7, 1), on: app)

            XCTAssertEqual(summary.map(\.deviceID), ["a"])
            XCTAssertEqual(summary.first?.sessions, 1)
            XCTAssertEqual(summary.first?.crashes, 0)
        }
    }

    func testDeviceCountsAreDistinctPerRange() async throws {
        try await withApp { app in
            try await write(
                [
                    makeSession(start: utcDate(2026, 6, 10, 9), installID: "ia", deviceID: "a"),
                    makeSession(start: utcDate(2026, 6, 10, 15), installID: "ia", deviceID: "a"),
                    makeSession(start: utcDate(2026, 6, 10, 11), installID: "ib", deviceID: "b"),
                    makeSession(start: utcDate(2026, 6, 11, 8), installID: "ia", deviceID: "a"),
                ],
                to: app
            )

            let counts = try await deviceCounts(
                [
                    utcDate(2026, 6, 10)..<utcDate(2026, 6, 11),
                    utcDate(2026, 6, 11)..<utcDate(2026, 6, 12),
                    utcDate(2026, 6, 10, 12)..<utcDate(2026, 6, 10, 16),
                    utcDate(2026, 6, 1)..<utcDate(2026, 7, 1),
                    utcDate(2026, 5, 1)..<utcDate(2026, 6, 1),
                ],
                on: app
            )

            XCTAssertEqual(counts, [2, 1, 1, 2, 0])
        }
    }

    func testDeviceCountsRejectMalformedRanges() async throws {
        try await withApp { app in
            for list in ["", "100", "200-100", "abc-def", (0..<33).map { _ in "1-2" }.joined(separator: ",")] {
                try await app.test(
                    .GET, "api/v1/metrics/device-counts?ranges=\(list)",
                    headers: .authorized,
                    afterResponse: { res async in
                        XCTAssertEqual(res.status, .badRequest, "ranges=\(list)")
                    }
                )
            }
        }
    }
}
