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

    func testIdleStatusTreatsTypingAsReady() {
        XCTAssertEqual(CompanionStatus().line, "Ready to type")
        XCTAssertEqual(CompanionStatus(canSend: true).line, "Return to send")
        XCTAssertEqual(CompanionStatus(listening: true, conversation: true, canSend: true).line, "Listening…")
        XCTAssertEqual(CompanionStatus(paused: true, canSend: true).line, "Paused")
        XCTAssertEqual(CompanionStatus(speaking: true).line, "Speaking · tap mic to interrupt")
        XCTAssertEqual(CompanionStatus(waitingForMicrophone: true).line, "Waiting for microphone…")
        XCTAssertEqual(CompanionStatus(importing: true, canSend: true).line, "Adding files…")
        XCTAssertEqual(CompanionStatus(thinking: true, canSend: true).line, "Thinking…")
        XCTAssertEqual(CompanionStatus(conversation: true, canSend: true).line, "Conversation ready")
    }

    func testCodexSignInIsStatedBeforeTheFirstSend() {
        let missing = CodexSignInNotice.beforeFirstSend(executableFound: false)
        let found = CodexSignInNotice.beforeFirstSend(executableFound: true)
        XCTAssertTrue(missing.title.contains("Codex sign-in"))
        XCTAssertTrue(missing.detail.contains("codex login"))
        XCTAssertTrue(missing.detail.contains("Settings"))
        XCTAssertTrue(missing.detail.localizedCaseInsensitiveContains("typing"))
        XCTAssertTrue(found.title.contains("Codex sign-in"))
        XCTAssertTrue(found.detail.contains("codex login"))
        XCTAssertTrue(found.detail.localizedCaseInsensitiveContains("type"))
        XCTAssertFalse(found.detail.contains("Install the Codex CLI"))
    }

    func testModeNamesAreAssistantAndLearnWithHints() {
        XCTAssertEqual(ChatMode.assistant.label, "Assistant")
        XCTAssertEqual(ChatMode.learn.label, "Learn with hints")
    }

    func testUserTextIsNotShownAsMarkdown() {
        XCTAssertFalse(Message(role: "user", text: "let n = a * b").showsMarkdown)
        XCTAssertTrue(Message(role: "assistant", text: "Use `a * b`.").showsMarkdown)
    }

    func testCapsuleKeepsAnUnsentDraftVisible() {
        XCTAssertEqual(CapsuleLabel.text(draft: "", title: "New chat"), "Vale")
        XCTAssertEqual(CapsuleLabel.text(draft: "   \n", title: nil), "Vale")
        XCTAssertEqual(CapsuleLabel.text(draft: "", title: "Images and notes"), "Images and notes")
        XCTAssertEqual(CapsuleLabel.text(draft: "  How does this loop end?\nmore", title: "New chat"), "How does this loop end?")
        XCTAssertTrue(CapsuleLabel.showsDraft("  How does this loop end?"))
        XCTAssertFalse(CapsuleLabel.showsDraft(" \n "))
    }

    func testHistoryShowsAnUnsentDraft() {
        var chat = LearningSession(title: "New chat")
        chat.draft = "  How does this loop end?\nSecond line"
        XCTAssertEqual(chat.listPreview, "How does this loop end?")
        XCTAssertEqual(chat.unsentDraft, "How does this loop end?\nSecond line")
        XCTAssertFalse(chat.matches("loop"))
        XCTAssertFalse(chat.matches("missing"))
        chat.messages = [Message(role: "user", text: "Sent question")]
        XCTAssertEqual(chat.listPreview, "Sent question")
        chat.messages = []
        chat.draft = "  \n"
        chat.pendingAttachments = [AttachmentRecord(name: "Notes.md", kind: .text, byteCount: 12)]
        XCTAssertEqual(chat.listPreview, "1 files attached")
        chat.pendingAttachments = []
        XCTAssertEqual(chat.listPreview, "Ready when you are.")
        XCTAssertNil(chat.unsentDraft)
    }

    func testGuideStartConfirmsBeforeClearingWork() {
        XCTAssertFalse(GuideStart.needsConfirmation(draft: "", attachmentCount: 0))
        XCTAssertFalse(GuideStart.needsConfirmation(draft: "  \n", attachmentCount: 0))
        XCTAssertTrue(GuideStart.needsConfirmation(draft: "How does this loop end?", attachmentCount: 0))
        XCTAssertTrue(GuideStart.needsConfirmation(draft: "", attachmentCount: 1))
    }

    func testAssistantReplyStaysVisibleWhenFormattingDropsIt() {
        XCTAssertTrue(AssistantReplyDisplay.needsLiteral(source: "Use Array<Int>.", rendered: "Use Array."))
        XCTAssertTrue(AssistantReplyDisplay.needsLiteral(source: "Print 50% done.", rendered: "Print 50 done."))
        XCTAssertTrue(AssistantReplyDisplay.needsLiteral(source: "Answer", rendered: ""))
        XCTAssertFalse(AssistantReplyDisplay.needsLiteral(source: "Use **bold**.", rendered: "Use bold."))
        XCTAssertFalse(AssistantReplyDisplay.needsLiteral(source: "", rendered: ""))
    }

    func testDroppedAttachmentExplainsWhyItWasNotKept() {
        XCTAssertNil(AttachmentRefusal.message(libraryAvailable: true, hasChat: true, importing: false))
        XCTAssertEqual(AttachmentRefusal.message(libraryAvailable: false, hasChat: true, importing: false), "The chat library is unavailable. Restore the library folder before attaching files.")
        XCTAssertEqual(AttachmentRefusal.message(libraryAvailable: true, hasChat: false, importing: false), "Start a chat before attaching files.")
        XCTAssertEqual(AttachmentRefusal.message(libraryAvailable: true, hasChat: true, importing: true), "Wait for your files to finish attaching.")
    }

    func testFolderDropIsNotReportedAsTooLarge() {
        XCTAssertEqual(AttachmentFileKind.refusal(isRegularFile: false, byteCount: 100), "Choose a file, not a folder.")
        XCTAssertEqual(AttachmentFileKind.refusal(isRegularFile: true, byteCount: nil), "Choose a file, not a folder.")
        XCTAssertEqual(AttachmentFileKind.refusal(isRegularFile: true, byteCount: AttachmentFileKind.maxBytes + 1), "Choose a file under 25 MB.")
        XCTAssertNil(AttachmentFileKind.refusal(isRegularFile: true, byteCount: AttachmentFileKind.maxBytes))
    }

    func testVoiceOptInWaitsForTheReply() {
        XCTAssertFalse(ConversationOptIn.startsListeningNow(busy: true, speaking: false))
        XCTAssertFalse(ConversationOptIn.startsListeningNow(busy: false, speaking: true))
        XCTAssertFalse(ConversationOptIn.startsListeningNow(busy: true, speaking: true))
        XCTAssertTrue(ConversationOptIn.startsListeningNow(busy: false, speaking: false))
    }

    func testRetryStaysAfterTheErrorIsDismissed() {
        XCTAssertTrue(ReplyRetry.isAvailable(busy: false, hasFailedQuestion: true, lastRole: "user"))
        XCTAssertFalse(ReplyRetry.isAvailable(busy: true, hasFailedQuestion: true, lastRole: "user"))
        XCTAssertFalse(ReplyRetry.isAvailable(busy: false, hasFailedQuestion: false, lastRole: "user"))
        XCTAssertFalse(ReplyRetry.isAvailable(busy: false, hasFailedQuestion: true, lastRole: "assistant"))
        XCTAssertFalse(ReplyRetry.isAvailable(busy: false, hasFailedQuestion: true, lastRole: nil))
    }

    func testModeChangeKeepsTheReply() {
        XCTAssertTrue(ModeChange.keepsInFlightReply)
    }

    func testComposerGrowsToShowAPasteAndThenStops() {
        XCTAssertEqual(ComposerHeight.clamped(20), ComposerHeight.minimum)
        XCTAssertEqual(ComposerHeight.clamped(61), 61)
        XCTAssertEqual(ComposerHeight.clamped(96), 96)
        XCTAssertEqual(ComposerHeight.clamped(400), ComposerHeight.maximum)
        XCTAssertEqual(ComposerHeight.clamped(Double.nan), ComposerHeight.minimum)
    }

    func testComposerFocusRetriesUntilTheFieldExists() {
        XCTAssertTrue(ComposerFocus.shouldRetry(found: false, attemptsLeft: ComposerFocus.attempts))
        XCTAssertFalse(ComposerFocus.shouldRetry(found: true, attemptsLeft: ComposerFocus.attempts))
        XCTAssertFalse(ComposerFocus.shouldRetry(found: false, attemptsLeft: 0))
    }

    func testNewestReplyOpensAtItsFirstLine() {
        XCTAssertTrue(TranscriptReveal.showsStartOfNewestMessage)
    }

    func testSharedWindowLabelUsesThePickedTitle() {
        XCTAssertEqual(SharedWindowLabel.text(windowTitle: "Notes — Plan", applicationName: "Notes"), "Notes — Plan")
        XCTAssertEqual(SharedWindowLabel.text(windowTitle: "   ", applicationName: "Safari"), "Safari window")
        XCTAssertEqual(SharedWindowLabel.text(windowTitle: nil, applicationName: nil), "Selected window")
        XCTAssertEqual(SharedWindowLabel.text(windowTitle: nil, applicationName: "  "), "Selected window")
        XCTAssertEqual(SharedWindowLabel.text(windowTitle: String(repeating: "A", count: 200), applicationName: "X").count, 120)
    }

    func testCommandPromptKeepsTheComposerDraft() {
        XCTAssertTrue(CommandPrompt.keepsComposerDraft(sendsOwnPrompt: true))
        XCTAssertFalse(CommandPrompt.keepsComposerDraft(sendsOwnPrompt: false))
    }

    func testCapsuleShowsAFailedSend() {
        XCTAssertEqual(CapsuleFailure.text(hasError: true), "Couldn't answer")
        XCTAssertNil(CapsuleFailure.text(hasError: false))
    }

    func testShortcutFailureStaysReadable() {
        XCTAssertNil(ShortcutNotice.text(nil))
        XCTAssertNil(ShortcutNotice.text("  \n"))
        XCTAssertEqual(ShortcutNotice.text("  The shortcut is already in use. Open Vale from the menu bar.  "), "The shortcut is already in use. Open Vale from the menu bar.")
    }

    func testGuideStepIsShownInFull() {
        let step = String(repeating: "Follow the curved edge. ", count: 12)
        XCTAssertEqual(GuideStepText.visible(step), step)
        XCTAssertTrue(step.count > 200)
    }

    func testCloseLeavesTheChatForTheNextLaunch() {
        var chat=LearningSession(title:"First question"); chat.completed=true
        chat=LaunchSelection.chatAfterClose(chat)
        XCTAssertFalse(chat.completed)
        XCTAssertEqual(LaunchSelection.resumeID(in:[chat]),chat.id)
    }

    func testPickerCancelKeepsTheSelectedWindow() {
        let current=SharedWindowSelection(id:7,title:"Notes window",live:true)
        let replacement=SharedWindowSelection(id:8,title:"Browser window",live:false)
        XCTAssertEqual(SharingPicker.selection(after:.cancelled,keeping:current),current)
        XCTAssertEqual(SharingPicker.selection(after:.failedToOpen,keeping:current),current)
        XCTAssertNil(SharingPicker.selection(after:.cancelled,keeping:nil))
        XCTAssertEqual(SharingPicker.selection(after:.chose(replacement),keeping:current),replacement)
        XCTAssertEqual(SharingPicker.failureMessage(keeping:nil),"Couldn’t open window sharing. Keep typing or attach an image.")
        XCTAssertEqual(SharingPicker.failureMessage(keeping:current),"Couldn’t open window sharing. The window you already chose is still shared.")
    }

    func testHighlightStaysWhileTheWindowIsUnchanged() {
        XCTAssertFalse(PointHighlight.shouldClear(windowUnchanged:true,visible:true))
        XCTAssertTrue(PointHighlight.shouldClear(windowUnchanged:false,visible:true))
        XCTAssertTrue(PointHighlight.shouldClear(windowUnchanged:true,visible:false))
    }

    func testCollapsedCoachShowsThatAnAnswerIsReady() {
        XCTAssertEqual(CapsuleAnswer.title(coachOpen:false,chatTitle:"How do I export",lastRole:"assistant"),CapsuleAnswer.ready)
        XCTAssertEqual(CapsuleAnswer.title(coachOpen:true,chatTitle:"How do I export",lastRole:"assistant"),"How do I export")
        XCTAssertEqual(CapsuleAnswer.title(coachOpen:false,chatTitle:"How do I export",lastRole:"user"),"How do I export")
        XCTAssertEqual(CapsuleAnswer.title(coachOpen:false,chatTitle:"New chat",lastRole:nil),"Vale")
        XCTAssertEqual(CapsuleAnswer.title(coachOpen:false,chatTitle:nil,lastRole:nil),"Vale")
    }

    func testWebSearchControlIsNamed() {
        XCTAssertEqual(WebSearchLabel.title(enabled:false),"Web search")
        XCTAssertEqual(WebSearchLabel.title(enabled:true),"Web search on")
    }

    func testPasteKeepsCopiedText() {
        XCTAssertEqual(ComposerPaste.choice(text:"See the docs",hasFile:false,hasImage:true),.text)
        XCTAssertEqual(ComposerPaste.choice(text:"/tmp/notes.pdf",hasFile:true,hasImage:false),.files)
        XCTAssertEqual(ComposerPaste.choice(text:nil,hasFile:false,hasImage:true),.image)
        XCTAssertEqual(ComposerPaste.choice(text:"  ",hasFile:false,hasImage:true),.image)
        XCTAssertEqual(ComposerPaste.choice(text:nil,hasFile:false,hasImage:false),.text)
    }

    func testStaleAnswerStaysMarkedOutsideTheCoach() {
        let stale=Message(role:"assistant",text:"Use the old button",screenChanged:true)
        let fresh=Message(role:"assistant",text:"Use the new button")
        XCTAssertTrue(StaleWindowAnswer.applies(to:stale))
        XCTAssertFalse(StaleWindowAnswer.applies(to:fresh))
        XCTAssertFalse(StaleWindowAnswer.applies(to:Message(role:"user",text:"Where?",screenChanged:true)))
        var chat=LearningSession(title:"Export")
        chat.messages=[Message(role:"user",text:"Where is it?"),stale]
        XCTAssertTrue(SessionStore.export(chat).contains(StaleWindowAnswer.notice))
    }

    func testHistoryPreviewShowsTheMatchingMessage() {
        var chat=LearningSession(title:"Notes")
        chat.messages=[Message(role:"user",text:"How do I export a PDF?"),Message(role:"assistant",text:"Open the share menu and save.")]
        chat.takeaway="Keep a copy"
        chat.pendingAttachments=[AttachmentRecord(name:"report.pdf",kind:.pdf,byteCount:10)]
        XCTAssertEqual(chat.historyPreview(matching:""),"Open the share menu and save.")
        XCTAssertEqual(chat.historyPreview(matching:" export "),"How do I export a PDF?")
        XCTAssertEqual(chat.historyPreview(matching:"SHARE"),"Open the share menu and save.")
        XCTAssertEqual(chat.historyPreview(matching:"copy"),"Keep a copy")
        XCTAssertEqual(chat.historyPreview(matching:"report.pdf"),"report.pdf")
        XCTAssertEqual(LearningSession(title:"Empty").historyPreview(matching:""),"Ready when you are.")
    }

    func testSpokenReplyKeepsTheLinkAddress() {
        let spoken=SpokenReply.text(from:"See [the docs](https://example.com/docs) and `code` plus **this**.")
        XCTAssertTrue(spoken.contains("the docs"))
        XCTAssertTrue(spoken.contains("https://example.com/docs"))
        XCTAssertFalse(spoken.contains("]("))
        XCTAssertFalse(spoken.contains("`"))
        XCTAssertFalse(spoken.contains("**"))
        let both=SpokenReply.text(from:"[One](https://one.example) and [Two](https://two.example)")
        XCTAssertTrue(both.contains("https://one.example"))
        XCTAssertTrue(both.contains("https://two.example"))
    }

    func testSidebarUsesTheSearchWhileItIsVisible() {
        var matched=LearningSession(title:"Export")
        matched.messages=[Message(role:"user",text:"How do I export?")]
        let other=LearningSession(title:"Weather")
        let sessions=[matched,other]
        XCTAssertEqual(HistoryLists.sidebar(sessions,query:"export",searchVisible:true).map(\.title),["Export"])
        XCTAssertEqual(HistoryLists.sidebar(sessions,query:"export",searchVisible:false).map(\.title),["Export","Weather"])
        XCTAssertEqual(HistoryLists.sidebar(sessions,query:"",searchVisible:true).map(\.title),["Export","Weather"])
    }

    func testHistoryCountsTheReply() {
        var chat=LearningSession(title:"Export")
        XCTAssertEqual(ChatSummary.messageCount(chat.messages),0)
        chat.messages=[Message(role:"user",text:"How?")]
        XCTAssertEqual(ChatSummary.messageCount(chat.messages),1)
        chat.messages.append(Message(role:"assistant",text:"Use the menu."))
        XCTAssertEqual(ChatSummary.messageCount(chat.messages),2)
    }

    func testReadAloudSpeaksTheReplyAlreadyOnScreen() {
        let messages=[Message(role:"user",text:"How?"),Message(role:"assistant",text:"Use the menu.")]
        XCTAssertEqual(ReadAloud.replyToSpeak(messages:messages,enabled:true,alreadySpeaking:false),"Use the menu.")
        XCTAssertNil(ReadAloud.replyToSpeak(messages:messages,enabled:false,alreadySpeaking:false))
        XCTAssertNil(ReadAloud.replyToSpeak(messages:messages,enabled:true,alreadySpeaking:true))
        XCTAssertNil(ReadAloud.replyToSpeak(messages:[Message(role:"user",text:"How?")],enabled:true,alreadySpeaking:false))
        XCTAssertNil(ReadAloud.replyToSpeak(messages:[Message(role:"assistant",text:"  ")],enabled:true,alreadySpeaking:false))
    }

    func testExcerptKeepsTheEndOfALongReply() {
        let text=String(repeating:"A",count:5_000)+"CONCLUSION"
        let piece=MessageExcerpt.keepingEnds(text,limit:1_000)
        XCTAssertTrue(piece.truncated)
        XCTAssertEqual(piece.text.count,1_000)
        XCTAssertTrue(piece.text.hasPrefix("A"))
        XCTAssertTrue(piece.text.hasSuffix("CONCLUSION"))
        let short=MessageExcerpt.keepingEnds("Short reply",limit:1_000)
        XCTAssertFalse(short.truncated)
        XCTAssertEqual(short.text,"Short reply")
        let long=String(repeating:"A",count:9_000)+"CONCLUSION"
        let followUp=ConversationWindow(messages:[Message(role:"assistant",text:long)])
        XCTAssertTrue(followUp.excerpted)
        XCTAssertTrue(followUp.text.contains("CONCLUSION"))
        XCTAssertTrue(followUp.text.contains("Message excerpt"))
        XCTAssertFalse(followUp.text.contains(String(repeating:"A",count:9_000)))
    }

    func testStorageFailureStillOpensTheCoach() {
        XCTAssertTrue(LaunchPresentation.presentsCoach(hasActiveChat:false,hasError:true))
        XCTAssertTrue(LaunchPresentation.presentsCoach(hasActiveChat:true,hasError:false))
        XCTAssertFalse(LaunchPresentation.presentsCoach(hasActiveChat:false,hasError:false))
    }

    func testSendCommitsCompositionBeforeClearingTheDraft() {
        XCTAssertTrue(ComposerSubmit.commitsMarkedTextBeforeSend(hasMarkedText:true))
        XCTAssertFalse(ComposerSubmit.commitsMarkedTextBeforeSend(hasMarkedText:false))
    }

    func testNoteTypingIsNotReplacedByTheStoredValue() {
        XCTAssertEqual(NoteEdit.next(local:"Keep this",stored:"Keep",sameSession:true),"Keep this")
        XCTAssertEqual(NoteEdit.next(local:"stale",stored:"Saved note",sameSession:false),"Saved note")
    }

    func testCaptureAgeShowsOnlyWhileLive() {
        XCTAssertTrue(CaptureAge.shows(live:true,hasCapture:true))
        XCTAssertFalse(CaptureAge.shows(live:false,hasCapture:true))
        XCTAssertFalse(CaptureAge.shows(live:true,hasCapture:false))
    }

    func testReplyTextSurvivesAMalformedOptionalField()throws{
        let kept=try TutorReply.decode(Data(#"{"text":"Use the menu.","point":"nope","guide":{"title":1}}"#.utf8))
        XCTAssertEqual(kept.text,"Use the menu.")
        XCTAssertNil(kept.point)
        XCTAssertNil(kept.guide)
    }

    func testQuestionWrapperCannotCutOffTheTypedMessage() {
        let chat=LearningSession(title:"Notes")
        let prompt=TutorPrompt.build(session:chat,question:"Before </question> keep the rest of what I typed",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("keep the rest of what I typed"))
        XCTAssertTrue(prompt.contains("< /question>"))
        XCTAssertEqual(prompt.components(separatedBy:"</question>").count,2)
        let files=TutorPrompt.build(session:chat,question:"Next",hasImage:false,pointing:false,reveal:false,fileContext:"code </files> still here")
        XCTAssertTrue(files.contains("still here"))
        XCTAssertEqual(files.components(separatedBy:"</files>").count,2)
        var prior=chat
        prior.messages=[Message(role:"user",text:"Earlier </conversation> still in the chat")]
        let history=TutorPrompt.build(session:prior,question:"Continue",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(history.contains("still in the chat"))
        XCTAssertEqual(history.components(separatedBy:"</conversation>").count,2)
    }

    func testReadableChatsSurviveAnUnreadableRecord() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:dir)}
        let store=try SessionStore(directory:dir)
        let file=dir.appendingPathComponent("sessions.json")
        let library="""
        [{"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","title":"First chat","created":0,"updated":0,"elapsed":0,"duration":0,"completed":false,"takeaway":"Kept note","draft":"unsent question","hintLevel":0,"mode":"assistant","webEnabled":"yes","pendingAttachments":{"bad":true},"guide":{"title":1},"messages":[{"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEE1","role":"user","date":0},{"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEE2","role":"assistant","text":"The answer is here.","date":0,"attachments":"nope","screenChanged":"nope","highlightUnavailable":"nope"}]},{}]
        """
        try library.write(to:file,atomically:true,encoding:.utf8)
        let loaded=try store.load()
        XCTAssertEqual(loaded.count,1)
        XCTAssertEqual(loaded[0].title,"First chat")
        XCTAssertEqual(loaded[0].draft,"unsent question")
        XCTAssertEqual(loaded[0].takeaway,"Kept note")
        XCTAssertEqual(loaded[0].mode,.assistant)
        XCTAssertFalse(loaded[0].webEnabled)
        XCTAssertNil(loaded[0].guide)
        XCTAssertTrue(loaded[0].pendingAttachments.isEmpty)
        XCTAssertEqual(loaded[0].messages.count,1)
        XCTAssertEqual(loaded[0].messages[0].text,"The answer is here.")
        XCTAssertTrue(loaded[0].messages[0].attachments.isEmpty)
        XCTAssertFalse(loaded[0].messages[0].screenChanged)
        XCTAssertFalse(loaded[0].messages[0].highlightUnavailable)
        try XCTAssertEqual(String(contentsOf:file),library)
        let broken="[{}]"
        try broken.write(to:file,atomically:true,encoding:.utf8)
        XCTAssertThrowsError(try store.load())
        try XCTAssertEqual(String(contentsOf:file),broken)
        var search=LearningSession(title:"Search")
        search.webEnabled=true
        search.guide=GuideProgress(plan:GuidePlan(title:"Plan",steps:["One","Two"]))
        let restored=try JSONDecoder().decode(LearningSession.self,from:JSONEncoder().encode(search))
        XCTAssertTrue(restored.webEnabled)
        XCTAssertEqual(restored.guide?.current,"One")
        let unknown=Data(#"{"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","title":"Mode","created":0,"updated":0,"messages":[],"elapsed":0,"duration":0,"completed":false,"takeaway":"","draft":"","hintLevel":0,"mode":"nope"}"#.utf8)
        let mode=try JSONDecoder().decode(LearningSession.self,from:unknown)
        XCTAssertEqual(mode.mode,.assistant)
        XCTAssertFalse(mode.webEnabled)
    }

    func testFirstQuestionWaitsForCodexLookup() {
        XCTAssertEqual(CodexStartup.next(executableFound: true, lookupPending: true), .start)
        XCTAssertEqual(CodexStartup.next(executableFound: true, lookupPending: false), .start)
        XCTAssertEqual(CodexStartup.next(executableFound: false, lookupPending: true), .wait)
        XCTAssertEqual(CodexStartup.next(executableFound: false, lookupPending: false), .missing)
    }

    func testBlankRenameKeepsTheExistingTitle() {
        XCTAssertEqual(ChatTitle.saved("  Images and planning notes  "),"Images and planning notes")
        XCTAssertNil(ChatTitle.saved("   "))
        XCTAssertNil(ChatTitle.saved("\n"))
        XCTAssertEqual(ChatTitle.saved(String(repeating:"a",count:120))?.count,100)
    }

    func testFinishedReplyFileIsKeptWhenTheProcessReportsFailure() {
        let ready=Data(#"{"text":"Use the menu.","point":null,"guide":null}"#.utf8)
        XCTAssertEqual(FinishedReply.decoded(ready)?.text,"Use the menu.")
        XCTAssertNil(FinishedReply.decoded(nil))
        XCTAssertNil(FinishedReply.decoded(Data("broken".utf8)))
        XCTAssertNil(FinishedReply.decoded(Data(#"{"text":"  ","point":null}"#.utf8)))
    }

    func testModelChoiceIgnoresSurroundingSpace() {
        XCTAssertEqual(ModelChoice.argument("  gpt-5.4 \n"),"gpt-5.4")
        XCTAssertEqual(ModelChoice.argument("\n  local-model"),"local-model")
        XCTAssertNil(ModelChoice.argument("  \n"))
        XCTAssertNil(ModelChoice.argument(""))
    }

    func testOutgoingMessageKeepsLeadingIndentation() {
        XCTAssertEqual(OutgoingMessage.text("    func f() {\n        return 1\n    }\n"),"    func f() {\n        return 1\n    }")
        XCTAssertEqual(OutgoingMessage.text("\n    func f()"),"    func f()")
        XCTAssertEqual(OutgoingMessage.text("  hello  "),"  hello")
        XCTAssertEqual(OutgoingMessage.text("hello"),"hello")
        XCTAssertNil(OutgoingMessage.text("  \n\t"))
        XCTAssertNil(OutgoingMessage.text(""))
    }

    func testAnswerTextIsShownBeforeTheWindowIsRechecked() {
        let ready=ShownAnswer(text:"Use the menu.")
        XCTAssertEqual(ready.text,"Use the menu.")
        XCTAssertFalse(ready.windowChanged)
        let changed=ready.withWindowChanged(true)
        XCTAssertEqual(changed.text,"Use the menu.")
        XCTAssertTrue(changed.windowChanged)
        XCTAssertFalse(ready.withWindowChanged(false).windowChanged)
    }

    func testConfiguredEmptyChatIsKept() {
        XCTAssertTrue(EmptyChat.canDiscard(title:"New chat",messageCount:0,draft:"",fileCount:0,duration:0,mode:.assistant,webEnabled:false))
        XCTAssertFalse(EmptyChat.canDiscard(title:"New chat",messageCount:0,draft:"",fileCount:0,duration:1800,mode:.assistant,webEnabled:false))
        XCTAssertFalse(EmptyChat.canDiscard(title:"New chat",messageCount:0,draft:"",fileCount:0,duration:0,mode:.learn,webEnabled:false))
        XCTAssertFalse(EmptyChat.canDiscard(title:"New chat",messageCount:0,draft:"",fileCount:0,duration:0,mode:.assistant,webEnabled:true))
        XCTAssertFalse(EmptyChat.canDiscard(title:"Plan",messageCount:0,draft:"",fileCount:0,duration:0,mode:.assistant,webEnabled:false))
        XCTAssertFalse(EmptyChat.canDiscard(title:"New chat",messageCount:1,draft:"",fileCount:0,duration:0,mode:.assistant,webEnabled:false))
        XCTAssertFalse(EmptyChat.canDiscard(title:"New chat",messageCount:0,draft:"hello",fileCount:0,duration:0,mode:.assistant,webEnabled:false))
        XCTAssertFalse(EmptyChat.canDiscard(title:"New chat",messageCount:0,draft:"",fileCount:1,duration:0,mode:.assistant,webEnabled:false))
    }

    func testWebSearchDoesNotEnableCodeExecution() {
        XCTAssertFalse(RequestTools.allowsCodeExecution(webSearch: false))
        XCTAssertFalse(RequestTools.allowsCodeExecution(webSearch: true))
    }

    func testQuestionIsClosedOnlyAfterTheFullTextIsWritten() {
        let full=Data("What is 2 + 2?".utf8)
        XCTAssertTrue(PromptDelivery.canClose(afterWriting:full.count,of:full.count))
        XCTAssertFalse(PromptDelivery.canClose(afterWriting:4,of:full.count))
        XCTAssertFalse(PromptDelivery.canClose(afterWriting:full.count+1,of:full.count))
        XCTAssertFalse(PromptDelivery.canClose(afterWriting:-1,of:full.count))
        XCTAssertFalse(PromptDelivery.canClose(afterWriting:0,of:0))
    }

    func testExportUsesTheAnswerThatArrivedWhileSaving() {
        var shown=LearningSession(title:"First chat")
        shown.messages=[Message(role:"user",text:"What is 2 + 2?")]
        var saved=shown
        saved.messages.append(Message(role:"assistant",text:"4"))
        let current=ExportedChat.latest(id:shown.id,in:[saved],shown:shown)
        let file=SessionStore.export(current)
        XCTAssertTrue(file.contains("What is 2 + 2?"))
        XCTAssertTrue(file.contains("4"))
        XCTAssertEqual(ExportedChat.latest(id:UUID(),in:[saved],shown:shown).messages.count,1)
    }

    func testChatHistoryShowsTheChatYouWereJustIn() {
        let active=UUID();let other=UUID()
        XCTAssertEqual(HistoryFocus.selection(active:active,selected:other,openingHistory:true),active)
        XCTAssertFalse(HistoryFocus.showsSettings(openingHistory:true,settings:true))
        XCTAssertEqual(HistoryFocus.selection(active:nil,selected:other,openingHistory:true),other)
        XCTAssertEqual(HistoryFocus.selection(active:active,selected:other,openingHistory:false),other)
        XCTAssertTrue(HistoryFocus.showsSettings(openingHistory:false,settings:true))
    }

    func testOpenedPreviewClosesWhenTheQuestionIsSent() {
        XCTAssertTrue(QuestionPreview.shouldCloseOpenedPreview(questionWasSent:true))
        XCTAssertFalse(QuestionPreview.shouldCloseOpenedPreview(questionWasSent:false))
    }

    func testChatListShowsTheAnswerWhenTheFirstLineIsBlank() {
        XCTAssertEqual(ChatListLine.text(from:"\n\nThe result is 4."),"The result is 4.")
        XCTAssertEqual(ChatListLine.text(from:"The result is 4."),"The result is 4.")
        XCTAssertEqual(ChatListLine.text(from:"  Keep this line"),"Keep this line")
        XCTAssertNil(ChatListLine.text(from:"\n  \n"))
        XCTAssertNil(ChatListLine.text(from:nil))
    }

    func testFirstLaunchOpensTheSavedChatByItsId() {
        var saved=LearningSession(title:"Saved answer"); saved.updated=Date(timeIntervalSince1970:20)
        var finished=LearningSession(title:"Finished"); finished.updated=Date(timeIntervalSince1970:30); finished.completed=true
        XCTAssertEqual(LaunchSelection.target(in:[finished,saved])?.chatID,saved.id)
        XCTAssertNil(LaunchSelection.target(in:[finished]))
    }

    func testFirstQuestionKeepsGoingWhenInstructionsAreMissing() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let bundle=root.appendingPathComponent("Bundle")
        let work=root.appendingPathComponent("Work")
        try FileManager.default.createDirectory(at:bundle,withIntermediateDirectories:true)
        try FileManager.default.createDirectory(at:work.appendingPathComponent("Resources"),withIntermediateDirectories:true)
        XCTAssertNil(InstructionFile.directory(bundleResources:nil,workingDirectory:work))
        XCTAssertNil(InstructionFile.directory(bundleResources:bundle,workingDirectory:work))
        try "instructions".write(to:work.appendingPathComponent("Resources/tutor.md"),atomically:true,encoding:.utf8)
        XCTAssertNil(InstructionFile.directory(bundleResources:nil,workingDirectory:work))
        try "{}".write(to:work.appendingPathComponent("Resources/reply.schema.json"),atomically:true,encoding:.utf8)
        XCTAssertEqual(InstructionFile.directory(bundleResources:nil,workingDirectory:work),work.appendingPathComponent("Resources"))
        try "instructions".write(to:bundle.appendingPathComponent("tutor.md"),atomically:true,encoding:.utf8)
        try "{}".write(to:bundle.appendingPathComponent("reply.schema.json"),atomically:true,encoding:.utf8)
        XCTAssertEqual(InstructionFile.directory(bundleResources:bundle,workingDirectory:work),bundle)
    }

    func testQuestionCanRunTheProgramBesideCodex() {
        let locked=AssistantPath.locked
        let nvm="/Users/me/.nvm/versions/node/v20/bin/codex"
        XCTAssertEqual(AssistantPath.value(executable:nvm),"/Users/me/.nvm/versions/node/v20/bin:"+locked)
        XCTAssertEqual(AssistantPath.value(executable:"/opt/homebrew/bin/codex"),locked)
        XCTAssertEqual(AssistantPath.value(executable:"codex"),locked)
        XCTAssertEqual(AssistantPath.value(executable:"/tmp/evil:/bin/codex"),locked)
    }

    func testUnsavedQuestionReturnsToTheComposer() {
        let file=AttachmentRecord(name:"Notes.txt",kind:.text,byteCount:4)
        var chat=LearningSession(title:"New chat")
        let previous=chat.title
        chat.messages.append(Message(role:"user",text:"Hello",attachments:[file]))
        chat.title="Hello"
        let restored=SendSave.restore(previousTitle:previous,messages:chat.messages,pending:[],question:"Hello",draft:"Hello")
        XCTAssertEqual(restored.title,"New chat")
        XCTAssertTrue(restored.messages.isEmpty)
        XCTAssertEqual(restored.pending,[file])
        XCTAssertEqual(restored.draft,"Hello")
        var older=LearningSession(title:"Earlier")
        older.messages=[Message(role:"user",text:"First"),Message(role:"assistant",text:"Answer"),Message(role:"user",text:"Second")]
        let kept=SendSave.restore(previousTitle:"Earlier",messages:older.messages,pending:[],question:"Second",draft:"Second ")
        XCTAssertEqual(kept.title,"Earlier")
        XCTAssertEqual(kept.messages.map(\.text),["First","Answer"])
        XCTAssertEqual(kept.draft,"Second ")
    }

    func testAnswerAppliesOnlyToTheCurrentChat() {
        let request=UUID();let chat=UUID();let other=UUID()
        XCTAssertTrue(ReplyDelivery.shouldApply(request:request,current:request,chat:chat,active:chat))
        XCTAssertFalse(ReplyDelivery.shouldApply(request:request,current:UUID(),chat:chat,active:chat))
        XCTAssertFalse(ReplyDelivery.shouldApply(request:request,current:request,chat:chat,active:other))
        XCTAssertFalse(ReplyDelivery.shouldApply(request:request,current:request,chat:chat,active:nil))
    }

    func testAnswerIsSavedBeforeSpeechOrPointing() {
        XCTAssertEqual(AnswerStep.sequence(speaks:false,points:false),[.save])
        XCTAssertEqual(AnswerStep.sequence(speaks:true,points:false),[.save,.speak])
        XCTAssertEqual(AnswerStep.sequence(speaks:true,points:true),[.save,.speak,.point])
        XCTAssertEqual(AnswerStep.sequence(speaks:false,points:true).first,.save)
    }

    func testQuestionSkipsACaptureThatWasAlreadyRunning() {
        XCTAssertFalse(RequestCapture.useFrame(joinedExisting:true,waitsSoFar:0))
        XCTAssertFalse(RequestCapture.useFrame(joinedExisting:true,waitsSoFar:RequestCapture.maxWaits-1))
        XCTAssertTrue(RequestCapture.useFrame(joinedExisting:false,waitsSoFar:0))
        XCTAssertTrue(RequestCapture.useFrame(joinedExisting:true,waitsSoFar:RequestCapture.maxWaits))
    }

    func testHistoryShowsTheFullSavedAnswer() {
        XCTAssertTrue(HistoryReply.usesIntrinsicHeight)
    }

    func testAnswerSurvivesTheOutputPipe() {
        XCTAssertFalse(OutputPipe.closesReaderBeforeFile(exited:true, onHandlerThread:true))
        XCTAssertTrue(OutputPipe.closesReaderBeforeFile(exited:true, onHandlerThread:false))
        XCTAssertFalse(OutputPipe.closesReaderBeforeFile(exited:false, onHandlerThread:false))
    }

    func testWaitingClearsWhenTheQuestionDoesNotGoOut() {
        let id=UUID()
        XCTAssertTrue(QuestionSend.shouldClearWaiting(request:id, current:id, handedOff:false))
        XCTAssertFalse(QuestionSend.shouldClearWaiting(request:id, current:id, handedOff:true))
        XCTAssertFalse(QuestionSend.shouldClearWaiting(request:id, current:UUID(), handedOff:false))
    }

    func testLongGuideStepIsKept()throws{
        let step=String(repeating:"Walk through the diagram. ",count:20)
        XCTAssertTrue(step.count>300)
        let plan=GuidePlan(title:"Follow the diagram",steps:[step,"Name the shape"])
        let decoded=try TutorReply.decode(JSONEncoder().encode(TutorReply(text:"Start with the first part of the diagram.",guide:plan)))
        XCTAssertEqual(decoded.guide,plan)
        let titled=GuidePlan(title:String(repeating:"A",count:121),steps:["Find the circle","Name its color"])
        try XCTAssertEqual(TutorReply.decode(JSONEncoder().encode(TutorReply(text:"Begin.",guide:titled))).guide,titled)
        var chat=LearningSession(title:"Diagram");chat.guide=GuideProgress(plan:plan)
        let restored=try JSONDecoder().decode(LearningSession.self,from:JSONEncoder().encode(chat))
        XCTAssertEqual(restored.guide?.plan,plan)
        XCTAssertFalse(GuidePlan(title:"   ",steps:["One","Two"]).isValid)
        XCTAssertFalse(GuidePlan(title:"Plan",steps:[String(repeating:"x",count:4_001),"Next"]).isValid)
        try XCTAssertNil(TutorReply.decode(JSONEncoder().encode(TutorReply(text:"Answer",guide:GuidePlan(title:"Bad",steps:["Only one"])))).guide)
    }

    func testNumericPdfTextIsReadable() {
        XCTAssertTrue(PdfText.hasReadableText(pageBodies:["1840\n220\n15"]))
        XCTAssertTrue(PdfText.hasReadableText(pageBodies:["1,250.00","340.10"]))
        XCTAssertTrue(PdfText.hasReadableText(pageBodies:["HARBOR-73"]))
        XCTAssertFalse(PdfText.hasReadableText(pageBodies:["", " \n"]))
        XCTAssertFalse(PdfText.hasReadableText(pageBodies:["A"]))
        XCTAssertFalse(PdfText.hasReadableText(pageBodies:[]))
    }

    func testUnicodeTextFileIsReadable() {
        let words="Total 1840"
        let utf16=Data([0xFF,0xFE])+words.data(using:.utf16LittleEndian)!
        XCTAssertEqual(TextFile.decode(utf16),words)
        XCTAssertEqual(TextFile.decode(Data([0xFE,0xFF,0x00,0x54,0x00,0x6F])),"To")
        XCTAssertEqual(TextFile.decode(Data([0xEF,0xBB,0xBF])+Data("Hello".utf8)),"Hello")
        XCTAssertEqual(TextFile.decode(Data("Hello".utf8)),"Hello")
        XCTAssertNil(TextFile.decode(Data([0x00,0x01,0x02,0x03])))
        XCTAssertNil(TextFile.decode(Data("bad\0byte".utf8)))
    }

    func testRestrictionOnlyPdfCanBeRead() {
        XCTAssertTrue(PdfAccess.shouldAccept(wasLocked:false, unlockSucceeded:false))
        XCTAssertTrue(PdfAccess.shouldAccept(wasLocked:true, unlockSucceeded:true))
        XCTAssertFalse(PdfAccess.shouldAccept(wasLocked:true, unlockSucceeded:false))
    }

    func testHighlightUsesTheMainDisplay() {
        let laptop=DisplayFrame(x:-1440,y:0,width:1440,height:900)
        let external=DisplayFrame(x:0,y:0,width:2560,height:1440)
        XCTAssertEqual(HighlightPlacement.primaryHeight([laptop, external]), 1440)
        XCTAssertEqual(HighlightPlacement.primaryHeight([DisplayFrame(x:0,y:0,width:1440,height:900)]), 900)
        XCTAssertNil(HighlightPlacement.primaryHeight([]))
        XCTAssertEqual(HighlightPlacement.appKitOriginY(cgMinY:100, cgHeight:40, primaryHeight:1000), 860)
    }

    func testLinkedDropReadsTheTargetFile() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:dir) }
        let target=dir.appendingPathComponent("notes.txt")
        try "Bring a notebook.".write(to:target,atomically:true,encoding:.utf8)
        let link=dir.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:target)
        let readable=DroppedPath.pathToRead(link.path)
        try XCTAssertEqual(String(contentsOfFile:readable,encoding:.utf8),"Bring a notebook.")
        XCTAssertEqual(URL(fileURLWithPath:readable).lastPathComponent,"notes.txt")
        try XCTAssertEqual(String(contentsOfFile:DroppedPath.pathToRead(target.path),encoding:.utf8),"Bring a notebook.")
    }

    func testLaterTiffPagesAreKeptWhenTheyFit() {
        XCTAssertEqual(ImagePages.extraPages(pageCount:1, extraRoom:7), 0)
        XCTAssertEqual(ImagePages.extraPages(pageCount:5, extraRoom:7), 4)
        XCTAssertEqual(ImagePages.extraPages(pageCount:10, extraRoom:2), 2)
        XCTAssertEqual(ImagePages.extraPages(pageCount:5, extraRoom:0), 0)
    }

    func testSignInCheckFinishes() {
        XCTAssertFalse(SignInCheck.timedOut(elapsed: 14))
        XCTAssertTrue(SignInCheck.timedOut(elapsed: 15))
        XCTAssertEqual(SignInCheck.result(status: 0, output: "Logged in using ChatGPT", timedOut: false), "Signed in with ChatGPT.")
        XCTAssertEqual(SignInCheck.result(status: 0, output: "Logged in", timedOut: false), "Codex is signed in.")
        XCTAssertEqual(SignInCheck.result(status: 1, output: "", timedOut: false), "Not signed in. Run codex login in Terminal.")
        XCTAssertEqual(SignInCheck.result(status: 15, output: "ChatGPT", timedOut: true), "Couldn’t check sign-in. Try again.")
    }

    func testQuestionStillSendsWhenAFileCannotBeRead() {
        let note=AttachmentRead.omission("notes.txt")
        XCTAssertTrue(note.contains("notes.txt"))
        XCTAssertTrue(note.contains("not included"))
        let prompt=TutorPrompt.build(session:LearningSession(title:"Notes"),question:"What does the file say?",hasImage:false,pointing:false,reveal:false,fileContext:note,hasWindow:false)
        XCTAssertTrue(prompt.contains("What does the file say?"))
        XCTAssertTrue(prompt.contains("not included"))
        XCTAssertTrue(prompt.contains("Disabled"))
    }

    func testHistoryWindowComesBackOnScreen() {
        let screen=DisplayRect(x:0,y:0,width:1440,height:900)
        XCTAssertTrue(WindowPlacement.isVisible(DisplayRect(x:100,y:80,width:900,height:650), on:[screen]))
        XCTAssertFalse(WindowPlacement.isVisible(DisplayRect(x:4000,y:80,width:900,height:650), on:[screen]))
        XCTAssertFalse(WindowPlacement.isVisible(DisplayRect(x:1400,y:80,width:900,height:650), on:[screen]))
        XCTAssertTrue(WindowPlacement.isVisible(DisplayRect(x:4000,y:0,width:900,height:650), on:[]))
    }

    func testReadableImageIsKeptWhenPreviewFails() {
        XCTAssertTrue(ImageRead.shouldKeep(preview:false, fullImage:true))
        XCTAssertTrue(ImageRead.shouldKeep(preview:true, fullImage:false))
        XCTAssertFalse(ImageRead.shouldKeep(preview:false, fullImage:false))
    }

    func testPastedPdfIsKeptWhenItIsNotAnImage() {
        XCTAssertTrue(PasteChoice.usePDF(hasFile:false, hasImage:false, hasPDF:true))
        XCTAssertFalse(PasteChoice.usePDF(hasFile:true, hasImage:false, hasPDF:true))
        XCTAssertFalse(PasteChoice.usePDF(hasFile:false, hasImage:true, hasPDF:true))
        XCTAssertFalse(PasteChoice.usePDF(hasFile:false, hasImage:false, hasPDF:false))
    }

    func testUnnamedPDFIsNotRefusedAsText() {
        let header=Data("%PDF-1.4\n%\0\0\0\0".utf8)
        XCTAssertTrue(FileSignature.treatAsPDF(fileExtension:"pdf",data:Data("not a header".utf8),isTextExtension:false))
        XCTAssertTrue(FileSignature.treatAsPDF(fileExtension:"",data:header,isTextExtension:false))
        XCTAssertTrue(FileSignature.treatAsPDF(fileExtension:"bin",data:header,isTextExtension:false))
        XCTAssertFalse(FileSignature.treatAsPDF(fileExtension:"txt",data:header,isTextExtension:true))
        XCTAssertFalse(FileSignature.treatAsPDF(fileExtension:"",data:Data("notes".utf8),isTextExtension:false))
        XCTAssertFalse(FileSignature.treatAsPDF(fileExtension:"png",data:Data([0x89,0x50,0x4E,0x47]),isTextExtension:false))
    }

    func testExportNameKeepsAColonFromSplittingTheFile() {
        XCTAssertEqual(ExportFile.suggestedName(for:"Fix: the login"),"Fix- the login-notes.md")
        XCTAssertEqual(ExportFile.suggestedName(for:"a/b"),"a-b-notes.md")
        XCTAssertEqual(ExportFile.suggestedName(for:"New chat"),"New chat-notes.md")
        XCTAssertEqual(ExportFile.suggestedName(for:"  "),"chat-notes.md")
        XCTAssertFalse(ExportFile.suggestedName(for:"Notes: a/b").contains(":"))
        XCTAssertFalse(ExportFile.suggestedName(for:"Notes: a/b").contains("/"))
    }

    func testLongPointLabelKeepsTheHighlight() throws {
        let label=String(repeating:"A",count:180)
        let kept=try TutorReply.decode(Data(#"{"text":"Look here.","point":{"x":0.2,"y":0.3,"width":0.4,"height":0.05,"label":"\#(label)"}}"#.utf8))
        XCTAssertEqual(kept.point?.label,label)
        XCTAssertEqual(kept.point?.width,0.4)
        let outside=try TutorReply.decode(Data(#"{"text":"No box.","point":{"x":1.2,"y":0.1,"width":0.3,"height":0.1,"label":"\#(label)"}}"#.utf8))
        XCTAssertNil(outside.point)
    }

    func testSavedGuideStepIsFoundInHistory() {
        var chat=LearningSession(title:"Install")
        chat.messages=[Message(role:"assistant",text:"Start with the first action.")]
        chat.guide=GuideProgress(plan:GuidePlan(title:"Install the tool",steps:["Download the package","Open the disk image"]),index:0)
        XCTAssertEqual(chat.guide?.savedSteps,"Install the tool\n1. Download the package (current)\n2. Open the disk image")
        XCTAssertTrue(chat.matches("disk image"))
        XCTAssertFalse(LearningSession(title:"Install").matches("disk image"))
        let exported=SessionStore.export(chat)
        XCTAssertFalse(exported.contains("Open the disk image"))
    }

    func testFollowUpKeepsTheWholeGuidePlan() {
        var chat=LearningSession(title:"Install")
        chat.guide=GuideProgress(plan:GuidePlan(title:"Install the tool",steps:["Download the package","Open the disk image","Move it to Applications"]),index:1)
        let prompt=TutorPrompt.build(session:chat,question:"I finished the first step",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("1. Download the package"))
        XCTAssertTrue(prompt.contains("2. Open the disk image (current)"))
        XCTAssertTrue(prompt.contains("3. Move it to Applications"))
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        let none=TutorPrompt.build(session:LearningSession(title:"Install"),question:"Hi",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(none.contains("Current guide: None"))
        XCTAssertFalse(SessionStore.export(chat).contains("Open the disk image"))
    }

    func testFollowUpHearsWhenTheHighlightWasHidden() {
        let hidden=Message(role:"assistant",text:"The control is in the toolbar.",highlightUnavailable:true)
        let shown=Message(role:"assistant",text:"The control is in the toolbar.",screenChanged:true)
        XCTAssertTrue(ConversationWindow(messages:[hidden]).text.contains("Highlight unavailable. The place could not be shown on the selected window."))
        XCTAssertFalse(ConversationWindow(messages:[shown]).text.contains("Highlight unavailable"))
        var chat=LearningSession(title:"Toolbar")
        chat.messages=[hidden]
        let prompt=TutorPrompt.build(session:chat,question:"Where is it?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Highlight unavailable. The place could not be shown on the selected window."))
        XCTAssertTrue(prompt.contains("Current guide: None"))
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertFalse(SessionStore.export(chat).contains("Highlight unavailable"))
    }

    func testUnreadScanPageIsNotDescribedAsAttached() {
        let full=ScanPages.note(name:"scan.pdf",pageCount:10,rendered:4)
        XCTAssertEqual(full,"\nScanned PDF: scan.pdf. Only the first 4 of 10 pages follow as images. Do not imply access to later pages.\n")
        let none=ScanPages.note(name:"scan.pdf",pageCount:10,rendered:0)
        XCTAssertTrue(none.contains("None of the first 4 of 10 pages could be read as images"))
        XCTAssertFalse(none.contains("follow as images"))
        let partial=ScanPages.note(name:"scan.pdf",pageCount:10,rendered:2)
        XCTAssertTrue(partial.contains("2 of the first 4 of 10 pages follow as images"))
        XCTAssertTrue(partial.contains("Do not invent unseen pages"))
        let prompt=TutorPrompt.build(session:LearningSession(title:"Scan"),question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Current guide: None"))
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
    }

    func testRichTextKeepsTheWordsWithoutNullBytes() {
        XCTAssertEqual(RichText.textToStore("Bring the notes"),"Bring the notes")
        XCTAssertEqual(RichText.textToStore(""),"")
        XCTAssertNil(RichText.textToStore(nil))
        XCTAssertNil(RichText.textToStore("Bring\0the notes"))
        let prompt=TutorPrompt.build(session:LearningSession(title:"Notes"),question:"Read this",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Current guide: None"))
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
    }

    func testNamedTextFileIsNotReadAsAnImage() {
        XCTAssertTrue(TextFileRoute.readBeforeImage(fileExtension:"swift",isTextExtension:true))
        XCTAssertTrue(TextFileRoute.readBeforeImage(fileExtension:"md",isTextExtension:true))
        XCTAssertTrue(TextFileRoute.readBeforeImage(fileExtension:"txt",isTextExtension:true))
        XCTAssertFalse(TextFileRoute.readBeforeImage(fileExtension:"png",isTextExtension:false))
        XCTAssertFalse(TextFileRoute.readBeforeImage(fileExtension:"",isTextExtension:false))
        XCTAssertEqual(TextFileRoute.stored("func main() {}"),"func main() {}")
        XCTAssertNil(TextFileRoute.stored("func\0main()"))
        let prompt=TutorPrompt.build(session:LearningSession(title:"Code"),question:"Read this",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Current guide: None"))
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
    }

    func testSVGDrawingIsReadableText() {
        XCTAssertTrue(TextKind.extensions.contains("svg"))
        XCTAssertTrue(TextKind.extensions.contains("rtf"))
        XCTAssertTrue(TextKind.extensions.contains("swift"))
        XCTAssertFalse(TextKind.extensions.contains("png"))
        XCTAssertFalse(TextKind.extensions.contains(""))
        XCTAssertFalse(TextKind.extensions.contains("pdf"))
        XCTAssertTrue(TextKind.keeps("<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>"))
        XCTAssertFalse(TextKind.keeps("<svg>\0</svg>"))
        let prompt=TutorPrompt.build(session:LearningSession(title:"Diagram"),question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Current guide: None"))
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
    }

    func testOpeningAPreviewKeepsTheFileYouAreReading() {
        XCTAssertEqual(PreviewRoom.indexToClose(existing:[.screen,.screen,.screen],adding:.screen),0)
        XCTAssertEqual(PreviewRoom.indexToClose(existing:[.file,.file,.screen],adding:.screen),2)
        XCTAssertNil(PreviewRoom.indexToClose(existing:[.file,.file,.file],adding:.screen))
        XCTAssertNil(PreviewRoom.indexToClose(existing:[.screen,.screen,.screen],adding:.file))
        XCTAssertNil(PreviewRoom.indexToClose(existing:[.screen,.screen],adding:.screen))
        let prompt=TutorPrompt.build(session:LearningSession(title:"Notes"),question:"Read this",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Current guide: None"))
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
    }

    func testTypedGuideRequestKeepsAPlan() {
        XCTAssertTrue(GuideRequest.explicit("Guide me through the installer"))
        XCTAssertTrue(GuideRequest.explicit("Explain this step by step"))
        XCTAssertTrue(GuideRequest.explicit("Walk it step-by-step"))
        XCTAssertFalse(GuideRequest.explicit("What is this button?"))
        XCTAssertFalse(GuidePlan(title:"Only",steps:["One step"]).isValid)
        let typed=TutorPrompt.build(session:LearningSession(title:"Install"),question:"Guide me through the installer",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(typed.contains("explicitly requested a step-by-step guide"))
        XCTAssertTrue(typed.contains("Current guide: None"))
        XCTAssertTrue(typed.contains("Web search: Disabled"))
        let ordinary=TutorPrompt.build(session:LearningSession(title:"Install"),question:"What is this button?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(ordinary.contains("Return null for guide"))
    }

    func testAttachedImageIsNumberedAfterTheWindow() {
        XCTAssertEqual(ImageOrder.line(name:"photo.png",placedBefore:1,fileImagesSoFar:1),"\nImage 2 (after any shared-window image): photo.png.\n")
        XCTAssertEqual(ImageOrder.line(name:"photo.png",placedBefore:0,fileImagesSoFar:1),"\nImage 1 (after any shared-window image): photo.png.\n")
        XCTAssertEqual(ImageOrder.line(name:"second.png",placedBefore:1,fileImagesSoFar:2),"\nImage 3 (after any shared-window image): second.png.\n")
        let prompt=TutorPrompt.build(session:LearningSession(title:"Window"),question:"What is this?",hasImage:true,pointing:false,reveal:false,hasWindow:true)
        XCTAssertTrue(prompt.contains("Current guide: None"))
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("Return null for guide"))
    }

    func testGuideStepStaysWhenTheQuestionDoesNotStart() {
        XCTAssertEqual(GuideStep.indexToSave(current:0,requested:1,questionStarts:false),0)
        XCTAssertEqual(GuideStep.indexToSave(current:1,requested:2,questionStarts:true),2)
        XCTAssertFalse(GuidePlan(title:"Only",steps:["One step"]).isValid)
        let ordinary=TutorPrompt.build(session:LearningSession(title:"Install"),question:"What is this button?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(ordinary.contains("Return null for guide"))
        XCTAssertTrue(ordinary.contains("Current guide: None"))
        XCTAssertTrue(ordinary.contains("Web search: Disabled"))
    }

    func testFollowUpHearsWhenTheWindowChanged() {
        let changed=Message(role:"assistant",text:"Use the toolbar.",screenChanged:true)
        let hidden=Message(role:"assistant",text:"Use the toolbar.",highlightUnavailable:true)
        let plain=Message(role:"assistant",text:"Use the toolbar.")
        XCTAssertTrue(ConversationWindow(messages:[changed]).text.contains("The shared window changed while this answer was prepared."))
        XCTAssertFalse(ConversationWindow(messages:[changed]).text.contains("Highlight unavailable"))
        XCTAssertFalse(ConversationWindow(messages:[hidden]).text.contains("shared window changed"))
        XCTAssertFalse(ConversationWindow(messages:[plain]).text.contains("shared window changed"))
        var chat=LearningSession(title:"Toolbar")
        chat.messages=[changed]
        let prompt=TutorPrompt.build(session:chat,question:"What should I do now?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("The shared window changed while this answer was prepared."))
        XCTAssertTrue(prompt.contains("Return null for guide"))
        XCTAssertTrue(prompt.contains("Current guide: None"))
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertFalse(GuidePlan(title:"Only",steps:["One step"]).isValid)
        XCTAssertFalse(SessionStore.export(chat).contains("shared window changed"))
    }

    func testEndedGuideIsNotRestoredByTheAnswer() {
        XCTAssertTrue(GuideInstall.shouldInstall(requested:true,windowChanged:false,stillCurrent:true))
        XCTAssertFalse(GuideInstall.shouldInstall(requested:true,windowChanged:false,stillCurrent:false))
        XCTAssertFalse(GuideInstall.shouldInstall(requested:true,windowChanged:true,stillCurrent:true))
        XCTAssertFalse(GuideInstall.shouldInstall(requested:false,windowChanged:false,stillCurrent:true))
        XCTAssertFalse(GuidePlan(title:"Only",steps:["One step"]).isValid)
        let ordinary=TutorPrompt.build(session:LearningSession(title:"Install"),question:"What is this button?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(ordinary.contains("Return null for guide"))
        XCTAssertTrue(ordinary.contains("Current guide: None"))
        XCTAssertTrue(ordinary.contains("Web search: Disabled"))
    }

    func testRefreshOfPointItOutStillPoints() {
        XCTAssertTrue(PointRequest.wasPointing(PointRequest.prompt))
        XCTAssertFalse(PointRequest.wasPointing("What is this button?"))
        let again=TutorPrompt.build(session:LearningSession(title:"Window"),question:PointRequest.prompt,hasImage:true,pointing:true,reveal:false,hasWindow:true)
        XCTAssertTrue(again.contains("Pointing requested: Yes"))
        let ordinary=TutorPrompt.build(session:LearningSession(title:"Window"),question:"What is this button?",hasImage:true,pointing:PointRequest.wasPointing("What is this button?"),reveal:false,hasWindow:true)
        XCTAssertTrue(ordinary.contains("Pointing requested: No"))
        XCTAssertTrue(ordinary.contains("Return null for guide"))
        XCTAssertTrue(ordinary.contains("Current guide: None"))
        XCTAssertTrue(ordinary.contains("Web search: Disabled"))
        XCTAssertFalse(GuidePlan(title:"Only",steps:["One step"]).isValid)
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testLongAnswerLineKeepsEveryCharacter() {
        let token=String(repeating:"A",count:41)
        let shown=ReadableLine.display(token)
        XCTAssertEqual(shown.replacingOccurrences(of:"\u{200B}",with:""),token)
        XCTAssertTrue(shown.contains("\u{200B}"))
        XCTAssertEqual(ReadableLine.display("short line"),"short line")
        let url="https://example.com/"+String(repeating:"a",count:50)
        XCTAssertFalse(ReadableLine.display(url).contains("\u{200B}"))
        XCTAssertEqual(ReadableLine.display("see "+token).hasPrefix("see "),true)
        let prompt=TutorPrompt.build(session:LearningSession(title:"Code"),question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Return null for guide"))
        XCTAssertTrue(prompt.contains("Current guide: None"))
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertFalse(GuidePlan(title:"Only",steps:["One step"]).isValid)
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testJpegPasteAttachesWhenThereIsNoText() {
        let jpeg=Data([0xFF,0xD8,0xFF,0xD9])
        XCTAssertEqual(ClipboardImage.attachableJPEG(jpeg:jpeg,plainText:nil),jpeg)
        XCTAssertNil(ClipboardImage.attachableJPEG(jpeg:jpeg,plainText:"keep these words"))
        XCTAssertNil(ClipboardImage.attachableJPEG(jpeg:Data(),plainText:nil))
        XCTAssertNil(ClipboardImage.attachableJPEG(jpeg:nil,plainText:nil))
        let chat=LearningSession(title:"Photo")
        XCTAssertFalse(chat.webEnabled)
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
        let point=TutorPrompt.build(session:chat,question:"Point out the relevant part of the shared window, with one short explanation.",hasImage:true,pointing:true,reveal:false,hasWindow:true)
        XCTAssertTrue(point.contains("Pointing requested: Yes."))
    }

    func testDraftEchoIsNotTyping() {
        XCTAssertFalse(DraftEcho.isTyping("hello",stored:"hello"))
        XCTAssertTrue(DraftEcho.isTyping("hello!",stored:"hello"))
        XCTAssertTrue(DraftEcho.isTyping("",stored:"hello"))
        let chat=LearningSession(title:"New chat")
        XCTAssertFalse(chat.webEnabled)
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testNewestFileIsReadBeforeOlderOnes() {
        let older=AttachmentRecord(name:"Notes.md",kind:.text,byteCount:20)
        let newer=AttachmentRecord(name:"Error.log",kind:.text,byteCount:20)
        let image=AttachmentRecord(name:"Shot.png",kind:.image,byteCount:20)
        XCTAssertEqual(FileBudget.ordered([older,image,newer],newest:[newer.id,image.id]).map(\.name),["Shot.png","Error.log","Notes.md"])
        XCTAssertEqual(FileBudget.ordered([older,newer],newest:[older.id,newer.id]).map(\.name),["Notes.md","Error.log"])
        XCTAssertEqual(FileBudget.ordered([older,newer],newest:[newer.id,UUID()]).map(\.name),["Error.log","Notes.md"])
        XCTAssertEqual(FileBudget.ordered([older,newer],newest:[]).map(\.name),["Notes.md","Error.log"])
        let chat=LearningSession(title:"New chat")
        XCTAssertFalse(chat.webEnabled)
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testDroppedWebLinkBecomesDraftText() {
        let page=URL(string:"https://example.com/notes")!
        let secure=URL(string:"http://example.com/a")!
        XCTAssertEqual(DroppedLink.text(from:[page,secure]),"https://example.com/notes\nhttp://example.com/a")
        XCTAssertEqual(DroppedLink.inserted(into:"", links:"https://example.com/notes"),"https://example.com/notes")
        XCTAssertEqual(DroppedLink.inserted(into:"What is this?", links:"https://example.com/notes"),"What is this?\nhttps://example.com/notes")
        XCTAssertEqual(DroppedLink.inserted(into:"What is this?\n", links:"https://example.com/notes"),"What is this?\nhttps://example.com/notes")
        XCTAssertNil(DroppedLink.text(from:[URL(fileURLWithPath:"/tmp/Notes.md")]))
        XCTAssertNil(DroppedLink.text(from:[URL(string:"javascript:alert(1)")!]))
        XCTAssertNil(DroppedLink.text(from:[]))
        let chat=LearningSession(title:"New chat")
        XCTAssertFalse(chat.webEnabled)
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testObjectiveCSourceIsText() {
        XCTAssertTrue(SourceFile.extensions.contains("m"))
        XCTAssertTrue(SourceFile.extensions.contains("mm"))
        XCTAssertTrue(SourceFile.extensions.contains("h"))
        XCTAssertTrue(SourceFile.extensions.contains("swift"))
        XCTAssertTrue(SourceFile.extensions.contains("rtf"))
        XCTAssertFalse(SourceFile.extensions.contains("svg"))
        XCTAssertFalse(SourceFile.extensions.contains("png"))
        XCTAssertFalse(SourceFile.extensions.contains(""))
        XCTAssertTrue(SourceFile.isReadable("- (void)hello {}"))
        XCTAssertFalse(SourceFile.isReadable("int x;\0"))
        let chat=LearningSession(title:"New chat")
        XCTAssertFalse(chat.webEnabled)
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testSavedDraftCaretStaysAtTheEnd() {
        XCTAssertEqual(DraftCaret.location(previousUTF16:0,nextUTF16:11,caret:0),11)
        XCTAssertEqual(DraftCaret.location(previousUTF16:5,nextUTF16:11,caret:5),11)
        XCTAssertEqual(DraftCaret.location(previousUTF16:5,nextUTF16:11,caret:2),2)
        XCTAssertEqual(DraftCaret.location(previousUTF16:5,nextUTF16:0,caret:5),0)
        XCTAssertEqual(DraftCaret.location(previousUTF16:2,nextUTF16:4,caret:0),0)
        let chat=LearningSession(title:"New chat")
        XCTAssertFalse(chat.webEnabled)
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testSharedWindowUsesPlainBitmapWhenPNGFails() {
        let png=Data([0x89,0x50,0x4E,0x47])
        let plain=Data([1,2,3,4])
        XCTAssertEqual(WindowImage.png(primary:png,flattened:plain),png)
        XCTAssertEqual(WindowImage.png(primary:nil,flattened:plain),plain)
        XCTAssertEqual(WindowImage.png(primary:Data(),flattened:plain),plain)
        XCTAssertNil(WindowImage.png(primary:nil,flattened:nil))
        XCTAssertNil(WindowImage.png(primary:Data(),flattened:Data()))
        let chat=LearningSession(title:"New chat")
        XCTAssertFalse(chat.webEnabled)
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:true,pointing:false,reveal:false,hasWindow:true)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testSearchFindsEveryWord() {
        var chat=LearningSession(title:"Weekend plan")
        chat.messages=[Message(role:"user",text:"Where is the harbor?"),Message(role:"assistant",text:"Bring a notebook.")]
        chat.draft="secret draft words"
        XCTAssertTrue(chat.matches("weekend notebook"))
        XCTAssertTrue(chat.matches("HARBOR plan"))
        XCTAssertFalse(chat.matches("weekend missing"))
        XCTAssertFalse(chat.matches("secret draft"))
        XCTAssertTrue(chat.matches("  "))
        let fresh=LearningSession(title:"New chat")
        XCTAssertFalse(fresh.webEnabled)
        let prompt=TutorPrompt.build(session:fresh,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testEveryFailedFileIsReported() {
        XCTAssertEqual(ImportReport.summary(["notes.txt: Choose a file under 25 MB."]),"notes.txt: Choose a file under 25 MB.")
        XCTAssertEqual(ImportReport.summary(["notes.txt: Choose a file under 25 MB.","clip.zip: This file type isn’t supported yet."]),"notes.txt: Choose a file under 25 MB.\nclip.zip: This file type isn’t supported yet.")
        XCTAssertNil(ImportReport.summary([]))
        XCTAssertNil(ImportReport.summary([" ","\n"]))
        let chat=LearningSession(title:"New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testDroppedFileKeepsReadAccess() {
        XCTAssertTrue(ScopedRead.needsAccess(isFileURL:true))
        XCTAssertFalse(ScopedRead.needsAccess(isFileURL:false))
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testHTMLPasteKeepsTheWords() {
        XCTAssertEqual(ClipboardHTML.text(html:"<p>Hello <b>there</b></p>",plain:nil),"Hello there")
        XCTAssertEqual(ClipboardHTML.text(html:"a&amp;b",plain:" "),"a&b")
        XCTAssertEqual(ClipboardHTML.text(html:"<script>alert(1)</script><p>Keep</p>",plain:nil),"Keep")
        XCTAssertNil(ClipboardHTML.text(html:"<p>Hidden</p>",plain:"Keep these words"))
        XCTAssertNil(ClipboardHTML.text(html:"<style>p{}</style>",plain:nil))
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testMicIntakeClosesBeforeTheRequestEnds() {
        let intake=MicIntake()
        XCTAssertFalse(intake.isAccepting)
        intake.allow()
        XCTAssertTrue(intake.isAccepting)
        intake.stop()
        XCTAssertFalse(intake.isAccepting)
        intake.stop()
        XCTAssertFalse(intake.isAccepting)
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testPDFWorkHopsToTheMainThread() {
        XCTAssertFalse(MainThread.mustHop(isMainThread:true))
        XCTAssertTrue(MainThread.mustHop(isMainThread:false))
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testFinderAliasReadsTheTargetFile() {
        let original=URL(fileURLWithPath:"/Users/vale/Desktop/Notes alias")
        let resolved=URL(fileURLWithPath:"/Users/vale/Notes.txt")
        XCTAssertEqual(AliasFile.urlToRead(original:original,resolved:resolved,isAlias:true),resolved)
        XCTAssertEqual(AliasFile.urlToRead(original:original,resolved:resolved,isAlias:false),original)
        XCTAssertEqual(AliasFile.urlToRead(original:original,resolved:nil,isAlias:true),original)
        XCTAssertFalse(AliasFile.shouldResolve(isAlias:false))
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testTypedWordsAreNotCorrected() {
        XCTAssertFalse(TypedText.correctsSpelling)
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testChatHeadingUsesTheFirstLine() {
        XCTAssertEqual(ChatHeading.from("Summary\r\nThe rest of the question"),"Summary")
        XCTAssertEqual(ChatHeading.from("Hello\rWorld"),"Hello")
        XCTAssertEqual(ChatHeading.from("One\nTwo"),"One")
        XCTAssertEqual(ChatHeading.from("Hello\u{2028}there"),"Hello")
        XCTAssertEqual(ChatHeading.from("Hello world"),"Hello world")
        XCTAssertEqual(ChatHeading.from(String(repeating:"A",count:70)),String(repeating:"A",count:60))
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testSpeechLocaleDropsTheExtraSuffix() {
        XCTAssertEqual(SpeechLocale.identifier(preferred:"",current:"en_US@rg=uszzzz"),"en-US")
        XCTAssertEqual(SpeechLocale.identifier(preferred:"  ",current:"fr_FR@calendar=gregorian"),"fr-FR")
        XCTAssertEqual(SpeechLocale.identifier(preferred:"fr_CA",current:"en_US"),"fr-CA")
        XCTAssertEqual(SpeechLocale.identifier(preferred:"en-US",current:"de_DE"),"en-US")
        XCTAssertEqual(SpeechLocale.identifier(preferred:"",current:""),"en-US")
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testMicFormatIsReadAfterPrepare() {
        XCTAssertTrue(MicFormat.canUse(sampleRate:48_000,channels:1))
        XCTAssertFalse(MicFormat.canUse(sampleRate:0,channels:1))
        XCTAssertFalse(MicFormat.canUse(sampleRate:48_000,channels:0))
        XCTAssertFalse(MicFormat.canUse(sampleRate:.nan,channels:2))
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testPasteDoesNotAdjustSpaces() {
        XCTAssertFalse(PasteSpacing.adjustsAutomatically)
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testCaptureSizeStaysEven() {
        XCTAssertEqual(CaptureSize.even(100),100)
        XCTAssertEqual(CaptureSize.even(101),100)
        XCTAssertEqual(CaptureSize.even(3),2)
        XCTAssertEqual(CaptureSize.even(2),2)
        XCTAssertEqual(CaptureSize.even(0),2)
        XCTAssertEqual(CaptureSize.even(.nan),2)
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testOptionReturnDoesNotSend() {
        XCTAssertTrue(LineBreak.sends(shift:false,option:false,marked:false))
        XCTAssertFalse(LineBreak.sends(shift:true,option:false,marked:false))
        XCTAssertFalse(LineBreak.sends(shift:false,option:true,marked:false))
        XCTAssertFalse(LineBreak.sends(shift:false,option:false,marked:true))
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testWordCompletionDoesNotInsert() {
        XCTAssertFalse(WordCompletion.insertsSuggestions)
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testRecognitionStartsAfterEngine() {
        XCTAssertTrue(RecognitionStart.canListen(engineRunning:true))
        XCTAssertFalse(RecognitionStart.canListen(engineRunning:false))
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testAnswerOpensMailLink() {
        XCTAssertTrue(AnswerLink.canOpen(URL(string:"https://example.com")!))
        XCTAssertTrue(AnswerLink.canOpen(URL(string:"HTTP://example.com")!))
        XCTAssertTrue(AnswerLink.canOpen(URL(string:"mailto:ada@example.com")!))
        XCTAssertFalse(AnswerLink.canOpen(URL(string:"file:///tmp/secret")!))
        XCTAssertFalse(AnswerLink.canOpen(URL(string:"javascript:alert(1)")!))
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testPasteKeepsWebAddress() {
        XCTAssertEqual(ClipboardAddress.text(plain:nil,urls:[URL(string:"https://example.com/a")!]),"https://example.com/a")
        XCTAssertEqual(ClipboardAddress.text(plain:"  ",urls:[URL(string:"mailto:ada@example.com")!]),"mailto:ada@example.com")
        XCTAssertNil(ClipboardAddress.text(plain:"hello",urls:[URL(string:"https://example.com")!]))
        XCTAssertNil(ClipboardAddress.text(plain:nil,urls:[URL(string:"file:///tmp/secret")!]))
        XCTAssertNil(ClipboardAddress.text(plain:nil,urls:[URL(string:"javascript:alert(1)")!]))
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testWordDocumentKeepsText() {
        XCTAssertTrue(WordFile.isDocument("docx"))
        XCTAssertFalse(WordFile.isDocument("pdf"))
        XCTAssertFalse(WordFile.isDocument("txt"))
        XCTAssertEqual(WordFile.text("Hello\u{0}  world"),"Hello  world")
        XCTAssertNil(WordFile.text(" \n\u{0}"))
        XCTAssertNil(WordFile.text(""))
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testEscapeLeavesAnOpenDialog() {
        XCTAssertFalse(EscapeKey.stopsSession(dialogOpen:true))
        XCTAssertTrue(EscapeKey.stopsSession(dialogOpen:false))
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testEmptyGreetingSitsWithTheComposer() {
        XCTAssertTrue(EmptyCoach.greetingAnchoredToComposer)
        XCTAssertEqual(EmptyCoach.kickerSize, 11)
        XCTAssertEqual(EmptyCoach.bodySize, 15)
        XCTAssertEqual(EmptyCoach.blockSpacing, 16)
        XCTAssertTrue(EmptyCoach.sitsWithComposer(messageCount: 0))
        XCTAssertFalse(EmptyCoach.sitsWithComposer(messageCount: 1))
        var chat=LearningSession(title:"New chat")
        XCTAssertTrue(EmptyCoach.sitsWithComposer(messageCount: chat.messages.count))
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testAttachControlShowsItsName() {
        XCTAssertEqual(AttachControl.title, "Attach")
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testCapsuleMicStaysQuietUntilUsed() {
        XCTAssertTrue(CapsuleMic.idleIsQuiet(listening:false,speaking:false,busy:false))
        XCTAssertFalse(CapsuleMic.idleIsQuiet(listening:true,speaking:false,busy:false))
        XCTAssertFalse(CapsuleMic.idleIsQuiet(listening:false,speaking:true,busy:false))
        XCTAssertFalse(CapsuleMic.idleIsQuiet(listening:false,speaking:false,busy:true))
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testEmptyFieldPromptSitsOnTheCaret() {
        XCTAssertEqual(ComposerPrompt.words, "Ask quietly…")
        XCTAssertEqual(ComposerPrompt.opacity, 1)
        XCTAssertTrue(ComposerPrompt.usesMediumWeight)
        XCTAssertEqual(ComposerPrompt.topInset, 5)
        XCTAssertEqual(ComposerPrompt.leadingInset, 7)
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testShareControlLooksPressable() {
        XCTAssertEqual(ShareControl.title, "Share a window")
        XCTAssertTrue(ShareControl.showsAsButton)
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testCapsuleTitleMatchesTheCoach() {
        XCTAssertEqual(CapsuleTitle.size, 15)
        XCTAssertTrue(CapsuleTitle.usesSemibold)
        var chat=LearningSession(title:"New chat")
        XCTAssertEqual(chat.title, "New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testComposerRowsLeaveRoomUnderTheLine() {
        XCTAssertEqual(ComposerRows.spacing, 10)
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testConversationControlLooksPressable() {
        XCTAssertTrue(ConversationControl.showsAsButton)
        XCTAssertEqual(ConversationControl.title(on: false), "Start conversation")
        XCTAssertEqual(ConversationControl.title(on: true), "End conversation")
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testIdleWaveStaysQuietUntilVoice() {
        XCTAssertFalse(IdleWave.usesAccent(active: false))
        XCTAssertTrue(IdleWave.usesAccent(active: true))
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testSendSitsOnTheTypedLine() {
        XCTAssertTrue(SendPlacement.onTheTypedLine)
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testSendControlLooksReady() {
        XCTAssertFalse(SendMark.filled(hasInput: false, busy: false, hasChat: true, importing: false))
        XCTAssertTrue(SendMark.filled(hasInput: true, busy: false, hasChat: true, importing: false))
        XCTAssertTrue(SendMark.filled(hasInput: false, busy: true, hasChat: true, importing: false))
        XCTAssertFalse(SendMark.filled(hasInput: true, busy: false, hasChat: false, importing: false))
        XCTAssertFalse(SendMark.filled(hasInput: true, busy: false, hasChat: true, importing: true))
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
    }

    func testFocusTimerStaysInLearn() {
        XCTAssertFalse(FocusTimer.shows(mode: .assistant, running: false))
        XCTAssertTrue(FocusTimer.shows(mode: .learn, running: false))
        XCTAssertTrue(FocusTimer.shows(mode: .assistant, running: true))
        let chat = LearningSession(title: "New chat")
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(FocusTimer.shows(mode: chat.mode, running: chat.duration > 0))
        XCTAssertFalse(chat.webEnabled)
    }

    func testMicrophoneSitsWithTheTools() {
        XCTAssertTrue(MicPlacement.withTheTools)
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testEmptyThreadSaysWhereTheReplyShows() {
        XCTAssertTrue(EmptyThread.showsPlace)
        XCTAssertEqual(EmptyThread.line, "Your question and the reply show here.")
        var chat=LearningSession(title:"New chat")
        XCTAssertTrue(chat.messages.isEmpty)
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testCoachDismissIsNotAQuitMark() {
        XCTAssertEqual(CoachDismiss.symbol, "chevron.down")
        XCTAssertFalse(CoachDismiss.symbol == "xmark")
        XCTAssertEqual(CoachDismiss.label, "Collapse coach")
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testPauseLivesInTheMenu() {
        XCTAssertTrue(CapsulePause.inTheMenu)
        XCTAssertEqual(CapsulePause.title(paused: false), "Pause")
        XCTAssertEqual(CapsulePause.title(paused: true), "Resume")
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testGuideControlLeavesTheComposer() {
        XCTAssertTrue(GuideControl.inTheMenu)
        XCTAssertEqual(GuideControl.title, "Start step-by-step help")
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testChatListUsesAConversationMark() {
        XCTAssertEqual(HistoryMark.symbol, "bubble.left.and.bubble.right")
        XCTAssertFalse(HistoryMark.symbol == "rectangle.stack")
        XCTAssertEqual(HistoryMark.label, "Chat history")
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testShareRowFollowsTheComposer() {
        XCTAssertTrue(ShareRow.afterTheComposer)
        var chat=LearningSession(title:"New chat")
        chat.draft="secret draft"
        XCTAssertFalse(chat.webEnabled)
        XCTAssertFalse(chat.matches("secret"))
        XCTAssertFalse(chat.matches("missing"))
        let prompt=TutorPrompt.build(session:chat,question:"What is this?",hasImage:false,pointing:false,reveal:false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertTrue(prompt.contains("No. Return null for point."))
        XCTAssertFalse(PointTarget(x:1.2,y:0.1,width:0.2,height:0.1,label:"Edge").isValid)
    }

    func testModeChoiceLeavesTheHeader() {
        XCTAssertTrue(ModePlace.inTheMenu)
        XCTAssertEqual(ModePlace.assistantTitle, "Assistant")
        XCTAssertEqual(ModePlace.learnTitle, "Learn with hints")
        XCTAssertEqual(ChatMode.assistant.label, "Assistant")
        let chat = LearningSession(title: "New chat")
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(chat.webEnabled)
        let prompt = TutorPrompt.build(session: chat, question: "What is this?", hasImage: false, pointing: false, reveal: false)
        XCTAssertTrue(prompt.contains("Web search: Disabled"))
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testCapsuleSitsOnTheCoach() {
        XCTAssertTrue(CapsuleSeat.onTheCoach)
        XCTAssertEqual(CapsuleSeat.gap, 8)
        let seated = CapsuleSeat.y(coachMaxY: 24 + 480, capsuleHeight: 62, visibleMaxY: 900)
        XCTAssertEqual(seated, 24 + 480 + 8)
        let grown = CapsuleSeat.y(coachMaxY: 24 + 700, capsuleHeight: 62, visibleMaxY: 900)
        XCTAssertEqual(grown, 24 + 700 + 8)
        let tight = CapsuleSeat.y(coachMaxY: 24 + 480, capsuleHeight: 62, visibleMaxY: 500)
        XCTAssertEqual(tight, 500 - 82)
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testCapsuleNameLeadsTheBars() {
        XCTAssertTrue(CapsuleFace.nameLeads)
        XCTAssertEqual(CapsuleFace.order(hasTimer: false, hasWindow: false), ["name", "bars"])
        XCTAssertEqual(CapsuleFace.order(hasTimer: true, hasWindow: true), ["name", "timer", "bars", "window"])
        XCTAssertEqual(CapsuleFace.order(hasTimer: false, hasWindow: false).first, "name")
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testYourTurnSitsOnTheTrailingSide() {
        XCTAssertTrue(SpeakerTurn.yoursTrails)
        XCTAssertTrue(SpeakerTurn.trails("user"))
        XCTAssertFalse(SpeakerTurn.trails("assistant"))
        XCTAssertEqual(SpeakerTurn.leadingClearance, 48)
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testSentFileStaysWithTheQuestion() {
        var chat = LearningSession(title: "New chat")
        let file = AttachmentRecord(name: "notes.txt", kind: .text, byteCount: 20, detail: "text")
        XCTAssertTrue(SentFile.canRemove(id: file.id, session: chat))
        chat.messages = [Message(role: "user", text: "What is this?", attachments: [file])]
        XCTAssertFalse(SentFile.canRemove(id: file.id, session: chat))
        XCTAssertEqual(chat.messages[0].attachments.count, 1)
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testReplyKeepsItsLines() {
        XCTAssertEqual(ReplyLines.forDisplay("Check the left panel.\nThen press Save."), "Check the left panel.\\\nThen press Save.")
        XCTAssertEqual(ReplyLines.forDisplay("First.\n\nSecond."), "First.\n\nSecond.")
        let fenced = "```\nline1\nline2\n```"
        XCTAssertEqual(ReplyLines.forDisplay(fenced), fenced)
        XCTAssertEqual(ReplyLines.forDisplay("One line."), "One line.")
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testReplyShowsTheAddress() {
        XCTAssertEqual(ReplyAddress.forDisplay("See [the guide](https://example.com/guide)."), "See [the guide (https://example.com/guide)](https://example.com/guide).")
        XCTAssertEqual(ReplyAddress.forDisplay("See [https://example.com](https://example.com)."), "See [https://example.com](https://example.com).")
        XCTAssertEqual(ReplyAddress.forDisplay("Write [me](mailto:a@b.com)."), "Write [me (a@b.com)](mailto:a@b.com).")
        XCTAssertEqual(ReplyAddress.forDisplay("Line one.\n[docs](https://ex.com)\n"), "Line one.\n[docs (https://ex.com)](https://ex.com)\n")
        let fenced = "```\n[the guide](https://example.com)\n```"
        XCTAssertEqual(ReplyAddress.forDisplay(fenced), fenced)
        XCTAssertEqual(ReplyAddress.forDisplay("Use `[the guide](https://example.com)` here."), "Use `[the guide](https://example.com)` here.")
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testReplyCodeStaysABlock() {
        let parts = ReplyCode.segments("Run this:\n```\nswift test\n```\nThen stop.")
        XCTAssertEqual(parts.count, 3)
        XCTAssertFalse(parts[0].code)
        XCTAssertEqual(parts[0].text, "Run this:\n")
        XCTAssertTrue(parts[1].code)
        XCTAssertEqual(parts[1].text, "swift test\n")
        XCTAssertFalse(parts[2].code)
        XCTAssertEqual(parts[2].text, "Then stop.")
        let tagged = ReplyCode.segments("```swift\nlet x = 1\n```")
        XCTAssertEqual(tagged.count, 1)
        XCTAssertTrue(tagged[0].code)
        XCTAssertEqual(tagged[0].text, "let x = 1\n")
        let plain = ReplyCode.segments("Check the left panel.\nThen press Save.")
        XCTAssertEqual(plain.count, 1)
        XCTAssertFalse(plain[0].code)
        XCTAssertEqual(plain[0].text, "Check the left panel.\nThen press Save.")
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testReplyWaitSitsInTheThread() {
        XCTAssertTrue(ReplyWait.inTheThread)
        XCTAssertEqual(ReplyWait.speaker, "LILT")
        var chat = LearningSession(title: "New chat")
        chat.messages = [Message(role: "user", text: "What is this?")]
        XCTAssertEqual(chat.messages.last?.role, "user")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testReplyShowsItIsBeingRead() {
        XCTAssertFalse(ReplyPlayback.reading(message: "The answer.", spoken: nil, speaking: false))
        XCTAssertFalse(ReplyPlayback.reading(message: "The answer.", spoken: "The answer.", speaking: false))
        XCTAssertFalse(ReplyPlayback.reading(message: "Other.", spoken: "The answer.", speaking: true))
        XCTAssertTrue(ReplyPlayback.reading(message: "The answer.", spoken: "The answer.", speaking: true))
        XCTAssertFalse(ReplyPlayback.reading(message: "", spoken: "", speaking: true))
        let linked = "See [the docs](https://example.com/docs)"
        XCTAssertTrue(ReplyPlayback.reading(message: linked, spoken: SpokenReply.text(from: linked), speaking: true))
        XCTAssertFalse(ReplyPlayback.reading(message: linked, spoken: SpokenReply.text(from: "Other"), speaking: true))
        XCTAssertEqual(ReplyPlayback.symbol(reading: false), "speaker.wave.2")
        XCTAssertEqual(ReplyPlayback.symbol(reading: true), "stop.fill")
        XCTAssertEqual(ReplyPlayback.label(reading: false), "Read")
        XCTAssertEqual(ReplyPlayback.label(reading: true), "Stop reading")
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
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

    func testSentPictureShowsInTheExchange() {
        XCTAssertTrue(SentPicture.shownInTheExchange)
        XCTAssertEqual(SentPicture.maxHeight, 160)
        let picture = AttachmentRecord(name: "Pasted image.png", kind: .image, byteCount: 12, detail: "image")
        let note = AttachmentRecord(name: "notes.txt", kind: .text, byteCount: 12, detail: "text")
        XCTAssertTrue(SentPicture.shows(picture))
        XCTAssertFalse(SentPicture.shows(note))
        var chat = LearningSession(title: "New chat")
        chat.messages = [Message(role: "user", text: "What is this?", attachments: [picture])]
        XCTAssertEqual(chat.messages[0].attachments.first?.kind, .image)
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testReplyIsItsOwnTurn() {
        XCTAssertTrue(ReplyTurn.ruled("assistant"))
        XCTAssertFalse(ReplyTurn.ruled("user"))
        XCTAssertEqual(ReplyTurn.ruleWidth, 3)
        XCTAssertEqual(ReplyTurn.inset, 11)
        var chat = LearningSession(title: "New chat")
        chat.messages = [Message(role: "user", text: "What is this?"), Message(role: "assistant", text: "Here is the answer.")]
        XCTAssertEqual(chat.messages.last?.role, "assistant")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testExchangeSitsWithTheComposer() {
        XCTAssertTrue(ThreadSeat.withTheComposer)
        XCTAssertFalse(ThreadSeat.pins(0))
        XCTAssertTrue(ThreadSeat.pins(1))
        var chat = LearningSession(title: "New chat")
        XCTAssertFalse(ThreadSeat.pins(chat.messages.count))
        chat.messages = [Message(role: "user", text: "What is this?")]
        XCTAssertTrue(ThreadSeat.pins(chat.messages.count))
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testCoachShowsTheChatName() {
        XCTAssertEqual(CoachHeading.product, "Vale")
        XCTAssertEqual(CoachHeading.title(for: nil), "Vale")
        XCTAssertEqual(CoachHeading.title(for: "New chat"), "Vale")
        XCTAssertEqual(CoachHeading.title(for: "  "), "Vale")
        XCTAssertEqual(CoachHeading.title(for: "What is this?"), "What is this?")
        var chat = LearningSession(title: "New chat")
        XCTAssertEqual(CoachHeading.title(for: chat.title), "Vale")
        chat.title = "What is this?"
        XCTAssertEqual(CoachHeading.title(for: chat.title), chat.title)
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testRecordMarkOnlyWhileAPreviewIsHeld() {
        XCTAssertEqual(ShareMark.symbol(selected: false, live: false, capturing: false), "macwindow")
        XCTAssertEqual(ShareMark.symbol(selected: true, live: false, capturing: false), "macwindow")
        XCTAssertEqual(ShareMark.symbol(selected: true, live: true, capturing: false), "record.circle")
        XCTAssertEqual(ShareMark.symbol(selected: true, live: false, capturing: true), "record.circle")
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testPreviewOpensOnlyWhileHeld() {
        XCTAssertFalse(HeldPreview.canShow(held: false))
        XCTAssertTrue(HeldPreview.canShow(held: true))
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testStoppedQuestionStaysVisible() throws {
        XCTAssertEqual(StoppedReply.label, "Stopped")
        XCTAssertFalse(StoppedReply.shows(role: "user", stopped: false))
        XCTAssertFalse(StoppedReply.shows(role: "assistant", stopped: true))
        XCTAssertTrue(StoppedReply.shows(role: "user", stopped: true))
        var message = Message(role: "user", text: "What is this?")
        XCTAssertFalse(message.replyStopped)
        message.replyStopped = true
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertTrue(decoded.replyStopped)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object.removeValue(forKey: "replyStopped")
        let bare = try JSONSerialization.data(withJSONObject: object)
        let legacy = try JSONDecoder().decode(Message.self, from: bare)
        XCTAssertFalse(legacy.replyStopped)
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testMissingWindowCheckIsNotAChange() {
        XCTAssertFalse(WindowCheck.changed(matches: nil))
        XCTAssertFalse(WindowCheck.changed(matches: true))
        XCTAssertTrue(WindowCheck.changed(matches: false))
        XCTAssertFalse(WindowCheck.highlightUnavailable(askedToPoint: true, compared: false, changed: false, canPoint: false))
        XCTAssertFalse(WindowCheck.highlightUnavailable(askedToPoint: true, compared: true, changed: true, canPoint: false))
        XCTAssertTrue(WindowCheck.highlightUnavailable(askedToPoint: true, compared: true, changed: false, canPoint: false))
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testAttachmentQuestionStaysWhatYouSent() {
        XCTAssertEqual(AttachmentQuestion.savedText(typed: "", hasAttachment: true), "")
        XCTAssertEqual(AttachmentQuestion.promptText(typed: "", hasAttachment: true), AttachmentQuestion.modelPrompt)
        XCTAssertEqual(AttachmentQuestion.savedText(typed: "  \n", hasAttachment: true), "")
        XCTAssertNil(AttachmentQuestion.promptText(typed: "   ", hasAttachment: false))
        XCTAssertEqual(AttachmentQuestion.savedText(typed: "What is this?", hasAttachment: true), "What is this?")
        XCTAssertEqual(AttachmentQuestion.promptText(typed: "What is this?", hasAttachment: false), "What is this?")
        XCTAssertFalse(AttachmentQuestion.savedText(typed: "", hasAttachment: true).contains("Help me understand"))
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testCapsuleShowsTheWait() {
        XCTAssertEqual(CapsuleWait.label(title: "New chat", busy: false), "Vale")
        XCTAssertEqual(CapsuleWait.label(title: nil, busy: false), "Vale")
        XCTAssertEqual(CapsuleWait.label(title: "What is this?", busy: false), "What is this?")
        XCTAssertEqual(CapsuleWait.label(title: "What is this?", busy: true), "Thinking…")
        XCTAssertEqual(CapsuleWait.label(title: "New chat", busy: true), "Thinking…")
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testCapsuleShowsSpeech() {
        XCTAssertEqual(CapsuleSpeech.label(title: "What is this?", busy: false, speaking: true), "Speaking…")
        XCTAssertEqual(CapsuleSpeech.label(title: "What is this?", busy: true, speaking: false), "Thinking…")
        XCTAssertEqual(CapsuleSpeech.label(title: "What is this?", busy: false, speaking: false), "What is this?")
        XCTAssertEqual(CapsuleSpeech.label(title: "New chat", busy: false, speaking: false), "Vale")
        XCTAssertEqual(CapsuleSpeech.label(title: nil, busy: false, speaking: false), "Vale")
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testSentFilesAreListedInFull() {
        XCTAssertTrue(SentFiles.listedInFull)
        let picture = AttachmentRecord(name: "Pasted image.png", kind: .image, byteCount: 12, detail: "image")
        let note = AttachmentRecord(name: "notes.txt", kind: .text, byteCount: 20, detail: "text")
        XCTAssertEqual(SentFiles.names([picture, note]), ["Pasted image.png", "notes.txt"])
        XCTAssertEqual(SentFiles.names([picture, note]).count, 2)
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testReturnKeepsAWaitingAnswer() {
        XCTAssertFalse(ComposerReturn.sends(whileWaiting: true))
        XCTAssertTrue(ComposerReturn.sends(whileWaiting: false))
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testFileNameIsShownInFull() {
        let name = "Quarterly-report-final-version.pdf"
        let shown = FileName.shown(name)
        XCTAssertEqual(shown.replacingOccurrences(of: "\u{200B}", with: ""), name)
        XCTAssertTrue(shown.contains("\u{200B}"))
        let solid = "Supercalifragilisticexpialidocious"
        XCTAssertEqual(FileName.shown(solid).replacingOccurrences(of: "\u{200B}", with: ""), solid)
        XCTAssertTrue(FileName.shown(solid).contains("\u{200B}"))
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testReplyActionsAreNamed() {
        XCTAssertEqual(ReplyActions.titles(), ["Read", "Copy"])
        XCTAssertEqual(ReplyActions.read, "Read")
        XCTAssertEqual(ReplyActions.copy, "Copy")
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testFailedAnswerStaysOnTheQuestion() throws {
        XCTAssertEqual(FailedAnswer.label, "No answer")
        XCTAssertTrue(FailedAnswer.shows(failed: true, waiting: false))
        XCTAssertFalse(FailedAnswer.shows(failed: true, waiting: true))
        XCTAssertFalse(FailedAnswer.shows(failed: false, waiting: false))
        let message = Message(role: "user", text: "Hi", answerFailed: true)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertTrue(decoded.answerFailed)
        XCTAssertEqual(decoded.text, "Hi")
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object.removeValue(forKey: "answerFailed")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let older = try JSONDecoder().decode(Message.self, from: legacy)
        XCTAssertFalse(older.answerFailed)
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testUndoDoesNotRestoreASentQuestion() {
        XCTAssertTrue(ComposerUndo.dropsSentText)
        XCTAssertFalse(ComposerUndo.restoresSentText())
        XCTAssertTrue(ComposerUndo.clearsUndo(previous: "What is this?", replacement: ""))
        XCTAssertFalse(ComposerUndo.clearsUndo(previous: "", replacement: ""))
        XCTAssertFalse(ComposerUndo.clearsUndo(previous: "What is this?", replacement: "What is this? And"))
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testQuestionOpensAtTheStart() {
        XCTAssertTrue(QuestionScroll.opensAtTheStart(role: "user"))
        XCTAssertFalse(QuestionScroll.opensAtTheStart(role: "assistant"))
        XCTAssertFalse(QuestionScroll.opensAtTheStart(role: "assistant", text: "A short reply."))
        XCTAssertTrue(QuestionScroll.opensAtTheStart(role: "assistant", text: String(repeating: "A long answer. ", count: 40)))
        XCTAssertTrue(QuestionScroll.opensAtTheStart(role: "assistant", text: (0..<9).map { "Line \($0)" }.joined(separator: "\n")))
        XCTAssertFalse(QuestionScroll.opensAtTheStart(role: nil))
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testFieldDropAttachesAFile() {
        let notes = URL(fileURLWithPath: "/Users/vale/notes.txt")
        let page = URL(string: "https://example.com/notes")!
        let attached = FieldDrop.attaches([notes, page])
        XCTAssertEqual(attached.count, 1)
        XCTAssertEqual(attached.first?.lastPathComponent, "notes.txt")
        XCTAssertTrue(FieldDrop.attaches([page]).isEmpty)
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testMicStopsReadingWithoutStarting() {
        XCTAssertFalse(MicInterrupt.startsMicrophone(speaking: true, waiting: false))
        XCTAssertTrue(MicInterrupt.startsMicrophone(speaking: true, waiting: true))
        XCTAssertTrue(MicInterrupt.startsMicrophone(speaking: false, waiting: false))
        XCTAssertTrue(MicInterrupt.startsMicrophone(speaking: false, waiting: true))
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testSendClickDoesNotStop() {
        XCTAssertFalse(SendGesture.stops(elapsed: 0))
        XCTAssertFalse(SendGesture.stops(elapsed: 0.2))
        XCTAssertTrue(SendGesture.stops(elapsed: SendGesture.separateStop))
        XCTAssertTrue(SendGesture.stops(elapsed: 1))
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testFocusReturnsAfterSend() {
        XCTAssertTrue(ComposerFocus.returns(afterSending: true))
        XCTAssertFalse(ComposerFocus.returns(afterSending: false))
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testQuestionStaysUnmarked() {
        XCTAssertFalse(ComposerMarks.grammar)
        XCTAssertFalse(ComposerMarks.dataDetectors)
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testNewChatKeepsAnUnsentQuestion() {
        XCTAssertFalse(NewChat.leaves(hasUnsentWork: true))
        XCTAssertTrue(NewChat.leaves(hasUnsentWork: false))
        XCTAssertTrue(NewChat.hasUnsentWork(draft: "What is this?", fileCount: 0, importing: false))
        XCTAssertTrue(NewChat.hasUnsentWork(draft: "", fileCount: 1, importing: false))
        XCTAssertTrue(NewChat.hasUnsentWork(draft: "", fileCount: 0, importing: true))
        XCTAssertFalse(NewChat.hasUnsentWork(draft: "  ", fileCount: 0, importing: false))
        XCTAssertFalse(NewChat.leaves(hasUnsentWork: NewChat.hasUnsentWork(draft: "What is this?", fileCount: 0, importing: false)))
        XCTAssertEqual(NewChat.keptMessage, "Send or clear what you’ve written before starting a new chat.")
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testThumbnailShowsTheWholePicture() {
        XCTAssertTrue(PictureThumb.wholePicture)
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testReplyShowsWhenItArrived() {
        XCTAssertTrue(ReplyClock.shows(on: "assistant"))
        XCTAssertFalse(ReplyClock.shows(on: "user"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 20, minute: 5))!
        XCTAssertEqual(ReplyClock.label(for: now, now: now, calendar: calendar), "8:05 PM")
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        XCTAssertEqual(ReplyClock.label(for: yesterday, now: now, calendar: calendar), "Oct 16, 8:05 PM")
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testFileRowStaysWithinTheCoach() {
        XCTAssertTrue(FileRowWidth.staysWithinTheCoach)
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertFalse(PointTarget(x: 1.2, y: 0.1, width: 0.2, height: 0.1, label: "Edge").isValid)
    }

    func testCapsuleNameEndsOnAWord() {
        let title = "How do I reset my password tonight"
        let names = CapsuleTitle.candidates(title)
        XCTAssertEqual(names.first, title)
        XCTAssertTrue(names.count > 1)
        for name in names.dropFirst() {
            XCTAssertTrue(name.hasSuffix("…"))
            let stem = String(name.dropLast())
            XCTAssertFalse(stem.hasSuffix(" "))
            XCTAssertTrue(title.hasPrefix(stem))
        }
        XCTAssertEqual(names[1], "How do I reset my password…")
        XCTAssertEqual(CapsuleTitle.candidates("Vale"), ["Vale"])
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
    }

    func testWaitingFieldKeepsTheQuestionVisible() {
        XCTAssertEqual(WaitingField.shown(waiting: false), WaitingField.idle)
        XCTAssertEqual(WaitingField.idle, "Ask quietly…")
        XCTAssertEqual(WaitingField.shown(waiting: true), "Your question is in the chat")
        XCTAssertFalse(WaitingField.shown(waiting: true).contains("Thinking"))
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
    }

    func testUnsentFileStaysWithTheDraft() {
        XCTAssertTrue(UnsentFilePlace.withTheDraft)
        var chat = LearningSession(title: "New chat")
        chat.pendingAttachments = [AttachmentRecord(name: "notes.txt", kind: .text, byteCount: 4, detail: "TXT")]
        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertEqual(chat.pendingAttachments.map(\.name), ["notes.txt"])
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
    }

    func testRemovingAnUnsentFileKeepsTheReply() {
        XCTAssertFalse(UnsentRemoval.stopsTheReply(waiting: true, unsent: true))
        XCTAssertTrue(UnsentRemoval.stopsTheReply(waiting: true, unsent: false))
        XCTAssertFalse(UnsentRemoval.stopsTheReply(waiting: false, unsent: true))
        var chat = LearningSession(title: "New chat")
        let file = AttachmentRecord(name: "notes.txt", kind: .text, byteCount: 4, detail: "TXT")
        chat.pendingAttachments = [file]
        let unsent = chat.pendingAttachments.contains { $0.id == file.id } && !chat.messages.contains { $0.attachments.contains { $0.id == file.id } }
        XCTAssertTrue(unsent)
        XCTAssertFalse(UnsentRemoval.stopsTheReply(waiting: true, unsent: unsent))
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
    }

    func testSameFileNameIsNumbered() {
        let first = AttachmentRecord(name: "Pasted image.png", kind: .image, byteCount: 10, detail: "Image")
        let other = AttachmentRecord(name: "notes.txt", kind: .text, byteCount: 4, detail: "TXT")
        let second = AttachmentRecord(name: "Pasted image.png", kind: .image, byteCount: 12, detail: "Image")
        let files = [first, other, second]
        XCTAssertEqual(FileCopy.detail(for: first, among: files), "Image · 1")
        XCTAssertEqual(FileCopy.detail(for: second, among: files), "Image · 2")
        XCTAssertEqual(FileCopy.detail(for: other, among: files), "TXT")
        XCTAssertEqual(FileCopy.detail(for: first, among: [first]), "Image")
        XCTAssertEqual(first.name, second.name)
        let pdfA = AttachmentRecord(name: "notes.pdf", kind: .pdf, byteCount: 10, detail: "PDF · 3 pages")
        let pdfB = AttachmentRecord(name: "notes.pdf", kind: .pdf, byteCount: 12, detail: "3 pages")
        XCTAssertEqual(FileCopy.line(for: pdfA, among: [pdfA]), "PDF · 3 pages")
        XCTAssertEqual(FileCopy.line(for: pdfA, among: [pdfA, pdfB]), "PDF · 3 pages · 1")
        XCTAssertEqual(FileCopy.line(for: pdfB, among: [pdfA, pdfB]), "PDF · 3 pages · 2")
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
    }

    func testReplyControlsStayWhole() {
        XCTAssertTrue(ReplyControls.stayWhole)
        XCTAssertTrue(ReplyControls.clips("user"))
        XCTAssertFalse(ReplyControls.clips("assistant"))
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
    }

    func testQuestionLineWrapsALongWord() {
        let word = String(repeating: "A", count: 30)
        let shown = QuestionLine.shown(word)
        XCTAssertEqual(shown.replacingOccurrences(of: "\u{200B}", with: ""), word)
        XCTAssertTrue(shown.contains("\u{200B}"))
        XCTAssertEqual(QuestionLine.shown("short words"), "short words")
        let url = "https://example.com/a-very-long-address-that-stays-whole"
        XCTAssertEqual(QuestionLine.shown(url), url)
        XCTAssertEqual(QuestionLine.shown("one\ntwo"), "one\ntwo")
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
    }

    func testFilePreviewStaysBesideTheCoach() {
        let beside = FilePreviewPlace.origin(screenX: 0, screenY: 0, screenWidth: 1440, screenHeight: 900, previewWidth: 800, previewHeight: 550, coachX: 1010, coachWidth: 410)
        XCTAssertTrue(beside.x + 800 + 16 <= 1010)
        XCTAssertTrue(beside.x >= 16)
        XCTAssertTrue(beside.y >= 16)
        XCTAssertTrue(beside.y + 550 <= 900)
        let otherSide = FilePreviewPlace.origin(screenX: 0, screenY: 0, screenWidth: 1440, screenHeight: 900, previewWidth: 800, previewHeight: 550, coachX: 16, coachWidth: 410)
        XCTAssertTrue(otherSide.x >= 16 + 410 + 16)
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
    }

    func testOpeningLineDoesNotRequireAWindow() {
        XCTAssertEqual(OpeningLine.assistant, "Ask anything, or drop a file.")
        XCTAssertFalse(OpeningLine.assistant.contains("window"))
        XCTAssertFalse(OpeningLine.assistant.contains("share"))
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
    }

    func testFieldSurfaceStaysClear() {
        XCTAssertTrue(FieldSurface.staysClear)
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertEqual(chat.draft, "")
    }

    func testPdfChipSaysPdf() {
        XCTAssertEqual(PdfChip.detail(pages: 1), "PDF · 1 page")
        XCTAssertEqual(PdfChip.detail(pages: 3), "PDF · 3 pages")
        XCTAssertFalse(PdfChip.detail(pages: 2).hasPrefix("2"))
        XCTAssertEqual(PdfChip.symbol, "doc.fill")
        XCTAssertEqual(PdfChip.shown(kind: .pdf, stored: "3 pages"), "PDF · 3 pages")
        XCTAssertEqual(PdfChip.shown(kind: .pdf, stored: "PDF · 1 page"), "PDF · 1 page")
        XCTAssertEqual(PdfChip.shown(kind: .pdf, stored: "  "), "PDF")
        XCTAssertEqual(PdfChip.shown(kind: .text, stored: "SWIFT"), "SWIFT")
        XCTAssertEqual(PdfChip.shown(kind: .image, stored: "Image"), "Image")
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
    }

    func testWebToggleWaitsForTheReply() {
        XCTAssertTrue(WebToggle.changes(waiting: false))
        XCTAssertFalse(WebToggle.changes(waiting: true))
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
    }

    func testPdfPreviewWaitsToRead() {
        XCTAssertFalse(PreviewRead.showsFailure(loaded: false, hasPage: false))
        XCTAssertTrue(PreviewRead.showsFailure(loaded: true, hasPage: false))
        XCTAssertFalse(PreviewRead.showsFailure(loaded: true, hasPage: true))
        XCTAssertEqual(PreviewRead.pageLabel(loaded: false, index: 0, count: 0), "")
        XCTAssertEqual(PreviewRead.pageLabel(loaded: true, index: 0, count: 3), "Page 1 of 3")
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
    }

    func testNoSpeakingWhenThereIsNothingToRead() {
        XCTAssertFalse(SpeechStart.speaks("   "))
        XCTAssertFalse(SpeechStart.speaks("**"))
        XCTAssertFalse(SpeechStart.speaks("`"))
        XCTAssertTrue(SpeechStart.speaks("Hello"))
        XCTAssertEqual(SpeechStart.spoken("[Page](https://example.com/docs)"), "Page")
        XCTAssertTrue(SpeechStart.speaks("[Page](https://example.com/docs)"))
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
    }

    func testPromptShowsWhenTheFieldHasNoWords() {
        XCTAssertTrue(FieldPrompt.showsIdle(""))
        XCTAssertTrue(FieldPrompt.showsIdle(" \n "))
        XCTAssertFalse(FieldPrompt.showsIdle("  hello"))
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertTrue(FieldPrompt.showsIdle(chat.draft))
    }

    func testComposerStaysOnScreen() {
        XCTAssertTrue(ComposerSeat.staysOnScreen)
        var chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        chat.messages.append(Message(role: "assistant", text: String(repeating: "Answer ", count: 80)))
        XCTAssertTrue((chat.messages.last?.text.count ?? 0) > 400)
    }

    func testOneFileDoesNotUseAScroller() {
        XCTAssertFalse(FileScroll.usesScroll(fileCount: 0))
        XCTAssertFalse(FileScroll.usesScroll(fileCount: 1))
        XCTAssertTrue(FileScroll.usesScroll(fileCount: 2))
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
    }

    func testAskedNewChatShowsOnTheCapsule() {
        XCTAssertEqual(CapsuleName.shown(title: "New chat", hasMessages: false), "Vale")
        XCTAssertEqual(CapsuleName.shown(title: "New chat", hasMessages: true), "New chat")
        XCTAssertEqual(CapsuleName.shown(title: "Hello", hasMessages: true), "Hello")
        XCTAssertEqual(CapsuleName.shown(title: "Project", hasMessages: false), "Project")
        let chat = LearningSession(title: "New chat")
        XCTAssertFalse(chat.webEnabled)
        XCTAssertEqual(chat.mode, .assistant)
        XCTAssertTrue(chat.messages.isEmpty)
    }

    func testTextPreviewKeepsTheFile() {
        let short = "The file ends here.\n"
        XCTAssertEqual(TextPreview.shown(short), short)
        let own = "Preview limited to the first line, then more."
        XCTAssertEqual(TextPreview.shown(own), own)
        let long = String(repeating: "a", count: TextPreview.characterLimit + 12)
        let shown = TextPreview.shown(long)
        XCTAssertEqual(shown.count, TextPreview.characterLimit)
        XCTAssertFalse(shown.contains("Preview limited"))
        XCTAssertFalse(shown.contains("["))
    }

    func testTwoSpacesStaySpaces() {
        XCTAssertFalse(DoubleSpace.insertsPeriod)
        XCTAssertEqual(DoubleSpace.shown("Wait  "), "Wait  ")
        XCTAssertEqual(DoubleSpace.shown("Hello  there"), "Hello  there")
        XCTAssertFalse(DoubleSpace.shown("Done  ").hasSuffix(". "))
        XCTAssertEqual(DoubleSpace.shown("Already done."), "Already done.")
    }

    func testCloseWindowHidesTheCoach() {
        XCTAssertTrue(CoachClose.hidesTheCoach(key: "w", command: true, shift: false, option: false, control: false, coachIsKey: true, blocked: false))
        XCTAssertFalse(CoachClose.hidesTheCoach(key: "w", command: true, shift: false, option: false, control: false, coachIsKey: false, blocked: false))
        XCTAssertFalse(CoachClose.hidesTheCoach(key: "w", command: true, shift: false, option: false, control: false, coachIsKey: true, blocked: true))
        XCTAssertFalse(CoachClose.hidesTheCoach(key: "w", command: true, shift: true, option: false, control: false, coachIsKey: true, blocked: false))
        XCTAssertFalse(CoachClose.hidesTheCoach(key: "q", command: true, shift: false, option: false, control: false, coachIsKey: true, blocked: false))
        XCTAssertFalse(CoachClose.hidesTheCoach(key: "w", command: false, shift: false, option: false, control: false, coachIsKey: true, blocked: false))
    }

    func testEarlierContextNoticeIsNotTheCurrentMessage() {
        XCTAssertFalse(EarlierContext.showsNotice(omitted: 0))
        XCTAssertTrue(EarlierContext.showsNotice(omitted: 2))
        var chat = LearningSession(title: "New chat")
        chat.messages = [Message(role: "user", text: String(repeating: "a", count: 9_000))]
        XCTAssertTrue(chat.contextLimited)
        XCTAssertFalse(chat.showsEarlierContextNotice)
        chat.messages = (0..<20).map { Message(role: "user", text: "Note \($0)") }
        XCTAssertTrue(chat.showsEarlierContextNotice)
    }

    func testCodexNoticeWaitsForLookup() {
        XCTAssertFalse(CodexNotice.shows(executableKnown: false, lookupFinished: false))
        XCTAssertFalse(CodexNotice.shows(executableKnown: true, lookupFinished: false))
        XCTAssertFalse(CodexNotice.shows(executableKnown: true, lookupFinished: true))
        XCTAssertTrue(CodexNotice.shows(executableKnown: false, lookupFinished: true))
    }

    func testPauseDoesNotHoldATypedQuestion() {
        XCTAssertTrue(PausedTyping.allowsQuestion(paused: true))
        XCTAssertTrue(PausedTyping.allowsQuestion(paused: false))
    }

    func testWaitStaysWhileAFileIsAdded() {
        XCTAssertEqual(FooterStatus.line(paused: false, importing: true, microphoneStarting: false, listening: false, waiting: true, speaking: false, conversation: false), "Thinking…")
        XCTAssertEqual(FooterStatus.line(paused: false, importing: true, microphoneStarting: false, listening: false, waiting: false, speaking: false, conversation: false), "Adding files…")
        XCTAssertEqual(FooterStatus.line(paused: false, importing: false, microphoneStarting: false, listening: false, waiting: false, speaking: false, conversation: false), "Voice off")
        XCTAssertEqual(FooterStatus.line(paused: false, importing: false, microphoneStarting: false, listening: true, waiting: true, speaking: false, conversation: false), "Listening…")
        XCTAssertEqual(FooterStatus.line(paused: true, importing: true, microphoneStarting: false, listening: false, waiting: true, speaking: false, conversation: false), "Paused")
    }

    func testRetryWaitsUntilTheReplyFails() {
        XCTAssertFalse(RetryOffer.shows(waiting: true, lastRoleIsUser: true))
        XCTAssertTrue(RetryOffer.shows(waiting: false, lastRoleIsUser: true))
        XCTAssertFalse(RetryOffer.shows(waiting: false, lastRoleIsUser: false))
        XCTAssertFalse(RetryOffer.shows(waiting: true, lastRoleIsUser: false))
    }

    func testPointControlExplainsAMissingWindow() {
        XCTAssertTrue(PointControl.enabled(waiting: false))
        XCTAssertFalse(PointControl.enabled(waiting: true))
    }

    func testCapsuleMicStaysOffTheOpenCoach() {
        XCTAssertFalse(CapsuleMic.shows(coachOpen: true))
        XCTAssertTrue(CapsuleMic.shows(coachOpen: false))
        XCTAssertTrue(CapsuleMic.idleIsQuiet(listening: false, speaking: false, busy: false))
        XCTAssertFalse(CapsuleMic.idleIsQuiet(listening: true, speaking: false, busy: false))
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
 ("Idle coach status prefers typing",tests.testIdleStatusTreatsTypingAsReady),
 ("Codex sign-in is stated before the first send",tests.testCodexSignInIsStatedBeforeTheFirstSend),
 ("Mode names are Assistant and Learn with hints",tests.testModeNamesAreAssistantAndLearnWithHints),
 ("User text is not shown as markdown",tests.testUserTextIsNotShownAsMarkdown),
 ("Capsule keeps an unsent draft visible",tests.testCapsuleKeepsAnUnsentDraftVisible),
 ("History shows an unsent draft",tests.testHistoryShowsAnUnsentDraft),
 ("Guide start confirms before clearing work",tests.testGuideStartConfirmsBeforeClearingWork),
 ("Assistant reply stays visible when formatting drops it",tests.testAssistantReplyStaysVisibleWhenFormattingDropsIt),
 ("Dropped attachment explains why it was not kept",tests.testDroppedAttachmentExplainsWhyItWasNotKept),
 ("Folder drop is not reported as too large",tests.testFolderDropIsNotReportedAsTooLarge),
 ("Voice opt-in waits for the reply",tests.testVoiceOptInWaitsForTheReply),
 ("Retry stays after the error is dismissed",tests.testRetryStaysAfterTheErrorIsDismissed),
 ("Mode change keeps the reply",tests.testModeChangeKeepsTheReply),
 ("Composer grows to show a paste and then stops",tests.testComposerGrowsToShowAPasteAndThenStops),
 ("Composer focus retries until the field exists",tests.testComposerFocusRetriesUntilTheFieldExists),
 ("Newest reply opens at its first line",tests.testNewestReplyOpensAtItsFirstLine),
 ("Shared window label uses the picked title",tests.testSharedWindowLabelUsesThePickedTitle),
 ("Command prompt keeps the composer draft",tests.testCommandPromptKeepsTheComposerDraft),
 ("Capsule shows a failed send",tests.testCapsuleShowsAFailedSend),
 ("Shortcut failure stays readable",tests.testShortcutFailureStaysReadable),
 ("Guide step is shown in full",tests.testGuideStepIsShownInFull),
 ("Close leaves the chat resumable",tests.testCloseLeavesTheChatForTheNextLaunch),
 ("Picker cancel keeps the selected window",tests.testPickerCancelKeepsTheSelectedWindow),
 ("Highlight stays while the window is unchanged",tests.testHighlightStaysWhileTheWindowIsUnchanged),
 ("Collapsed coach shows that an answer is ready",tests.testCollapsedCoachShowsThatAnAnswerIsReady),
 ("Web search control is named",tests.testWebSearchControlIsNamed),
 ("Paste keeps copied text",tests.testPasteKeepsCopiedText),
 ("Stale answer stays marked outside the coach",tests.testStaleAnswerStaysMarkedOutsideTheCoach),
 ("History preview shows the matching message",tests.testHistoryPreviewShowsTheMatchingMessage),
 ("Spoken reply keeps the link address",tests.testSpokenReplyKeepsTheLinkAddress),
 ("Sidebar uses the search while it is visible",tests.testSidebarUsesTheSearchWhileItIsVisible),
 ("History counts the reply",tests.testHistoryCountsTheReply),
 ("Read aloud speaks the reply already on screen",tests.testReadAloudSpeaksTheReplyAlreadyOnScreen),
 ("Excerpt keeps the end of a long reply",tests.testExcerptKeepsTheEndOfALongReply),
 ("Storage failure still opens the coach",tests.testStorageFailureStillOpensTheCoach),
 ("Send commits composition before clearing the draft",tests.testSendCommitsCompositionBeforeClearingTheDraft),
 ("Note typing is not replaced by the stored value",tests.testNoteTypingIsNotReplacedByTheStoredValue),
 ("Capture age shows only while live",tests.testCaptureAgeShowsOnlyWhileLive),
 ("Reply text survives a malformed optional field",tests.testReplyTextSurvivesAMalformedOptionalField),
 ("Question wrapper cannot cut off the typed message",tests.testQuestionWrapperCannotCutOffTheTypedMessage),
 ("Readable chats survive an unreadable record",tests.testReadableChatsSurviveAnUnreadableRecord),
 ("First question waits for Codex lookup",tests.testFirstQuestionWaitsForCodexLookup),
 ("Blank rename keeps the existing title",tests.testBlankRenameKeepsTheExistingTitle),
 ("Finished reply file is kept when the process reports failure",tests.testFinishedReplyFileIsKeptWhenTheProcessReportsFailure),
 ("Model choice ignores surrounding space",tests.testModelChoiceIgnoresSurroundingSpace),
 ("Outgoing message keeps leading indentation",tests.testOutgoingMessageKeepsLeadingIndentation),
 ("Answer text is shown before the window is rechecked",tests.testAnswerTextIsShownBeforeTheWindowIsRechecked),
 ("Configured empty chat is kept",tests.testConfiguredEmptyChatIsKept),
 ("Web search does not enable code execution",tests.testWebSearchDoesNotEnableCodeExecution),
 ("Question is closed only after the full text is written",tests.testQuestionIsClosedOnlyAfterTheFullTextIsWritten),
 ("Export uses the answer that arrived while saving",tests.testExportUsesTheAnswerThatArrivedWhileSaving),
 ("Chat history shows the chat you were just in",tests.testChatHistoryShowsTheChatYouWereJustIn),
 ("Opened preview closes when the question is sent",tests.testOpenedPreviewClosesWhenTheQuestionIsSent),
 ("Chat list shows the answer when the first line is blank",tests.testChatListShowsTheAnswerWhenTheFirstLineIsBlank),
 ("First launch opens the saved chat by its id",tests.testFirstLaunchOpensTheSavedChatByItsId),
 ("First question keeps going when instructions are missing",tests.testFirstQuestionKeepsGoingWhenInstructionsAreMissing),
 ("Question can run the program beside Codex",tests.testQuestionCanRunTheProgramBesideCodex),
 ("Unsaved question returns to the composer",tests.testUnsavedQuestionReturnsToTheComposer),
 ("Answer applies only to the current chat",tests.testAnswerAppliesOnlyToTheCurrentChat),
 ("Answer is saved before speech or pointing",tests.testAnswerIsSavedBeforeSpeechOrPointing),
 ("Question skips a capture that was already running",tests.testQuestionSkipsACaptureThatWasAlreadyRunning),
 ("History shows the full saved answer",tests.testHistoryShowsTheFullSavedAnswer),
 ("Answer survives the output pipe",tests.testAnswerSurvivesTheOutputPipe),
 ("Waiting clears when the question does not go out",tests.testWaitingClearsWhenTheQuestionDoesNotGoOut),
 ("Keep a guide plan with a long step",tests.testLongGuideStepIsKept),
 ("Numeric PDF text stays readable",tests.testNumericPdfTextIsReadable),
 ("Unicode text files stay readable",tests.testUnicodeTextFileIsReadable),
 ("Restriction-only PDF can be read",tests.testRestrictionOnlyPdfCanBeRead),
 ("Highlight uses the main display",tests.testHighlightUsesTheMainDisplay),
 ("Linked drop reads the target file",tests.testLinkedDropReadsTheTargetFile),
 ("Later TIFF pages are kept when they fit",tests.testLaterTiffPagesAreKeptWhenTheyFit),
 ("Sign-in check finishes",tests.testSignInCheckFinishes),
 ("Question still sends when a file cannot be read",tests.testQuestionStillSendsWhenAFileCannotBeRead),
 ("History window comes back on screen",tests.testHistoryWindowComesBackOnScreen),
 ("Readable image is kept when preview fails",tests.testReadableImageIsKeptWhenPreviewFails),
 ("Pasted PDF is kept when it is not an image",tests.testPastedPdfIsKeptWhenItIsNotAnImage),
 ("Unnamed PDF is not refused as text",tests.testUnnamedPDFIsNotRefusedAsText),
 ("Export name keeps a colon from splitting the file",tests.testExportNameKeepsAColonFromSplittingTheFile),
 ("Long point label keeps the highlight",tests.testLongPointLabelKeepsTheHighlight),
 ("Saved guide step is found in history",tests.testSavedGuideStepIsFoundInHistory),
 ("Follow-up keeps the whole guide plan",tests.testFollowUpKeepsTheWholeGuidePlan),
 ("Follow-up hears when the highlight was hidden",tests.testFollowUpHearsWhenTheHighlightWasHidden),
 ("Unread scan page is not described as attached",tests.testUnreadScanPageIsNotDescribedAsAttached),
 ("Rich text keeps the words without null bytes",tests.testRichTextKeepsTheWordsWithoutNullBytes),
 ("Named text file is not read as an image",tests.testNamedTextFileIsNotReadAsAnImage),
 ("SVG drawing is readable text",tests.testSVGDrawingIsReadableText),
 ("Opening a preview keeps the file you are reading",tests.testOpeningAPreviewKeepsTheFileYouAreReading),
 ("Typed guide request keeps a plan",tests.testTypedGuideRequestKeepsAPlan),
 ("Attached image is numbered after the window",tests.testAttachedImageIsNumberedAfterTheWindow),
 ("Guide step stays when the question does not start",tests.testGuideStepStaysWhenTheQuestionDoesNotStart),
 ("Follow-up hears when the window changed",tests.testFollowUpHearsWhenTheWindowChanged),
 ("Ended guide is not restored by the answer",tests.testEndedGuideIsNotRestoredByTheAnswer),
 ("Refresh of point it out still points",tests.testRefreshOfPointItOutStillPoints),
 ("Long answer line keeps every character",tests.testLongAnswerLineKeepsEveryCharacter),
 ("JPEG paste attaches when there is no text",tests.testJpegPasteAttachesWhenThereIsNoText),
 ("Draft echo is not typing",tests.testDraftEchoIsNotTyping),
 ("Newest file is read before older ones",tests.testNewestFileIsReadBeforeOlderOnes),
 ("Dropped web link becomes draft text",tests.testDroppedWebLinkBecomesDraftText),
 ("Objective-C source is text",tests.testObjectiveCSourceIsText),
 ("Saved draft caret stays at the end",tests.testSavedDraftCaretStaysAtTheEnd),
 ("Shared window uses a plain bitmap when PNG fails",tests.testSharedWindowUsesPlainBitmapWhenPNGFails),
 ("Search finds every word",tests.testSearchFindsEveryWord),
 ("Every failed file is reported",tests.testEveryFailedFileIsReported),
 ("Dropped file keeps read access",tests.testDroppedFileKeepsReadAccess),
 ("HTML paste keeps the words",tests.testHTMLPasteKeepsTheWords),
 ("Mic intake closes before the request ends",tests.testMicIntakeClosesBeforeTheRequestEnds),
 ("PDF work hops to the main thread",tests.testPDFWorkHopsToTheMainThread),
 ("Finder alias reads the target file",tests.testFinderAliasReadsTheTargetFile),
 ("Typed words are not corrected",tests.testTypedWordsAreNotCorrected),
 ("Chat heading uses the first line",tests.testChatHeadingUsesTheFirstLine),
 ("Speech locale drops the extra suffix",tests.testSpeechLocaleDropsTheExtraSuffix),
 ("Mic format is read after prepare",tests.testMicFormatIsReadAfterPrepare),
 ("Paste does not adjust spaces",tests.testPasteDoesNotAdjustSpaces),
 ("Capture size stays even",tests.testCaptureSizeStaysEven),
 ("Option-Return does not send",tests.testOptionReturnDoesNotSend),
 ("Word completion does not insert",tests.testWordCompletionDoesNotInsert),
 ("Recognition starts after the engine",tests.testRecognitionStartsAfterEngine),
 ("Answer opens a mail link",tests.testAnswerOpensMailLink),
 ("Paste keeps a web address",tests.testPasteKeepsWebAddress),
 ("Word document keeps text",tests.testWordDocumentKeepsText),
 ("Escape leaves an open dialog",tests.testEscapeLeavesAnOpenDialog),
 ("Empty greeting sits with the composer",tests.testEmptyGreetingSitsWithTheComposer),
 ("Attach control shows its name",tests.testAttachControlShowsItsName),
 ("Capsule mic stays quiet until used",tests.testCapsuleMicStaysQuietUntilUsed),
 ("Empty field prompt sits on the caret",tests.testEmptyFieldPromptSitsOnTheCaret),
 ("Share control looks pressable",tests.testShareControlLooksPressable),
 ("Capsule title matches the coach",tests.testCapsuleTitleMatchesTheCoach),
 ("Composer rows leave room under the line",tests.testComposerRowsLeaveRoomUnderTheLine),
 ("Conversation control looks pressable",tests.testConversationControlLooksPressable),
 ("Idle wave stays quiet until voice",tests.testIdleWaveStaysQuietUntilVoice),
 ("Send sits on the typed line",tests.testSendSitsOnTheTypedLine),
 ("The send control looks ready",tests.testSendControlLooksReady),
 ("A focus timer stays in Learn",tests.testFocusTimerStaysInLearn),
 ("Microphone sits with the tools",tests.testMicrophoneSitsWithTheTools),
 ("Empty thread says where the reply shows",tests.testEmptyThreadSaysWhereTheReplyShows),
 ("Coach dismiss is not a quit mark",tests.testCoachDismissIsNotAQuitMark),
 ("Pause lives in the menu",tests.testPauseLivesInTheMenu),
 ("Guide control leaves the composer",tests.testGuideControlLeavesTheComposer),
 ("Chat list uses a conversation mark",tests.testChatListUsesAConversationMark),
 ("Share row follows the composer",tests.testShareRowFollowsTheComposer),
 ("Mode choice leaves the header",tests.testModeChoiceLeavesTheHeader),
 ("Capsule sits on the coach",tests.testCapsuleSitsOnTheCoach),
 ("Capsule name leads the bars",tests.testCapsuleNameLeadsTheBars),
 ("Your turn sits on the trailing side",tests.testYourTurnSitsOnTheTrailingSide),
 ("Sent file stays with the question",tests.testSentFileStaysWithTheQuestion),
 ("Reply keeps its lines",tests.testReplyKeepsItsLines),
 ("Reply shows the address",tests.testReplyShowsTheAddress),
 ("Reply code stays a block",tests.testReplyCodeStaysABlock),
 ("Reply wait sits in the thread",tests.testReplyWaitSitsInTheThread),
 ("Reply shows it is being read",tests.testReplyShowsItIsBeingRead),
 ("Reply shows the companion",tests.testReplyShowsTheCompanion),
 ("Sent picture shows in the exchange",tests.testSentPictureShowsInTheExchange),
 ("Reply is its own turn",tests.testReplyIsItsOwnTurn),
 ("Exchange sits with the composer",tests.testExchangeSitsWithTheComposer),
 ("Coach shows the chat name",tests.testCoachShowsTheChatName),
 ("Record mark only while a preview is held",tests.testRecordMarkOnlyWhileAPreviewIsHeld),
 ("Preview opens only while held",tests.testPreviewOpensOnlyWhileHeld),
 ("Stopped question stays visible",tests.testStoppedQuestionStaysVisible),
 ("Missing window check is not a change",tests.testMissingWindowCheckIsNotAChange),
 ("Attachment question stays what you sent",tests.testAttachmentQuestionStaysWhatYouSent),
 ("Capsule shows the wait",tests.testCapsuleShowsTheWait),
 ("Capsule shows speech",tests.testCapsuleShowsSpeech),
 ("Sent files are listed in full",tests.testSentFilesAreListedInFull),
 ("Return keeps a waiting answer",tests.testReturnKeepsAWaitingAnswer),
 ("A file name is shown in full",tests.testFileNameIsShownInFull),
 ("Reply actions are named",tests.testReplyActionsAreNamed),
 ("A failed answer stays on the question",tests.testFailedAnswerStaysOnTheQuestion),
 ("Undo does not restore a sent question",tests.testUndoDoesNotRestoreASentQuestion),
 ("A question opens at the start",tests.testQuestionOpensAtTheStart),
 ("A file dropped on the field is attached",tests.testFieldDropAttachesAFile),
 ("The mic stops reading without starting",tests.testMicStopsReadingWithoutStarting),
 ("A send click does not also stop",tests.testSendClickDoesNotStop),
 ("Focus returns after send",tests.testFocusReturnsAfterSend),
 ("A typed question stays unmarked",tests.testQuestionStaysUnmarked),
 ("New chat keeps an unsent question",tests.testNewChatKeepsAnUnsentQuestion),
 ("A thumbnail shows the whole picture",tests.testThumbnailShowsTheWholePicture),
 ("A reply shows when it arrived",tests.testReplyShowsWhenItArrived),
 ("A file row stays within the coach",tests.testFileRowStaysWithinTheCoach),
 ("The capsule name ends on a word",tests.testCapsuleNameEndsOnAWord),
 ("The waiting field keeps the question visible",tests.testWaitingFieldKeepsTheQuestionVisible),
 ("An unsent file stays with the draft",tests.testUnsentFileStaysWithTheDraft),
 ("Removing an unsent file keeps the reply",tests.testRemovingAnUnsentFileKeepsTheReply),
 ("The same file name is numbered",tests.testSameFileNameIsNumbered),
 ("Reply controls stay whole",tests.testReplyControlsStayWhole),
 ("A long word in the question wraps",tests.testQuestionLineWrapsALongWord),
 ("A file preview stays beside the coach",tests.testFilePreviewStaysBesideTheCoach),
 ("The opening line does not require a window",tests.testOpeningLineDoesNotRequireAWindow),
 ("The field stays clear behind the words",tests.testFieldSurfaceStaysClear),
 ("A PDF chip says it is a PDF",tests.testPdfChipSaysPdf),
 ("Web search waits until the reply arrives",tests.testWebToggleWaitsForTheReply),
 ("A PDF preview waits until the file is read",tests.testPdfPreviewWaitsToRead),
 ("Nothing is read when the reply has no words",tests.testNoSpeakingWhenThereIsNothingToRead),
 ("The prompt shows when the field has no words",tests.testPromptShowsWhenTheFieldHasNoWords),
 ("The composer stays on screen",tests.testComposerStaysOnScreen),
 ("One file does not use a scroller",tests.testOneFileDoesNotUseAScroller),
 ("A question named New chat shows on the capsule",tests.testAskedNewChatShowsOnTheCapsule),
 ("Text preview keeps the file",tests.testTextPreviewKeepsTheFile),
 ("Two spaces stay spaces",tests.testTwoSpacesStaySpaces),
 ("Close window hides the coach",tests.testCloseWindowHidesTheCoach),
 ("History note is for earlier messages",tests.testEarlierContextNoticeIsNotTheCurrentMessage),
 ("Codex notice waits for lookup",tests.testCodexNoticeWaitsForLookup),
 ("Pause does not hold a typed question",tests.testPauseDoesNotHoldATypedQuestion),
 ("Wait stays while a file is added",tests.testWaitStaysWhileAFileIsAdded),
 ("Retry waits until the reply fails",tests.testRetryWaitsUntilTheReplyFails),
 ("Point it out explains a missing window",tests.testPointControlExplainsAMissingWindow),
 ("The capsule microphone waits while the coach is open",tests.testCapsuleMicStaysOffTheOpenCoach),
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
