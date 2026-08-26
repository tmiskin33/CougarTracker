import Foundation
import XCTest

/// Loads the saved API and page samples the parsing tests run against.
///
/// Everything here is a file on disk: no test touches the network, and none needs
/// a live Canvas token or a Learning Suite session.
enum Fixture {
    static func data(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> Data {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
            ?? bundle.url(forResource: name, withExtension: nil) else {
            XCTFail("Missing fixture \(name). Check it is in the test target's Copy Bundle Resources.", file: file, line: line)
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    static func string(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let data = try data(name, file: file, line: line)
        guard let string = String(data: data, encoding: .utf8) else {
            XCTFail("Fixture \(name) is not UTF-8.", file: file, line: line)
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return string
    }

    private final class BundleToken {}
}

extension XCTestCase {
    /// A fixed "now" so year inference and overdue checks are deterministic.
    var referenceNow: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 5
        components.hour = 9
        components.minute = 0
        return Calendar.current.date(from: components)!
    }

    func makeDate(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0,
        calendar: Calendar = .current
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }
}
