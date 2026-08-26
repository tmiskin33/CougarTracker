import XCTest
@testable import CougarDeadlineTracker

/// Learning Suite scraping, against saved page samples.
///
/// The fixtures here are synthetic stand-ins, clearly marked as such in the files
/// themselves. They pin the parser's *behaviour* — table reading, fallback
/// reading, login detection, and the "this page changed" signal — so that
/// swapping in real saved markup is a matter of replacing a file and adjusting
/// the expected values, not rewriting the suite.
final class LearningSuiteParsingTests: XCTestCase {
    private let parser = LearningSuiteHeuristicParser()

    private func context() -> LearningSuiteParseContext {
        LearningSuiteParseContext(
            now: referenceNow,
            fallbackCourseName: "Learning Suite",
            baseURL: URL(string: "https://learningsuite.byu.edu")
        )
    }

    // MARK: Tables

    func testReadsATableOfAssignments() throws {
        let html = try Fixture.string("learningsuite_table.html")
        let items = try parser.parse(html: html, context: context())

        XCTAssertEqual(items.count, 3, "the row with no due date is skipped")
        XCTAssertEqual(items.map(\.title), [
            "Reading Response 3",
            "Concert Report",
            "Unit 4 Quiz"
        ])
    }

    func testTableRowsCarryCourseSourceAndLink() throws {
        let html = try Fixture.string("learningsuite_table.html")
        let items = try parser.parse(html: html, context: context())

        let first = try XCTUnwrap(items.first)
        XCTAssertEqual(first.source, .learningSuite)
        XCTAssertEqual(first.courseName, "A HTG 100")
        XCTAssertEqual(
            first.url?.absoluteString,
            "https://learningsuite.byu.edu/student/assignments/view/44821"
        )
    }

    func testTableDueDatesAreParsedInSeveralWrittenForms() throws {
        let html = try Fixture.string("learningsuite_table.html")
        let items = try parser.parse(html: html, context: context())

        // "Sep 8, 2026 11:59 PM"
        XCTAssertEqual(items[0].dueDate, makeDate(2026, 9, 8, 23, 59))
        // "9/12/2026 at 5:00 PM"
        XCTAssertEqual(items[1].dueDate, makeDate(2026, 9, 12, 17, 0))
        // "Sep 15" — no year, no time: the year is inferred and 11:59 PM assumed
        XCTAssertEqual(items[2].dueDate, makeDate(2026, 9, 15, 23, 59))
    }

    func testSubmittedStatusIsReadAsCompleted() throws {
        let html = try Fixture.string("learningsuite_table.html")
        let items = try parser.parse(html: html, context: context())

        XCTAssertEqual(items[0].isCompleted, false, "Not submitted")
        XCTAssertEqual(items[1].isCompleted, true, "Submitted")
    }

    func testStatusWordsMeaningTheOppositeAreNotReadAsComplete() throws {
        // Every word that means "done" is a substring of some phrase that means
        // the opposite. Getting this backwards would tick off work still owed.
        let html = """
        <table>
          <tr><th>Assignment</th><th>Due</th><th>Status</th></tr>
          <tr><td><a href="/a/1">Reading Response</a></td><td>Sep 9, 2026 11:59 PM</td><td>Not submitted</td></tr>
          <tr><td><a href="/a/2">Lab Report</a></td><td>Sep 10, 2026 11:59 PM</td><td>Unsubmitted</td></tr>
          <tr><td><a href="/a/3">Essay Draft</a></td><td>Sep 11, 2026 11:59 PM</td><td>Missing</td></tr>
          <tr><td><a href="/a/4">Final Paper</a></td><td>Sep 12, 2026 11:59 PM</td><td>Submitted</td></tr>
        </table>
        """
        let items = try parser.parse(html: html, context: context())
        XCTAssertEqual(items.map(\.title), ["Reading Response", "Lab Report", "Essay Draft", "Final Paper"])
        XCTAssertEqual(items.map(\.isCompleted), [false, false, false, true])
    }

    func testTitleDrivesTheItemType() throws {
        let html = try Fixture.string("learningsuite_table.html")
        let items = try parser.parse(html: html, context: context())
        XCTAssertEqual(items[2].type, .quiz, "“Unit 4 Quiz”")
    }

