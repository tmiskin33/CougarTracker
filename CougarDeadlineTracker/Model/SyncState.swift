import Foundation

/// Outcome of the most recent sync for one source, surfaced in the UI so a
/// failure is visible rather than silent.
enum SourceSyncState: Equatable {
    case notConfigured
    case idle(lastSyncedAt: Date?, itemCount: Int)
    case syncing
    case failed(SyncFailure)

    var isSyncing: Bool {
        if case .syncing = self { return true }
        return false
    }

    var failure: SyncFailure? {
        if case .failed(let failure) = self { return failure }
        return nil
    }
}

/// A sync failure the user can act on. Every case says what to do next, because
/// "sync failed" on its own leaves nobody anywhere.
struct SyncFailure: Equatable, Error {
    enum Kind: Equatable {
        case notAuthenticated
        case sessionExpired
        case network
        case server(status: Int)
        /// The page loaded but nothing recognisable came out of it — the single
        /// most likely symptom of Learning Suite changing its markup.
        case parsingChanged
        case other
    }

    var kind: Kind
    var message: String
    var underlyingDescription: String? = nil

    var requiresReauthentication: Bool {
        kind == .notAuthenticated || kind == .sessionExpired
    }

    var symbolName: String {
        switch kind {
        case .notAuthenticated, .sessionExpired: return "person.badge.key"
        case .network: return "wifi.exclamationmark"
        case .server: return "exclamationmark.icloud"
        case .parsingChanged: return "questionmark.square.dashed"
        case .other: return "exclamationmark.triangle"
        }
    }

    static func sessionExpired(_ source: DeadlineSource) -> SyncFailure {
        SyncFailure(
            kind: .sessionExpired,
            message: "Your \(source.displayName) session has expired. Sign in again to keep syncing."
        )
    }

    static func notAuthenticated(_ source: DeadlineSource) -> SyncFailure {
        SyncFailure(
            kind: .notAuthenticated,
            message: "Connect \(source.displayName) to start syncing deadlines."
        )
    }

    static let learningSuiteMarkupChanged = SyncFailure(
        kind: .parsingChanged,
        message: """
        Learning Suite loaded, but no assignments could be read from it. \
        The site's layout may have changed, or there may be nothing due. \
        Open Settings › Learning Suite to re-check the connection.
        """
    )
}
