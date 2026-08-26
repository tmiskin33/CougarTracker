import Foundation

/// The seam that makes the scraper swappable.
///
/// Everything above this protocol — sync, storage, UI — depends only on
/// `[ImportedDeadline]`. When Learning Suite redesigns its pages, a new
/// conforming type is the entire blast radius.
protocol LearningSuiteParsing {
    func parse(html: String, context: LearningSuiteParseContext) throws -> [ImportedDeadline]
}

struct LearningSuiteParseContext {
    var now: Date = Date()
    /// Used when a row does not name its own course.
    var fallbackCourseName: String = "Learning Suite"
    var baseURL: URL? = URL(string: "https://learningsuite.byu.edu")
}

/// Text the parser matches against, kept out of the code so it can be retargeted
/// without touching parsing logic — including from a bundled JSON override once
/// the real markup is known.
struct LearningSuiteSelectorConfig: Codable, Equatable {
    var dueColumnLabels: [String]
    var titleColumnLabels: [String]
    var courseColumnLabels: [String]
    var statusColumnLabels: [String]
    var completedStatusWords: [String]
    var itemClassHints: [String]
    var courseClassHints: [String]
    var loginPageMarkers: [String]
    var ignoredRowWords: [String]

    static let `default` = LearningSuiteSelectorConfig(
        dueColumnLabels: ["due", "due date", "due on", "date due", "deadline", "date"],
        titleColumnLabels: ["assignment", "title", "name", "task", "item", "description", "activity"],
        courseColumnLabels: ["course", "class", "section", "subject"],
        statusColumnLabels: ["status", "submitted", "state", "completed"],
        completedStatusWords: ["submitted", "complete", "completed", "turned in", "done", "graded"],
        itemClassHints: ["assignment", "due", "task", "deadline", "event", "item", "row", "card", "todo"],
        courseClassHints: ["course", "class", "section"],
        loginPageMarkers: ["cas.byu.edu", "byu net id", "netid", "duo security", "two-factor", "sign in to byu"],
        ignoredRowWords: ["no assignments", "nothing due", "no items"]
    )

    /// Loads an override shipped in the app bundle, falling back to the built-in
    /// defaults. Retargeting the scraper can then be a resource change.
    static func loadBundled(named name: String = "LearningSuiteSelectors", in bundle: Bundle = .main) -> LearningSuiteSelectorConfig {
        guard let url = bundle.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(LearningSuiteSelectorConfig.self, from: data) else {
            return .default
        }
        return config
    }
}

/// Parses Learning Suite's assignment pages without depending on exact class
/// names.
///
/// Two passes, most-structured first:
///   1. tables whose header row names a due-date column
///   2. any repeated block that contains both a date and a link
///
/// Matching on what a row *says* rather than what it is *called* is the only
/// defence available against a redesign, but it is a defence, not a guarantee:
/// a page that stops using tables and stops writing dates in text will need this
/// type replaced.
struct LearningSuiteHeuristicParser: LearningSuiteParsing {
    var config: LearningSuiteSelectorConfig
    var dateParser: LearningSuiteDateParser

    init(
        config: LearningSuiteSelectorConfig = .default,
        dateParser: LearningSuiteDateParser = LearningSuiteDateParser()
    ) {
        self.config = config
        self.dateParser = dateParser
    }

    func parse(html: String, context: LearningSuiteParseContext) throws -> [ImportedDeadline] {
        let document = HTMLDocument.parse(html)

        var results = parseTables(in: document, context: context)
        if results.isEmpty {
            results = parseBlocks(in: document, context: context)
        }

        if results.isEmpty {
            if looksLikeLoginPage(document) {
                throw SyncFailure.sessionExpired(.learningSuite)
            }
            if statesNothingIsDue(document) {
                return []
            }
            throw SyncFailure.learningSuiteMarkupChanged
        }

        return deduplicated(results).sorted { $0.dueDate < $1.dueDate }
    }

    // MARK: Login / empty detection

