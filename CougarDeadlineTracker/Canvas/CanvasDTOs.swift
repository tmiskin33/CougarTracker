import Foundation

/// Wire types for the Canvas REST API, plus the mapping into `ImportedDeadline`.
///
/// Everything here is pure: give it `Data` from a fixture and it produces the
/// same result it would from the network, which is what the parsing tests rely on.
enum CanvasAPI {

    // MARK: Wire types

    struct Course: Decodable, Equatable {
        var id: Int
        var name: String?
        var courseCode: String?
        var accessRestrictedByDate: Bool?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case courseCode = "course_code"
            case accessRestrictedByDate = "access_restricted_by_date"
        }

        var isAccessible: Bool {
            accessRestrictedByDate != true && name != nil
        }
    }

    struct Submission: Decodable, Equatable {
        var submittedAt: Date?
        var workflowState: String?
        var missing: Bool?

        enum CodingKeys: String, CodingKey {
            case submittedAt = "submitted_at"
            case workflowState = "workflow_state"
            case missing
        }

        /// Canvas calls a submission "unsubmitted" until something is turned in;
        /// "graded" without a submission date happens for on-paper work, which we
        /// also treat as done.
        var isSubmitted: Bool {
            if submittedAt != nil { return true }
            return workflowState == "graded" || workflowState == "submitted" || workflowState == "complete"
        }
    }

    struct Assignment: Decodable, Equatable {
        var id: Int
        var name: String?
        var dueAt: Date?
        var htmlURL: URL?
        var description: String?
        var courseID: Int?
        var submissionTypes: [String]?
        var quizID: Int?
        var isQuizAssignment: Bool?
        var submission: Submission?
        var hasSubmittedSubmissions: Bool?
        var lockedForUser: Bool?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case dueAt = "due_at"
            case htmlURL = "html_url"
            case description
            case courseID = "course_id"
            case submissionTypes = "submission_types"
            case quizID = "quiz_id"
            case isQuizAssignment = "is_quiz_assignment"
            case submission
            case hasSubmittedSubmissions = "has_submitted_submissions"
            case lockedForUser = "locked_for_user"
        }

        var inferredType: DeadlineType {
            let types = submissionTypes ?? []
            if quizID != nil || isQuizAssignment == true || types.contains("online_quiz") {
                // A "quiz" worth a lot of points and named like an exam is an exam.
                let named = DeadlineType.inferred(from: name ?? "")
                return named == .exam ? .exam : .quiz
            }
            if types.contains("discussion_topic") {
                return .discussion
            }
            let named = DeadlineType.inferred(from: name ?? "")
            return named == .other ? .assignment : named
        }
    }

    /// An entry from `GET /api/v1/users/self/todo`.
    struct TodoItem: Decodable, Equatable {
        var type: String?
        var assignment: Assignment?
        var contextName: String?
        var courseID: Int?
        var htmlURL: URL?

        enum CodingKeys: String, CodingKey {
            case type
            case assignment
            case contextName = "context_name"
            case courseID = "course_id"
            case htmlURL = "html_url"
        }

        /// "grading" items are for instructors; a student only cares about
        /// things they still have to hand in.
        var isForStudent: Bool {
            type == nil || type == "submitting"
        }
    }

    // MARK: Decoding

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = CanvasDateFormatter.date(from: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unrecognised Canvas date: \(raw)"
                )
            }
            return date
        }
        return decoder
    }

    static func decodeCourses(_ data: Data) throws -> [Course] {
        try decoder().decode([Course].self, from: data)
    }

    static func decodeAssignments(_ data: Data) throws -> [Assignment] {
        try decoder().decode([Assignment].self, from: data)
    }

    static func decodeTodo(_ data: Data) throws -> [TodoItem] {
        try decoder().decode([TodoItem].self, from: data)
    }

    // MARK: Mapping

    /// Maps assignments for one course into the unified model. Anything without a
    /// due date is dropped — a deadline tracker has nothing to show for it.
    static func deadlines(
        from assignments: [Assignment],
        courseName: String,
        courseCode: String,
        host: String
    ) -> [ImportedDeadline] {
        assignments.compactMap { assignment in
            guard let dueDate = assignment.dueAt else { return nil }
            let title = assignment.name?.trimmed.nilIfBlank ?? "Untitled assignment"
            return ImportedDeadline(
                source: .canvas,
                sourceItemID: "assignment-\(assignment.id)",
                courseName: courseName,
                courseCode: courseCode,
                title: title,
                type: assignment.inferredType,
                dueDate: dueDate,
                url: assignment.htmlURL ?? fallbackURL(for: assignment, host: host),
                details: assignment.description.flatMap(HTMLText.plainText(from:)),
                isCompleted: assignment.submission?.isSubmitted
            )
        }
    }

    /// Maps the to-do feed. It spans every course at once and carries the course
    /// name inline, so it works even when the course list call is restricted.
    static func deadlines(from todo: [TodoItem], host: String) -> [ImportedDeadline] {
        todo.compactMap { item in
            guard item.isForStudent,
                  let assignment = item.assignment,
                  let dueDate = assignment.dueAt else { return nil }
            let courseName = item.contextName?.trimmed.nilIfBlank ?? "Canvas"
            return ImportedDeadline(
                source: .canvas,
                sourceItemID: "assignment-\(assignment.id)",
                courseName: courseName,
                courseCode: "",
                title: assignment.name?.trimmed.nilIfBlank ?? "Untitled assignment",
                type: assignment.inferredType,
                dueDate: dueDate,
                url: assignment.htmlURL ?? item.htmlURL ?? fallbackURL(for: assignment, host: host),
                details: assignment.description.flatMap(HTMLText.plainText(from:)),
                isCompleted: assignment.submission?.isSubmitted
            )
        }
    }

    /// Combines both feeds, preferring whichever entry carries the richer course
    /// label. The to-do feed often has only a display name; the per-course call
    /// has the code as well.
    static func merge(_ groups: [ImportedDeadline]...) -> [ImportedDeadline] {
        var byID: [String: ImportedDeadline] = [:]
        for group in groups {
            for item in group {
                guard let existing = byID[item.sourceItemID] else {
                    byID[item.sourceItemID] = item
                    continue
                }
                byID[item.sourceItemID] = richer(existing, item)
            }
        }
        return byID.values.sorted { $0.dueDate < $1.dueDate }
    }

    private static func richer(_ lhs: ImportedDeadline, _ rhs: ImportedDeadline) -> ImportedDeadline {
        var result = lhs
        if result.courseCode.isEmpty { result.courseCode = rhs.courseCode }
        if result.courseName.isEmpty || result.courseName == "Canvas" { result.courseName = rhs.courseName }
        if result.details == nil { result.details = rhs.details }
        if result.url == nil { result.url = rhs.url }
        if result.isCompleted == nil { result.isCompleted = rhs.isCompleted }
        return result
    }

    private static func fallbackURL(for assignment: Assignment, host: String) -> URL? {
        guard let courseID = assignment.courseID else { return nil }
        return URL(string: "https://\(host)/courses/\(courseID)/assignments/\(assignment.id)")
    }
}

/// Canvas timestamps are ISO 8601 in UTC, occasionally with fractional seconds.
enum CanvasDateFormatter {
    private static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from string: String) -> Date? {
        plain.date(from: string) ?? withFractionalSeconds.date(from: string)
    }
}
