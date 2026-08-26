import XCTest
@testable import CougarDeadlineTracker

/// Canvas response parsing, against saved API samples.
final class CanvasParsingTests: XCTestCase {

    func testDecodesTodoFeed() throws {
        let items = try CanvasAPI.decodeTodo(Fixture.data("canvas_todo.json"))
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items.first?.contextName, "MATH 113: Calculus 2")
        XCTAssertEqual(items.first?.assignment?.id, 990101)
    }

    func testTodoMappingKeepsOnlyStudentItemsWithDueDates() throws {
        let items = try CanvasAPI.decodeTodo(Fixture.data("canvas_todo.json"))
        let deadlines = CanvasAPI.deadlines(from: items, host: "byu.instructure.com")

        // The "grading" entry and the one with no due date are both dropped.
        XCTAssertEqual(deadlines.count, 2)
        XCTAssertFalse(deadlines.contains { $0.title.contains("Grading queue") })
        XCTAssertFalse(deadlines.contains { $0.title.contains("no due date") })
    }

    func testTodoMappingCarriesCourseTitleAndType() throws {
        let items = try CanvasAPI.decodeTodo(Fixture.data("canvas_todo.json"))
        let deadlines = CanvasAPI.deadlines(from: items, host: "byu.instructure.com")

        let homework = try XCTUnwrap(deadlines.first { $0.sourceItemID == "assignment-990101" })
        XCTAssertEqual(homework.source, .canvas)
        XCTAssertEqual(homework.courseName, "MATH 113: Calculus 2")
        XCTAssertEqual(homework.title, "Section 7.4 Homework")
        XCTAssertEqual(homework.type, .assignment)
        XCTAssertEqual(homework.isCompleted, false)
        XCTAssertEqual(
            homework.url?.absoluteString,
            "https://byu.instructure.com/courses/21001/assignments/990101"
        )
        // The HTML description is flattened to text, entities and all.
        XCTAssertEqual(homework.details, "Complete problems 1–25 odd.")
    }

    func testQuizNamedLikeAnExamIsTypedAsAnExam() throws {
        let items = try CanvasAPI.decodeTodo(Fixture.data("canvas_todo.json"))
        let deadlines = CanvasAPI.deadlines(from: items, host: "byu.instructure.com")

        let midterm = try XCTUnwrap(deadlines.first { $0.sourceItemID == "assignment-990202" })
        XCTAssertEqual(midterm.type, .exam)
    }

    func testDecodesCoursesAndSkipsRestrictedOnes() throws {
        let courses = try CanvasAPI.decodeCourses(Fixture.data("canvas_courses.json"))
        XCTAssertEqual(courses.count, 3)
        XCTAssertEqual(courses.filter(\.isAccessible).map(\.id), [21001, 21002])
    }

    func testAssignmentMappingReadsSubmissionState() throws {
        let assignments = try CanvasAPI.decodeAssignments(Fixture.data("canvas_assignments.json"))
        let deadlines = CanvasAPI.deadlines(
            from: assignments,
            courseName: "Calculus 2",
            courseCode: "MATH 113",
            host: "byu.instructure.com"
        )

        XCTAssertEqual(deadlines.count, 3, "the assignment with no due date is dropped")

        let submitted = try XCTUnwrap(deadlines.first { $0.sourceItemID == "assignment-990105" })
        XCTAssertEqual(submitted.isCompleted, true)

        let outstanding = try XCTUnwrap(deadlines.first { $0.sourceItemID == "assignment-990101" })
        XCTAssertEqual(outstanding.isCompleted, false)
        XCTAssertEqual(outstanding.courseCode, "MATH 113")
    }

    func testDiscussionSubmissionTypeIsTypedAsDiscussion() throws {
        let assignments = try CanvasAPI.decodeAssignments(Fixture.data("canvas_assignments.json"))
        let deadlines = CanvasAPI.deadlines(
            from: assignments,
            courseName: "Calculus 2",
            courseCode: "MATH 113",
            host: "byu.instructure.com"
        )
        let discussion = try XCTUnwrap(deadlines.first { $0.sourceItemID == "assignment-990106" })
        XCTAssertEqual(discussion.type, .discussion)
    }

    func testAssignmentWithoutLinkFallsBackToAConstructedURL() throws {
        let assignments = try CanvasAPI.decodeAssignments(Fixture.data("canvas_assignments.json"))
        let deadlines = CanvasAPI.deadlines(
            from: assignments,
            courseName: "Calculus 2",
            courseCode: "MATH 113",
            host: "byu.instructure.com"
        )
        let discussion = try XCTUnwrap(deadlines.first { $0.sourceItemID == "assignment-990106" })
        XCTAssertEqual(
            discussion.url?.absoluteString,
            "https://byu.instructure.com/courses/21001/assignments/990106"
        )
    }

    func testFractionalSecondTimestampsDecode() throws {
        let assignments = try CanvasAPI.decodeAssignments(Fixture.data("canvas_assignments.json"))
        let withFraction = try XCTUnwrap(assignments.first { $0.id == 990105 })
        XCTAssertNotNil(withFraction.dueAt)
    }

    func testMergePrefersTheRicherCourseLabel() throws {
        let todoItems = try CanvasAPI.decodeTodo(Fixture.data("canvas_todo.json"))
        let fromTodo = CanvasAPI.deadlines(from: todoItems, host: "byu.instructure.com")

        let assignments = try CanvasAPI.decodeAssignments(Fixture.data("canvas_assignments.json"))
        let fromCourse = CanvasAPI.deadlines(
            from: assignments,
            courseName: "Calculus 2",
            courseCode: "MATH 113",
            host: "byu.instructure.com"
        )

        let merged = CanvasAPI.merge(fromTodo, fromCourse)
        let homework = try XCTUnwrap(merged.first { $0.sourceItemID == "assignment-990101" })

        XCTAssertEqual(homework.courseCode, "MATH 113", "the code comes from the per-course call")
        XCTAssertEqual(homework.courseName, "MATH 113: Calculus 2", "the to-do feed's fuller name is kept")
        XCTAssertEqual(
            merged.filter { $0.sourceItemID == "assignment-990101" }.count,
            1,
            "the same assignment from both feeds must not duplicate"
        )
    }

    func testLinkHeaderPagination() {
        let header = """
        <https://byu.instructure.com/api/v1/courses?page=1>; rel="current",\
        <https://byu.instructure.com/api/v1/courses?page=2>; rel="next",\
        <https://byu.instructure.com/api/v1/courses?page=1>; rel="first"
        """
        XCTAssertEqual(
            CanvasLinkHeader.nextURL(in: header)?.absoluteString,
            "https://byu.instructure.com/api/v1/courses?page=2"
        )
    }

    func testLinkHeaderWithoutNextReturnsNil() {
        let header = "<https://byu.instructure.com/api/v1/courses?page=3>; rel=\"last\""
        XCTAssertNil(CanvasLinkHeader.nextURL(in: header))
    }
}
