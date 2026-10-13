import AppKit
import Combine
import LiltCore
import UniformTypeIdentifiers

@MainActor final class AppModel: ObservableObject {
    @Published var sessions: [LearningSession] = []
    @Published var activeID: UUID?
    @Published var paused = true
    @Published var busy = false
    @Published var error: String?
    @Published var draft = "" { didSet { if !loading { updateActive { $0.draft = draft }; scheduleSave() } } }
    @Published var selectedID: UUID?
    @Published var attachment: NSImage?
    @Published var attachmentName: String?
    @Published var settings = false
    @Published var onboarding = false
    @Published var readAloud = UserDefaults.standard.bool(forKey: "readAloud") { didSet { UserDefaults.standard.set(readAloud, forKey: "readAloud"); if !readAloud { voice.stopSpeaking() } } }
    let context = WindowContext()
    let voice = VoiceController()
    let provider = TutorProvider()
    private let store: SessionStore?
    private var timer: Timer?
    private var lastTick = Date()
    private var saveWork: DispatchWorkItem?
    private var requestID = UUID()
    private var captureTask: Task<Void, Never>?
    private var attachmentData: Data?
    private var loading = false
    private let testing: Bool
    private var observerTokens: [AnyCancellable] = []
    private var failedQuestion: String?
    private var spokenDraftPrefix = ""
    var showCoach: (() -> Void)?
    var showLibrary: (() -> Void)?
    var hideOverlay: (() -> Void)?
    var showPoint: ((PointTarget, ContextSnapshot) -> Void)?
    var showPreview: ((NSImage) -> Void)?
    var active: LearningSession? { sessions.first { $0.id == activeID } }
    var selected: LearningSession? { sessions.first { $0.id == selectedID } }
    var contextName: String? { attachmentName ?? context.title }
    var status: String { paused ? "Paused" : voice.listening ? "Listening…" : busy ? "Thinking…" : voice.speaking ? "Speaking…" : "Voice off" }
    init(dataDirectory: URL? = nil) {
        testing = dataDirectory != nil
        let directory = dataDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Lilt")
        var loadedStore: SessionStore?
        do { let candidate = try SessionStore(directory: directory); sessions = try candidate.load().sorted { $0.updated > $1.updated }; loadedStore = candidate }
        catch { self.error = "Couldn’t open your session library. Check the storage folder before starting a session." }
        store = loadedStore
        onboarding = !UserDefaults.standard.bool(forKey: "onboardingComplete")
        context.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &observerTokens)
        voice.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &observerTokens)
        context.failed = { [weak self] in self?.error = $0 }
        context.changed = { [weak self] in
            guard let self else { return }; self.hideOverlay?()
            if self.busy { self.cancel(); self.error = "Sharing changed. Your question is saved; retry when you’re ready." }
        }
        voice.failed = { [weak self] in self?.error = $0 }
        voice.partial = { [weak self] text in guard let self else { return }; self.draft = self.spokenDraftPrefix + text }
        voice.finished = { [weak self] _ in guard let self else { return }; self.send(spoken: true) }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
    }
    func newSession(title: String, minutes: Int = 30) {
        guard store != nil else { error = "The session library is unavailable. Restore the library folder before starting."; return }
        suspend()
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = LearningSession(title: title.isEmpty ? "Learning session" : String(title.prefix(100)), duration: max(5, min(180, minutes)) * 60)
        sessions.insert(session, at: 0); activeID = session.id; selectedID = session.id
        loading = true; draft = ""; loading = false; paused = false; lastTick = Date(); error = nil
        onboarding = false; if !testing { UserDefaults.standard.set(true, forKey: "onboardingComplete") }
        persist(); showCoach?()
    }
    func resume(_ id: UUID) {
        suspend()
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        activeID = id; selectedID = id
        loading = true; draft = session.draft; loading = false
        updateActive { $0.completed = false }; paused = false; lastTick = Date(); error = nil
        persist(); showCoach?()
    }
    func tick() {
        defer { lastTick = Date() }
        guard !paused, active != nil else { return }
        let seconds = max(0, Int(Date().timeIntervalSince(lastTick).rounded()))
        updateActive { $0.elapsed += seconds }
        if active?.elapsed.isMultiple(of: 30) == true { persist() }
    }
    func togglePause() {
        if paused { paused = false; lastTick = Date(); error = nil }
        else { tick(); suspend() }
        persist()
    }
    func suspend() {
        paused = true; voice.stop(); cancel(); context.stop(); attachment = nil; attachmentData = nil; attachmentName = nil; hideOverlay?(); persist()
    }
    func complete() {
        tick(); updateActive { $0.completed = true }; suspend(); selectedID = activeID; activeID = nil
        loading = true; draft = ""; loading = false; persist(); showLibrary?()
    }
    func cancel() {
        requestID = UUID(); captureTask?.cancel(); captureTask = nil; provider.cancel(); busy = false; voice.stopSpeaking(); hideOverlay?()
    }
    func send(_ override: String? = nil, spoken: Bool = false, pointing: Bool = false, reveal: Bool = false, retry: Bool = false) {
        guard var session = active else { return }
        let question = (override ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        if paused { error = "Resume the session before sending a question."; return }
        guard question.count <= 32_000 else { error = "That message is too long. Send a smaller excerpt."; return }
        cancel(); voice.stopListening(); error = nil; busy = true
        let id = UUID(); requestID = id; let sessionID = session.id
        if !retry {
            session.messages.append(Message(role: "user", text: question)); session.updated = Date()
            replace(session)
            draft = ""
        }
        failedQuestion = question; persist()
        // Exclude the current question from history; it is passed as its own message.
        var history = session
        if history.messages.last?.role == "user", history.messages.last?.text == question { history.messages.removeLast() }
        captureTask = Task { [weak self] in
            guard let self else { return }
            var snapshot: ContextSnapshot?
            do {
                if self.context.filter != nil { snapshot = try await self.context.capture() }
                guard !Task.isCancelled, self.requestID == id, self.activeID == sessionID else { return }
                let data = snapshot?.data ?? self.attachmentData
                let prompt = TutorPrompt.build(session: history, question: question, hasImage: data != nil, pointing: pointing, reveal: reveal)
                self.provider.ask(prompt: prompt, image: data) { [weak self] result in
                    guard let self, self.requestID == id, self.activeID == sessionID else { return }
                    self.busy = false
                    switch result {
                    case .success(let reply):
                        self.updateActive { $0.messages.append(Message(role: "assistant", text: reply.text)); $0.updated = Date() }
                        self.failedQuestion = nil
                        if self.readAloud || spoken { self.voice.speak(reply.text) }
                        if let point = reply.point, let snapshot, snapshot.generation == self.context.generation, Date().timeIntervalSince(snapshot.capturedAt) < 30,
                           snapshot.frame == self.context.currentFrame() {
                            Task { [weak self] in
                                guard let self, self.requestID == id else { return }
                                guard let fresh = try? await self.context.capture(), self.requestID == id, fresh.data == snapshot.data, fresh.frame == snapshot.frame else { return }
                                self.showPoint?(point, snapshot)
                            }
                        }
                        self.persist()
                    case .failure(let error): self.error = error.localizedDescription
                    }
                }
            } catch {
                guard self.requestID == id else { return }; self.busy = false
                self.error = "The shared window is unavailable. Choose it again, or stop sharing and retry with text."
            }
        }
    }
    func retry() { if let failedQuestion { send(failedQuestion, retry: true) } }
    func nextHint() { updateActive { $0.hintLevel = min(3, $0.hintLevel + 1) }; send("Give me one slightly more concrete hint, without revealing the full solution.") }
    func pointItOut() {
        guard context.filter != nil else { error = "Share a window first so Lilt can point to something specific."; return }
        send("Point out the specific part I should examine next, with one short explanation.", pointing: true)
    }
    func toggleVoice() {
        guard !paused, active != nil else { return }
        if voice.listening { voice.finishUtterance() }
        else { cancel(); spokenDraftPrefix = draft.isEmpty ? "" : draft + " "; voice.start() }
    }
    func stopSharing() { context.stop(); attachment = nil; attachmentData = nil; attachmentName = nil }
    func previewContext() {
        if let attachment { showPreview?(attachment); return }
        Task { do { let snapshot = try await context.capture(); showPreview?(snapshot.image) } catch { self.error = "That window couldn’t be captured. Choose it again." } }
    }
    func attachImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 15_000_000, let image = NSImage(data: data) else { error = "Choose an image under 15 MB."; return }
            let size = image.size; let scale = min(1, 1600 / max(size.width, size.height))
            let target = NSSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
            let resized = NSImage(size: target); resized.lockFocus(); image.draw(in: NSRect(origin: .zero, size: target)); resized.unlockFocus()
            guard let tiff = resized.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { throw AppError("Couldn’t read this image.") }
            context.stop(); attachment = resized; attachmentData = png; attachmentName = url.lastPathComponent
        } catch { self.error = "Couldn’t read this image. Try a PNG or JPEG." }
    }
    func setTakeaway(_ text: String, for id: UUID) { if let index = sessions.firstIndex(where: { $0.id == id }) { sessions[index].takeaway = text; scheduleSave() } }
    func delete(_ id: UUID) {
        if id == activeID { suspend(); activeID = nil; draft = "" }
        sessions.removeAll { $0.id == id }; if selectedID == id { selectedID = nil }; persist(); showLibrary?()
    }
    func export(_ session: LearningSession) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]; panel.nameFieldStringValue = "\(session.title.replacingOccurrences(of: "/", with: "-"))-notes.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try SessionStore.export(session).write(to: url, atomically: true, encoding: .utf8) } catch { self.error = "Couldn’t export your notes." }
    }
    func updateActive(_ change: (inout LearningSession) -> Void) { guard let index = sessions.firstIndex(where: { $0.id == activeID }) else { return }; change(&sessions[index]) }
    private func replace(_ session: LearningSession) { if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index] = session } }
    private func scheduleSave() { saveWork?.cancel(); let work = DispatchWorkItem { [weak self] in self?.persist() }; saveWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work) }
    func persist() { do { sessions.sort { $0.updated > $1.updated }; try store?.save(sessions) } catch { self.error = "Couldn’t save your session. Check available disk space." } }
}
