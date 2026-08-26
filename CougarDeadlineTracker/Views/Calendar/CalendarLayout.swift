import Foundation

/// Date arithmetic for the calendar grids, kept separate from the views so it
/// can be reasoned about (and tested) on its own.
enum CalendarLayout {
    /// Every cell a month grid shows, including the days from the neighbouring
    /// months that fill out the first and last weeks.
    static func monthGrid(containing date: Date, calendar: Calendar = .current) -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date),
              let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count else {
            return []
        }
        let firstOfMonth = monthInterval.start
        let weekdayOfFirst = calendar.component(.weekday, from: firstOfMonth)
        let leading = (weekdayOfFirst - calendar.firstWeekday + 7) % 7

        guard let start = calendar.date(byAdding: .day, value: -leading, to: firstOfMonth) else {
            return []
        }
        let cellCount = Int((Double(leading + daysInMonth) / 7.0).rounded(.up)) * 7
        return (0..<cellCount).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func week(containing date: Date, calendar: Calendar = .current) -> [Date] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    /// Single-letter-ish weekday headers in the user's own first-day-of-week order.
    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.shortWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        guard symbols.count == 7, offset > 0 else { return symbols }
        return Array(symbols[offset...] + symbols[..<offset])
    }

    static func isSameMonth(_ lhs: Date, _ rhs: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(lhs, equalTo: rhs, toGranularity: .month)
    }
}
