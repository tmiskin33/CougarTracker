import XCTest
@testable import CougarDeadlineTracker

/// Grouping and the calendar grid. The badge counts and the day list read the
/// same helper, so these tests are what keep the two from drifting apart.
final class CalendarAndGroupingTests: XCTestCase {
    private var calendar: Calendar { .current }

    private func deadline(
        title: String,
        due: Date,
        completed: Bool = false,
        source: DeadlineSource = .canvas
    ) -> Deadline {
        Deadline(
            source: source,
            sourceItemID: title,
            courseName: "Course",
            courseCode: "ABC 100",
            title: title,
            type: .assignment,
            dueDate: due,
            isCompleted: completed
        )
    }

    func testGroupsByCalendarDayInOrder() {
        let items = [
            deadline(title: "Later same day", due: makeDate(2026, 9, 8, 23, 59)),
            deadline(title: "Next day", due: makeDate(2026, 9, 9, 9, 0)),
            deadline(title: "Earlier same day", due: makeDate(2026, 9, 8, 9, 0))
        ]

        let days = DeadlineGrouping.byDay(items, calendar: calendar)

        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].deadlines.map(\.title), ["Earlier same day", "Later same day"])
        XCTAssertEqual(days[1].deadlines.map(\.title), ["Next day"])
    }

    func testBadgeCountsMatchTheGroupedList() {
        let day = makeDate(2026, 9, 8, 12, 0)
        let items = [
            deadline(title: "One", due: day),
            deadline(title: "Two", due: makeDate(2026, 9, 8, 18, 0)),
            deadline(title: "Done", due: makeDate(2026, 9, 8, 20, 0), completed: true)
        ]

        let visible = items.filter { !$0.isCompleted }
        let counts = DeadlineGrouping.countsByDay(visible, includingCompleted: false, calendar: calendar)
        let days = DeadlineGrouping.byDay(visible, calendar: calendar)

        let startOfDay = calendar.startOfDay(for: day)
        XCTAssertEqual(counts[startOfDay], 2)
        XCTAssertEqual(counts[startOfDay], days.first?.deadlines.count)
    }

    func testCountsCanIncludeCompletedItems() {
        let day = makeDate(2026, 9, 8, 12, 0)
        let items = [
            deadline(title: "One", due: day),
            deadline(title: "Done", due: day, completed: true)
        ]

        let counts = DeadlineGrouping.countsByDay(items, includingCompleted: true, calendar: calendar)
        XCTAssertEqual(counts[calendar.startOfDay(for: day)], 2)
    }

    func testOverdueIsPastDueAndNotCompleted() {
        let past = deadline(title: "Past", due: makeDate(2026, 9, 1, 9, 0))
        let pastDone = deadline(title: "Past done", due: makeDate(2026, 9, 1, 9, 0), completed: true)
        let future = deadline(title: "Future", due: makeDate(2026, 9, 30, 9, 0))

        XCTAssertTrue(past.isOverdue(asOf: referenceNow))
        XCTAssertFalse(pastDone.isOverdue(asOf: referenceNow))
        XCTAssertFalse(future.isOverdue(asOf: referenceNow))
    }

    func testMonthGridIsWholeWeeksAndCoversTheMonth() {
        let grid = CalendarLayout.monthGrid(containing: makeDate(2026, 9, 15), calendar: calendar)

        XCTAssertEqual(grid.count % 7, 0, "the grid is whole weeks")
        XCTAssertTrue(grid.contains { calendar.isDate($0, inSameDayAs: makeDate(2026, 9, 1)) })
        XCTAssertTrue(grid.contains { calendar.isDate($0, inSameDayAs: makeDate(2026, 9, 30)) })
    }

    func testMonthGridStartsOnTheUsersFirstWeekday() throws {
        let grid = CalendarLayout.monthGrid(containing: makeDate(2026, 9, 15), calendar: calendar)
        let first = try XCTUnwrap(grid.first)
        XCTAssertEqual(calendar.component(.weekday, from: first), calendar.firstWeekday)
    }

    func testWeekIsSevenConsecutiveDays() throws {
        let week = CalendarLayout.week(containing: makeDate(2026, 9, 15), calendar: calendar)

        XCTAssertEqual(week.count, 7)
        XCTAssertTrue(week.contains { calendar.isDate($0, inSameDayAs: makeDate(2026, 9, 15)) })

        let first = try XCTUnwrap(week.first)
        let last = try XCTUnwrap(week.last)
        XCTAssertEqual(calendar.dateComponents([.day], from: first, to: last).day, 6)
    }

    func testWeekdaySymbolsAreRotatedToTheFirstWeekday() {
        let symbols = CalendarLayout.weekdaySymbols(calendar: calendar)
        XCTAssertEqual(symbols.count, 7)
        XCTAssertEqual(symbols.first, calendar.shortWeekdaySymbols[calendar.firstWeekday - 1])
    }

    func testAccessibilityDescriptionCoversTheRowsMeaning() {
        let item = deadline(title: "Essay", due: makeDate(2026, 9, 1, 9, 0))
        let description = item.accessibilityDescription(asOf: referenceNow)

        XCTAssertTrue(description.contains("Essay"))
        XCTAssertTrue(description.contains("ABC 100"))
        XCTAssertTrue(description.contains("Canvas"))
        XCTAssertTrue(description.contains("overdue"))
    }
}
