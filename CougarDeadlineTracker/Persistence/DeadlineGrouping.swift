import Foundation

/// One day's worth of deadlines, ready to render.
struct DeadlineDay: Identifiable, Equatable {
    var date: Date
    var deadlines: [Deadline]

    var id: Date { date }

    func overdueCount(asOf now: Date) -> Int {
        deadlines.filter { $0.isOverdue(asOf: now) }.count
    }

    var incompleteCount: Int {
        deadlines.filter { !$0.isCompleted }.count
    }
}

/// Pure grouping/counting helpers shared by the day list and the calendar, so a
/// badge count can never disagree with the list behind it.
enum DeadlineGrouping {
    /// Groups by calendar day and sorts days ascending, items within a day by time.
    static func byDay(
        _ deadlines: [Deadline],
        calendar: Calendar = .current
    ) -> [DeadlineDay] {
        let grouped = Dictionary(grouping: deadlines) { calendar.startOfDay(for: $0.dueDate) }
        return grouped
            .map { DeadlineDay(date: $0.key, deadlines: $0.value.sorted(by: chronologically)) }
            .sorted { $0.date < $1.date }
    }

    /// Count per day, keyed by start-of-day — the calendar badge source.
    static func countsByDay(
        _ deadlines: [Deadline],
        includingCompleted: Bool,
        calendar: Calendar = .current
    ) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        for deadline in deadlines where includingCompleted || !deadline.isCompleted {
            let day = calendar.startOfDay(for: deadline.dueDate)
            counts[day, default: 0] += 1
        }
        return counts
    }

    static func chronologically(_ lhs: Deadline, _ rhs: Deadline) -> Bool {
        if lhs.dueDate != rhs.dueDate {
            return lhs.dueDate < rhs.dueDate
        }
        if lhs.courseLabel != rhs.courseLabel {
            return lhs.courseLabel < rhs.courseLabel
        }
        return lhs.title < rhs.title
    }
}
