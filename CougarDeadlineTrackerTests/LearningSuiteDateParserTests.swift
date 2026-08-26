import XCTest
@testable import CougarDeadlineTracker

/// The written date formats a scraped page can throw at us.
final class LearningSuiteDateParserTests: XCTestCase {
    private let parser = LearningSuiteDateParser()

    func testNamedMonthWithYearAndTime() {
        XCTAssertEqual(
            parser.date(in: "Sep 8, 2026 11:59 PM", now: referenceNow),
            makeDate(2026, 9, 8, 23, 59)
        )
    }

    func testFullMonthName() {
        XCTAssertEqual(
            parser.date(in: "September 8, 2026 at 9:05 AM", now: referenceNow),
            makeDate(2026, 9, 8, 9, 5)
        )
    }

    func testWeekdayPrefixIsIgnored() {
        XCTAssertEqual(
            parser.date(in: "Tue, Sep 8 at 11:59 PM", now: referenceNow),
            makeDate(2026, 9, 8, 23, 59)
        )
    }

    func testNumericSlashFormat() {
        XCTAssertEqual(
            parser.date(in: "9/12/2026 5:00 PM", now: referenceNow),
            makeDate(2026, 9, 12, 17, 0)
        )
    }

    func testTwoDigitYear() {
        XCTAssertEqual(
            parser.date(in: "9/12/26", now: referenceNow),
            makeDate(2026, 9, 12, 23, 59)
        )
    }

    func testMissingTimeDefaultsToEndOfDay() {
        XCTAssertEqual(
            parser.date(in: "Sep 15", now: referenceNow),
            makeDate(2026, 9, 15, 23, 59)
        )
    }

    func testMissingYearIsInferredAsTheNearestOne() {
        // Seen in December, "Jan 8" is next year, not ten months ago.
        let december = makeDate(2026, 12, 15, 9, 0)
        XCTAssertEqual(
            parser.date(in: "Jan 8", now: december),
            makeDate(2027, 1, 8, 23, 59)
        )
    }

    func testRelativeWords() {
        XCTAssertEqual(
            parser.date(in: "Today at 11:59 PM", now: referenceNow),
            makeDate(2026, 9, 5, 23, 59)
        )
        XCTAssertEqual(
            parser.date(in: "Tomorrow 8:00 AM", now: referenceNow),
            makeDate(2026, 9, 6, 8, 0)
        )
    }

    func testDueLabelIsStripped() {
        XCTAssertEqual(
            parser.date(in: "Due: Sep 9, 2026 11:59 PM", now: referenceNow),
            makeDate(2026, 9, 9, 23, 59)
        )
    }

    func testMidnightAndNoonConvertCorrectly() {
        XCTAssertEqual(
            parser.date(in: "Sep 9, 2026 12:00 AM", now: referenceNow),
            makeDate(2026, 9, 9, 0, 0)
        )
        XCTAssertEqual(
            parser.date(in: "Sep 9, 2026 12:00 PM", now: referenceNow),
            makeDate(2026, 9, 9, 12, 0)
        )
    }

    func testTextWithoutADateReturnsNil() {
        XCTAssertNil(parser.date(in: "Not submitted", now: referenceNow))
        XCTAssertNil(parser.date(in: "", now: referenceNow))
        XCTAssertNil(parser.date(in: "—", now: referenceNow))
    }

    func testImpossibleDatesAreRejected() {
        XCTAssertNil(parser.date(in: "19/45/2026", now: referenceNow))
    }
}
