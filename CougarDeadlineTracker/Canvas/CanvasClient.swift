import Foundation

/// Talks to the Canvas REST API with a personal access token.
///
/// Two calls make up a sync:
///   1. `/users/self/todo` — everything still to hand in, across all courses
///   2. `/courses/:id/assignments?bucket=upcoming` — richer per-course detail
///
/// The to-do feed alone is enough to show something useful, so a failure in the
/// per-course pass degrades rather than sinking the whole sync.
actor CanvasClient {
    private let session: URLSession
    private let host: String
    private let token: String

    init(host: String, token: String, session: URLSession = .shared) {
        self.host = host
        self.token = token
        self.session = session
    }

    /// Confirms a pasted token actually works, and returns the account name so
    /// setup can show the user who they just connected as.
    func verifyToken() async throws -> String {
        let data = try await get(path: "/api/v1/users/self")
        struct Profile: Decodable {
            var name: String?
            var shortName: String?
            enum CodingKeys: String, CodingKey {
                case name
                case shortName = "short_name"
            }
        }
        let profile = try CanvasAPI.decoder().decode(Profile.self, from: data)
        return profile.shortName?.nilIfBlank ?? profile.name?.nilIfBlank ?? "your Canvas account"
    }

    func fetchTodo() async throws -> [CanvasAPI.TodoItem] {
        let pages = try await getPaged(path: "/api/v1/users/self/todo", query: [
            URLQueryItem(name: "per_page", value: "100")
        ])
        return try pages.flatMap { try CanvasAPI.decodeTodo($0) }
    }

    func fetchActiveCourses() async throws -> [CanvasAPI.Course] {
        let pages = try await getPaged(path: "/api/v1/courses", query: [
            URLQueryItem(name: "enrollment_state", value: "active"),
            URLQueryItem(name: "enrollment_type", value: "student"),
            URLQueryItem(name: "state[]", value: "available"),
            URLQueryItem(name: "per_page", value: "100")
        ])
        return try pages.flatMap { try CanvasAPI.decodeCourses($0) }.filter(\.isAccessible)
    }

    func fetchUpcomingAssignments(courseID: Int) async throws -> [CanvasAPI.Assignment] {
        let pages = try await getPaged(path: "/api/v1/courses/\(courseID)/assignments", query: [
            URLQueryItem(name: "bucket", value: "upcoming"),
            URLQueryItem(name: "include[]", value: "submission"),
            URLQueryItem(name: "order_by", value: "due_at"),
            URLQueryItem(name: "per_page", value: "100")
        ])
        return try pages.flatMap { try CanvasAPI.decodeAssignments($0) }
    }

    // MARK: Transport

    private func get(path: String, query: [URLQueryItem] = []) async throws -> Data {
        guard let url = url(path: path, query: query) else {
            throw SyncFailure(kind: .other, message: "Couldn't build a Canvas URL for \(path).")
        }
        return try await perform(request(for: url)).data
    }

    /// Follows Canvas's `Link: <...>; rel="next"` pagination to the end.
    private func getPaged(path: String, query: [URLQueryItem] = []) async throws -> [Data] {
        guard var next = url(path: path, query: query) else {
            throw SyncFailure(kind: .other, message: "Couldn't build a Canvas URL for \(path).")
        }
        var pages: [Data] = []
        var guardrail = 0

        while guardrail < 20 {
            guardrail += 1
            let result = try await perform(request(for: next))
            pages.append(result.data)
            guard let link = result.response.value(forHTTPHeaderField: "Link"),
                  let following = CanvasLinkHeader.nextURL(in: link) else {
                break
            }
            next = following
        }
        return pages
    }

    private func url(path: String, query: [URLQueryItem]) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = query.isEmpty ? nil : query
        return components.url
    }

    private func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Plain JSON on purpose: the string-ids variant would turn every id into
        // a String and break decoding.
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw SyncFailure(
                kind: .network,
                message: "Couldn't reach Canvas. Check your connection and try again.",
                underlyingDescription: error.localizedDescription
            )
        }

        guard let http = response as? HTTPURLResponse else {
            throw SyncFailure(kind: .other, message: "Canvas returned an unexpected response.")
        }

        switch http.statusCode {
        case 200...299:
            return (data, http)
        case 401:
            throw SyncFailure(
                kind: .sessionExpired,
                message: "Canvas rejected your access token. Generate a new one and paste it in Settings."
            )
        case 403:
            // Canvas uses 403 both for permission problems and for throttling.
            let body = String(data: data, encoding: .utf8) ?? ""
            let throttled = body.localizedCaseInsensitiveContains("rate limit")
            throw SyncFailure(
                kind: throttled ? .server(status: 403) : .sessionExpired,
                message: throttled
                    ? "Canvas is rate limiting this account. Try again in a few minutes."
                    : "Canvas denied that request. Your token may not have the right permissions."
            )
        default:
            throw SyncFailure(
                kind: .server(status: http.statusCode),
                message: "Canvas returned an error (\(http.statusCode)). Try again shortly."
            )
        }
    }
}

/// Parses the `Link` header Canvas uses for pagination.
enum CanvasLinkHeader {
    static func nextURL(in header: String) -> URL? {
        for part in header.split(separator: ",") {
            let segments = part.split(separator: ";")
            guard let urlSegment = segments.first else { continue }
            let relations = segments.dropFirst().map { $0.trimmed.lowercased() }
            guard relations.contains(where: { $0 == "rel=\"next\"" || $0 == "rel=next" }) else { continue }
            let trimmed = urlSegment.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            return URL(string: trimmed)
        }
        return nil
    }
}

private extension Substring {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
