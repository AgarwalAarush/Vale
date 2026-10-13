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
    @Published var importing = false
    @Published var error: String?
    @Published var draft = "" { didSet { if !loading { updateActive { $0.draft = draft }; scheduleSave() } } }
    @Published var selectedID: UUID?
    @Published var settings = false
    @Published var onboarding = false // Kept for old preference compatibility; no setup gate.
    @Published var readAloud = UserDefaults.standard.bool(forKey: "readAloud") { didSet { UserDefaults.standard.set(readAloud, forKey: "readAloud"); if !readAloud { voice.stopSpeaking() } } }
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
    var showCoach: (() -> Void)?
    var showLibrary: (() -> Void)?
    var hideOverlay: (() -> Void)?
    var showPoint: ((PointTarget, ContextSnapshot) -> Void)?
    var showPreview: ((NSImage) -> Void)?
    var showFile: ((AttachmentRecord) -> Void)?
    var active: LearningSession? { sessions.first { $0.id == activeID } }
    var selected: LearningSession? { sessions.first { $0.id == selectedID } }
    var contextName: String? { context.title }
    var pendingFiles: [AttachmentRecord] { active?.pendingAttachments ?? [] }
    var hasInput: Bool { !draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || !pendingFiles.isEmpty }
    var status: String { paused ? "Paused" : importing ? "Adding files…" : voice.listening ? "Listening…" : busy ? "Thinking…" : voice.speaking ? "Speaking…" : "Voice off" }
    init(dataDirectory: URL? = nil) {
        // Retain the 1.0 storage identifier so the Mythos rename never strands chats.
        let directory = dataDirectory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Lilt")
        var loadedStore: SessionStore?; var loadedFiles: AttachmentStore?
        do { let candidate=try SessionStore(directory:directory); sessions=try candidate.load().sorted{$0.updated>$1.updated}; loadedFiles=try AttachmentStore(directory:directory); loadedStore=candidate }
        catch { self.error="Couldn’t open your chats. Check the storage folder before starting a new chat." }
        store=loadedStore; fileStore=loadedFiles
        updates.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in:&observerTokens)
        context.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in:&observerTokens)
        voice.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in:&observerTokens)
        context.failed = { [weak self] in self?.error=$0 }
        context.changed = { [weak self] in guard let self else{return}; self.hideOverlay?(); if self.busy { self.cancel(); self.error="Sharing changed. Your message is saved; retry when you’re ready." } }
        voice.failed = { [weak self] in self?.error=$0 }
        voice.partial = { [weak self] text in guard let self else{return}; self.draft=self.spokenDraftPrefix+text }
        voice.finished = { [weak self] _ in self?.send(spoken:true) }
        timer=Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in MainActor.assumeIsolated {self?.tick()} }
    }
    func prepareChat() {
        guard active == nil else { showCoach?(); return }
        if let recent=sessions.first(where:{ !$0.completed && $0.mode == .assistant }) { resume(recent.id) }
        else { newSession() }
    }
    func newSession(title: String = "New chat", minutes: Int = 0, mode: ChatMode = .assistant) {
        guard store != nil else { error="The chat library is unavailable. Restore the library folder before starting."; return }
        suspend()
        if let old=active, old.title == "New chat",old.messages.isEmpty,old.draft.isEmpty,old.files.isEmpty {sessions.removeAll{$0.id==old.id}}
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
    func setMode(_ mode: ChatMode) { cancel(); voice.stopListening(); updateActive{$0.mode=mode}; persist() }
    func setWeb(_ enabled: Bool) { updateActive{$0.webEnabled=enabled}; persist() }
    func setFocus(minutes: Int) { updateActive{$0.duration=minutes>0 ? $0.elapsed+minutes*60 : 0}; persist() }
    func tick() {
        defer{lastTick=Date()}; guard !paused,active != nil else{return}
        let seconds=max(0,Int(Date().timeIntervalSince(lastTick).rounded())); updateActive{$0.elapsed+=seconds}
        if active?.elapsed.isMultiple(of:30)==true {persist()}
    }
    func togglePause() {if paused {paused=false; lastTick=Date(); error=nil} else{tick();suspend()};persist()}
    func suspend() {paused=true;voice.stop();cancel();context.stop();hideOverlay?();persist()}
    func complete() {
        tick();updateActive{$0.completed=true};suspend();selectedID=activeID;activeID=nil
        loading=true;draft="";loading=false;persist();showLibrary?()
    }
    func cancel() {requestID=UUID();captureTask?.cancel();captureTask=nil;provider.cancel();busy=false;voice.stopSpeaking();hideOverlay?()}
    func send(_ override: String? = nil, spoken: Bool = false, pointing: Bool = false, reveal: Bool = false, retry: Bool = false) {
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
                if self.context.filter != nil {snapshot=try await self.context.capture()}
                guard !Task.isCancelled,self.requestID==id,self.activeID==chatID else{return}
                let fileContext=try await Task.detached(priority:.userInitiated) {try files?.context(for:records) ?? FileContext()}.value
                guard !Task.isCancelled,self.requestID==id,self.activeID==chatID else{return}
                var images=snapshot.map{[$0.data]} ?? [];images+=fileContext.images
                let prompt=TutorPrompt.build(session:history,question:question,hasImage:!images.isEmpty,pointing:pointing,reveal:reveal,fileContext:fileContext.text,hasWindow:snapshot != nil)
                self.provider.ask(prompt:prompt,images:images,search:wantsSearch) { [weak self] result in
                    guard let self,self.requestID==id,self.activeID==chatID else{return};self.busy=false
                    switch result {
                    case .success(let reply):
                        self.updateActive{$0.messages.append(Message(role:"assistant",text:reply.text));$0.updated=Date()};self.failedQuestion=nil
                        if self.readAloud || spoken {self.voice.speak(reply.text)}
                        if let point=reply.point,let snapshot,snapshot.generation==self.context.generation,Date().timeIntervalSince(snapshot.capturedAt)<30,snapshot.frame==self.context.currentFrame() {
                            Task { [weak self] in guard let self,self.requestID==id else{return};guard let fresh=try? await self.context.capture(),self.requestID==id,fresh.data==snapshot.data,fresh.frame==snapshot.frame else{return};self.showPoint?(point,snapshot) }
                        }
                        self.persist()
                    case .failure(let error):self.error=error.localizedDescription
                    }
                }
            } catch {
                guard self.requestID==id else{return};self.busy=false
                self.error=(error as? AppError)?.message ?? "The shared window is unavailable. Choose it again, or stop sharing and retry."
            }
        }
    }
    func retry(){if let question=failedQuestion ?? active?.messages.last.flatMap({$0.role == "user" ? $0.text : nil}){send(question,retry:true)}}
    func nextHint(){updateActive{$0.hintLevel=min(3,$0.hintLevel+1)};send("Give me one slightly more concrete hint, without revealing the full solution.")}
    func pointItOut(){guard context.filter != nil else{error="Share a window first so I can point to something specific.";return};send("Point out the relevant part of the shared window, with one short explanation.",pointing:true)}
    func toggleVoice(){guard !paused,active != nil else{return};if voice.listening{voice.finishUtterance()}else{cancel();spokenDraftPrefix=draft.isEmpty ? "" : draft+" ";voice.start()}}
    func stopSharing(){context.stop()}
    func previewContext(){Task{do{let snapshot=try await context.capture();showPreview?(snapshot.image)}catch{self.error="That window couldn’t be captured. Choose it again."}}}
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
        guard let index=sessions.firstIndex(where:{$0.id==chatID}) else{for item in outcomes{if let record=item.record{files.remove(record)}};return}
        sessions[index].pendingAttachments+=outcomes.compactMap(\.record);sessions[index].updated=Date()
        if let failure=outcomes.compactMap(\.error).first{error=failure}
        persist()
    }
    func pasteImage(_ data:Data){
        guard let files=fileStore,active != nil else{return}
        guard (active?.files.count ?? 0)<8 else{error="Attach up to 8 files in a chat.";return}
        do{let record=try files.importData(data,name:"Pasted image.png",fileExtension:"png");updateActive{$0.pendingAttachments.append(record)};persist()}catch{self.error=error.localizedDescription}
    }
    func removeFile(_ record:AttachmentRecord){
        if busy{cancel()}
        updateActive{chat in chat.pendingAttachments.removeAll{$0.id==record.id};for i in chat.messages.indices{chat.messages[i].attachments.removeAll{$0.id==record.id}}}
        if !sessions.contains(where:{$0.files.contains(where:{$0.id==record.id})}){fileStore?.remove(record)};persist()
    }
    func rename(_ id:UUID,to title:String){let cleaned=title.trimmingCharacters(in:.whitespacesAndNewlines);guard !cleaned.isEmpty,let index=sessions.firstIndex(where:{$0.id==id})else{return};sessions[index].title=String(cleaned.prefix(100));persist()}
    func setTakeaway(_ text:String,for id:UUID){if let i=sessions.firstIndex(where:{$0.id==id}){sessions[i].takeaway=text;scheduleSave()}}
    func delete(_ id:UUID){
        let records=sessions.first(where:{$0.id==id})?.files ?? []
        if id==activeID{suspend();activeID=nil;draft=""}
        sessions.removeAll{$0.id==id};if selectedID==id{selectedID=nil}
        for record in records where !sessions.contains(where:{$0.files.contains(where:{$0.id==record.id})}){fileStore?.remove(record)}
        persist();showLibrary?()
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
