import AppKit
import Combine
import LiltCore
import UniformTypeIdentifiers

private struct ImportOutcome: Sendable { var record: AttachmentRecord?; var error: String? }

@MainActor final class AppModel: ObservableObject {
    @Published var sessions: [LearningSession] = []
    @Published var activeID: UUID?
    @Published var paused = true
    @Published var busy = false
    @Published var conversation=false
    @Published var importing = false
    @Published private(set) var errorOffersSettings = false
    private var settingsForNextError = false
    @Published var error: String? {
        didSet {
            if error == nil { errorOffersSettings = false; settingsForNextError = false }
            else { errorOffersSettings = settingsForNextError; settingsForNextError = false }
        }
    }
    @Published var draft = "" { didSet { if !loading { updateActive { $0.draft = draft }; scheduleSave() } } }
    @Published var selectedID: UUID?
    @Published var settings = false
    @Published var onboarding = false // Kept for old preference compatibility; no setup gate.
    @Published var readAloud = UserDefaults.standard.bool(forKey: "readAloud") { didSet { UserDefaults.standard.set(readAloud, forKey: "readAloud"); if !readAloud && !conversation { voice.stopSpeaking() } } }
    let context = WindowContext()
    let voice = VoiceController()
    let provider = TutorProvider()
    let updates = UpdateController()
    let fileStore: AttachmentStore?
    private let store: SessionStore?
    private var timer: Timer?
    private var lastTick = Date()
    private var saveWork: DispatchWorkItem?
    private var requestID = UUID()
    private var captureTask: Task<Void, Never>?
    private var loading = false
    private var observerTokens: [AnyCancellable] = []
    private var failedQuestion: String?
    private var spokenDraftPrefix = ""
    private var conversationTask:Task<Void,Never>?
    @Published var shortcutWarning:String?
    var showCoach: (() -> Void)?
    var showLibrary: (() -> Void)?
    var hideOverlay: (() -> Void)?
    var showPoint: ((PointTarget, ContextSnapshot) -> Void)?
    var contextReset:(()->Void)?
    var filesRemoved:((Set<UUID>)->Void)?
    var showPreview: ((NSImage) -> Void)?
    var expandCoach:(()->Void)?
    @Published var expanded=false
    var showFile: ((AttachmentRecord) -> Void)?
    var active: LearningSession? { sessions.first { $0.id == activeID } }
    var selected: LearningSession? { sessions.first { $0.id == selectedID } }
    var contextName: String? { context.title }
    var pendingFiles: [AttachmentRecord] { active?.pendingAttachments ?? [] }
    var hasInput: Bool { !draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || !pendingFiles.isEmpty }
    var status: String { paused ? "Paused" : importing ? "Adding files…" : voice.starting ? "Waiting for microphone…" : voice.listening ? "Listening…" : busy ? "Thinking…" : voice.speaking ? "Speaking · tap mic to interrupt" : conversation ? "Conversation ready" : "Voice off" }
    init(dataDirectory: URL? = nil,fileRemoval:(@Sendable(URL)throws->Void)?=nil) {
        // Retain the 1.0 storage identifier so the Vale rename never strands chats.
        let directory = dataDirectory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Lilt")
        var loadedStore: SessionStore?; var loadedFiles: AttachmentStore?
        do { let candidate=try SessionStore(directory:directory); sessions=try candidate.load().sorted{$0.updated>$1.updated}; loadedFiles=try AttachmentStore(directory:directory,unlink:fileRemoval); loadedStore=candidate }
        catch { self.error="Couldn’t open your chats. Check the storage folder before starting a new chat." }
        store=loadedStore; fileStore=loadedFiles
        updates.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in:&observerTokens)
        context.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in:&observerTokens)
        voice.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in:&observerTokens)
        context.failed = { [weak self] message in self?.stopResponse();self?.error=message }
        context.changed = { [weak self] in guard let self else{return};self.contextReset?(); self.hideOverlay?(); if self.busy { self.cancel(); self.error="Sharing changed. Your message is saved; retry when you’re ready." } }
        voice.failed = { [weak self] message in self?.conversation=false;self?.conversationTask?.cancel();self?.error=message }
        voice.playbackFinished = { [weak self] in self?.listenForNextTurn() }
        voice.playbackInterrupted = { [weak self] in self?.conversation=false }
        voice.partial = { [weak self] text in guard let self else{return}; self.draft=self.spokenDraftPrefix+text }
        voice.finished = { [weak self] _ in self?.send(spoken:true) }
        provider.located = { [weak self] in self?.objectWillChange.send() }
        provider.locateWithLoginShell()
        timer=Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in MainActor.assumeIsolated {self?.tick()} }
    }
    func openSettings() { settings = true; showLibrary?() }
    func showError(_ message: String, settings: Bool = false) { settingsForNextError = settings; error = message }
    func prepareChat() {
        guard active == nil else { showCoach?(); return }
        if let recent=LaunchSelection.resumeID(in: sessions) { resume(recent.id) }
        else { newSession() }
    }
    func newSession(title: String = "New chat", minutes: Int = 0, mode: ChatMode = .assistant) {
        guard store != nil else { error="The chat library is unavailable. Restore the library folder before starting."; return }
        suspend()
        if !importing,let old=active, old.title == "New chat",old.messages.isEmpty,old.draft.isEmpty,old.files.isEmpty {sessions.removeAll{$0.id==old.id}}
        let title=title.trimmingCharacters(in:.whitespacesAndNewlines)
        let chat=LearningSession(title:title.isEmpty ? "New chat" : String(title.prefix(100)),duration:minutes>0 ? max(5,min(180,minutes))*60 : 0,mode:mode)
        sessions.insert(chat,at:0); activeID=chat.id; selectedID=chat.id
        loading=true; draft=""; loading=false; paused=false; lastTick=Date(); error=nil; failedQuestion=nil
        persist(); showCoach?()
    }
    func resume(_ id: UUID) {
        suspend(); guard let chat=sessions.first(where:{$0.id==id}) else{return}
        activeID=id; selectedID=id; loading=true; draft=chat.draft; loading=false
        updateActive{$0.completed=false}; paused=false; lastTick=Date(); error=nil; failedQuestion=nil
        persist(); showCoach?()
    }
    func setMode(_ mode: ChatMode) { conversation=false;conversationTask?.cancel();cancel(); voice.stopListening(); updateActive{$0.mode=mode}; persist() }
    func setWeb(_ enabled: Bool) { updateActive{$0.webEnabled=enabled}; persist() }
    func setFocus(minutes: Int) { updateActive{$0.duration=minutes>0 ? $0.elapsed+minutes*60 : 0}; persist() }
    func tick() {
        defer{lastTick=Date()}; guard !paused,active != nil else{return}
        let seconds=max(0,Int(Date().timeIntervalSince(lastTick).rounded())); updateActive{$0.elapsed+=seconds}
        if active?.elapsed.isMultiple(of:30)==true {persist()}
    }
    func togglePause() {if paused {paused=false; lastTick=Date(); error=nil} else{tick();suspend()};persist()}
    func suspend() {paused=true;conversation=false;conversationTask?.cancel();voice.stop();cancel();context.stop();hideOverlay?();persist()}
    func complete() {
        tick();updateActive{$0.completed=true};suspend();selectedID=activeID;activeID=nil
        loading=true;draft="";loading=false;persist();showLibrary?()
    }
    func cancel() {requestID=UUID();captureTask?.cancel();captureTask=nil;provider.cancel();busy=false;voice.stopSpeaking();hideOverlay?()}
    func send(_ override: String? = nil, spoken: Bool = false, pointing: Bool = false, reveal: Bool = false, retry: Bool = false,guideRequested:Bool=false) {
        guard var chat=active else{return}
        var question=(override ?? draft).trimmingCharacters(in:.whitespacesAndNewlines)
        if question.isEmpty && !chat.pendingAttachments.isEmpty {question="Help me understand these attachments."}
        guard !question.isEmpty else{return}
        guard !importing else{error="Wait for your files to finish attaching.";return}
        guard !paused else{error="Resume the chat before sending a message.";return}
        guard question.count<=32_000 else{error="That message is too long. Attach it as a text file or send a smaller excerpt.";return}
        cancel();voice.stopListening();error=nil;busy=true
        let id=UUID();requestID=id;let chatID=chat.id
        if !retry {
            chat.messages.append(Message(role:"user",text:question,attachments:chat.pendingAttachments));chat.pendingAttachments=[];chat.updated=Date()
            if chat.title == "New chat" {chat.title=String(question.split(separator:"\n").first.map(String.init)?.prefix(60) ?? question.prefix(60))}
            replace(chat);draft=""
        }
        failedQuestion=question;persist()
        var history=chat
        if history.messages.last?.role=="user",history.messages.last?.text==question{history.messages.removeLast()}
        let records=chat.files;let files=fileStore;let wantsSearch=chat.webEnabled
        captureTask=Task { [weak self] in
            guard let self else{return};var snapshot:ContextSnapshot?
            do {
                if self.context.hasSelection {snapshot=try await self.context.capture()}
                guard !Task.isCancelled,self.requestID==id,self.activeID==chatID else{return}
                let fileContext=try await Task.detached(priority:.userInitiated) {try files?.context(for:records) ?? FileContext()}.value
                guard !Task.isCancelled,self.requestID==id,self.activeID==chatID else{return}
                var images=snapshot.map{[$0.data]} ?? [];images+=fileContext.images
                let prompt=TutorPrompt.build(session:history,question:question,hasImage:!images.isEmpty,pointing:pointing,reveal:reveal,fileContext:fileContext.text,hasWindow:snapshot != nil,guideRequested:guideRequested)
                self.provider.ask(prompt:prompt,images:images,search:wantsSearch) { [weak self] result in
                    guard let self,self.requestID==id,self.activeID==chatID else{return}
                    Task{[weak self]in
                        guard let self,self.requestID==id,self.activeID==chatID else{return}
                        switch result{
                        case .success(let reply):
                            var fresh:ContextSnapshot?
                            if snapshot != nil,self.context.hasSelection{fresh=try? await self.context.capture()}
                            guard self.requestID==id,self.activeID==chatID else{return}
                            let changed=snapshot.map{original in fresh.map{!original.evidence.reflectsSameView($0.evidence)} ?? true} ?? false
                            let canPoint:Bool
                            if let point=reply.point,let snapshot,let fresh,let frame=snapshot.frame,!changed{canPoint=snapshot.evidence.matches(fresh.evidence) && self.context.pointIsVisible(point,frame:frame,windowID:snapshot.windowID)}else{canPoint=false}
                            self.busy=false
                            self.updateActive{chat in
                                chat.messages.append(Message(role:"assistant",text:reply.text,screenChanged:changed,highlightUnavailable:reply.point != nil && !changed && !canPoint));chat.updated=Date()
                                if let plan=reply.guide,guideRequested,!changed{chat.guide=GuideProgress(plan:plan)}
                            }
                            if guideRequested,reply.guide != nil,!changed,!self.expanded{self.expandCoach?()}
                            self.failedQuestion=nil
                            if !changed,(self.readAloud || spoken || self.conversation){self.voice.speak(reply.text)}
                            else if changed,(self.readAloud || spoken || self.conversation){self.voice.speak("Your window changed while I was answering. Ask again for the current view.")}
                            else if self.conversation{self.listenForNextTurn()}
                            if canPoint,let point=reply.point,let snapshot{self.showPoint?(point,snapshot)}
                            self.persist()
                        case .failure(let failure):
                            self.busy=false;self.conversation=false
                            let app=failure as? AppError
                            self.showError(app?.message ?? failure.localizedDescription, settings: app?.offersSettings == true)
                        }
                    }
                }

            } catch {
                guard self.requestID==id else{return};self.busy=false
                self.conversation=false
                self.error=(error as? AppError)?.message ?? "Couldn’t read the selected context. Your message is saved; check the window or attachments and retry."
            }
        }
    }
    func retry(){if let question=failedQuestion ?? active?.messages.last.flatMap({$0.role == "user" ? $0.text : nil}){send(question,retry:true)}}
    func nextHint(){updateActive{$0.hintLevel=min(3,$0.hintLevel+1)};send("Give me one slightly more concrete hint, without revealing the full solution.")}
    func pointItOut(){guard context.hasSelection else{error="Share a window first so I can point to something specific.";return};guard let frame=context.currentFrame(),frame.width>1,frame.height>1,context.windowID != nil else{error="The window’s position is unavailable. Choose it again, or continue with text help.";return};send("Point out the relevant part of the shared window, with one short explanation.",pointing:true)}
    func toggleVoice(){
        guard !paused,active != nil else{return}
        if voice.listening{voice.finishUtterance()}
        else if voice.starting{conversation=false;voice.stopListening()}
        else{cancel();spokenDraftPrefix=draft.isEmpty ? "" : draft+" ";voice.start()}
    }
    func setConversation(_ enabled:Bool){
        conversationTask?.cancel();conversation=enabled
        if enabled{guard !paused,active != nil else{conversation=false;return};cancel();spokenDraftPrefix=draft.isEmpty ? "" : draft+" ";voice.start()}
        else{voice.stop();cancel()}
    }
    private func listenForNextTurn(){
        conversationTask?.cancel();guard conversation,!paused,active != nil else{return}
        let id=requestID;let chatID=activeID
        conversationTask=Task{[weak self]in
            try? await Task.sleep(nanoseconds:300_000_000)
            guard !Task.isCancelled,let self,self.conversation,!self.paused,self.requestID==id,self.activeID==chatID,!self.busy,!self.voice.speaking else{return}
            self.spokenDraftPrefix=self.draft.isEmpty ? "" : self.draft+" ";self.voice.start()
        }
    }
    func editDraft(_ text:String){conversation=false;conversationTask?.cancel();if voice.listening || voice.starting{voice.stopListening()};draft=text}
    func stopResponse(){conversation=false;conversationTask?.cancel();voice.stop();cancel()}
    func stopInteraction(){stopResponse();context.stop();hideOverlay?()}
    func startGuide(){
        guard !paused,!busy else{return}
        let goal=draft.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !goal.isEmpty || context.hasSelection else{error="Type what you’d like to work through, or share a window first.";return}
        send(goal.isEmpty ? "Guide me through the selected window, one step at a time. Start by identifying the task and the first useful action." : "Guide me step by step: \(goal)",pointing:context.hasSelection,reveal:true,guideRequested:true)
    }
    func moveGuide(_ delta:Int){
        guard let guide=active?.guide,!busy,!paused else{return}
        let index=max(0,min(guide.plan.steps.count-1,guide.index+delta));updateActive{$0.guide?.index=index};persist()
        send("Help me with step \(index+1): \(guide.plan.steps[index]). ",pointing:context.hasSelection,reveal:true)
    }
    func endGuide(){updateActive{$0.guide=nil};persist()}
    func refreshAnswer(){guard let question=active?.messages.last(where:{$0.role=="user"})?.text else{return};send(question,retry:true)}
    func stopSharing(){context.stop()}
    func previewContext(){
        let chatID=activeID;let generation=context.generation
        Task{[weak self]in
            guard let self else{return}
            do{let snapshot=try await self.context.capture();guard self.activeID==chatID,self.context.generation==generation else{return};self.showPreview?(snapshot.image)}
            catch{guard self.activeID==chatID,self.context.generation==generation else{return};self.error="That window couldn’t be captured. Choose it again."}
        }
    }
    func attachFiles(){
        if active == nil {prepareChat()}
        let panel=NSOpenPanel();panel.canChooseDirectories=false;panel.allowsMultipleSelection=true
        panel.message="Add images, PDFs, text, or code files"
        guard panel.runModal() == .OK else{return};let urls=panel.urls
        Task{await importFiles(urls)}
    }
    func importFiles(_ urls:[URL]) async {
        guard !importing,let chatID=activeID,let files=fileStore else{return}
        let valid=urls.filter(\.isFileURL)
        guard (active?.files.count ?? 0)+valid.count<=8 else{error="Attach up to 8 files in a chat. Remove a file or start a new chat.";return}
        importing=true;defer{importing=false}
        let outcomes=await Task.detached(priority:.userInitiated){valid.map{url -> ImportOutcome in do{return ImportOutcome(record:try files.importFile(url))}catch{return ImportOutcome(error:"\(url.lastPathComponent): \(error.localizedDescription)")}}}.value
        guard let index=sessions.firstIndex(where:{$0.id==chatID}) else{
            var retained:[AttachmentRecord]=[]
            for item in outcomes{if let record=item.record{do{try files.remove(record)}catch{retained.append(record)}}}
            if !retained.isEmpty{var recovery=LearningSession(title:"Files awaiting removal");recovery.pendingAttachments=retained;sessions.insert(recovery,at:0);persist();error="Some imported files couldn’t be removed. They were kept in Files awaiting removal so you can retry Forget."};return
        }
        sessions[index].pendingAttachments+=outcomes.compactMap(\.record);sessions[index].updated=Date()
        if let failure=outcomes.compactMap(\.error).first{error=failure}
        persist()
    }
    func pasteImage(_ data:Data){
        guard let files=fileStore,active != nil else{return}
        guard (active?.files.count ?? 0)<8 else{error="Attach up to 8 files in a chat.";return}
        do{let record=try files.importData(data,name:"Pasted image.png",fileExtension:"png");updateActive{$0.pendingAttachments.append(record)};persist()}catch{self.error=error.localizedDescription}
    }
    private func removeReferences(_ ids:Set<UUID>,from id:UUID){
        guard let index=sessions.firstIndex(where:{$0.id==id}) else{return}
        sessions[index].pendingAttachments.removeAll{ids.contains($0.id)}
        for i in sessions[index].messages.indices{sessions[index].messages[i].attachments.removeAll{ids.contains($0.id)}}
    }
    func removeFile(_ record:AttachmentRecord){
        guard let chatID=activeID else{return};if busy{cancel()}
        do{
            if !sessions.contains(where:{$0.id != chatID && $0.files.contains(where:{$0.id==record.id})}){try fileStore?.remove(record)}
            removeReferences([record.id],from:chatID);filesRemoved?([record.id]);persist()
        }catch{self.error="Couldn’t remove \(record.name). It is still attached; try removing it again."}
    }
    func rename(_ id:UUID,to title:String){guard let cleaned=ChatTitle.saved(title),let index=sessions.firstIndex(where:{$0.id==id})else{return};sessions[index].title=cleaned;persist()}
    func setTakeaway(_ text:String,for id:UUID){if let i=sessions.firstIndex(where:{$0.id==id}){sessions[i].takeaway=text;scheduleSave()}}
    @Published var deletionToRetry:UUID?
    func delete(_ id:UUID){
        guard !importing else{error="Files are still being added. Wait for them to finish, then try Forget again.";return}
        guard let chat=sessions.first(where:{$0.id==id}),let store else{return}
        if id==activeID{suspend()}
        var removed=Set<UUID>()
        do{
            for record in chat.files where !sessions.contains(where:{$0.id != id && $0.files.contains(where:{$0.id==record.id})}){
                try fileStore?.remove(record);removed.insert(record.id)
            }
            try store.forget(id,keeping:sessions)
            filesRemoved?(Set(chat.files.map(\.id)))
            sessions.removeAll{$0.id==id};if selectedID==id{selectedID=nil}
            if activeID==id{activeID=nil;loading=true;draft="";loading=false}
            deletionToRetry=nil;error=nil;showLibrary?()
        }catch{
            removeReferences(removed,from:id);filesRemoved?(removed);persist()
            deletionToRetry=id
            self.error="Couldn’t finish forgetting this chat. It was kept so you can retry. Some files may already have been removed."
            showLibrary?()
        }
    }
    func export(_ chat:LearningSession){
        let panel=NSSavePanel();panel.allowedContentTypes=[UTType(filenameExtension:"md") ?? .plainText];panel.nameFieldStringValue="\(chat.title.replacingOccurrences(of:"/",with:"-"))-notes.md"
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do{try SessionStore.export(chat).write(to:url,atomically:true,encoding:.utf8)}catch{self.error="Couldn’t export your chat."}
    }
    func updateActive(_ change:(inout LearningSession)->Void){guard let i=sessions.firstIndex(where:{$0.id==activeID})else{return};change(&sessions[i])}
    private func replace(_ chat:LearningSession){if let i=sessions.firstIndex(where:{$0.id==chat.id}){sessions[i]=chat}}
    private func scheduleSave(){saveWork?.cancel();let work=DispatchWorkItem{[weak self]in self?.persist()};saveWork=work;DispatchQueue.main.asyncAfter(deadline:.now()+0.5,execute:work)}
    func persist(){do{sessions.sort{$0.updated>$1.updated};try store?.save(sessions)}catch{self.error="Couldn’t save your chat. Check available disk space."}}
}
