import Foundation

/// A very small, forgiving HTML parser.
///
/// This exists so the Learning Suite scraper has no third-party dependency and so
/// its behaviour is fully testable against saved fixtures. It is deliberately
/// lenient: real pages have unclosed tags, stray `<`, and attributes without
/// quotes, and a scraper that throws on those is a scraper that never runs.
final class HTMLNode {
    enum Kind: Equatable {
        case document
        case element(String)
        case text(String)
    }

    let kind: Kind
    private(set) var attributes: [String: String]
    private(set) var children: [HTMLNode] = []
    weak var parent: HTMLNode?

    init(kind: Kind, attributes: [String: String] = [:]) {
        self.kind = kind
        self.attributes = attributes
    }

    var tagName: String? {
        if case .element(let name) = kind { return name }
        return nil
    }

    func append(_ child: HTMLNode) {
        child.parent = self
        children.append(child)
    }

    func attribute(_ name: String) -> String? {
        attributes[name.lowercased()]
    }

    var classNames: [String] {
        (attribute("class") ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
    }

    func hasClass(_ name: String) -> Bool {
        classNames.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// All text under this node, whitespace-collapsed.
    var text: String {
        var pieces: [String] = []
        collectText(into: &pieces)
        return pieces
            .joined(separator: " ")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func collectText(into pieces: inout [String]) {
        switch kind {
        case .text(let value):
            pieces.append(value)
        case .element(let name):
            guard name != "script", name != "style" else { return }
            for child in children { child.collectText(into: &pieces) }
        case .document:
            for child in children { child.collectText(into: &pieces) }
        }
    }

    // MARK: Queries

    /// Depth-first descendants, excluding self.
    var descendants: [HTMLNode] {
        var result: [HTMLNode] = []
        for child in children {
            result.append(child)
            result.append(contentsOf: child.descendants)
        }
        return result
    }

    func elements(tag: String) -> [HTMLNode] {
        descendants.filter { $0.tagName == tag.lowercased() }
    }

    func firstElement(tag: String) -> HTMLNode? {
        elements(tag: tag).first
    }

    func elements(where predicate: (HTMLNode) -> Bool) -> [HTMLNode] {
        descendants.filter { $0.tagName != nil && predicate($0) }
    }

    /// Direct element children with the given tag, which is what table walking
    /// wants — a `<tr>`'s cells, not every cell in a nested table.
    func childElements(tag: String? = nil) -> [HTMLNode] {
        children.filter { node in
            guard let name = node.tagName else { return false }
            guard let tag else { return true }
            return name == tag.lowercased()
        }
    }

    func ancestor(where predicate: (HTMLNode) -> Bool) -> HTMLNode? {
        var current = parent
        while let node = current {
            if predicate(node) { return node }
            current = node.parent
        }
        return nil
    }
}

enum HTMLDocument {
    private static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr"
    ]

    private static let rawTextElements: Set<String> = ["script", "style", "textarea", "title"]

    /// Tags that implicitly close a previous sibling of the same kind.
    private static let implicitlyClosing: [String: Set<String>] = [
        "li": ["li"],
        "p": ["p"],
        "tr": ["tr"],
        "td": ["td", "th"],
        "th": ["td", "th"],
        "option": ["option"],
        "dt": ["dt", "dd"],
        "dd": ["dt", "dd"]
    ]

    static func parse(_ html: String) -> HTMLNode {
        let characters = Array(html)
        let root = HTMLNode(kind: .document)
        var stack: [HTMLNode] = [root]
        var index = 0
        var textStart = 0

        func flushText(upTo end: Int) {
            guard end > textStart else { return }
            let raw = String(characters[textStart..<end])
            let decoded = HTMLText.decodingEntities(raw)
            guard !decoded.trimmed.isEmpty else { return }
            stack.last?.append(HTMLNode(kind: .text(decoded)))
        }

        while index < characters.count {
            guard characters[index] == "<" else {
                index += 1
                continue
            }

            // Comment or doctype.
            if matches(characters, at: index, "<!--") {
                flushText(upTo: index)
                index = indexAfter(characters, from: index + 4, of: "-->") ?? characters.count
                textStart = index
                continue
            }
            if matches(characters, at: index, "<!") {
                flushText(upTo: index)
                index = indexAfter(characters, from: index + 2, of: ">") ?? characters.count
                textStart = index
                continue
            }

            // Closing tag.
            if matches(characters, at: index, "</") {
                flushText(upTo: index)
                var cursor = index + 2
                let name = readTagName(characters, from: &cursor)
                cursor = indexAfter(characters, from: cursor, of: ">") ?? characters.count
                if !name.isEmpty, let depth = stack.lastIndex(where: { $0.tagName == name }), depth > 0 {
                    stack.removeSubrange(depth...)
                }
                index = cursor
                textStart = index
                continue
            }

            // Opening tag — but a bare `<` in prose is not one.
            var cursor = index + 1
            let name = readTagName(characters, from: &cursor)
            guard !name.isEmpty else {
                index += 1
                continue
            }
            flushText(upTo: index)

            var attributes: [String: String] = [:]
            var selfClosing = false
            readAttributes(characters, from: &cursor, into: &attributes, selfClosing: &selfClosing)

            if let closes = implicitlyClosing[name],
               let openIndex = stack.lastIndex(where: { $0.tagName.map(closes.contains) ?? false }),
               openIndex > 0 {
                stack.removeSubrange(openIndex...)
            }

            let element = HTMLNode(kind: .element(name), attributes: attributes)
            stack.last?.append(element)

            if rawTextElements.contains(name) {
                let closing = "</\(name)"
                let contentEnd = firstIndex(characters, from: cursor, of: closing) ?? characters.count
                if contentEnd > cursor, name == "title" || name == "textarea" {
                    let raw = String(characters[cursor..<contentEnd])
                    element.append(HTMLNode(kind: .text(HTMLText.decodingEntities(raw))))
                }
                index = indexAfter(characters, from: contentEnd, of: ">") ?? characters.count
                textStart = index
                continue
            }

            if !selfClosing && !voidElements.contains(name) {
                stack.append(element)
            }
            index = cursor
            textStart = index
        }

        flushText(upTo: characters.count)
        return root
    }

    // MARK: Scanning helpers

    private static func readTagName(_ characters: [Character], from index: inout Int) -> String {
        var name = ""
        while index < characters.count {
            let character = characters[index]
            if character.isLetter || character.isNumber || character == "-" || character == "_" || character == ":" {
                name.append(character)
                index += 1
            } else {
                break
            }
        }
        return name.lowercased()
    }

    private static func readAttributes(
        _ characters: [Character],
        from index: inout Int,
        into attributes: inout [String: String],
        selfClosing: inout Bool
    ) {
        while index < characters.count {
            while index < characters.count, characters[index].isWhitespace { index += 1 }
            guard index < characters.count else { return }

            if characters[index] == ">" {
                index += 1
                return
            }
            if characters[index] == "/" {
                selfClosing = true
                index += 1
                continue
            }

            var name = ""
            while index < characters.count,
                  !characters[index].isWhitespace,
                  characters[index] != "=",
                  characters[index] != ">",
                  characters[index] != "/" {
                name.append(characters[index])
                index += 1
            }
            guard !name.isEmpty else {
                index += 1
                continue
            }

            while index < characters.count, characters[index].isWhitespace { index += 1 }
            var value = ""
            if index < characters.count, characters[index] == "=" {
                index += 1
                while index < characters.count, characters[index].isWhitespace { index += 1 }
                if index < characters.count, characters[index] == "\"" || characters[index] == "'" {
                    let quote = characters[index]
                    index += 1
                    while index < characters.count, characters[index] != quote {
                        value.append(characters[index])
                        index += 1
                    }
                    if index < characters.count { index += 1 }
                } else {
                    while index < characters.count,
                          !characters[index].isWhitespace,
                          characters[index] != ">" {
                        value.append(characters[index])
                        index += 1
                    }
                }
            }
            attributes[name.lowercased()] = HTMLText.decodingEntities(value)
        }
    }

    private static func matches(_ characters: [Character], at index: Int, _ needle: String) -> Bool {
        let needleCharacters = Array(needle)
        guard index + needleCharacters.count <= characters.count else { return false }
        for offset in needleCharacters.indices where characters[index + offset] != needleCharacters[offset] {
            return false
        }
        return true
    }

    private static func firstIndex(_ characters: [Character], from start: Int, of needle: String) -> Int? {
        let needleCharacters = Array(needle.lowercased())
        guard !needleCharacters.isEmpty, start >= 0 else { return nil }
        var index = start
        while index + needleCharacters.count <= characters.count {
            var matched = true
            for offset in needleCharacters.indices
            where characters[index + offset].lowercased() != String(needleCharacters[offset]) {
                matched = false
                break
            }
            if matched { return index }
            index += 1
        }
        return nil
    }

    private static func indexAfter(_ characters: [Character], from start: Int, of needle: String) -> Int? {
        firstIndex(characters, from: start, of: needle).map { $0 + needle.count }
    }
}

/// Text-level HTML helpers used by both the scraper and the Canvas importer
/// (Canvas assignment descriptions come back as HTML).
enum HTMLText {
    static func plainText(from html: String) -> String? {
        let parsed = HTMLDocument.parse(html).text
        return parsed.nilIfBlank
    }

    static func decodingEntities(_ input: String) -> String {
        guard input.contains("&") else { return input }
        var result = ""
        result.reserveCapacity(input.count)
        var iterator = input.startIndex

        while iterator < input.endIndex {
            let character = input[iterator]
            guard character == "&",
                  let semicolon = input[iterator...].firstIndex(of: ";"),
                  input.distance(from: iterator, to: semicolon) <= 10 else {
                result.append(character)
                iterator = input.index(after: iterator)
                continue
            }

            let entity = String(input[input.index(after: iterator)..<semicolon])
            if let decoded = decode(entity: entity) {
                result.append(decoded)
                iterator = input.index(after: semicolon)
            } else {
                result.append(character)
                iterator = input.index(after: iterator)
            }
        }
        return result
    }

    private static let named: [String: Character] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00a0}", "mdash": "—", "ndash": "–", "hellip": "…",
        "rsquo": "’", "lsquo": "‘", "ldquo": "“", "rdquo": "”"
    ]

    private static func decode(entity: String) -> Character? {
        if let character = named[entity.lowercased()] { return character }
        guard entity.hasPrefix("#") else { return nil }
        let digits = entity.dropFirst()
        let scalarValue: UInt32?
        if digits.lowercased().hasPrefix("x") {
            scalarValue = UInt32(digits.dropFirst(), radix: 16)
        } else {
            scalarValue = UInt32(digits)
        }
        guard let scalarValue, let scalar = Unicode.Scalar(scalarValue) else { return nil }
        return Character(scalar)
    }
}
