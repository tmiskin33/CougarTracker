import Foundation

/// What a sync pipeline produces before anything touches the database.
///
/// Both the Canvas client and the Learning Suite parser return these. Keeping
/// them free of SwiftData is what lets the parsing tests run without a model
/// container, and what lets the Learning Suite module be swapped wholesale.
struct ImportedDeadline: Equatable, Hashable, Sendable {
    var source: DeadlineSource
    var sourceItemID: String
    var courseName: String
    var courseCode: String
    var title: String
    var type: DeadlineType
    var dueDate: Date
    var url: URL?
    var details: String?
    /// Nil when the source does not report completion (Learning Suite scraping
    /// generally cannot), which tells the store to leave the local value alone.
    var isCompleted: Bool?

    init(
        source: DeadlineSource,
        sourceItemID: String,
        courseName: String,
        courseCode: String = "",
        title: String,
        type: DeadlineType,
        dueDate: Date,
        url: URL? = nil,
        details: String? = nil,
        isCompleted: Bool? = nil
    ) {
        self.source = source
        self.sourceItemID = sourceItemID
        self.courseName = courseName
        self.courseCode = courseCode
        self.title = title
        self.type = type
        self.dueDate = dueDate
        self.url = url
        self.details = details
        self.isCompleted = isCompleted
    }
}
