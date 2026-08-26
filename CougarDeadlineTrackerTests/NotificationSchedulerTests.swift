import XCTest
@testable import CougarDeadlineTracker

/// Reminder planning and digest wording. Both are pure functions, so neither
/// test needs notification permission or a real notification centre.
final class NotificationSchedulerTests: XCTestCase {
    private let scheduler = NotificationScheduler()

    private func snapshot(
        title: String = "Section 7.4 Homework",
        course: String = "MATH 113",
        due: Date,
        completed: Bool = false
    ) -> DeadlineSnapshot {
        DeadlineSnapshot(
            id: UUID(),
            title: title,
            courseLabel: course,
            dueDate: due,
            isCompleted: completed
        )
    }

    func testOneReminderPerOffset() {
        let due = makeDate(2026, 9, 20, 23, 59)
        let planned = scheduler.plannedReminders(
            deadlines: [snapshot(due: due)],
            offsets: [24 * 60, 3 * 60],
            now: referenceNow
        )

        XCTAssertEqual(planned.count, 2)
        XCTAssertEqual(planned.map(\.fireDate), [
            due.addingTimeInterval(-24 * 60 * 60),
            due.addingTimeInterval(-3 * 60 * 60)
        ])
    }

    func testRemindersAreOrderedSoonestFirst() {
        let near = makeDate(2026, 9, 6, 12, 0)
        let far = makeDate(2026, 9, 30, 12, 0)
        let planned = scheduler.plannedReminders(
            deadlines: [snapshot(title: "Far", due: far), snapshot(title: "Near", due: near)],
            offsets: [60],
            now: referenceNow
        )

        XCTAssertEqual(planned.map(\.title), ["Near", "Far"])
    }

    func testCompletedAndPastItemsAreNotScheduled() {
        let planned = scheduler.plannedReminders(
            deadlines: [
                snapshot(title: "Done", due: makeDate(2026, 9, 20, 23, 59), completed: true),
                snapshot(title: "Already passed", due: makeDate(2026, 9, 1, 23, 59))
            ],
            offsets: [60],
            now: referenceNow
        )

        XCTAssertTrue(planned.isEmpty)
    }

    func testAnOffsetThatWouldFireInThePastIsSkipped() {
        // Due in two hours, with a one-day-ahead reminder: that moment is gone.
        let due = referenceNow.addingTimeInterval(2 * 60 * 60)
        let planned = scheduler.plannedReminders(
            deadlines: [snapshot(due: due)],
            offsets: [24 * 60, 60],
            now: referenceNow
        )

        XCTAssertEqual(planned.count, 1)
        XCTAssertEqual(planned.first?.offsetMinutes, 60)
    }

    func testDuplicateOffsetsAreCollapsed() {
        let planned = scheduler.plannedReminders(
            deadlines: [snapshot(due: makeDate(2026, 9, 20, 23, 59))],
            offsets: [60, 60, 60],
            now: referenceNow
        )
        XCTAssertEqual(planned.count, 1)
    }

    func testReminderBodyNamesTheCourseAndHowLongIsLeft() {
        let body = NotificationScheduler.reminderBody(
            for: snapshot(due: makeDate(2026, 9, 20, 23, 59)),
            offsetMinutes: 24 * 60
        )
        XCTAssertTrue(body.contains("MATH 113"))
        XCTAssertTrue(body.contains("tomorrow"))
    }

    func testRelativeWording() {
        XCTAssertEqual(NotificationScheduler.relativeDescription(offsetMinutes: 30), "in 30 minutes")
        XCTAssertEqual(NotificationScheduler.relativeDescription(offsetMinutes: 60), "in an hour")
        XCTAssertEqual(NotificationScheduler.relativeDescription(offsetMinutes: 180), "in 3 hours")
        XCTAssertEqual(NotificationScheduler.relativeDescription(offsetMinutes: 24 * 60), "tomorrow")
        XCTAssertEqual(NotificationScheduler.relativeDescription(offsetMinutes: 3 * 24 * 60), "in 3 days")
    }

    func testDigestBodyListsUpToThreeThenCounts() {
        let due = makeDate(2026, 9, 5, 23, 59)
        let items = (1...5).map { snapshot(title: "Item \($0)", due: due.addingTimeInterval(Double($0))) }

        let body = NotificationScheduler.digestBody(for: items)
        XCTAssertEqual(body, "5 deadlines: Item 1, Item 2, Item 3 and 2 more")
    }

    func testDigestBodyForASingleItem() {
        let body = NotificationScheduler.digestBody(for: [snapshot(title: "Essay", due: referenceNow)])
        XCTAssertEqual(body, "1 deadline: Essay")
    }

    func testDigestBodyWhenNothingIsDue() {
        XCTAssertEqual(NotificationScheduler.digestBody(for: []), "Nothing due today.")
    }
}
