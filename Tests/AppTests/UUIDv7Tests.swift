//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Fluent
import XCTVapor

@testable import App

final class UUIDv7Tests: XCTestCase {

    private func bytes(of uuid: UUID) -> [UInt8] {
        withUnsafeBytes(of: uuid.uuid) { Array($0) }
    }

    func testSetsVersionAndVariantBits() {
        let raw = bytes(of: .v7())
        XCTAssertEqual(raw[6] >> 4, 0x7, "high nibble of byte 6 must encode version 7")
        XCTAssertEqual(raw[8] >> 6, 0b10, "top two bits of byte 8 must encode the RFC 4122 variant")
    }

    func testEncodesTheTimestampPrefix() {
        let date = utcDate(2026, 6, 13, 12, 30)
        let raw = bytes(of: .v7(now: date))

        var milliseconds: UInt64 = 0
        for byte in raw[0..<6] {
            milliseconds = (milliseconds << 8) | UInt64(byte)
        }
        XCTAssertEqual(milliseconds, UInt64(date.timeIntervalSince1970 * 1000))
    }

    func testOrdersByCreationTime() {
        let earlier = UUID.v7(now: utcDate(2026, 6, 13, 12, 0))
        let later = UUID.v7(now: utcDate(2026, 6, 13, 12, 1))
        XCTAssertTrue(
            bytes(of: earlier).lexicographicallyPrecedes(bytes(of: later)),
            "a later timestamp must sort after an earlier one"
        )
    }

    func testGeneratesDistinctValues() {
        let count = 1000
        let ids = Set((0..<count).map { _ in UUID.v7() })
        XCTAssertEqual(ids.count, count, "random tail must keep ids unique within a millisecond")
    }

    /// Proves Fluent persists the id we assign in `RecordModel(dto:)` rather
    /// than substituting its own random version 4.
    func testPersistedRecordIdsUseVersion7() async throws {
        try await withApp { app in
            let event = makeEvent(name: "login", date: utcDate(2026, 6, 10))
            try await write([event], to: app)

            let model = try await RecordModel.query(on: app.db)
                .filter(\.$recordName == event.recordName)
                .first()
            let id = try XCTUnwrap(model?.id)
            XCTAssertEqual(bytes(of: id)[6] >> 4, 0x7)
        }
    }
}
