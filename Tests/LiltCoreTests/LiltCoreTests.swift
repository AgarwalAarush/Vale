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
        let prompt = TutorPrompt.build(session: LearningSession(title: "Study",mode:.learn), question: "What can you see?", hasImage: false, pointing: true, reveal: false)
        XCTAssertTrue(prompt.contains("No screen image is attached"))
        XCTAssertTrue(prompt.contains("Do not reveal a full solution"))
        XCTAssertTrue(prompt.contains("No. Return null for point"))
    }
    func testWalkthroughRequiresExplicitRequest() {
        let session = LearningSession(title: "Study",mode:.learn)
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
    func testGeneralModeIsUntimedAndDirect() {
        let chat=LearningSession(title:"New chat")
        XCTAssertEqual(chat.mode,.assistant);XCTAssertEqual(chat.duration,0)
        let prompt=TutorPrompt.build(session:chat,question:"Write the answer",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Answer directly"));XCTAssertFalse(prompt.contains("Do not reveal a full solution"))
    }
    func testLegacyMigrationPreservesLearningAndBacksUp() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:dir)}
        let store=try SessionStore(directory:dir)
        var chat=LearningSession(title:"Old study",duration:1800,mode:.learn)
        chat.draft="Keep this draft";chat.messages=[Message(role:"user",text:"An old question")]
        let encoded=try JSONEncoder().encode([chat]);var rows=try JSONSerialization.jsonObject(with:encoded) as! [[String:Any]]
        rows[0].removeValue(forKey:"mode");rows[0].removeValue(forKey:"webEnabled");rows[0].removeValue(forKey:"pendingAttachments")
        var messages=rows[0]["messages"] as! [[String:Any]];messages[0].removeValue(forKey:"attachments");rows[0]["messages"]=messages
        let legacy=try JSONSerialization.data(withJSONObject:rows)
        try legacy.write(to:dir.appendingPathComponent("sessions.json"))
        let restored=try store.load()[0]
        XCTAssertEqual(restored.id,chat.id);XCTAssertEqual(restored.mode,.learn);XCTAssertEqual(restored.draft,"Keep this draft")
        try XCTAssertEqual(Data(contentsOf:dir.appendingPathComponent("sessions-v1-backup.json")),legacy)
    }
    func testAttachmentMetadataAndSearchRoundTrip() throws {
        var chat=LearningSession(title:"Weekend plan")
        let file=AttachmentRecord(name:"report.pdf",kind:.pdf,byteCount:400,detail:"2 pages")
        chat.pendingAttachments=[file];chat.takeaway="Bring a notebook"
        let restored=try JSONDecoder().decode(LearningSession.self,from:JSONEncoder().encode(chat))
        XCTAssertEqual(restored.pendingAttachments,[file]);XCTAssertTrue(restored.matches("REPORT"));XCTAssertTrue(restored.matches("notebook"));XCTAssertFalse(restored.matches("unrelated"))
    }
    func testUploadedImageIsNotClaimedAsLiveScreen() {
        let prompt=TutorPrompt.build(session:LearningSession(title:"Images"),question:"Compare",hasImage:true,pointing:true,reveal:false,fileContext:"Two uploaded images",hasWindow:false)
        XCTAssertTrue(prompt.contains("No live window is shared"));XCTAssertTrue(prompt.contains("No. Return null for point"))
    }
    func testUpdaterRequiresHTTPSKeyAndBothVerificationGates() throws {
        // Published example public key from Sparkle docs; not a generated credential.
        let key="pfIShU4dEXqPd5ObYNfDBiQWcXozk7estwzTnF9BamQ="
        _=try UpdateConfiguration(feed:"https://updates.example.invalid/appcast.xml",publicKey:key,requiresSignedFeed:true,verifiesBeforeExtraction:true)
        XCTAssertThrowsError(try UpdateConfiguration(feed:"http://updates.example.invalid/appcast.xml",publicKey:key,requiresSignedFeed:true,verifiesBeforeExtraction:true))
        XCTAssertThrowsError(try UpdateConfiguration(feed:"https://user:pass@example.invalid/feed",publicKey:key,requiresSignedFeed:true,verifiesBeforeExtraction:true))
        XCTAssertThrowsError(try UpdateConfiguration(feed:"https://updates.example.invalid/feed",publicKey:"bad",requiresSignedFeed:true,verifiesBeforeExtraction:true))
        XCTAssertThrowsError(try UpdateConfiguration(feed:"https://updates.example.invalid/feed",publicKey:key,requiresSignedFeed:false,verifiesBeforeExtraction:true))
    }
    func testUpdaterRejectsForeignAndInsecureArchiveURLs() throws {
        let key="pfIShU4dEXqPd5ObYNfDBiQWcXozk7estwzTnF9BamQ="
        let config=try UpdateConfiguration(feed:"https://private.example.invalid/appcast.xml",publicKey:key,requiresSignedFeed:true,verifiesBeforeExtraction:true)
        XCTAssertTrue(config.permitsRelease(URL(string:"https://private.example.invalid/Mythos.zip")!))
        XCTAssertFalse(config.permitsRelease(URL(string:"https://elsewhere.example.invalid/Mythos.zip")!))
        XCTAssertFalse(config.permitsRelease(URL(string:"http://private.example.invalid/Mythos.zip")!))
        XCTAssertFalse(config.permitsRelease(URL(string:"https://private.example.invalid:444/Mythos.zip")!))
    }
    func testUpdaterLocalReleasePolicyFixtures() throws {
        struct Fixture:Decodable {
            struct Archive:Decodable {let url:URL;let allowed:Bool}
            let feed:String;let publicKey:String;let archives:[Archive]
        }
        let fixture=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:Bundle.module.url(forResource:"update-policy",withExtension:"json",subdirectory:"Fixtures")!))
        let config=try UpdateConfiguration(feed:fixture.feed,publicKey:fixture.publicKey,requiresSignedFeed:true,verifiesBeforeExtraction:true)
        for archive in fixture.archives {XCTAssertEqual(config.permitsRelease(archive.url),archive.allowed)}
        XCTAssertThrowsError(try UpdateConfiguration(feed:fixture.feed,publicKey:fixture.publicKey,requiresSignedFeed:true,verifiesBeforeExtraction:false))
    }

}

