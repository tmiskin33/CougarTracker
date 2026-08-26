import Foundation

/// A captured Learning Suite web session: the cookies the WebView login produced,
/// plus when we expect them to lapse.
///
/// Only the session cookies are kept. The NetID password is typed into BYU's own
/// login page inside the WebView and never passes through this app.
struct LearningSuiteSession: Codable, Equatable {
    struct Cookie: Codable, Equatable {
        var name: String
        var value: String
        var domain: String
        var path: String
        var expiresDate: Date?
        var isSecure: Bool

        var httpCookie: HTTPCookie? {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: value,
                .domain: domain,
                .path: path.isEmpty ? "/" : path
            ]
            if let expiresDate { properties[.expires] = expiresDate }
            if isSecure { properties[.secure] = "TRUE" }
            return HTTPCookie(properties: properties)
        }

        init(name: String, value: String, domain: String, path: String, expiresDate: Date?, isSecure: Bool) {
            self.name = name
            self.value = value
            self.domain = domain
            self.path = path
            self.expiresDate = expiresDate
            self.isSecure = isSecure
        }

        init(_ cookie: HTTPCookie) {
            self.init(
                name: cookie.name,
                value: cookie.value,
                domain: cookie.domain,
                path: cookie.path,
                expiresDate: cookie.expiresDate,
                isSecure: cookie.isSecure
            )
        }
    }

    var cookies: [Cookie]
    var capturedAt: Date
    /// Our own conservative expiry. Session cookies often carry no expiry at all,
    /// so we assume one rather than letting a dead session look healthy.
    var assumedExpiry: Date

    static let assumedLifetime: TimeInterval = 60 * 60 * 8

    init(cookies: [HTTPCookie], capturedAt: Date = Date()) {
        self.cookies = cookies.map(Cookie.init)
        self.capturedAt = capturedAt
        let earliestServerExpiry = cookies.compactMap(\.expiresDate).min()
        let assumed = capturedAt.addingTimeInterval(Self.assumedLifetime)
        self.assumedExpiry = earliestServerExpiry.map { min($0, assumed) } ?? assumed
    }

    func isExpired(asOf now: Date = Date()) -> Bool {
        now >= assumedExpiry
    }

    var httpCookies: [HTTPCookie] {
        cookies.compactMap(\.httpCookie)
    }
}

/// Reads and writes both sources' credentials. The rest of the app asks this
/// object questions like "is Canvas connected" rather than touching the keychain.
struct CredentialStore {
    private let keychain: Keychain

    init(keychain: Keychain = Keychain()) {
        self.keychain = keychain
    }

    // MARK: Canvas

    func canvasToken() -> String? {
        (try? keychain.string(for: Keychain.Account.canvasToken))?.nilIfBlank
    }

    func saveCanvasToken(_ token: String) throws {
        try keychain.setString(token.trimmed, for: Keychain.Account.canvasToken)
    }

    func clearCanvasToken() throws {
        try keychain.remove(Keychain.Account.canvasToken)
    }

    // MARK: Learning Suite

    func learningSuiteSession() -> LearningSuiteSession? {
        try? keychain.value(LearningSuiteSession.self, for: Keychain.Account.learningSuiteSession)
    }

    func saveLearningSuiteSession(_ session: LearningSuiteSession) throws {
        try keychain.setValue(session, for: Keychain.Account.learningSuiteSession)
    }

    func clearLearningSuiteSession() throws {
        try keychain.remove(Keychain.Account.learningSuiteSession)
    }

    func clearEverything() throws {
        try clearCanvasToken()
        try clearLearningSuiteSession()
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var nilIfBlank: String? {
        let trimmed = self.trimmed
        return trimmed.isEmpty ? nil : trimmed
    }
}