    /// A scraped session that has lapsed comes back as BYU's sign-in page with a
    /// 200 status, which would otherwise read as "the site changed".
    func looksLikeLoginPage(_ document: HTMLNode) -> Bool {
        let haystack = document.text.lowercased()
        if config.loginPageMarkers.contains(where: { haystack.contains($0.lowercased()) }) {
            return true
        }
        let hasPasswordField = document.elements(tag: "input").contains {
            $0.attribute("type")?.lowercased() == "password"
        }
        return hasPasswordField
    }

    private func statesNothingIsDue(_ document: HTMLNode) -> Bool {
        let haystack = document.text.lowercased()
        return config.ignoredRowWords.contains { haystack.contains($0.lowercased()) }
    }

    // MARK: Strategy 1 — tables

    private func parseTables(in document: HTMLNode, context: LearningSuiteParseContext) -> [ImportedDeadline] {
        var results: [ImportedDeadline] = []

        for table in document.elements(tag: "table") {
            let rows = table.elements(tag: "tr")
            guard rows.count > 1 else { continue }
            guard let header = headerColumns(of: rows) else { continue }
            guard header.map[.due] != nil else { continue }

            for row in rows where row !== header.row {
                let cells = row.childElements().filter { $0.tagName == "td" || $0.tagName == "th" }
                guard !cells.isEmpty else { continue }
                guard let item = deadline(fromCells: cells, header: header.map, row: row, context: context) else {
                    continue
                }
                results.append(item)
            }
        }
        return results
    }

    private enum Column: Hashable {
        case due, title, course, status
    }

    private func headerColumns(of rows: [HTMLNode]) -> (row: HTMLNode, map: [Column: Int])? {
        for row in rows.prefix(3) {
            let cells = row.childElements().filter { $0.tagName == "th" || $0.tagName == "td" }
            guard !cells.isEmpty else { continue }

            var map: [Column: Int] = [:]
            for (index, cell) in cells.enumerated() {
                let label = cell.text.lowercased().trimmed
                guard !label.isEmpty else { continue }
                if map[.due] == nil, matches(label, config.dueColumnLabels) { map[.due] = index }
                if map[.title] == nil, matches(label, config.titleColumnLabels) { map[.title] = index }
                if map[.course] == nil, matches(label, config.courseColumnLabels) { map[.course] = index }
                if map[.status] == nil, matches(label, config.statusColumnLabels) { map[.status] = index }
            }
            if map[.due] != nil && (map[.title] != nil || map[.course] != nil) {
                return (row, map)
            }
        }
        return nil
    }

    private func matches(_ label: String, _ candidates: [String]) -> Bool {
        candidates.contains { label == $0 || label.contains($0) }
    }

    private func deadline(
        fromCells cells: [HTMLNode],
        header map: [Column: Int],
        row: HTMLNode,
        context: LearningSuiteParseContext
    ) -> ImportedDeadline? {
        func cell(_ column: Column) -> HTMLNode? {
            guard let index = map[column], cells.indices.contains(index) else { return nil }
            return cells[index]
        }

        guard let dueText = cell(.due)?.text.nilIfBlank,
              let dueDate = dateParser.date(in: dueText, now: context.now) else { return nil }

        let link = row.elements(tag: "a").first
        let titleFromColumn = cell(.title)?.text.nilIfBlank
        let title = titleFromColumn ?? link?.text.nilIfBlank
        guard let title, !isNoise(title) else { return nil }

        let course = cell(.course)?.text.nilIfBlank ?? context.fallbackCourseName

        var completed: Bool?
        if let statusText = cell(.status)?.text.nilIfBlank {
            completed = isCompletedStatus(statusText)
        }

        return makeDeadline(
            title: title,
            course: course,
            dueDate: dueDate,
            href: link?.attribute("href"),
            isCompleted: completed,
            context: context
        )
    }

    private func isCompletedStatus(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return config.completedStatusWords.contains { lowered.contains($0) }
    }

    // MARK: Strategy 2 — repeated blocks

