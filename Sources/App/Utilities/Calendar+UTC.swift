//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Foundation

extension Calendar {
    /// The calendar Scout uses for every date bucket, byte-for-byte the
    /// client's `Calendar.utc`: Gregorian, `firstWeekday = 1`, UTC.
    /// Week buckets depend on its `firstWeekday` (1 = Sunday), so the
    /// server must not deviate from the client here — and the client picks
    /// Gregorian on purpose, because the `iso8601` identifier pins the first
    /// weekday to Monday on some platforms and ignores the override below.
    ///
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
}

extension Date {
    var startOfHour: Date {
        Calendar.utc.dateComponents([.calendar, .year, .month, .day, .hour], from: self).date!
    }

    var startOfDay: Date {
        Calendar.utc.startOfDay(for: self)
    }

    var startOfWeek: Date {
        Calendar.utc.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: self).date!
    }

    var startOfMonth: Date {
        Calendar.utc.dateComponents([.calendar, .year, .month], from: self).date!
    }
}
