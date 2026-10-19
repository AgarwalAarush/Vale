import AppKit
import LiltCore
import SwiftUI

private final class DeletionFault:@unchecked Sendable {let lock=NSLock();private var failing=true;func recover(){lock.lock();failing=false;lock.unlock()};func remove(_ url:URL)throws{lock.lock();let denied=failing;lock.unlock();if denied{throw AppError("Generated fixture deletion denial")};try FileManager.default.removeItem(at:url)}}

extension AppController {
    func until(_ condition:()->Bool,seconds:Double=4)async{let deadline=Date().addingTimeInterval(seconds);while !condition(),Date()<deadline{try? await Task.sleep(nanoseconds:50_000_000)}}
    func runInteractionFixtures(output:URL,results:inout [String:Bool])async throws{
        let frame=CGRect(x:100,y:100,width:400,height:260)
        let fixtures=try makeFixtures(in:output)
        let first=try Data(contentsOf:fixtures[0]);let second=try Data(contentsOf:fixtures[1])
        var bytes=first;var captureCount=0;var transmitted=0;var pending:((Result<TutorReply,Error>)->Void)?
        var selectedFrameSent=false;var pointCount=0;let originalPoint=model.showPoint;model.showPoint={_,_ in pointCount+=1}
        defer{model.provider.fixtureReply=nil;model.context.stop();model.voice.stop();model.conversation=false;model.showPoint=originalPoint}
        func snapshotFor(_ data:Data,id:CGWindowID=42)->ContextSnapshot{ContextSnapshot(data:data,image:NSImage(data:data)!,windowID:id,frame:frame,generation:UUID(),capturedAt:Date())}
        func selectFixture(){model.context.installFixture{captureCount+=1;return snapshotFor(bytes)}}
        model.newSession(title:"Synthetic live context");model.voice.enableFixtures()
        model.provider.fixtureReply={_,images,_,completion in transmitted+=1;pending=completion;selectedFrameSent=images.first == bytes}
        // Keep observations in local values; no captured screen or audio is persisted by the product.
        selectFixture();let beforeNames=try FileManager.default.contentsOfDirectory(atPath:model.fileStore!.directory.path)
        model.context.startLive();await until{model.context.latest != nil}
        results["fixture_liveRequiresSelectionAndDoesNotTransmit"]=model.context.live && model.context.latest?.data==first && transmitted==0
        await settle();try snapshot(workspace,to:output.appendingPathComponent("12-live-context.png"))
        bytes=second;await until({model.context.latest?.data==second},seconds:3)
        results["fixture_liveRefreshesOnlyLatestFrame"]=model.context.latest?.data==second && captureCount>=2
        results["fixture_liveDoesNotPersistCaptureBytes"]=(try FileManager.default.contentsOfDirectory(atPath:model.fileStore!.directory.path))==beforeNames
        model.context.stopLive();let stoppedCount=captureCount;try? await Task.sleep(nanoseconds:2_100_000_000)
        results["fixture_stopLiveClearsPreviewAndStopsRefresh"]=model.context.latest==nil && !model.context.live && model.context.hasSelection && captureCount==stoppedCount
        model.previewContext();await settle();results["fixture_previewRequiresHeldPixels"] = model.contextPreview == nil && model.inspector != .context
        model.context.startLive();await until{model.context.latest != nil};model.previewContext();await settle();let previewHeld=model.inspector == .context && model.contextPreview != nil;model.stopSharing();await settle();results["fixture_stopSharingClosesPreviewPixels"]=previewHeld && model.contextPreview == nil && model.inspector != .context;selectFixture();openWorkspace()
        model.send("Explain the synthetic window",guideRequested:true);await until{pending != nil}
        results["fixture_requestUsesFreshSelectedFrame"]=selectedFrameSent && model.busy
        results["fixture_onDemandDoesNotKeepPreviewPixels"]=model.context.latest==nil
        await settle();try snapshot(workspace,to:output.appendingPathComponent("13-loading.png"))
        bytes=first;let stale=pending;pending=nil;stale?(.success(TutorReply(text:"This reply used the earlier synthetic frame.",point:PointTarget(x:0.35,y:0.3,width:0.3,height:0.4,label:"Fixture shape"),guide:GuidePlan(title:"Old frame",steps:["Read old frame","Act on old frame"]))))
        await until{model.active?.messages.last?.screenChanged==true}
        results["fixture_changedScreenSuppressesPointAndMarksReply"]=model.active?.messages.last?.screenChanged==true && pointCount==0
        results["fixture_staleScreenCannotInstallNewGuide"]=model.active?.guide==nil
        await settle();try snapshot(workspace,to:output.appendingPathComponent("14-window-changed.png"))
        model.send("A generated connection failure");await until{pending != nil};let failure=pending;pending=nil;failure?(.failure(AppError("Fixture connection interrupted. Your message is saved.")))
        await until{!model.busy};let count=model.active?.messages.count ?? 0
        results["fixture_failedReplyKeepsMessageAndShowsError"]=model.error != nil && model.active?.messages.last?.role=="user"
        await settle();try snapshot(workspace,to:output.appendingPathComponent("15-error-retry.png"))
        model.retry();await until{pending != nil};let retry=pending;pending=nil;retry?(.success(TutorReply(text:"Recovered from the synthetic connection failure.")));await until{!model.busy}
        results["fixture_retryDoesNotDuplicateUserMessage"]=model.error==nil && model.active?.messages.count==count+1 && model.active?.messages.last?.role=="assistant"
        model.send("Delayed fixture reply");await until{pending != nil};let late=pending;pending=nil;let oldID=model.activeID
        model.newSession(title:"A new chat after interruption");late?(.success(TutorReply(text:"LATE-FIXTURE-MUST-NOT-APPEAR")));await settle()
        results["fixture_sessionSwitchRejectsLateReplyAndClearsContext"]=model.activeID != oldID && model.active?.messages.isEmpty==true && !model.context.hasSelection && model.context.latest==nil
        let sentBefore=transmitted;model.context.installFixture{snapshotFor(first,id:99)};model.send("Never send a different window");await until{!model.busy}
        results["fixture_unrelatedWindowIsRejectedBeforeTransmission"]=transmitted==sentBefore && model.error != nil
        model.setConversation(true);model.context.installFixture{throw AppError("Fixture screen permission denied")};model.context.startLive();await until{!model.context.live}
        results["fixture_captureFailureStopsSelectionAndClearsMemory"] = !model.context.hasSelection && model.context.latest==nil && model.error != nil && !model.conversation && !model.voice.listening
        let geometrySent=transmitted;model.context.installFixture(frame:.zero){snapshotFor(first)};model.pointItOut();results["fixture_missingGeometryExplainsPointingLimitWithoutSending"]=transmitted==geometrySent && model.error?.contains("position is unavailable")==true
        model.context.installFixture(timeout:0.15){try await Task.sleep(nanoseconds:5_000_000_000);return snapshotFor(first)};model.context.startLive();await until{!model.context.live}
        results["fixture_captureTimeoutStopsAndClearsContext"] = !model.context.hasSelection && model.context.latest==nil && !model.context.capturing
        let hiddenSent=transmitted;model.context.installFixture(onScreen:false){snapshotFor(first)};model.context.startLive();await until{!model.context.live};results["fixture_hiddenSelectedWindowStopsBeforeTransmission"]=transmitted==hiddenSent && !model.context.hasSelection && model.context.latest==nil
        model.newSession(title:"Synthetic spoken conversation");selectFixture()
        model.provider.fixtureReply={_,_,_,complete in transmitted+=1;complete(.success(TutorReply(text:"A short synthetic spoken answer.")))}
        model.setConversation(true);let token=model.voice.fixtureRecognitionToken
        results["fixture_conversationStartsOnlyOnOptIn"]=model.conversation && model.voice.listening
        model.voice.simulateUtterance("Explain this fixture",token:token);await until{model.voice.speaking}
        results["fixture_turnTakingWaitsDuringReply"]=model.conversation && model.voice.speaking && !model.voice.listening
        let oldPlayback=model.voice.fixturePlaybackToken;model.toggleVoice();let interruptedToken=model.voice.fixtureRecognitionToken;model.voice.simulatePlaybackFinished(token:oldPlayback)
        results["fixture_interruptStopsPlaybackWithoutOldRearm"] = !model.voice.listening && !model.voice.speaking && model.voice.fixtureRecognitionToken==interruptedToken
        model.setConversation(true);let nextToken=model.voice.fixtureRecognitionToken
        model.voice.simulateUtterance("One more fixture question",token:nextToken);await until{model.voice.speaking};let playback=model.voice.fixturePlaybackToken;model.voice.simulatePlaybackFinished(token:playback);await until{model.voice.listening}
        results["fixture_conversationRearmsAfterCurrentPlayback"]=model.conversation && model.voice.listening && !model.voice.speaking
        model.context.startLive();await until{model.context.latest != nil};await settle();try snapshot(workspace,to:output.appendingPathComponent("17-conversation.png"))
        let pausedToken=model.voice.fixtureRecognitionToken;model.togglePause();let messages=model.active?.messages.count
        model.voice.simulateUtterance("STALE-SPEECH",token:pausedToken);await settle()
        results["fixture_pauseStopsActiveVoiceLiveCaptureAndLateSpeech"]=model.paused && !model.conversation && !model.voice.listening && !model.voice.speaking && !model.context.hasSelection && model.context.latest==nil && model.active?.messages.count==messages
        model.togglePause();results["fixture_resumeDoesNotRestartMicOrCapture"] = !model.voice.listening && !model.context.hasSelection && !model.conversation
        model.voice.fixturePermission=false;model.setConversation(true)
        results["fixture_permissionDenialKeepsTypedFallback"] = !model.voice.listening && !model.conversation && model.error != nil
        model.editDraft("Typed fallback after permission denial");model.send();await until{!model.busy};results["fixture_typedFallbackRecoversAfterVoiceDenial"]=model.active?.messages.last?.role=="assistant" && model.error==nil
        model.voice.fixturePermission=true
        model.newSession(title:"Conversation opt-out fixture")
        var deferredVoice:((Result<TutorReply,Error>)->Void)?
        model.provider.fixtureReply={_,_,_,completion in deferredVoice=completion}
        model.setConversation(true);model.voice.simulateUtterance("A delayed spoken question",token:model.voice.fixtureRecognitionToken);await until{deferredVoice != nil}
        model.setConversation(false);deferredVoice?(.success(TutorReply(text:"The delayed answer remains in the chat.")));await until{!model.busy}
        results["fixture_conversationOptOutKeepsReplyWithoutRearming"] = model.active?.messages.last?.role=="assistant" && !model.conversation && !model.voice.listening && model.voice.speaking==model.readAloud
        model.voice.stop()
        model.newSession(title:"Synthetic step-by-step help");selectFixture();let plan=GuidePlan(title:"Understand the diagram",steps:["Find the red circle","Trace its curved boundary","Describe its color and shape"])
        model.provider.fixtureReply={prompt,_,_,complete in complete(.success(TutorReply(text:prompt.contains("Help me with step 2") ? "Follow the curved edge. Every point stays the same distance from the center." : "Start by locating the red circle.",point:PointTarget(x:0.35,y:0.3,width:0.3,height:0.4,label:"Synthetic circle"),guide:plan)))}
        model.draft="Help me understand the circle";model.startGuide();await until{model.active?.guide?.plan==plan}
        results["fixture_guideStartsWithValidatedPlan"]=model.active?.guide?.index==0 && model.active?.guide?.plan==plan
        results["fixture_stableSelectedFrameAllowsValidatedPoint"]=pointCount>0
        let beforeStep=captureCount;model.moveGuide(1);await until{!model.busy && !model.context.capturing};await settle();model.persist()
        results["fixture_nextGuideStepCapturesFreshContext"]=model.active?.guide?.index==1 && captureCount>beforeStep
        let saved=try SessionStore(directory:output.appendingPathComponent("test-library")).load().first{$0.id==model.activeID}
        results["fixture_guideProgressPersists"]=saved?.guide?.index==1
        await settle();try snapshot(workspace,to:output.appendingPathComponent("19-step-guide.png"))
        let pointsBefore=pointCount;model.context.installFixture(pointVisible:false){captureCount+=1;return snapshotFor(first)};model.pointItOut();await until{model.active?.messages.last?.highlightUnavailable==true};results["fixture_occludedPointIsSuppressedAndExplained"]=pointCount==pointsBefore && model.active?.messages.last?.highlightUnavailable==true
        await settle();try snapshot(workspace,to:output.appendingPathComponent("20-occluded-highlight.png"));selectFixture()
        model.endGuide()
        model.updateActive{$0.messages=(0..<30).map{Message(role:"user",text:"Generated earlier context message \($0)")}}
        await settle();results["fixture_contextLimitIsExposed"]=model.active?.contextLimited==true;try snapshot(workspace,to:output.appendingPathComponent("21-context-limit.png"))
        model.newSession(title:"Own-window keyboard checks");selectFixture();model.context.startLive();model.setConversation(true);await settle()
        let previousID=model.activeID
        if let key=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:workspace.windowNumber,context:nil,characters:"n",charactersIgnoringModifiers:"n",isARepeat:false,keyCode:45){NSApp.sendEvent(key)}
        await settle();results["fixture_commandNStartsCleanChat"]=model.activeID != previousID && !model.conversation && !model.voice.listening && !model.context.hasSelection
        selectFixture();model.context.startLive();model.setConversation(true);await settle()
        if let key=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:workspace.windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53){NSApp.sendEvent(key)}
        await settle();results["fixture_escapeStopsConversationAndSharing"] = !model.conversation && !model.voice.listening && !model.context.hasSelection && !model.busy
        var repeated=true
        for _ in 0..<3{selectFixture();model.context.startLive();model.setConversation(true);await until{model.context.latest != nil};systemSuspend();repeated = repeated && model.paused && !model.voice.listening && !model.conversation && !model.context.hasSelection && model.context.latest==nil;model.togglePause()}
        results["fixture_repeatedSuspendResumeDoesNotRestartCaptureOrMic"]=repeated
        model.shortcutWarning="Fixture shortcut conflict: open from the menu bar.";model.newSession();results["fixture_shortcutWarningSurvivesNewChat"]=model.shortcutWarning != nil;model.shortcutWarning=nil
        try await deletionFixtures(output:output,source:first,results:&results)
        if CommandLine.arguments.contains("--integration-test"){
            model.newSession(title:"Real provider · synthetic window");selectFixture();model.provider.fixtureReply=nil
            model.draft="This is a synthetic test window showing a red circle. Give a concise three-step guide to describe this shape and its color, one step at a time."
            model.startGuide();await waitForReply();await until{model.active?.guide?.plan.isValid==true};results["realProviderGuideWithSyntheticScreen"]=model.active?.messages.last?.role=="assistant" && model.active?.guide?.plan.isValid==true
            await settle();try snapshot(workspace,to:output.appendingPathComponent("24-real-guide-synthetic-screen.png"))
        }
    }
    func deletionFixtures(output:URL,source:Data,results:inout [String:Bool])async throws{
        let directory=output.appendingPathComponent("privacy-fixtures-\(UUID().uuidString)");_=try SessionStore(directory:directory);let files=try AttachmentStore(directory:directory)
        let aFile=try files.importData(source,name:"Delete fixture.png",fileExtension:"png");let bFile=try files.importData(source,name:"Keep fixture.png",fileExtension:"png")
        var a=LearningSession(title:"Forget migrated fixture",mode:.learn);a.pendingAttachments=[aFile];var b=LearningSession(title:"Keep unrelated migrated fixture",mode:.learn);b.pendingAttachments=[bFile]
        var rows=try JSONSerialization.jsonObject(with:JSONEncoder().encode([a,b])) as! [[String:Any]];for i in rows.indices{rows[i].removeValue(forKey:"mode")}
        try JSONSerialization.data(withJSONObject:rows).write(to:directory.appendingPathComponent("sessions.json"))
        let fixture=AppModel(dataDirectory:directory);fixture.delete(a.id)
        let backup=try JSONDecoder().decode([LearningSession].self,from:Data(contentsOf:directory.appendingPathComponent("sessions-v1-backup.json")))
        results["fixture_forgetPurgesLegacyBackupAndManagedBytes"]=fixture.sessions.map(\.id)==[b.id] && backup.map(\.id)==[b.id] && files.image(for:aFile)==nil && files.image(for:bFile) != nil
        let proof:[String:Any]=["fixtureDirectory":directory.path,"targetID":a.id.uuidString,"remainingSessionIDs":fixture.sessions.map{$0.id.uuidString},"remainingBackupIDs":backup.map{$0.id.uuidString},"targetBytesRemoved":files.image(for:aFile)==nil,"unrelatedBytesPreserved":files.image(for:bFile) != nil]
        try JSONSerialization.data(withJSONObject:proof,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("privacy-proof.json"))
        let denialDirectory=output.appendingPathComponent("deletion-denial-fixture");let fault=DeletionFault();let denied=AppModel(dataDirectory:denialDirectory,fileRemoval:{try fault.remove($0)})
        denied.newSession(title:"Retryable deletion fixture");denied.pasteImage(source);let record=denied.active!.files[0];let id=denied.activeID!
        denied.importing=true;denied.delete(id);results["fixture_forgetWaitsForPendingImports"]=denied.sessions.contains{$0.id==id} && denied.fileStore?.image(for:record) != nil && denied.error != nil;denied.importing=false
        denied.removeFile(record);results["fixture_fileDeletionFailureKeepsAttachmentAndReportsError"]=denied.active?.files.contains(record)==true && denied.fileStore?.image(for:record) != nil && denied.error != nil
        denied.delete(id);results["fixture_forgetFailureKeepsRetryableChat"]=denied.sessions.contains{$0.id==id} && denied.error != nil
        denied.selectedID=id
        let originalContent = workspace.contentView
        let host = NSHostingView(rootView: WorkspaceView(model: denied)); host.sizingOptions = []; host.autoresizingMask = [.width, .height]
        workspace.contentView = host; workspace.setContentSize(NSSize(width: 1040, height: 740))
        await settle();try snapshot(workspace,to:output.appendingPathComponent("22-deletion-error.png"))
        fault.recover();denied.delete(id);results["fixture_retryForgetRemovesBytesAndChat"]=denied.sessions.isEmpty && denied.fileStore?.image(for:record)==nil && denied.error==nil
        await settle();try snapshot(workspace,to:output.appendingPathComponent("23-forget-recovered.png"));workspace.contentView = originalContent
        denied.suspend();fixture.suspend();model.error=nil;openWorkspace()
    }
}
