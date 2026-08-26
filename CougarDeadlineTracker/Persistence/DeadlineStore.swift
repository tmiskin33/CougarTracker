import Foundation
import SwiftData

/// Merges freshly imported deadlines into the local store.
///
/// The rules, in one place so both pipelines behave the same:
///  - identity is (source, sourceItemID); a re-sync updates in place
///  - a manual completion always beats the source's value
///  - items a source stops reporting are removed, but only future ones, so
///    finished coursework does not vanish out of the past when Canvas drops it
///    from the upcoming bucket
@MainActor
struct DeadlineStore {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func merge(
        _ imported: [ImportedDeadline],
        from source: DeadlineSource,
        prunesMissingFutureItems: Bool = true,
        now: Date = Date()
    ) throws -> MergeResult {
        let sourceRaw = source.rawValue
        let descriptor = FetchDescriptor<Deadline>(
            predicate: #Predicate { $0.sourceRaw == sourceRaw }
        )
        let existing = try context.fetch(descriptor)
        var byItemID = Dictionary(existing.map { ($0.sourceItemID, $0) }, uniquingKeysWith: { first, _ in first })

        var inserted = 0
        var updated = 0

        for item in imported {
            if let match = byItemID.removeValue(forKey: item.sourceItemID) {
                apply(item, to: match, now: now)
                updated += 1
            } else {
                let deadline = Deadline(
                    source: item.source,
                    sourceItemID: item.sourceItemID,
                    courseName: item.courseName,
                    courseCode: item.courseCode,
                    title: item.title,
                    type: item.type,
                    dueDate: item.dueDate,
                    url: item.url,
                    details: item.details,
                    isCompleted: item.isCompleted ?? false,
                    lastSyncedAt: now
                )
                context.insert(deadline)
                inserted += 1
            }
        }

        var removed = 0
        if prunesMissingFutureItems {
            for orphan in byItemID.values where orphan.dueDate >= now {
                context.delete(orphan)
                removed += 1
            }
        }

        try context.save()
        return MergeResult(inserted: inserted, updated: updated, removed: removed)
    }

    private func apply(_ item: ImportedDeadline, to deadline: Deadline, now: Date) {
        deadline.courseName = item.courseName
        deadline.courseCode = item.courseCode
        deadline.title = item.title
        deadline.type = item.type
        deadline.dueDate = item.dueDate
        deadline.url = item.url
        if let details = item.details {
            deadline.details = details
        }
        // A hand-set completion wins. Canvas can still mark something complete
        // that the user never touched, which is the common case.
        if let remote = item.isCompleted, deadline.completionOverriddenAt == nil {
            deadline.isCompleted = remote
        }
        deadline.lastSyncedAt = now
    }

    /// Records a completion the user made by hand, pinning it against sync.
    func setCompleted(_ isCompleted: Bool, on deadline: Deadline, at date: Date = Date()) throws {
        deadline.isCompleted = isCompleted
        deadline.completionOverriddenAt = date
        try context.save()
    }

    func deleteAll(from source: DeadlineSource) throws {
        let sourceRaw = source.rawValue
        let descriptor = FetchDescriptor<Deadline>(
            predicate: #Predicate { $0.sourceRaw == sourceRaw }
        )
        for deadline in try context.fetch(descriptor) {
            context.delete(deadline)
        }
        try context.save()
    }

    func deleteEverything() throws {
        for deadline in try context.fetch(FetchDescriptor<Deadline>()) {
            context.delete(deadline)
        }
        try context.save()
    }

    struct MergeResult: Equatable {
        var inserted: Int
        var updated: Int
        var removed: Int
        var touched: Int { inserted + updated }
    }
}
