import Foundation
import SwiftData

/// Where a deadline came from. Both sources map into the same `Deadline`.
enum DeadlineSource: String, Codable, CaseIterable, Sendable {
    case canvas
    case learningSuite

    var displayName: String {
        switch self {
        case .canvas: return "Canvas"
        case .learningSuite: return "Learning Suite"
        }
    }

    /// SF Symbol used to tag a row with its origin.
    var symbolName: String {
        switch self {
        case .canvas: return "globe"
        case .learningSuite: return "building.columns"
        }
    }
}

enum DeadlineType: String, Codable, CaseIterable, Sendable {
    case assignment
    case quiz
    case discussion
    case exam
    case other

    var displayName: String {
        switch self {
        case .assignment: return "Assignment"
        case .quiz: return "Quiz"
        case .discussion: return "Discussion"
        case .exam: return "Exam"
        case .other: return "Item"
        }
    }

    var symbolName: String {
        switch self {
        case .assignment: return "doc.text"
        case .quiz: return "checklist"
        case .discussion: return "bubble.left.and.bubble.right"
        case .exam: return "graduationcap"
        case .other: return "circle"
        }
    }

    /// Best-effort classification from a free-text title or a source's own type string.
    static func inferred(from text: String) -> DeadlineType {
        let lowered = text.lowercased()
        if lowered.contains("exam") || lowered.contains("midterm") || lowered.contains("final") {
            return .exam
        }
        if lowered.contains("quiz") || lowered.contains("test") {
            return .quiz
        }
        if lowered.contains("discussion") || lowered.contains("forum") || lowered.contains("board") {
            return .discussion
        }
        if lowered.contains("assignment") || lowered.contains("homework") || lowered.contains("paper") {
            return .assignment
        }
        return .other
    }
}

/// One due item, regardless of which system it came from.
///
/// `sourceItemID` is the stable identifier the origin system uses (a Canvas
/// assignment id, or a hash of the Learning Suite row). It is what sync keys on,
/// so a re-sync updates a row in place instead of duplicating it.
@Model
final class Deadline {
    var id: UUID = UUID()
    var sourceRaw: String = DeadlineSource.canvas.rawValue
    var sourceItemID: String = ""
    var courseName: String = ""
    var courseCode: String = ""
    var title: String = ""
    var typeRaw: String = DeadlineType.other.rawValue
    var dueDate: Date = Date()
    var urlString: String?
    var details: String?
    var isCompleted: Bool = false
    var lastSyncedAt: Date = Date()

    /// Set when the user completes or un-completes an item by hand. Sync will not
    /// overwrite `isCompleted` with the source's value after this timestamp, so a
    /// swipe-to-complete on a Learning Suite item (which has no completion state to
    /// read back) survives the next refresh.
    var completionOverriddenAt: Date?

    init(
        id: UUID = UUID(),
        source: DeadlineSource,
        sourceItemID: String,
        courseName: String,
        courseCode: String,
        title: String,
        type: DeadlineType,
        dueDate: Date,
        url: URL? = nil,
        details: String? = nil,
        isCompleted: Bool = false,
        lastSyncedAt: Date = Date(),
        completionOverriddenAt: Date? = nil
    ) {
        self.id = id
        self.sourceRaw = source.rawValue
        self.sourceItemID = sourceItemID
        self.courseName = courseName
        self.courseCode = courseCode
        self.title = title
        self.typeRaw = type.rawValue
        self.dueDate = dueDate
        self.urlString = url?.absoluteString
        self.details = details
        self.isCompleted = isCompleted
        self.lastSyncedAt = lastSyncedAt
        self.completionOverriddenAt = completionOverriddenAt
    }
}

extension Deadline {
    var source: DeadlineSource {
        get { DeadlineSource(rawValue: sourceRaw) ?? .canvas }
        set { sourceRaw = newValue.rawValue }
    }

    var type: DeadlineType {
        get { DeadlineType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    var url: URL? {
        get { urlString.flatMap(URL.init(string:)) }
        set { urlString = newValue?.absoluteString }
    }

    /// Past due and not marked done.
    func isOverdue(asOf now: Date = Date()) -> Bool {
        !isCompleted && dueDate < now
    }

    /// Course label for a row, preferring the short code when there is one.
    var courseLabel: String {
        courseCode.isEmpty ? courseName : courseCode
    }

    /// Everything a VoiceOver user needs from a row in one utterance.
    func accessibilityDescription(asOf now: Date = Date()) -> String {
        var parts: [String] = [title, courseLabel, source.displayName]
        let time = DateFormatter.deadlineTime.string(from: dueDate)
        if isCompleted {
            parts.append("completed")
        } else if isOverdue(asOf: now) {
            parts.append("overdue, was due \(time)")
        } else {
            parts.append("due \(time)")
        }
        return parts.joined(separator: ", ")
    }
}

extension DateFormatter {
    static let deadlineTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
