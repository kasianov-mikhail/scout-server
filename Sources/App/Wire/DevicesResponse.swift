//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Vapor

struct DevicesResponse: Content, Equatable {
    let devices: [DevicePoint]
}

struct DevicePoint: Content, Equatable {
    let deviceID: String
    let model: String?
    let osVersion: String?
    let lastSeen: Int64
    let sessions: Int
    let crashes: Int
}

struct DeviceCountsResponse: Content, Equatable {
    let counts: [Int]
}
