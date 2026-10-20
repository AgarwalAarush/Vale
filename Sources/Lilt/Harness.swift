import AppKit
import PDFKit
import LiltCore

extension AppController {
    func snapshot(_ window:NSWindow,to file:URL,provenance:NativeWindowEvidence.Provenance? = nil)throws{
        // Only this harness supplies the primary window's generated-data assertion.
        let source = provenance ?? (window === workspace ? .generatedHarness(account: model.provider.account) : .unknown)
        try NativeWindowEvidence.capture(window, to: file, provenance: source)
    }
    func settle()async{try? await Task.sleep(nanoseconds:650_000_000)}
    func waitForReply()async{let start=Date();while model.busy && Date().timeIntervalSince(start)<155{try? await Task.sleep(nanoseconds:200_000_000)}}
    func makeFixtures(in output:URL)throws->[URL]{
        let directory=output.appendingPathComponent("fixtures");try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        var urls:[URL]=[]
        for (name,color,square) in [("A.png",NSColor.systemRed,false),("B.png",NSColor.systemBlue,true)]{
            let image=NSImage(size:NSSize(width:400,height:260));image.lockFocus()
            NSColor.white.setFill();NSRect(x:0,y:0,width:400,height:260).fill();color.setFill()
            if square{NSRect(x:145,y:90,width:110,height:110).fill()}else{NSBezierPath(ovalIn:NSRect(x:145,y:90,width:110,height:110)).fill()}
            (name as NSString).draw(at:NSPoint(x:170,y:35),withAttributes:[.font:NSFont.systemFont(ofSize:18),.foregroundColor:NSColor.black]);image.unlockFocus()
            let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!;let file=directory.appendingPathComponent(name);try rep.representation(using:.png,properties:[:])!.write(to:file);urls.append(file)
        }
        let text=NSTextView(frame:NSRect(x:0,y:0,width:500,height:300));text.string="Document verification token: HARBOR-73.\nThis is a public test fixture, not a user document.";text.font = .systemFont(ofSize:18);text.textColor = .black;text.backgroundColor = .white
        let pdf=directory.appendingPathComponent("Brief.pdf");try text.dataWithPDF(inside:text.bounds).write(to:pdf);urls.append(pdf)
        let note=directory.appendingPathComponent("Notes.md");try "Reminder: bring a notebook.\n".write(to:note,atomically:true,encoding:.utf8);urls.append(note)
        return urls
    }
    func runHarness()async{
        let output=URL(fileURLWithPath:CommandLine.arguments.last!);var results:[String:Bool]=[:]
        do{
            try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
            model.voice.enableFixtures();model.sessions=[];model.activeID=nil;model.selectedID=nil;model.prepareChat();await settle()
            if CommandLine.arguments.contains("--compact-control-probe") {
                _ = try makeFixtures(in: output)
                try await runCompactCompanionAcceptance(output: output, results: &results)
                try await runImportFeedbackAcceptance(output: output, results: &results)
                try await runChatGPTWorkspaceVisualAcceptance(output: output, results: &results)
                for (name, passed) in await CurrentWorkContextChecks.run() { results[name] = passed }
                try await runCurrentWorkIntegrationAcceptance(output: output, results: &results)
                try await runManualHiddenCaptureAcceptance(output: output, results: &results)
                try await runCompanionCommandAcceptance(output: output, results: &results)
                try await runCurrentWorkVisualAcceptance(output: output, results: &results)
                let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: output.appendingPathComponent("results.json")); print(String(data: data, encoding: .utf8)!)
                model.suspend(); exit(results.values.allSatisfy { $0 } ? 0 : 1)
            }
            results["generalChatOpensWithoutSetup"]=model.active?.mode == .assistant && model.active?.duration == 0 && workspace.isVisible
            try snapshot(workspace,to:output.appendingPathComponent("01-new-chat.png"))
            func findEditor(_ view:NSView)->ComposerTextView?{if let editor=view as? ComposerTextView{return editor};for child in view.subviews{if let found=findEditor(child){return found}};return nil}
            let editor=findEditor(workspace.contentView!);results["composerGetsKeyboardFocus"]=workspace.firstResponder === editor
            model.draft="First line";await settle()
            if let editor,let enter=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.shift,timestamp:0,windowNumber:workspace.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36){editor.setSelectedRange(NSRange(location:editor.string.utf16.count,length:0));NSApp.sendEvent(enter);results["shiftReturnAddsNewline"]=model.draft.contains("\n")}
            model.send("Cancellation probe");model.cancel();await settle();results["cancelDiscardsPendingCompletion"] = !model.busy && model.active?.messages.last?.role == "user";model.updateActive{$0.messages=[];$0.title="New chat"}
            let fixtures=try makeFixtures(in:output);await model.importFiles(fixtures)
            results["multipleImagePDFTextImports"]=model.pendingFiles.count==4
            let faultDirectory=output.appendingPathComponent("send-save-fault-\(UUID().uuidString)")
            let faulted=AppModel(dataDirectory:faultDirectory);faulted.voice.enableFixtures();faulted.newSession(title:"Save failure fixture")
            faulted.draft="My personal unsent draft";faulted.pasteImage(try Data(contentsOf:fixtures[0]));faulted.persist()
            var faultRequests=0;faulted.provider.fixtureReply={_,_,_,_ in faultRequests+=1}
            let faultFile=faultDirectory.appendingPathComponent("sessions.json");let preserved=try Data(contentsOf:faultFile)
            try FileManager.default.removeItem(at:faultFile);try FileManager.default.createDirectory(at:faultFile,withIntermediateDirectories:false)
            faulted.send("A generated command prompt",preserveDraft:true)
            results["failedSendRestoresPersonalDraftAndPendingFile"] = !faulted.busy && faultRequests==0 && faulted.active?.messages.isEmpty==true && faulted.pendingFiles.count==1 && faulted.draft=="My personal unsent draft" && faulted.active?.draft==faulted.draft
            try FileManager.default.removeItem(at:faultFile);try preserved.write(to:faultFile,options:.atomic);faulted.persist()
            let recovered=try SessionStore(directory:faultDirectory).load().first
            results["failedSendDraftAndFilesSurviveStorageRecovery"] = recovered?.draft=="My personal unsent draft" && recovered?.pendingAttachments.count==1 && recovered?.messages.isEmpty==true
            faulted.suspend()
            do{_=try model.fileStore!.importData(Data([0,1,2,3]),name:"archive.zip",fileExtension:"zip");results["unsupportedBinaryRejected"]=false}catch{results["unsupportedBinaryRejected"]=true}
            await model.importFiles(Array(repeating:fixtures[0],count:5));results["fileLimitPreservesExistingAttachments"]=model.pendingFiles.count==4 && model.error != nil;model.error=nil
            model.pasteImage(try Data(contentsOf:fixtures[0]));results["pastedImageImports"]=model.pendingFiles.count==5 && model.pendingFiles.last?.name == "Pasted image.png"
            if let pasted=model.pendingFiles.last, pasted.name == "Pasted image.png"{model.removeFile(pasted)}
            let files=try model.fileStore!.context(for:model.active!.files)
            results["PDFTextExtraction"]=files.text.contains("HARBOR-73")
            results["textFileExtraction"]=files.text.contains("bring a notebook")
            results["twoImagesPrepared"]=files.images.count==2
            model.draft="Compare the two images and summarize the PDF and notes."
            await settle();try snapshot(workspace,to:output.appendingPathComponent("03-attachments.png"))
            if let pdf=model.pendingFiles.first(where:{$0.kind == .pdf}){model.showFile?(pdf);await settle();try snapshot(workspace,to:output.appendingPathComponent("04-PDF-preview.png"));model.closeInspector()}
            model.togglePause();results["pausePreservesDraftAndFiles"]=model.draft.contains("Compare") && model.pendingFiles.count==4
            results["pauseStopsMicAndSharing"] = !model.voice.listening && model.context.filter == nil && !model.busy
            await settle();try snapshot(workspace,to:output.appendingPathComponent("05-paused.png"));model.togglePause()
            model.setMode(.learn);results["modeSwitchPreservesContext"]=model.pendingFiles.count==4 && !model.draft.isEmpty
            await settle();try snapshot(workspace,to:output.appendingPathComponent("06-optional-learn-mode.png"));model.setMode(.assistant)
            if CommandLine.arguments.contains("--integration-test"){
                model.draft="Compare the two images, then give the verification token in the PDF and the reminder in the text file. Be brief."
                await settle()
                let eligible = model.provider.account.permitsPlanUsage
                let unsentDraft = model.draft, unsentFiles = model.pendingFiles
                let messageCount = model.active?.messages.count
                let unsentBytes = try unsentFiles.map { try Data(contentsOf: model.fileStore!.url(for: $0)) }
                if let editor,let enter=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:workspace.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36){workspace.makeFirstResponder(editor);NSApp.sendEvent(enter)}
                if eligible {
                    results["returnSendsMessage"]=model.active?.messages.last?.role == "user" && model.draft.isEmpty
                    await waitForReply()
                    let answer=model.active?.messages.last?.role == "assistant" ? model.active!.messages.last!.text.lowercased() : ""
                    results["realMultiImagePDFTextReply"]=answer.contains("red") && answer.contains("blue") && answer.contains("harbor-73") && answer.contains("notebook")
                    results["messageRetainsAttachments"]=model.active?.messages.first?.attachments.count==4 && model.pendingFiles.isEmpty
                    await settle();try snapshot(workspace,to:output.appendingPathComponent("07-real-general-reply.png"))
                } else {
                    let retainedBytes = try model.pendingFiles.map { try Data(contentsOf: model.fileStore!.url(for: $0)) }
                    results["disconnectedReturnPreservesExactDraftFilesAndMessageCount"] = model.draft == unsentDraft && model.pendingFiles.map(\.id) == unsentFiles.map(\.id) && retainedBytes == unsentBytes && model.active?.messages.count == messageCount && !model.busy
                    results["realMultiImagePDFTextReply"] = false
                    // Separate offline model/storage journey. This is not native Return or inference evidence.
                    let previousAdapter = model.provider.fixtureReply
                    var localCalls = 0
                    model.provider.fixtureReply = { _, _, _, complete in localCalls += 1; complete(.failure(AppError("Generated offline storage journey; no account request"))) }
                    model.send(); await until { !model.busy }
                    model.provider.fixtureReply = previousAdapter
                    results["offlineModelSendEstablishesSentFilePersistence"] = localCalls == 1 && model.active?.messages.last?.role == "user" && model.draft.isEmpty && model.active?.messages.first?.attachments.map(\.id) == unsentFiles.map(\.id) && model.pendingFiles.isEmpty
                    await settle();try snapshot(workspace,to:output.appendingPathComponent("07-offline-storage-journey.png"))
                }
            }else{
                let records=model.pendingFiles
                model.updateActive{$0.messages=[Message(role:"user",text:"Compare these and summarize the documents.",attachments:records),Message(role:"assistant",text:"A shows a red circle; B shows a blue square. The PDF’s verification token is HARBOR-73. Your note says to bring a notebook.")];$0.pendingAttachments=[];$0.title="Compare images and documents"}
                model.draft="Turn that into a short checklist."
                await settle();try snapshot(workspace,to:output.appendingPathComponent("07-general-reply-fixture.png"))
            }
            let id=model.activeID!;model.draft="A draft to preserve";model.persist();model.complete()
            results["closeChatKeepsSingleWorkspace"] = workspace.isVisible && model.activeID == nil
            let relaunched=AppModel(dataDirectory:output.appendingPathComponent("test-library"))
            relaunched.voice.enableFixtures();var launchPresented=false;relaunched.showWorkspace={launchPresented=true};relaunched.prepareChat()
            results["coldLaunchResumesClosedChatAndDraft"] = launchPresented && relaunched.activeID==id && relaunched.draft=="A draft to preserve" && relaunched.active?.files.count==4
            relaunched.suspend()
            model.setTakeaway("A circle and a square; HARBOR-73; bring a notebook.",for:id);model.persist();await settle();try snapshot(workspace,to:output.appendingPathComponent("08-chat-history.png"))
            model.resume(id);results["resumeRestoresFilesAndDraft"]=model.active?.files.count==4 && model.draft == "A draft to preserve"
            model.rename(id,to:"Images and planning notes");results["renameAndSearch"] = model.active?.title == "Images and planning notes" && model.active?.matches("Brief.pdf")==true
            if let image=model.active?.files.first(where:{$0.kind == .image}){model.removeFile(image);results["sentFileStaysWithItsQuestion"]=model.fileStore?.image(for:image) != nil && model.active?.files.count==4}
            model.pasteImage(try Data(contentsOf:fixtures[0]))
            if let unsent=model.pendingFiles.last{model.removeFile(unsent);results["removeDeletesUnsentManagedFile"]=model.fileStore?.image(for:unsent)==nil && model.pendingFiles.isEmpty && model.active?.files.count==4}
            model.openSettings();await settle();try snapshot(workspace,to:output.appendingPathComponent("09-settings-updates.png"))
            func scrollSettings(_ view:NSView)->Bool {
                if let scroll=view as? NSScrollView, !scroll.isHiddenOrHasHiddenAncestor, let document=scroll.documentView, document.bounds.height > scroll.contentView.bounds.height + 1 {
                    document.scroll(NSPoint(x:0,y:document.isFlipped ? max(0,document.bounds.height-scroll.contentView.bounds.height) : 0));scroll.reflectScrolledClipView(scroll.contentView);return true
                }
                for child in view.subviews{if scrollSettings(child){return true}};return false
            }
            _=scrollSettings(workspace.contentView!);await settle();try snapshot(workspace,to:output.appendingPathComponent("09b-update-controls.png"))
            results["unconfiguredUpdaterStaysInactive"] = !model.updates.canCheck && model.updates.configuration==nil
            results["singleStableCompanion"]=workspaceMinimumIsValid(workspace) && NSApp.windows.filter{$0.isVisible && $0.identifier?.rawValue == "vale.workspace"}.count == 1
            results["sessionStoreRoundTrip"]=try SessionStore(directory:output.appendingPathComponent("test-library")).load().contains{$0.id==id && $0.draft == "A draft to preserve" && $0.files.count==4}
            model.error="The connection stopped. Your message and attachments are saved.";model.backToChat();openWorkspace();await settle();try snapshot(workspace,to:output.appendingPathComponent("10-recovery.png"))
            if CommandLine.arguments.contains("--integration-test"){
                model.newSession(title:"Web search verification");model.setWeb(true)
                model.send("Search the web for Apple’s official ScreenCaptureKit documentation. Give one direct link to the developer.apple.com documentation page, with a brief description. You must actually use web search.")
                await waitForReply()
                let answer=model.active?.messages.last?.role == "assistant" ? model.active!.messages.last!.text : ""
                results["explicitWebSearchUsesRealTool"]=model.provider.usedWebSearch && answer.contains("developer.apple.com/documentation/screencapturekit")
                await settle();try snapshot(workspace,to:output.appendingPathComponent("11-live-web-search.png"))
                model.setWeb(false);results["webSearchCanBeTurnedOff"]=model.active?.webEnabled == false
            }
            try await runInteractionFixtures(output:output,results:&results)
            do {
                let defaults = UserDefaults.standard
                let savedAppearance = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "local.lilt.companion")?["valeAppearance"]
                defaults.set("system", forKey: "valeAppearance")
                defer {
                    if let savedAppearance { defaults.set(savedAppearance, forKey: "valeAppearance") }
                    else { defaults.removeObject(forKey: "valeAppearance") }
                }
                try await runWorkspaceAcceptance(output:output,results:&results)
            }
            for (name, passed) in await ChatGPTAccountChecks.run() { results[name] = passed }
            for (name, passed) in await CurrentWorkContextChecks.run() { results[name] = passed }
            try await runCurrentWorkIntegrationAcceptance(output: output, results: &results)
            try await runManualHiddenCaptureAcceptance(output: output, results: &results)
            try await runCompanionCommandAcceptance(output: output, results: &results)
            try await runCurrentWorkVisualAcceptance(output: output, results: &results)
            let data=try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]);try data.write(to:output.appendingPathComponent("results.json"));print(String(data:data,encoding:.utf8)!);model.suspend();exit(results.values.allSatisfy{$0} ? 0 : 1)
        }catch{print("Harness failed: \(error)");exit(1)}
    }
}
