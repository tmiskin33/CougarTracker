import Foundation

/// Turns Canvas credentials into a list of deadlines. Knows nothing about
/// SwiftData or SwiftUI, so it can be exercised straight from a test.
struct CanvasSyncService {
    var host: String
    var token: String
    var session: URLSession = .shared

    init?(settings: AppSettings, credentials: CredentialStore, session: URLSession = .shared) {
        guard let token = credentials.canvasToken() else { return nil }
        self.host = settings.canvasHost.trimmed
        self.token = token
        self.session = session
    }

    init(host: String, token: String, session: URLSession = .shared) {
        self.host = host
        self.token = token
        self.session = session
    }

    func fetchDeadlines() async throws -> [ImportedDeadline] {
        let client = CanvasClient(host: host, token: token, session: session)

        // The to-do feed is the backbone: one call, every course, and it is what
        // Canvas itself considers outstanding.
        let todo = try await client.fetchTodo()
        var results = CanvasAPI.deadlines(from: todo, host: host)

        // Per-course assignments add course codes, descriptions, and items the
        // to-do feed omits (anything already submitted but not yet due). If this
        // half fails we still return the to-do results rather than nothing.
        if let perCourse = try? await fetchPerCourseDeadlines(using: client) {
            results = CanvasAPI.merge(results, perCourse)
        } else {
            results = CanvasAPI.merge(results)
        }

        return results.sorted { $0.dueDate < $1.dueDate }
    }

    private func fetchPerCourseDeadlines(using client: CanvasClient) async throws -> [ImportedDeadline] {
        let courses = try await client.fetchActiveCourses()
        let host = self.host

        return try await withThrowingTaskGroup(of: [ImportedDeadline].self) { group in
            var collected: [ImportedDeadline] = []
            let maxConcurrent = 4
            var iterator = courses.makeIterator()

            func addNext() {
                guard let course = iterator.next() else { return }
                group.addTask {
                    // One course failing (a restricted section, say) must not sink
                    // the whole pass.
                    guard let assignments = try? await client.fetchUpcomingAssignments(courseID: course.id) else {
                        return []
                    }
                    return CanvasAPI.deadlines(
                        from: assignments,
                        courseName: course.name ?? "Canvas course",
                        courseCode: course.courseCode ?? "",
                        host: host
                    )
                }
            }

            for _ in 0..<min(maxConcurrent, courses.count) { addNext() }
            while let batch = try await group.next() {
                collected.append(contentsOf: batch)
                addNext()
            }
            return collected
        }
    }

    /// Used by the setup screen to check a token before saving it.
    static func verify(host: String, token: String, session: URLSession = .shared) async throws -> String {
        try await CanvasClient(host: host, token: token, session: session).verifyToken()
    }
}
