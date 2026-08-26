import Foundation
import UserNotifications

/// A value copy of the fields a notification needs.
///
/// SwiftData models are not `Sendable`, and scheduling happens off the main
/// actor, so reminders are planned from snapshots taken while still on it.
struct DeadlineSnapshot: Equatable, Sendable {
    var id: UUID
    var title: String
    var courseLabel: String
    var dueDate: Date
    var isCompleted: Bool

    static func chronologically(_ lhs: DeadlineSnapshot, _ rhs: DeadlineSnapshot) -> Bool {
        if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
        return lhs.title < rhs.title
    }
}

extension Deadline {
    var snapshot: DeadlineSnapshot {
        DeadlineSnapshot(
            id: id,
            title: title,
            courseLabel: courseLabel,
            dueDate: dueDate,
            isCompleted: isCompleted
        )
    }
}

/// All local notifications: per-deadline reminders and the daily digest.
///
/// No server and no push infrastructure — everything is scheduled on device with
/// `UNUserNotificationCenter`, so it keeps working with no account and no network.
struct NotificationScheduler {
    /// iOS caps pending local notifications at 64 per app. Reminders are
    /// scheduled soonest-first and the digest is reserved a slot.
    static let pendingLimit = 60

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    enum Identifier {
        static let digestPrefix = "digest."
        static let reminderPrefix = "reminder."

        static func reminder(deadlineID: UUID, offsetMinutes: Int) -> String {
            "\(reminderPrefix)\(deadlineID.uuidString).\(offsetMinutes)"
        }
    }

    // MARK: Permission

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    // MARK: Scheduling

    /// Replaces every scheduled notification with one derived from the current
    /// deadlines. Rescheduling wholesale is cheap and avoids drift between what
    /// is pending and what is actually due.
    func reschedule(
        deadlines: [DeadlineSnapshot],
        settings: AppSettings,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        guard await authorizationStatus() == .authorized else { return }

        center.removeAllPendingNotificationRequests()

        let requests = plannedReminders(
            deadlines: deadlines,
            offsets: settings.reminderOffsets,
            now: now
        )

        var scheduled = 0
        for planned in requests where scheduled < Self.pendingLimit {
            try? await center.add(planned.request())
            scheduled += 1
        }

        if settings.dailyDigestEnabled {
            try? await center.add(digestRequest(settings: settings, calendar: calendar))
        }
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    // MARK: Planning (pure, so it can be tested without a notification centre)

    struct PlannedReminder: Equatable {
        var deadlineID: UUID
        var offsetMinutes: Int
        var fireDate: Date
        var title: String
        var body: String

        func request() -> UNNotificationRequest {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.userInfo = ["deadlineID": deadlineID.uuidString]

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            return UNNotificationRequest(
                identifier: Identifier.reminder(deadlineID: deadlineID, offsetMinutes: offsetMinutes),
                content: content,
                trigger: trigger
            )
        }
    }

    /// One reminder per (deadline, offset) that is still in the future, soonest
    /// first so the 64-notification ceiling truncates the least useful ones.
    func plannedReminders(
        deadlines: [DeadlineSnapshot],
        offsets: [Int],
        now: Date = Date()
    ) -> [PlannedReminder] {
        var planned: [PlannedReminder] = []

        for deadline in deadlines where !deadline.isCompleted && deadline.dueDate > now {
            for offset in Set(offsets).sorted() {
                let fireDate = deadline.dueDate.addingTimeInterval(-Double(offset) * 60)
                guard fireDate > now else { continue }
                planned.append(
                    PlannedReminder(
                        deadlineID: deadline.id,
                        offsetMinutes: offset,
                        fireDate: fireDate,
                        title: deadline.title,
                        body: Self.reminderBody(for: deadline, offsetMinutes: offset)
                    )
                )
            }
        }
        return planned.sorted { $0.fireDate < $1.fireDate }
    }

    static func reminderBody(for deadline: DeadlineSnapshot, offsetMinutes: Int) -> String {
        let when = relativeDescription(offsetMinutes: offsetMinutes)
        let time = DateFormatter.deadlineTime.string(from: deadline.dueDate)
        return "\(deadline.courseLabel) · due \(when) at \(time)"
    }

    static func relativeDescription(offsetMinutes: Int) -> String {
        switch offsetMinutes {
        case ..<60:
            return "in \(offsetMinutes) minutes"
        case ..<(24 * 60):
            let hours = offsetMinutes / 60
            return hours == 1 ? "in an hour" : "in \(hours) hours"
        default:
            let days = offsetMinutes / (24 * 60)
            return days == 1 ? "tomorrow" : "in \(days) days"
        }
    }

    // MARK: Digest

    private func digestRequest(settings: AppSettings, calendar: Calendar) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Today's deadlines"
        // The body is filled in at delivery time from the cached store, so it
        // stays accurate without rescheduling every day.
        content.body = "Open Cougar Deadlines to see what's due today."
        content.sound = .default

        var components = DateComponents()
        components.hour = settings.dailyDigestHour
        components.minute = settings.dailyDigestMinute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        return UNNotificationRequest(
            identifier: Identifier.digestPrefix + "daily",
            content: content,
            trigger: trigger
        )
    }

    /// Replaces the standing digest with one that names today's actual items.
    /// Called after each sync, which is the only moment the count is known.
    func refreshDigestBody(
        deadlines: [DeadlineSnapshot],
        settings: AppSettings,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        guard settings.dailyDigestEnabled,
              await authorizationStatus() == .authorized else { return }

        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return }
        let dueToday = deadlines.filter {
            !$0.isCompleted && $0.dueDate >= today && $0.dueDate < tomorrow
        }

        let content = UNMutableNotificationContent()
        content.title = "Today's deadlines"
        content.body = Self.digestBody(for: dueToday)
        content.sound = .default

        var components = DateComponents()
        components.hour = settings.dailyDigestHour
        components.minute = settings.dailyDigestMinute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(
            identifier: Identifier.digestPrefix + "daily",
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    static func digestBody(for deadlines: [DeadlineSnapshot]) -> String {
        guard !deadlines.isEmpty else { return "Nothing due today." }
        let sorted = deadlines.sorted(by: DeadlineSnapshot.chronologically)
        let names = sorted.prefix(3).map(\.title)
        let remainder = sorted.count - names.count

        var body = names.joined(separator: ", ")
        if remainder > 0 {
            body += " and \(remainder) more"
        }
        let noun = sorted.count == 1 ? "deadline" : "deadlines"
        return "\(sorted.count) \(noun): \(body)"
    }
}
