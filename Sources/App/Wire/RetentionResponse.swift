//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Vapor

/// The native retention-cohort table the server aggregates from raw records
/// and serves directly from `GET /api/v1/metrics/retention`.
///
struct RetentionResponse: Content, Equatable {
    let cohorts: [RetentionCohortPoint]
}

/// One weekly acquisition cohort: the installs first seen during the UTC week
/// starting at `date`, and how many of them were active again at each
/// day-since-install milestone in `RetentionService.dayOffsets`.
///
/// `date` is milliseconds since the Unix epoch at UTC week start, matching the
/// rest of the wire format. `size` is the cohort's install count (the
/// denominator). `retained` is aligned to `RetentionService.dayOffsets`: entry
/// `i` is the number of installs active on exactly `install day + offset[i]`
/// (bounded day-N retention), or `null` when that milestone has not fully
/// elapsed for the whole cohort yet — the triangular gap of a cohort table.
/// `segments` splits the cohort by the OS major version of each install's
/// first session.
///
struct RetentionCohortPoint: Content, Equatable {
    let date: Int64
    let size: Int
    let retained: [Int?]
    let segments: [RetentionSegmentPoint]
}

/// The installs of one cohort that first ran on the OS major version `name`,
/// such as "iOS 18". `size` and `retained` read like the cohort's own;
/// `crashes` and `hangs` count the segment's installs with at least one crash
/// or hang within `RetentionService.horizon` days of install. Installs whose
/// sessions carry no OS version belong to no segment.
///
struct RetentionSegmentPoint: Content, Equatable {
    let name: String
    let size: Int
    let retained: [Int?]
    let crashes: Int
    let hangs: Int
}
