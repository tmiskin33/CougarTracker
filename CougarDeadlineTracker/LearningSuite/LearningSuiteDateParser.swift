import Foundation

/// Parses the human-written dates a scraped page shows.
///
/// Learning Suite renders due dates for people, not machines: "Sep 3", "9/3/2025",
/// "Wed, Sep 3 at 11:59 PM", "Today". Each of those has to become a real `Date`,
/// and a missing year or time has to be filled in the way a student would read it.
struct LearningSuiteDateParser {
    var calendar: Calendar
    /// Learning Suite's own convention for "end of day", used when a row gives a
    /// date but no time.
    var defaultDueTime: DateComponents

    init(calendar: Calendar = .current, defaultDueTime: DateComponents = DateComponents(hour: 23, minute: 59)) {
        var calendar = calendar
        calendar.locale = calendar.locale ?? Locale(identifier: "en_US_POSIX")
        self.calendar = calendar
        self.defaultDueTime = defaultDueTime
    }

    /// Pulls the first date out of arbitrary row text.
    /// `now` anchors relative words and the year guess, so tests are deterministic.
    func date(in text: String, now: Date = Date()) -> Date? {
        let cleaned = text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: " at ", with: " ", options: [.caseInsensitive])
            .replacingOccurrences(of: "Due:", with: " ", options: [.caseInsensitive])
            .replacingOccurrences(of: "Due ", with: " ", options: [.caseInsensitive])
            .trimmed

        guard !cleaned.isEmpty else { return nil }

        let time = self.time(in: cleaned)

        if let relative = relativeDay(in: cleaned, now: now) {
            return apply(time: time, to: relative)
        }
        if let numeric = numericDate(in: cleaned, now: now) {
            return apply(time: time, to: numeric)
        }
        if let named = namedMonthDate(in: cleaned, now: now) {
            return apply(time: time, to: named)
        }
        return nil
    }

    // MARK: Pieces

    private func apply(time: DateComponents?, to day: Date) -> Date? {
        let components = time ?? defaultDueTime
        return calendar.date(
            bySettingHour: components.hour ?? 23,
            minute: components.minute ?? 59,
            second: 0,
            of: day
        )
    }

    private func relativeDay(in text: String, now: Date) -> Date? {
        let lowered = text.lowercased()
        let today = calendar.startOfDay(for: now)
        if lowered.contains("today") { return today }
        if lowered.contains("tomorrow") { return calendar.date(byAdding: .day, value: 1, to: today) }
        if lowered.contains("yesterday") { return calendar.date(byAdding: .day, value: -1, to: today) }
        return nil
    }

    /// 9/3, 9/3/25, 9/3/2025, and the same with dashes.
    private func numericDate(in text: String, now: Date) -> Date? {
        let pattern = #"(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?"#
        guard let match = firstMatch(of: pattern, in: text) else { return nil }
        guard let month = Int(match[1] ?? ""), let day = Int(match[2] ?? "") else { return nil }
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }

        if let yearText = match[3], let year = Int(yearText) {
            return self.day(month: month, day: day, year: year < 100 ? 2000 + year : year)
        }
        return dayGuessingYear(month: month, day: day, now: now)
    }

    /// "Sep 3", "September 3, 2025", "Wed, Sep 3".
    private func namedMonthDate(in text: String, now: Date) -> Date? {
        let pattern = #"(?i)\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:\s*,?\s*(\d{4}))?"#
        guard let match = firstMatch(of: pattern, in: text) else { return nil }
        guard let monthText = match[1]?.lowercased(),
              let month = Self.monthNumbers[String(monthText.prefix(3))],
              let day = Int(match[2] ?? "") else { return nil }

        if let yearText = match[3], let year = Int(yearText) {
            return self.day(month: month, day: day, year: year)
        }
        return dayGuessingYear(month: month, day: day, now: now)
    }

    /// "11:59 PM", "9:00am", "23:59".
    private func time(in text: String) -> DateComponents? {
        let pattern = #"(?i)\b(\d{1,2}):(\d{2})\s*(am|pm)?"#
        guard let match = firstMatch(of: pattern, in: text) else { return nil }
        guard var hour = Int(match[1] ?? ""), let minute = Int(match[2] ?? "") else { return nil }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }

        if let meridiem = match[3]?.lowercased() {
            if meridiem == "pm" && hour < 12 { hour += 12 }
            if meridiem == "am" && hour == 12 { hour = 0 }
        }
        return DateComponents(hour: hour, minute: minute)
    }

    private func day(month: Int, day: Int, year: Int) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// With no year on the page, pick the one that puts the date nearest to now.
    /// A term spans a year boundary, so "Jan 8" seen in December means next year.
    private func dayGuessingYear(month: Int, day: Int, now: Date) -> Date? {
        let currentYear = calendar.component(.year, from: now)
        let candidates = [currentYear - 1, currentYear, currentYear + 1]
            .compactMap { self.day(month: month, day: day, year: $0) }
        return candidates.min { abs($0.timeIntervalSince(now)) < abs($1.timeIntervalSince(now)) }
    }

    private static let monthNumbers: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12
    ]

    /// Returns capture groups for the first match, index 0 being the whole match.
    private func firstMatch(of pattern: String, in text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let groupRange = Range(match.range(at: index), in: text) else { return nil }
            return String(text[groupRange])
        }
    }
}