    // MARK: Fallback pass

    func testReadsCardsWhenThereIsNoTable() throws {
        let html = try Fixture.string("learningsuite_cards.html")
        let items = try parser.parse(html: html, context: context())

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.map(\.title), [
            "Lab 5 Writeup",
            "Rhetorical Analysis Draft",
            "Problem Set 6"
        ])
    }

    func testCardsTakeTheirCourseFromTheGroupHeading() throws {
        let html = try Fixture.string("learningsuite_cards.html")
        let items = try parser.parse(html: html, context: context())

        let lab = try XCTUnwrap(items.first { $0.title == "Lab 5 Writeup" })
        XCTAssertEqual(lab.courseName, "PHSCS 121")

        let essay = try XCTUnwrap(items.first { $0.title == "Rhetorical Analysis Draft" })
        XCTAssertEqual(essay.courseName, "WRTG 150")
    }

    func testCardsDoNotReportCompletionTheyCannotSee() throws {
        let html = try Fixture.string("learningsuite_cards.html")
        let items = try parser.parse(html: html, context: context())
        // Nil, not false: the store must leave a hand-set completion alone.
        XCTAssertTrue(items.allSatisfy { $0.isCompleted == nil })
    }

    // MARK: Failure states

    func testALapsedSessionIsReportedAsSuchNotAsAParsingProblem() throws {
        let html = try Fixture.string("learningsuite_login.html")

        XCTAssertThrowsError(try parser.parse(html: html, context: context())) { error in
            let failure = error as? SyncFailure
            XCTAssertEqual(failure?.kind, .sessionExpired)
            XCTAssertEqual(failure?.requiresReauthentication, true)
        }
    }

    func testAnUnreadablePageReportsThatTheSiteMayHaveChanged() throws {
        let html = try Fixture.string("learningsuite_unrecognised.html")

        XCTAssertThrowsError(try parser.parse(html: html, context: context())) { error in
            let failure = error as? SyncFailure
            XCTAssertEqual(failure?.kind, .parsingChanged)
            XCTAssertEqual(failure?.requiresReauthentication, false)
        }
    }

    func testAPageThatSaysNothingIsDueIsNotAnError() throws {
        let html = """
        <html><body><div class="assignment-list"><p>No assignments are due.</p></div></body></html>
        """
        XCTAssertEqual(try parser.parse(html: html, context: context()).count, 0)
    }

    // MARK: Identity

    func testTheSameRowKeepsTheSameIdentityAcrossParses() throws {
        let html = try Fixture.string("learningsuite_table.html")
        let first = try parser.parse(html: html, context: context())
        let second = try parser.parse(html: html, context: context())

        XCTAssertEqual(first.map(\.sourceItemID), second.map(\.sourceItemID))
        XCTAssertEqual(Set(first.map(\.sourceItemID)).count, first.count, "identities must be unique")
    }

    func testIdentityIsStableForRowsWithoutALink() {
        let dueDate = makeDate(2026, 9, 20, 23, 59)
        let identity = "PHSCS 121|Lab 5|\(Int(dueDate.timeIntervalSince1970))"
        XCTAssertEqual(StableID.make(from: identity), StableID.make(from: identity))
        XCTAssertNotEqual(StableID.make(from: identity), StableID.make(from: identity + "x"))
    }

    // MARK: Configurability

    func testSelectorLabelsCanBeRetargetedWithoutTouchingTheParser() throws {
        var config = LearningSuiteSelectorConfig.default
        config.dueColumnLabels = ["fecha"]
        config.titleColumnLabels = ["tarea"]
        let retargeted = LearningSuiteHeuristicParser(config: config)

        let html = """
        <table>
          <tr><th>Tarea</th><th>Fecha</th></tr>
          <tr><td><a href="/x/1">Ensayo</a></td><td>Sep 9, 2026 11:59 PM</td></tr>
        </table>
        """
        let items = try retargeted.parse(html: html, context: context())
        XCTAssertEqual(items.map(\.title), ["Ensayo"])
        XCTAssertEqual(items.first?.dueDate, makeDate(2026, 9, 9, 23, 59))
    }
}
