//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Foundation

extension Calendar {
    static var utc: Calendar {
        // Must match the client's Calendar.utc: weeks start on Sunday.
        // Not .iso8601, which ignores firstWeekday on some platforms.
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
