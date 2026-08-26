import SwiftData
import XCTest
@testable import CougarDeadlineTracker

/// Merge behaviour: the rules that decide what a re-sync does to what is already
/// on the device.
final class DeadlineStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var store: DeadlineStore!

    /// Built per test rather than in `setUp`, so the store stays on the main
    /// actor without fighting XCTest's non-isolated lifecycle methods.
    @MainActor
    private func startFresh() throws {
        let schema = Schema([Deadline.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        store = DeadlineStore(context: container.mainContext)
    }

    private func imported(
        id: String,
        title: String = "Homework",
        due: Date? = nil,
        source: DeadlineSource = .canvas,
        completed: Bool? = nil
    ) -> ImportedDeadline {
        ImportedDeadline(
            source: source,
            sourceItemID: id,
            courseName: "Calculus 2",
            courseCode: "MATH 113",
            title: title,
            type: .assignment,
            dueDate: due ?? makeDate(2026, 9, 20, 23, 59),
            isCompleted: completed
        )
    }

    @MainActor
    private func fetchAll() throws -> [Deadline] {
        try container.mainContext.fetch(
            FetchDescriptor<Deadline>(sortBy: [SortDescriptor(\.dueDate)])
        )
    }

    @MainActor
    func testInsertsNewItems() throws {
        try startFresh()
        let result = try store.merge([imported(id: "a"), imported(id: "b")], from: .canvas, now: referenceNow)

        XCTAssertEqual(result.inserted, 2)
        XCTAssertEqual(try fetchAll().count, 2)
    }

    @MainActor
    func testResyncUpdatesInPlaceRatherThanDuplicating() throws {
        try startFresh()
        try store.merge([imported(id: "a", title: "Old title")], from: .canvas, now: referenceNow)
        let result = try store.merge([imported(id: "a", title: "New title")], from: .canvas, now: referenceNow)

        XCTAssertEqual(result.inserted, 0)
        XCTAssertEqual(result.updated, 1)

        let all = try fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "New title")
    }

    @MainActor
    func testSourcesDoNotCollideWithEachOther() throws {
        try startFresh()
        try store.merge([imported(id: "shared", source: .canvas)], from: .canvas, now: referenceNow)
        try store.merge(
            [imported(id: "shared", source: .learningSuite)],
            from: .learningSuite,
            now: referenceNow
        )

        XCTAssertEqual(try fetchAll().count, 2, "the same id in two systems is two different items")
    }

    @MainActor
    func testRemoteCompletionIsApplied() throws {
        try startFresh()
        try store.merge([imported(id: "a", completed: false)], from: .canvas, now: referenceNow)
        try store.merge([imported(id: "a", completed: true)], from: .canvas, now: referenceNow)

        XCTAssertEqual(try fetchAll().first?.isCompleted, true)
    }

    @MainActor
    func testAHandSetCompletionSurvivesTheNextSync() throws {
        try startFresh()
        try store.merge([imported(id: "a", completed: false)], from: .canvas, now: referenceNow)
        let deadline = try XCTUnwrap(try fetchAll().first)

        try store.setCompleted(true, on: deadline)
        try store.merge([imported(id: "a", completed: false)], from: .canvas, now: referenceNow)

        XCTAssertEqual(try fetchAll().first?.isCompleted, true, "sync must not undo a swipe-to-complete")
    }

    @MainActor
    func testASourceThatReportsNoCompletionLeavesTheLocalValueAlone() throws {
        try startFresh()
        try store.merge(
            [imported(id: "a", source: .learningSuite, completed: nil)],
            from: .learningSuite,
            now: referenceNow
        )
        let deadline = try XCTUnwrap(try fetchAll().first)
        try store.setCompleted(true, on: deadline)

        try store.merge(
            [imported(id: "a", source: .learningSuite, completed: nil)],
            from: .learningSuite,
            now: referenceNow
        )
        XCTAssertEqual(try fetchAll().first?.isCompleted, true)
    }

    @MainActor
    func testItemsTheSourceStopsReportingAreRemovedWhenStillUpcoming() throws {
        try startFresh()
        try store.merge(
            [imported(id: "a"), imported(id: "b")],
            from: .canvas,
            now: referenceNow
        )
        let result = try store.merge([imported(id: "a")], from: .canvas, now: referenceNow)

        XCTAssertEqual(result.removed, 1)
        XCTAssertEqual(try fetchAll().map(\.sourceItemID), ["a"])
    }

    @MainActor
    func testPastItemsSurviveEvenWhenTheSourceForgetsThem() throws {
        try startFresh()
        let lastWeek = makeDate(2026, 8, 29, 23, 59)
        try store.merge([imported(id: "old", due: lastWeek)], from: .canvas, now: referenceNow)

        let result = try store.merge([], from: .canvas, now: referenceNow)

        XCTAssertEqual(result.removed, 0, "finished coursework must not vanish out of the past")
        XCTAssertEqual(try fetchAll().count, 1)
    }

    @MainActor
    func testDisconnectingASourceClearsOnlyItsItems() throws {
        try startFresh()
        try store.merge([imported(id: "a", source: .canvas)], from: .canvas, now: referenceNow)
        try store.merge(
            [imported(id: "b", source: .learningSuite)],
            from: .learningSuite,
            now: referenceNow
        )

        try store.deleteAll(from: .canvas)
        XCTAssertEqual(try fetchAll().map(\.sourceRaw), [DeadlineSource.learningSuite.rawValue])
    }
}
