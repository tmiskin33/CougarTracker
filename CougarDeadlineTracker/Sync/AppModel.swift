import Foundation
import Observation
import SwiftData

/// The app's one piece of shared state: what's connected, what's syncing, and
/// what went wrong. Views read it; nothing else owns credentials or sync.
@MainActor
@Observable
final class AppModel {
    let settings: AppSettings
    let credentials: CredentialStore
    let notifications: NotificationScheduler

    private let container: ModelContainer

    private(set) var canvasState: SourceSyncState = .notConfigured
    private(set) var learningSuiteState: SourceSyncState = .notConfigured
    private(set) var isCanvasConnected = false
    private(set) var isLearningSuiteConnected = false
    private(set) var lastSyncStartedAt: Date?

    init(
        container: ModelContainer,
        settings: AppSettings = AppSettings(),
        credentials: CredentialStore = CredentialStore(),
        notifications: NotificationScheduler = NotificationScheduler()
    ) {
        self.container = container
        self.settings = settings
        self.credentials = credentials
        self.notifications = notifications
        refreshConnectionStatus()
    }

    // MARK: Connection status

    /// Both sources are independent: one being connected says nothing about the
    /// other, and either can lapse on its own.
    func refreshConnectionStatus() {
        isCanvasConnected = credentials.canvasToken() != nil
        if let session = credentials.learningSuiteSession() {
            isLearningSuiteConnected = !session.isExpired()
        } else {
            isLearningSuiteConnected = false
        }

        if !isCanvasConnected, canvasState.failure == nil {
            canvasState = .notConfigured
        }
        if !isLearningSuiteConnected, learningSuiteState.failure == nil {
            learningSuiteState = .notConfigured
        }
    }

    var needsAnyLogin: Bool {
        !isCanvasConnected || !isLearningSuiteConnected
    }

    /// True when a stored credential has lapsed, as opposed to never having been
    /// set up — the case that should interrupt the user on launch.
    var hasExpiredSession: Bool {
        canvasState.failure?.requiresReauthentication == true
            || learningSuiteState.failure?.requiresReauthentication == true
            || (credentials.learningSuiteSession()?.isExpired() ?? false)
    }

    // MARK: Credentials

    func saveCanvasToken(_ token: String) throws {
        try credentials.saveCanvasToken(token)
        canvasState = .idle(lastSyncedAt: nil, itemCount: 0)
        refreshConnectionStatus()
    }

    func saveLearningSuiteSession(_ session: LearningSuiteSession) throws {
        try credentials.saveLearningSuiteSession(session)
        learningSuiteState = .idle(lastSyncedAt: nil, itemCount: 0)
        refreshConnectionStatus()
    }

    func disconnect(_ source: DeadlineSource, removingCachedItems: Bool = true) throws {
        switch source {
        case .canvas:
            try credentials.clearCanvasToken()
            canvasState = .notConfigured
        case .learningSuite:
            try credentials.clearLearningSuiteSession()
            learningSuiteState = .notConfigured
        }
        if removingCachedItems {
            try DeadlineStore(context: container.mainContext).deleteAll(from: source)
        }
        refreshConnectionStatus()
    }

    /// Settings › Erase everything. Leaves the app as it was on first launch.
    func eraseAllData() throws {
        try credentials.clearEverything()
        try DeadlineStore(context: container.mainContext).deleteEverything()
        notifications.cancelAll()
        settings.resetToDefaults()
        canvasState = .notConfigured
        learningSuiteState = .notConfigured
        refreshConnectionStatus()
    }

    // MARK: Sync

    func syncAll(now: Date = Date()) async {
        lastSyncStartedAt = now
        async let canvas: Void = syncCanvas(now: now)
        async let learningSuite: Void = syncLearningSuite(now: now)
        _ = await (canvas, learningSuite)
        await rescheduleNotifications(now: now)
    }

    func syncCanvas(now: Date = Date()) async {
        guard let service = CanvasSyncService(settings: settings, credentials: credentials) else {
            canvasState = .failed(.notAuthenticated(.canvas))
            return
        }
        canvasState = .syncing
        do {
            let imported = try await service.fetchDeadlines()
            let result = try DeadlineStore(context: container.mainContext)
                .merge(imported, from: .canvas, now: now)
            canvasState = .idle(lastSyncedAt: now, itemCount: result.touched)
        } catch let failure as SyncFailure {
            canvasState = .failed(failure)
            if failure.requiresReauthentication { refreshConnectionStatus() }
        } catch {
            canvasState = .failed(
                SyncFailure(
                    kind: .other,
                    message: "Canvas sync failed.",
                    underlyingDescription: error.localizedDescription
                )
            )
        }
    }

    func syncLearningSuite(now: Date = Date()) async {
        guard let service = LearningSuiteSyncService(settings: settings, credentials: credentials) else {
            learningSuiteState = .failed(.notAuthenticated(.learningSuite))
            return
        }
        learningSuiteState = .syncing
        do {
            let imported = try await service.fetchDeadlines(now: now)
            let result = try DeadlineStore(context: container.mainContext)
                .merge(imported, from: .learningSuite, now: now)
            learningSuiteState = .idle(lastSyncedAt: now, itemCount: result.touched)
        } catch let failure as SyncFailure {
            learningSuiteState = .failed(failure)
            if failure.requiresReauthentication {
                // The cookie is dead; drop it so the UI prompts a fresh WebView login.
                try? credentials.clearLearningSuiteSession()
                refreshConnectionStatus()
            }
        } catch {
            learningSuiteState = .failed(
                SyncFailure(
                    kind: .other,
                    message: "Learning Suite sync failed.",
                    underlyingDescription: error.localizedDescription
                )
            )
        }
    }

    // MARK: Notifications

    func rescheduleNotifications(now: Date = Date()) async {
        let snapshots = (try? container.mainContext.fetch(FetchDescriptor<Deadline>()))?
            .map(\.snapshot) ?? []
        await notifications.reschedule(deadlines: snapshots, settings: settings, now: now)
        await notifications.refreshDigestBody(deadlines: snapshots, settings: settings, now: now)
    }

    func requestNotificationPermission() async {
        settings.hasAskedForNotifications = true
        _ = await notifications.requestAuthorization()
        await rescheduleNotifications()
    }

    // MARK: Completion

    func setCompleted(_ isCompleted: Bool, on deadline: Deadline) {
        try? DeadlineStore(context: container.mainContext).setCompleted(isCompleted, on: deadline)
        Task { await rescheduleNotifications() }
    }
}
