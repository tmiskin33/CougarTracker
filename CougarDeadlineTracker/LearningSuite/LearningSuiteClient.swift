import Foundation

/// Fetches Learning Suite pages using the cookies captured by the WebView login.
///
/// It only ever performs GETs of pages the signed-in user can already open in a
/// browser, at the pace of a manual refresh.
struct LearningSuiteClient {
    static let defaultHost = "learningsuite.byu.edu"

    var baseURL: URL
    var session: LearningSuiteSession

    init(baseURL: URL = URL(string: "https://\(LearningSuiteClient.defaultHost)")!, session: LearningSuiteSession) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Hosts that mean we were bounced to sign in rather than served a page.
    static let loginHostFragments = ["cas.byu.edu", "auth.byu.edu", "duosecurity.com", "login.byu.edu"]

    func fetchHTML(path: String) async throws -> String {
        guard !session.isExpired() else {
            throw SyncFailure.sessionExpired(.learningSuite)
        }
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw SyncFailure(kind: .other, message: "Couldn't build a Learning Suite URL for \(path).")
        }

        let urlSession = URLSession(configuration: configuration())
        defer { urlSession.finishTasksAndInvalidate() }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch let error as URLError {
            throw SyncFailure(
                kind: .network,
                message: "Couldn't reach Learning Suite. Check your connection and try again.",
                underlyingDescription: error.localizedDescription
            )
        }

        guard let http = response as? HTTPURLResponse else {
            throw SyncFailure(kind: .other, message: "Learning Suite returned an unexpected response.")
        }

        // A lapsed scraped session shows up as a redirect to CAS with a 200, not
        // as a 401, so the landing URL is the signal.
        if let finalHost = http.url?.host?.lowercased(),
           Self.loginHostFragments.contains(where: { finalHost.contains($0) }) {
            throw SyncFailure.sessionExpired(.learningSuite)
        }

        switch http.statusCode {
        case 200...299:
            guard let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
                throw SyncFailure.learningSuiteMarkupChanged
            }
            return html
        case 401, 403:
            throw SyncFailure.sessionExpired(.learningSuite)
        case 404:
            throw SyncFailure(
                kind: .parsingChanged,
                message: """
                Learning Suite has no page at \(path). Its layout may have changed — \
                you can point the app at a different path in Settings › Learning Suite.
                """
            )
        default:
            throw SyncFailure(
                kind: .server(status: http.statusCode),
                message: "Learning Suite returned an error (\(http.statusCode)). Try again shortly."
            )
        }
    }

    private func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        let storage = HTTPCookieStorage()
        for cookie in session.httpCookies {
            storage.setCookie(cookie)
        }
        configuration.httpCookieStorage = storage
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }
}
