import Foundation

/// Fetch + parse for Learning Suite, kept behind the same shape as the Canvas
/// service so the sync coordinator treats both sources identically.
struct LearningSuiteSyncService {
    var client: LearningSuiteClient
    var parser: any LearningSuiteParsing
    var primaryPath: String
    /// Tried in order if the configured path 404s. Learning Suite's routes are
    /// undocumented, so a wrong guess should cost a retry, not the whole sync.
    var fallbackPaths: [String]

    static let defaultFallbackPaths = [
        "/student/assignments",
        "/student",
        "/"
    ]

    init?(settings: AppSettings, credentials: CredentialStore, parser: (any LearningSuiteParsing)? = nil) {
        guard let session = credentials.learningSuiteSession() else { return nil }
        let path = settings.learningSuiteAssignmentsPath.nilIfBlank ?? AppSettings.defaultLearningSuitePath

        self.client = LearningSuiteClient(session: session)
        let fallbackParser: any LearningSuiteParsing =
            LearningSuiteHeuristicParser(config: .loadBundled())

        self.parser = parser ?? fallbackParser
        self.primaryPath = path
        self.fallbackPaths = Self.defaultFallbackPaths.filter { $0 != path }
    }

    init(
        client: LearningSuiteClient,
        parser: any LearningSuiteParsing = LearningSuiteHeuristicParser(),
        primaryPath: String = AppSettings.defaultLearningSuitePath,
        fallbackPaths: [String] = LearningSuiteSyncService.defaultFallbackPaths
    ) {
        self.client = client
        self.parser = parser
        self.primaryPath = primaryPath
        self.fallbackPaths = fallbackPaths
    }

    func fetchDeadlines(now: Date = Date()) async throws -> [ImportedDeadline] {
        var lastFailure: SyncFailure?

        for path in [primaryPath] + fallbackPaths {
            do {
                let html = try await client.fetchHTML(path: path)
                let context = LearningSuiteParseContext(now: now, baseURL: client.baseURL)
                return try parser.parse(html: html, context: context)
            } catch let failure as SyncFailure {
                // An expired session will not improve on the next path.
                if failure.requiresReauthentication { throw failure }
                lastFailure = failure
                continue
            }
        }

        throw lastFailure ?? SyncFailure.learningSuiteMarkupChanged
    }
}