@main struct CoreChecks {
static func main() {
let tests = LiltCoreTests()
let cases: [(String, () throws -> Void)] = [
 ("Session timer", tests.testSessionTimeDoesNotBecomeNegative),
 ("Atomic session storage and file permissions", tests.testStorageRoundTripPreservesDraftAndTakeaway),
 ("Corrupt library preservation", tests.testCorruptLibraryIsNotSilentlyOverwritten),
 ("Reject out-of-bounds pointing", tests.testOutOfBoundsPointIsDiscardedButAnswerSurvives),
 ("Structured reply validation", tests.testValidPointAcceptedAndEmptyResponseRejected),
 ("Truthful context prompt", tests.testPromptDoesNotClaimScreenWhenNoneIsAttached),
 ("Explicit walkthrough policy", tests.testWalkthroughRequiresExplicitRequest),
 ("Markdown export", tests.testExportUsesActualConversationAndTakeaway),
 ("General default without a timer",tests.testGeneralModeIsUntimedAndDirect),
 ("Legacy migration and backup",tests.testLegacyMigrationPreservesLearningAndBacksUp),
 ("Attachment metadata and history search",tests.testAttachmentMetadataAndSearchRoundTrip),
 ("Uploaded images distinguished from live sharing",tests.testUploadedImageIsNotClaimedAsLiveScreen),
 ("Updater configuration security gates",tests.testUpdaterRequiresHTTPSKeyAndBothVerificationGates),
 ("Updater archive origin policy",tests.testUpdaterRejectsForeignAndInsecureArchiveURLs),
 ("Updater local release fixtures",tests.testUpdaterLocalReleasePolicyFixtures)
]
for (name, test) in cases {
 let before = failures.count
 do { try test() } catch { failures.append("\(name): \(error)") }
 if failures.count == before { print("PASS: \(name)"); passed += 1 }
}
for failure in failures { print("FAIL: \(failure)") }
print("\(passed)/\(cases.count) core checks passed")
exit(failures.isEmpty ? 0 : 1)
}
}
