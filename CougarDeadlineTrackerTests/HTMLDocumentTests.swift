import XCTest
@testable import CougarDeadlineTracker

/// The bundled HTML parser. It has to survive the markup real pages contain,
/// not the markup a validator would accept.
final class HTMLDocumentTests: XCTestCase {

    func testExtractsTextAndCollapsesWhitespace() {
        let document = HTMLDocument.parse("<p>Hello\n   <b>there</b>  friend</p>")
        XCTAssertEqual(document.text, "Hello there friend")
    }

    func testDecodesEntities() {
        let document = HTMLDocument.parse("<p>1&ndash;25 &amp; more &#39;quoted&#x27;</p>")
        XCTAssertEqual(document.text, "1–25 & more 'quoted'")
    }

    func testReadsAttributes() throws {
        let document = HTMLDocument.parse(#"<a href="/x/1" class="link primary" data-id=7>Go</a>"#)
        let anchor = try XCTUnwrap(document.firstElement(tag: "a"))
        XCTAssertEqual(anchor.attribute("href"), "/x/1")
        XCTAssertEqual(anchor.attribute("data-id"), "7", "unquoted attribute values are read")
        XCTAssertTrue(anchor.hasClass("primary"))
        XCTAssertEqual(anchor.text, "Go")
    }

    func testHandlesUnclosedTags() {
        let document = HTMLDocument.parse("<ul><li>One<li>Two<li>Three</ul>")
        XCTAssertEqual(document.elements(tag: "li").count, 3)
        XCTAssertEqual(document.elements(tag: "li").map(\.text), ["One", "Two", "Three"])
    }

    func testIgnoresScriptContent() {
        let document = HTMLDocument.parse("<div>Real<script>var x = '<td>fake</td>';</script></div>")
        XCTAssertEqual(document.text, "Real")
        XCTAssertTrue(document.elements(tag: "td").isEmpty)
    }

    func testIgnoresCommentsAndDoctype() {
        let document = HTMLDocument.parse("<!doctype html><!-- <p>hidden</p> --><p>shown</p>")
        XCTAssertEqual(document.text, "shown")
        XCTAssertEqual(document.elements(tag: "p").count, 1)
    }

    func testTableStructureIsNavigable() {
        let html = "<table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>"
        let document = HTMLDocument.parse(html)
        let rows = document.elements(tag: "tr")

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1].childElements(tag: "td").map(\.text), ["1", "2"])
    }

    func testVoidElementsDoNotSwallowSiblings() {
        let document = HTMLDocument.parse("<div><br><img src='x.png'><span>after</span></div>")
        XCTAssertEqual(document.text, "after")
        XCTAssertEqual(document.elements(tag: "span").count, 1)
    }

    func testAStrayLessThanIsTreatedAsText() {
        let document = HTMLDocument.parse("<p>5 < 6 and 7 > 6</p>")
        XCTAssertTrue(document.text.contains("5"))
        XCTAssertTrue(document.text.contains("6"))
    }
}
