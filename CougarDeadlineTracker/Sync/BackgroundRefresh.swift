import BackgroundTasks
import Foundation

/// Opportunistic background sync.
///
/// iOS decides if and when this runs, based on how often the app is used and the
/// state of the device — it is a "sometimes, eventually" mechanism, not a push
/// channel. Canvas has no webhook that could reach a phone directly, so the
/// honest ceiling is: refreshed in the background when iOS allows, and always
/// refreshed when the app opens or is pulled down.
enum BackgroundRefresh {
    static let taskIdentifier = "com.cougardeadlines.refresh"

    /// Earliest the next attempt should be considered. iOS will usually run it
    /// later than this, and may skip it entirely.
    static let minimumInterval: TimeInterval = 60 * 60 * 2

    /// Called once at launch, before the app finishes starting up.
    static func register(model: @escaping @MainActor () -> AppModel?) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask, model: model)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Submission fails on Simulator and when the user has switched off
            // Background App Refresh. Neither is worth surfacing.
        }
    }

    private static func handle(_ task: BGAppRefreshTask, model: @escaping @MainActor () -> AppModel?) {
        // Always queue the next one first: if this run is cut short, there is
        // still a future attempt on the books.
        schedule()

        let work = Task { @MainActor in
            guard let model = model() else {
                task.setTaskCompleted(success: false)
                return
            }
            await model.syncAll()
            let failed = model.canvasState.failure != nil && model.learningSuiteState.failure != nil
            task.setTaskCompleted(success: !failed)
        }

        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
