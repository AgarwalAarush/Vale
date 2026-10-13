import Foundation
import LiltCore

var failures: [String] = []
var passed = 0
func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, file: StaticString = #file, line: UInt = #line) rethrows { if try !value() { failures.append("Assertion failed at \(file):\(line)") } }
func XCTAssertFalse(_ value: @autoclosure () throws -> Bool, file: StaticString = #file, line: UInt = #line) rethrows { try XCTAssertTrue(!value(), file: file, line: line) }
func XCTAssertEqual<T: Equatable>(_ first: @autoclosure () throws -> T, _ second: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) rethrows { try XCTAssertTrue(first() == second(), file: file, line: line) }
func XCTAssertNil<T>(_ value: @autoclosure () throws -> T?, file: StaticString = #file, line: UInt = #line) rethrows { try XCTAssertTrue(value() == nil, file: file, line: line) }
func XCTAssertNotNil<T>(_ value: @autoclosure () throws -> T?, file: StaticString = #file, line: UInt = #line) rethrows { try XCTAssertTrue(value() != nil, file: file, line: line) }
func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) { do { _ = try value(); failures.append("Expected error at \(file):\(line)") } catch {} }

final class LiltCoreTests {
    func testSessionTimeDoesNotBecomeNegative() {
        var session = LearningSession(title: "Algorithms", duration: 60)
        session.elapsed = 100
        XCTAssertEqual(session.remaining, 0)
        XCTAssertEqual(session.timerText, "00:00")
        XCTAssertEqual(LearningSession.formatTime(1800), "30:00")
    }
    func testStorageRoundTripPreservesDraftAndTakeaway() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SessionStore(directory: dir)
        var session = LearningSession(title: "A paper")
        session.draft = "A question\nwith pasted code"
        session.messages = [Message(role: "user", text: "What does this mean?")]
        session.takeaway = "My own explanation."
        try store.save([session])
        try XCTAssertEqual(try store.load(), [session])
        let attr = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("sessions.json").path)
        XCTAssertEqual((attr[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testCorruptLibraryIsNotSilentlyOverwritten() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SessionStore(directory: dir)
        let file = dir.appendingPathComponent("sessions.json")
        try Data("broken".utf8).write(to: file)
        XCTAssertThrowsError(try store.load())
        try XCTAssertEqual(try String(contentsOf: file), "broken")
    }
    func testOutOfBoundsPointIsDiscardedButAnswerSurvives() throws {
        let data = Data(#"{"text":"Examine the boundary.","point":{"x":0.9,"y":0.1,"width":0.3,"height":0.1,"label":"Boundary"}}"#.utf8)
        let reply = try TutorReply.decode(data)
        XCTAssertEqual(reply.text, "Examine the boundary.")
        XCTAssertNil(reply.point)
    }
    func testValidPointAcceptedAndEmptyResponseRejected() throws {
        let data = Data(#"{"text":"Check this condition.","point":{"x":0.2,"y":0.3,"width":0.4,"height":0.05,"label":"Condition"}}"#.utf8)
        try XCTAssertNotNil(try TutorReply.decode(data).point)
        XCTAssertThrowsError(try TutorReply.decode(Data(#"{"text":"  ","point":null}"#.utf8)))
    }
    func testPromptDoesNotClaimScreenWhenNoneIsAttached() {
        let prompt = TutorPrompt.build(session: LearningSession(title: "Study"), question: "What can you see?", hasImage: false, pointing: true, reveal: false)
        XCTAssertTrue(prompt.contains("No screen image is attached"))
        XCTAssertTrue(prompt.contains("Do not reveal a full solution"))
        XCTAssertTrue(prompt.contains("No. Return null for point"))
    }
    func testWalkthroughRequiresExplicitRequest() {
        let session = LearningSession(title: "Study")
        let ordinary = TutorPrompt.build(session: session, question: "A hint", hasImage: true, pointing: false, reveal: false)
        let full = TutorPrompt.build(session: session, question: "Show me", hasImage: true, pointing: false, reveal: true)
        XCTAssertFalse(ordinary.contains("explicitly requested a full walkthrough"))
        XCTAssertTrue(full.contains("explicitly requested a full walkthrough"))
    }
    func testExportUsesActualConversationAndTakeaway() {
        var session = LearningSession(title: "Two pointers")
        session.messages = [Message(role: "user", text: "Why?"), Message(role: "assistant", text: "What stays true?")]
        session.takeaway = "Preserve the invariant."
        let export = SessionStore.export(session)
        XCTAssertTrue(export.contains("## You\n\nWhy?"))
        XCTAssertTrue(export.contains("## Lilt\n\nWhat stays true?"))
        XCTAssertTrue(export.contains("## Takeaway\n\nPreserve the invariant."))
    }
}

let tests = LiltCoreTests()
let cases: [(String, () throws -> Void)] = [
 ("Session timer", tests.testSessionTimeDoesNotBecomeNegative),
 ("Atomic session storage and file permissions", tests.testStorageRoundTripPreservesDraftAndTakeaway),
 ("Corrupt library preservation", tests.testCorruptLibraryIsNotSilentlyOverwritten),
 ("Reject out-of-bounds pointing", tests.testOutOfBoundsPointIsDiscardedButAnswerSurvives),
 ("Structured reply validation", tests.testValidPointAcceptedAndEmptyResponseRejected),
 ("Truthful context prompt", tests.testPromptDoesNotClaimScreenWhenNoneIsAttached),
 ("Explicit walkthrough policy", tests.testWalkthroughRequiresExplicitRequest),
 ("Markdown export", tests.testExportUsesActualConversationAndTakeaway)
]
for (name, test) in cases {
 let before = failures.count
 do { try test() } catch { failures.append("\(name): \(error)") }
 if failures.count == before { print("PASS: \(name)"); passed += 1 }
}
for failure in failures { print("FAIL: \(failure)") }
print("\(passed)/\(cases.count) core checks passed")
exit(failures.isEmpty ? 0 : 1)
