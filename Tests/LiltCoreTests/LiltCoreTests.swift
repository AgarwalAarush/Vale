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
        XCTAssertTrue(config.permitsRelease(URL(string:"https://private.example.invalid/Vale.zip")!))
        XCTAssertFalse(config.permitsRelease(URL(string:"https://elsewhere.example.invalid/Vale.zip")!))
        XCTAssertFalse(config.permitsRelease(URL(string:"http://private.example.invalid/Vale.zip")!))
        XCTAssertFalse(config.permitsRelease(URL(string:"https://private.example.invalid:444/Vale.zip")!))
        let same=[URL(string:"https://private.example.invalid/Vale.zip")!,URL(string:"https://private.example.invalid/Vale.delta")!]
        XCTAssertTrue(config.permitsReleases(same))
        XCTAssertFalse(config.permitsReleases(same+[URL(string:"https://cdn.example.invalid/Vale.zip")!]))
        XCTAssertFalse(config.permitsReleases([]))
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

    func testForgetPurgesTargetFromBackupAndKeepsOthers()throws{
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:dir)}
        let store=try SessionStore(directory:dir);let a=LearningSession(title:"Forget this public fixture",mode:.learn);let b=LearningSession(title:"Keep unrelated public fixture",mode:.learn)
        var rows=try JSONSerialization.jsonObject(with:JSONEncoder().encode([a,b])) as! [[String:Any]]
        for i in rows.indices{rows[i].removeValue(forKey:"mode")}
        try JSONSerialization.data(withJSONObject:rows).write(to:dir.appendingPathComponent("sessions.json"));let chats=try store.load()
        try store.forget(a.id,keeping:chats)
        try XCTAssertEqual(store.load().map(\.id),[b.id])
        let backup=try JSONDecoder().decode([LearningSession].self,from:Data(contentsOf:dir.appendingPathComponent("sessions-v1-backup.json")))
        XCTAssertEqual(backup.map(\.id),[b.id]);XCTAssertEqual(backup.first?.title,b.title)
        try store.forget(b.id,keeping:try store.load());XCTAssertFalse(FileManager.default.fileExists(atPath:dir.appendingPathComponent("sessions-v1-backup.json").path));try XCTAssertTrue(store.load().isEmpty)
    }
    func testForgetFailurePreservesRetryableChat()throws{
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:dir)}
        let store=try SessionStore(directory:dir);let chat=LearningSession(title:"Retain on failure")
        try store.save([chat]);try Data("invalid backup".utf8).write(to:dir.appendingPathComponent("sessions-v1-backup.json"))
        XCTAssertThrowsError(try store.forget(chat.id,keeping:[chat]));try XCTAssertEqual(store.load(),[chat])
    }
    func testConversationLimitIsExplicit() {
        var chat=LearningSession(title:"Long chat");chat.messages=(0..<30).map{Message(role:"user",text:"UNIQUE_\($0)_END")}
        let window=ConversationWindow(messages:chat.messages);XCTAssertEqual(window.omitted,12);XCTAssertTrue(chat.contextLimited)
        let prompt=TutorPrompt.build(session:chat,question:"Continue",hasImage:false,pointing:false,reveal:false)
        XCTAssertFalse(prompt.contains("UNIQUE_0_END"));XCTAssertTrue(prompt.contains("UNIQUE_29_END"));XCTAssertTrue(prompt.contains("Earlier history is saved but unavailable"))
    }
    func testConversationExcerptsHaveBoundedBudget(){
        let messages=(0..<18).map{_ in Message(role:"user",text:String(repeating:"x",count:20_000))}
        let window=ConversationWindow(messages:messages);XCTAssertTrue(window.excerpted);XCTAssertTrue(window.omitted>0);XCTAssertTrue(window.text.count<49_000);XCTAssertTrue(window.text.contains("Message excerpt"))
    }
    func testGuideValidationAndLegacyReplyCompatibility()throws{
        let valid=GuidePlan(title:"Check the diagram",steps:["Locate the circle","Compare the square"])
        let reply=TutorReply(text:"Start with the circle",guide:valid)
        try XCTAssertEqual(TutorReply.decode(JSONEncoder().encode(reply)).guide,valid)
        let invalid=TutorReply(text:"Answer",guide:GuidePlan(title:"Bad",steps:["Only one"]))
        try XCTAssertNil(TutorReply.decode(JSONEncoder().encode(invalid)).guide)
        try XCTAssertNil(TutorReply.decode(Data(#"{"text":"Old reply","point":null}"#.utf8)).guide)
    }
    func testGuideProgressClampsPersistedIndex()throws{
        let plan=GuidePlan(title:"Plan",steps:["One","Two"])
        let data=try JSONEncoder().encode(GuideProgress(plan:plan,index:99));let result=try JSONDecoder().decode(GuideProgress.self,from:data)
        XCTAssertEqual(result.index,1);XCTAssertEqual(result.current,"Two")
    }
    func testScreenEvidenceRejectsChangedScopeAndPixels(){
        let now=Date();let id=UUID();let frame=CGRect(x:10,y:20,width:400,height:300)
        let original=ScreenEvidence(generation:id,windowID:42,frame:frame,fingerprint:Data([1]),capturedAt:now.addingTimeInterval(-10))
        var current=ScreenEvidence(generation:id,windowID:42,frame:frame,fingerprint:Data([1]),capturedAt:now)
        XCTAssertTrue(original.matches(current,now:now));current.fingerprint=Data([2]);XCTAssertFalse(original.matches(current,now:now))
        current.fingerprint=Data([1]);current.windowID=43;XCTAssertFalse(original.matches(current,now:now));current.windowID=42;current.generation=UUID();XCTAssertFalse(original.matches(current,now:now))
    }
    func testScreenEvidenceRejectsStaleMovedOrUnknownGeometry(){
        let now=Date();let id=UUID();let frame=CGRect(x:10,y:20,width:400,height:300)
        var original=ScreenEvidence(generation:id,windowID:42,frame:frame,fingerprint:Data([1]),capturedAt:now.addingTimeInterval(-10));var current=original;current.capturedAt=now
        current.frame=CGRect(x:11,y:20,width:400,height:300);XCTAssertFalse(original.matches(current,now:now));current.frame=frame
        current.capturedAt=now.addingTimeInterval(-6);XCTAssertFalse(original.matches(current,now:now));current.capturedAt=now;original.capturedAt=now.addingTimeInterval(-46);XCTAssertFalse(original.matches(current,now:now))
        original.capturedAt=now;original.frame=nil;current.frame=nil;XCTAssertFalse(original.matches(current,now:now));original.frame = .zero;current.frame = .zero;XCTAssertFalse(original.matches(current,now:now))
    }
    func testTextFreshnessWithoutGeometryStillRejectsPointing(){
        let now=Date();let id=UUID();let old=ScreenEvidence(generation:id,windowID:nil,frame:nil,fingerprint:Data([1]),capturedAt:now.addingTimeInterval(-60));let fresh=ScreenEvidence(generation:id,windowID:nil,frame:nil,fingerprint:Data([1]),capturedAt:now)
        XCTAssertTrue(old.reflectsSameView(fresh,now:now));XCTAssertFalse(old.matches(fresh,now:now))
    }
    func testPointVisibilityRejectsForegroundOcclusion(){
        let bounds=CGRect(x:100,y:100,width:400,height:300);let box=CGRect(x:200,y:200,width:80,height:60);let target=PointWindow(id:42,bounds:bounds)
        XCTAssertTrue(PointVisibility.isVisible(targetID:42,box:box,frontToBack:[target]))
        XCTAssertFalse(PointVisibility.isVisible(targetID:42,box:box,frontToBack:[PointWindow(id:99,bounds:box),target]))
        XCTAssertTrue(PointVisibility.isVisible(targetID:42,box:box,frontToBack:[PointWindow(id:99,bounds:CGRect(x:600,y:100,width:50,height:50)),target]))
    }
    func testPointVisibilityRejectsMissingAndUnknownWindows(){
        let box=CGRect(x:200,y:200,width:80,height:60);let target=PointWindow(id:42,bounds:CGRect(x:100,y:100,width:400,height:300))
        XCTAssertFalse(PointVisibility.isVisible(targetID:42,box:box,frontToBack:[]))
        XCTAssertFalse(PointVisibility.isVisible(targetID:42,box:box,frontToBack:[PointWindow(id:99,bounds:nil),target]))
        XCTAssertFalse(PointVisibility.isVisible(targetID:42,box:box,frontToBack:[PointWindow(id:42,bounds:nil)]))
        XCTAssertFalse(PointVisibility.isVisible(targetID:42,box:box,frontToBack:[PointWindow(id:42,bounds:target.bounds,opacity:0)]))
    }
    func testPointVisibilityIgnoresFullyTransparentForegroundOnly(){
        let box=CGRect(x:200,y:200,width:80,height:60);let target=PointWindow(id:42,bounds:CGRect(x:100,y:100,width:400,height:300))
        XCTAssertTrue(PointVisibility.isVisible(targetID:42,box:box,frontToBack:[PointWindow(id:99,bounds:nil,opacity:0),target]))
        XCTAssertFalse(PointVisibility.isVisible(targetID:42,box:.zero,frontToBack:[target]))
    }
    func testLaunchResumesNewestUnfinishedChat() {
        var older=LearningSession(title:"Older ask",mode:.assistant); older.updated=Date(timeIntervalSince1970:10); older.completed=false
        var newer=LearningSession(title:"Newer learn",mode:.learn); newer.updated=Date(timeIntervalSince1970:20); newer.completed=false
        var done=LearningSession(title:"Finished",mode:.assistant); done.updated=Date(timeIntervalSince1970:30); done.completed=true
        XCTAssertEqual(LaunchSelection.resumeID(in:[done,newer,older]),newer.id)
        XCTAssertNil(LaunchSelection.resumeID(in:[done]))
    }
    func testCodexLookupIncludesUserInstallAndParsesShellPath() {
        let home=URL(fileURLWithPath:"/Users/vale",isDirectory:true)
        let paths=CodexLocator.candidatePaths(home:home,customPath:" /custom/codex ",environmentPath:"/usr/bin:/Users/vale/.local/bin")
        XCTAssertEqual(paths.first,"/custom/codex")
        XCTAssertTrue(paths.contains("/Users/vale/.local/bin/codex"))
        XCTAssertTrue(paths.contains("/opt/homebrew/bin/codex"))
        XCTAssertTrue(paths.contains("/usr/local/bin/codex"))
        XCTAssertTrue(paths.contains("/Applications/Codex.app/Contents/Resources/codex"))
        XCTAssertEqual(paths.filter{$0=="/Users/vale/.local/bin/codex"}.count,1)
        XCTAssertEqual(CodexLocator.shellExecutable(from:"welcome\n/opt/homebrew/bin/codex\n"),"/opt/homebrew/bin/codex")
        XCTAssertNil(CodexLocator.shellExecutable(from:"codex not found\n"))
        XCTAssertNil(CodexLocator.shellExecutable(from:""))
    }
    func testGuideRequiresExplicitRequest(){
        let chat=LearningSession(title:"Explain this")
        let ordinary=TutorPrompt.build(session:chat,question:"What is it?",hasImage:false,pointing:false,reveal:false)
        let guide=TutorPrompt.build(session:chat,question:"Guide me",hasImage:true,pointing:true,reveal:true,hasWindow:true,guideRequested:true)
        XCTAssertTrue(ordinary.contains("Return null for guide"));XCTAssertTrue(guide.contains("explicitly requested a step-by-step guide"))
    }
    func testReplyShowsTheCompanion() {
        XCTAssertTrue(ReplySpeaker.showsMark(for: "assistant"))
        XCTAssertFalse(ReplySpeaker.showsMark(for: "user"))
        XCTAssertEqual(ReplySpeaker.name, "LILT")
        var chat = LearningSession(title: "New chat")
        chat.messages = [Message(role: "user", text: "What is this?"), Message(role: "assistant", text: "Here is the answer.")]
        XCTAssertEqual(chat.messages.last?.role, "assistant")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
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
 ("Resume newest unfinished chat",tests.testLaunchResumesNewestUnfinishedChat),
 ("Codex lookup locations and shell path",tests.testCodexLookupIncludesUserInstallAndParsesShellPath),
 ("Updater local release fixtures",tests.testUpdaterLocalReleasePolicyFixtures),
 ("Forget purges backup and preserves unrelated sessions",tests.testForgetPurgesTargetFromBackupAndKeepsOthers),
 ("Forget failure preserves retryable chat",tests.testForgetFailurePreservesRetryableChat),
 ("Visible conversation limit",tests.testConversationLimitIsExplicit),
 ("Bounded message excerpts",tests.testConversationExcerptsHaveBoundedBudget),
 ("Guide validation and legacy replies",tests.testGuideValidationAndLegacyReplyCompatibility),
 ("Guide progress bounds",tests.testGuideProgressClampsPersistedIndex),
 ("Reject changed screen scope and pixels",tests.testScreenEvidenceRejectsChangedScopeAndPixels),
 ("Reject stale or moved screen geometry",tests.testScreenEvidenceRejectsStaleMovedOrUnknownGeometry),
 ("Explicit step guide policy",tests.testGuideRequiresExplicitRequest),
 ("Text context without unsafe geometry fallback",tests.testTextFreshnessWithoutGeometryStillRejectsPointing),
 ("Reject foreground highlight occlusion",tests.testPointVisibilityRejectsForegroundOcclusion),
 ("Reject missing or unknown highlight windows",tests.testPointVisibilityRejectsMissingAndUnknownWindows),
 ("Transparent foreground visibility policy",tests.testPointVisibilityIgnoresFullyTransparentForegroundOnly),
 ("Reply shows the companion",tests.testReplyShowsTheCompanion)
]
var resultMap:[String:Bool]=[:]
for (name, test) in cases {
 let before = failures.count
 do { try test() } catch { failures.append("\(name): \(error)") }
 resultMap[name]=failures.count == before
 if failures.count == before { print("PASS: \(name)"); passed += 1 }
}
for failure in failures { print("FAIL: \(failure)") }
print("\(passed)/\(cases.count) core checks passed")
if let index=CommandLine.arguments.firstIndex(of:"--results"),CommandLine.arguments.count>index+1{try? JSONSerialization.data(withJSONObject:resultMap,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[index+1]))}
exit(failures.isEmpty ? 0 : 1)
}
}
