import Foundation
import Observation

/// Non-secret user preferences, backed by UserDefaults. Secrets never come here.
///
/// Each property is written out longhand — `access` on read, `withMutation` on
/// write — rather than relying on `didSet`. That is what the `@Observable` macro
/// generates for a plain stored property, and doing it by hand is what lets each
/// setter also write through to UserDefaults while staying observable.
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self._canvasHost = defaults.string(forKey: Key.canvasHost) ?? AppSettings.defaultCanvasHost
        self._learningSuiteAssignmentsPath = defaults.string(forKey: Key.learningSuitePath)
            ?? AppSettings.defaultLearningSuitePath
        self._reminderOffsets = (defaults.array(forKey: Key.reminderOffsets) as? [Int])
            ?? AppSettings.defaultReminderOffsets
        self._dailyDigestEnabled = defaults.object(forKey: Key.digestEnabled) as? Bool ?? true
        self._dailyDigestHour = defaults.object(forKey: Key.digestHour) as? Int ?? 7
        self._dailyDigestMinute = defaults.object(forKey: Key.digestMinute) as? Int ?? 0
        self._showsCompleted = defaults.object(forKey: Key.showsCompleted) as? Bool ?? false
        self._hasCompletedOnboarding = defaults.bool(forKey: Key.onboarded)
        self._hasAskedForNotifications = defaults.bool(forKey: Key.askedNotifications)
    }

    static let defaultCanvasHost = "byu.instructure.com"

    /// Best guess at the authenticated assignments page. Editable in Settings
    /// because Learning Suite's routes are not documented and may move.
    static let defaultLearningSuitePath = "/student/assignments"

    /// A day out and three hours out.
    static let defaultReminderOffsets = [24 * 60, 3 * 60]

    // MARK: Stored values

    @ObservationIgnored private var _canvasHost: String
    @ObservationIgnored private var _learningSuiteAssignmentsPath: String
    @ObservationIgnored private var _reminderOffsets: [Int]
    @ObservationIgnored private var _dailyDigestEnabled: Bool
    @ObservationIgnored private var _dailyDigestHour: Int
    @ObservationIgnored private var _dailyDigestMinute: Int
    @ObservationIgnored private var _showsCompleted: Bool
    @ObservationIgnored private var _hasCompletedOnboarding: Bool
    @ObservationIgnored private var _hasAskedForNotifications: Bool

    var canvasHost: String {
        get { access(keyPath: \.canvasHost); return _canvasHost }
        set { store(newValue, into: &_canvasHost, key: Key.canvasHost, keyPath: \.canvasHost) }
    }

    var learningSuiteAssignmentsPath: String {
        get { access(keyPath: \.learningSuiteAssignmentsPath); return _learningSuiteAssignmentsPath }
        set {
            store(
                newValue,
                into: &_learningSuiteAssignmentsPath,
                key: Key.learningSuitePath,
                keyPath: \.learningSuiteAssignmentsPath
            )
        }
    }

    /// How long before a due date to fire a reminder, in minutes.
    var reminderOffsets: [Int] {
        get { access(keyPath: \.reminderOffsets); return _reminderOffsets }
        set { store(newValue, into: &_reminderOffsets, key: Key.reminderOffsets, keyPath: \.reminderOffsets) }
    }

    var dailyDigestEnabled: Bool {
        get { access(keyPath: \.dailyDigestEnabled); return _dailyDigestEnabled }
        set { store(newValue, into: &_dailyDigestEnabled, key: Key.digestEnabled, keyPath: \.dailyDigestEnabled) }
    }

    var dailyDigestHour: Int {
        get { access(keyPath: \.dailyDigestHour); return _dailyDigestHour }
        set { store(newValue, into: &_dailyDigestHour, key: Key.digestHour, keyPath: \.dailyDigestHour) }
    }

    var dailyDigestMinute: Int {
        get { access(keyPath: \.dailyDigestMinute); return _dailyDigestMinute }
        set { store(newValue, into: &_dailyDigestMinute, key: Key.digestMinute, keyPath: \.dailyDigestMinute) }
    }

    var showsCompleted: Bool {
        get { access(keyPath: \.showsCompleted); return _showsCompleted }
        set { store(newValue, into: &_showsCompleted, key: Key.showsCompleted, keyPath: \.showsCompleted) }
    }

    var hasCompletedOnboarding: Bool {
        get { access(keyPath: \.hasCompletedOnboarding); return _hasCompletedOnboarding }
        set { store(newValue, into: &_hasCompletedOnboarding, key: Key.onboarded, keyPath: \.hasCompletedOnboarding) }
    }

    var hasAskedForNotifications: Bool {
        get { access(keyPath: \.hasAskedForNotifications); return _hasAskedForNotifications }
        set {
            store(
                newValue,
                into: &_hasAskedForNotifications,
                key: Key.askedNotifications,
                keyPath: \.hasAskedForNotifications
            )
        }
    }

    private func store<Value>(
        _ newValue: Value,
        into storage: inout Value,
        key: String,
        keyPath: KeyPath<AppSettings, Value>
    ) {
        withMutation(keyPath: keyPath) {
            storage = newValue
            defaults.set(newValue, forKey: key)
        }
    }

    // MARK: Derived

    var canvasBaseURL: URL? {
        URL(string: "https://\(canvasHost.trimmed)")
    }

    var dailyDigestTime: DateComponents {
        DateComponents(hour: dailyDigestHour, minute: dailyDigestMinute)
    }

    func setDailyDigestTime(_ date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        dailyDigestHour = components.hour ?? 7
        dailyDigestMinute = components.minute ?? 0
    }

    func resetToDefaults() {
        canvasHost = AppSettings.defaultCanvasHost
        learningSuiteAssignmentsPath = AppSettings.defaultLearningSuitePath
        reminderOffsets = AppSettings.defaultReminderOffsets
        dailyDigestEnabled = true
        dailyDigestHour = 7
        dailyDigestMinute = 0
        showsCompleted = false
        hasCompletedOnboarding = false
        hasAskedForNotifications = false
    }

    /// The offsets the settings screen offers, labelled.
    static let reminderChoices: [ReminderChoice] = [
        ReminderChoice(minutes: 7 * 24 * 60, label: "1 week before"),
        ReminderChoice(minutes: 3 * 24 * 60, label: "3 days before"),
        ReminderChoice(minutes: 24 * 60, label: "1 day before"),
        ReminderChoice(minutes: 12 * 60, label: "12 hours before"),
        ReminderChoice(minutes: 3 * 60, label: "3 hours before"),
        ReminderChoice(minutes: 60, label: "1 hour before"),
        ReminderChoice(minutes: 30, label: "30 minutes before")
    ]

    private enum Key {
        static let canvasHost = "settings.canvasHost"
        static let learningSuitePath = "settings.learningSuitePath"
        static let reminderOffsets = "settings.reminderOffsets"
        static let digestEnabled = "settings.digestEnabled"
        static let digestHour = "settings.digestHour"
        static let digestMinute = "settings.digestMinute"
        static let showsCompleted = "settings.showsCompleted"
        static let onboarded = "settings.hasCompletedOnboarding"
        static let askedNotifications = "settings.hasAskedForNotifications"
    }
}

/// One selectable reminder offset in Settings.
struct ReminderChoice: Identifiable, Equatable {
    var minutes: Int
    var label: String

    var id: Int { minutes }
}