    private func parseBlocks(in document: HTMLNode, context: LearningSuiteParseContext) -> [ImportedDeadline] {
        let candidates = document.elements { node in
            guard let tag = node.tagName else { return false }
            if tag == "li" || tag == "article" { return true }
            guard tag == "div" || tag == "section" || tag == "tr" else { return false }
            let names = node.classNames.map { $0.lowercased() } + [node.attribute("id")?.lowercased() ?? ""]
            return names.contains { name in
                config.itemClassHints.contains { name.contains($0) }
            }
        }

        // Keep the innermost candidate for each item: an outer wrapper repeats
        // the same date and would double every row.
        let innermost = candidates.filter { candidate in
            !candidates.contains { other in other !== candidate && isDescendant(other, of: candidate) }
        }

        var results: [ImportedDeadline] = []
        for node in innermost {
            let text = node.text
            guard let dueDate = dateParser.date(in: text, now: context.now) else { continue }

            let link = node.elements(tag: "a").first
            let title = link?.text.nilIfBlank
                ?? headingText(in: node)
                ?? text.nilIfBlank
            guard let title, !isNoise(title) else { continue }

            let course = courseName(near: node) ?? context.fallbackCourseName
            results.append(
                makeDeadline(
                    title: String(title.prefix(180)),
                    course: course,
                    dueDate: dueDate,
                    href: link?.attribute("href"),
                    isCompleted: nil,
                    context: context
                )
            )
        }
        return results
    }

    private func isDescendant(_ node: HTMLNode, of ancestor: HTMLNode) -> Bool {
        node.ancestor { $0 === ancestor } != nil
    }

    private func headingText(in node: HTMLNode) -> String? {
        for tag in ["h1", "h2", "h3", "h4", "h5", "strong", "b"] {
            if let text = node.firstElement(tag: tag)?.text.nilIfBlank { return text }
        }
        return nil
    }

    /// Walks up looking for something that names a course.
    ///
    /// A heading over a group of items wins over a class name, because a
    /// `class="course-group"` wrapper's own text is the whole group, not its title.
    private func courseName(near node: HTMLNode) -> String? {
        var current: HTMLNode? = node
        var hops = 0
        while let candidate = current, hops < 6 {
            for child in candidate.children where ["h1", "h2", "h3", "h4"].contains(child.tagName ?? "") {
                if let text = child.text.nilIfBlank, text.count <= 80 { return text }
            }

            let names = candidate.classNames.map { $0.lowercased() }
            if names.contains(where: { name in config.courseClassHints.contains { name.contains($0) } }),
               let text = candidate.text.nilIfBlank, text.count <= 60 {
                return text
            }

            current = candidate.parent
            hops += 1
        }
        return nil
    }

    // MARK: Shared

    private func isNoise(_ title: String) -> Bool {
        let lowered = title.lowercased()
        if lowered.count < 2 { return true }
        return config.ignoredRowWords.contains { lowered.contains($0) }
    }

    private func makeDeadline(
        title: String,
        course: String,
        dueDate: Date,
        href: String?,
        isCompleted: Bool?,
        context: LearningSuiteParseContext
    ) -> ImportedDeadline {
        let url = href.flatMap { URL(string: $0, relativeTo: context.baseURL)?.absoluteURL }
        let identity = href?.nilIfBlank
            ?? "\(course)|\(title)|\(Int(dueDate.timeIntervalSince1970))"

        return ImportedDeadline(
            source: .learningSuite,
            sourceItemID: StableID.make(from: identity),
            courseName: course,
            courseCode: "",
            title: title,
            type: DeadlineType.inferred(from: title),
            dueDate: dueDate,
            url: url,
            details: nil,
            isCompleted: isCompleted
        )
    }

    private func deduplicated(_ items: [ImportedDeadline]) -> [ImportedDeadline] {
        var seen = Set<String>()
        var result: [ImportedDeadline] = []
        for item in items where seen.insert(item.sourceItemID).inserted {
            result.append(item)
        }
        return result
    }
}

/// A hash that stays the same across launches, unlike `Hashable`, which is what a
/// scraped row needs for its identity to survive a re-sync.
enum StableID {
    static func make(from string: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return "ls-" + String(hash, radix: 16)
    }
}
