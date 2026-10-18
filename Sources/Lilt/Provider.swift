import Foundation
import LiltCore

// Inspect event types only; never retain model text, search queries, or credentials.
private final class SearchEventProbe: @unchecked Sendable {
    private let lock=NSLock()
    private var buffer=Data()
    private var detected=false
    var usedSearch:Bool{lock.lock();defer{lock.unlock()};return detected}
    func consume(_ data:Data){
        lock.lock();defer{lock.unlock()}
        buffer.append(data)
        while let newline=buffer.firstIndex(of:10){
            let line=buffer.prefix(upTo:newline);buffer.removeSubrange(...newline)
            guard line.count<=65_536,let event=(try? JSONSerialization.jsonObject(with:line)) as? [String:Any],let item=event["item"] as? [String:Any] else{continue}
            if item["type"] as? String == "web_search"{detected=true}
        }
        if buffer.count>65_536{buffer.removeAll(keepingCapacity:false)}
    }
}
@MainActor final class TutorProvider {
    var fixtureReply:((String,[Data],Bool,@escaping (Result<TutorReply,Error>)->Void)->Void)?
    private(set) var usedWebSearch=false
    private var process: Process?
    private var timeout: DispatchWorkItem?
    private var completion: ((Result<TutorReply, Error>) -> Void)?
    private var work: URL?
    private var shellResolved: String?
    private var lookupPending = false
    private var deferredAsk: (prompt: String, images: [Data], search: Bool, completion: (Result<TutorReply, Error>) -> Void)?
    var located:(()->Void)?
    var lookupEnded:(()->Void)?
    private(set) var lookupFinished=false
    var executable: String? {
        let custom = UserDefaults.standard.string(forKey: "codexPath")
        let candidates = CodexLocator.candidatePaths(home: FileManager.default.homeDirectoryForCurrentUser, customPath: custom, environmentPath: ProcessInfo.processInfo.environment["PATH"])
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return found }
        if let shellResolved, FileManager.default.isExecutableFile(atPath: shellResolved) { return shellResolved }
        return nil
    }
    func locateWithLoginShell() {
        let args = CommandLine.arguments
        guard !args.contains("--self-test"), !args.contains("--integration-test"), executable == nil else { lookupFinished = true; return }
        lookupPending = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let finish: (String?) -> Void = { path in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let path, FileManager.default.isExecutableFile(atPath: path) { self.shellResolved = path; self.located?() }
                    self.lookupPending = false
                    self.lookupFinished = true
                    self.lookupEnded?()
                    self.resumeDeferredAsk()
                }
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", "command -v codex"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { finish(nil); return }
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3, execute: timeout)
            process.waitUntilExit()
            timeout.cancel()
            let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let path = CodexLocator.shellExecutable(from: text)
            if let resolved = path, FileManager.default.isExecutableFile(atPath: resolved) { finish(resolved) }
            else { finish(nil) }
        }
    }
    var resources: URL {
        let bundled = Bundle.main.resourceURL!
        if FileManager.default.fileExists(atPath: bundled.appendingPathComponent("tutor.md").path) { return bundled }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
    }
    func ask(prompt: String, images: [Data] = [], search: Bool = false, completion: @escaping (Result<TutorReply, Error>) -> Void) {
        cancel()
        usedWebSearch=false
        if let fixtureReply,(CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--integration-test")){fixtureReply(prompt,images,search,completion);return}
        switch CodexStartup.next(executableFound: executable != nil, lookupPending: lookupPending) {
        case .start: begin(prompt: prompt, images: images, search: search, completion: completion)
        case .wait: deferredAsk = (prompt, images, search, completion)
        case .missing: reportMissingCodex(completion)
        }
    }
    private func resumeDeferredAsk() {
        guard let deferred = deferredAsk else { return }
        deferredAsk = nil
        switch CodexStartup.next(executableFound: executable != nil, lookupPending: false) {
        case .start: begin(prompt: deferred.prompt, images: deferred.images, search: deferred.search, completion: deferred.completion)
        case .wait: deferredAsk = deferred
        case .missing: reportMissingCodex(deferred.completion)
        }
    }
    private func reportMissingCodex(_ completion: @escaping (Result<TutorReply, Error>) -> Void) {
        completion(.failure(AppError("Codex wasn’t found. Choose it in Settings, or install the Codex CLI and run codex login in Terminal.", offersSettings: true)))
    }
    private func begin(prompt: String, images: [Data], search: Bool, completion: @escaping (Result<TutorReply, Error>) -> Void) {
        guard let executable else { reportMissingCodex(completion); return }
        self.completion = completion
        do {
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("lilt-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            self.work = work
            let output = work.appendingPathComponent("reply.json")
            let process = Process(); process.executableURL = URL(fileURLWithPath: executable)
            var args = ["exec", "--ignore-user-config", "--ignore-rules", "--skip-git-repo-check", "--ephemeral", "--sandbox", "read-only", "--json", "--color", "never", "-C", work.path]
            for option in ["approval_policy=\"never\"", "forced_login_method=\"chatgpt\"", "model_reasoning_effort=\"low\"", "features.shell_tool=false", "features.unified_exec=false", "features.apps=false", "features.plugins=false", "features.browser_use=false", "features.computer_use=false", "features.multi_agent=false", "features.memories=false", "features.hooks=false", "features.image_generation=false", "features.skill_search=false", "features.skip_host_skill_discovery=true", "features.code_mode_host=false", "features.view_image=false", "features.shell_snapshot=false"] { args += ["-c", option] }
            args += ["-c", "web_search=\"\(search ? "live" : "disabled")\"", "-c", "features.standalone_web_search=\(search)", "-c", "features.code_mode_host=\(RequestTools.allowsCodeExecution(webSearch: search))"]
            args += ["-c", "model_instructions_file=\"\(resources.appendingPathComponent("tutor.md").path)\""]
            let model = UserDefaults.standard.string(forKey: "model") ?? ""
            if !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { args += ["-m", model] }
            args += ["--output-schema", resources.appendingPathComponent("reply.schema.json").path, "-o", output.path]
            for (index,image) in images.enumerated() { let file = work.appendingPathComponent("context-\(index).png"); try image.write(to:file); args += ["--image",file.path] }
            args += ["-"]
            process.arguments = args
            var env: [String: String] = [:]
            for key in ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL", "CODEX_HOME", "SSL_CERT_FILE", "SSL_CERT_DIR", "HTTPS_PROXY", "HTTP_PROXY", "ALL_PROXY", "NO_PROXY"] { if let value = ProcessInfo.processInfo.environment[key] { env[key] = value } }
            env["PATH"] = AssistantPath.value(executable: executable)
            process.environment = env
            let input = Pipe(); let out = Pipe(); let err = Pipe()
            process.standardInput = input; process.standardOutput = out; process.standardError = err
            // Drain both pipes without persisting prompts, screen content, or credentials.
            let searchEvents=SearchEventProbe()
            out.fileHandleForReading.readabilityHandler = { handle in searchEvents.consume(handle.availableData) }
            err.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
            self.process = process; self.completion = completion
            process.terminationHandler = { [weak self, weak process] finished in
                out.fileHandleForReading.readabilityHandler = nil; err.fileHandleForReading.readabilityHandler = nil
                DispatchQueue.main.async {
                    guard let self, let process, self.process === process else { return }
                    self.usedWebSearch=searchEvents.usedSearch
                    if let reply = FinishedReply.decoded(try? Data(contentsOf: output)) { self.finish(.success(reply)) }
                    else if finished.terminationStatus == 0 { self.finish(.failure(AppError("The assistant returned an unreadable reply. Your question is saved; try again."))) }
                    else { self.finish(.failure(AppError("The connection stopped. Check your Codex sign-in or plan usage in Settings, then retry.", offersSettings: true))) }
                }
            }
            try process.run()
            DispatchQueue.global(qos: .userInitiated).async {
                try? input.fileHandleForWriting.write(contentsOf: Data(prompt.utf8)); try? input.fileHandleForWriting.close()
            }
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, self.process === process else { return }
                process.terminate(); self.finish(.failure(AppError("The response took too long. Your question is saved; try again.")))
            }
            self.timeout = timeout; DispatchQueue.main.asyncAfter(deadline: .now() + 150, execute: timeout)
        } catch { finish(.failure(AppError("Couldn’t start the assistant: \(error.localizedDescription)"))) }
    }
    func ask(prompt: String, image: Data?, completion: @escaping (Result<TutorReply, Error>) -> Void) { ask(prompt:prompt,images:image.map { [$0] } ?? [],completion:completion) }
    func cancel() {
        timeout?.cancel(); timeout = nil
        let old = process; process = nil; completion = nil
        if old?.isRunning == true { old?.terminate() }
        cleanup()
    }
    private func cleanup() { if let work { try? FileManager.default.removeItem(at: work) }; work = nil }
    private func finish(_ result: Result<TutorReply, Error>) {
        timeout?.cancel(); timeout = nil; process = nil
        let callback = completion; completion = nil; cleanup(); callback?(result)
    }
}
struct AppError: LocalizedError {
    let message: String
    var offersSettings = false
    init(_ message: String, offersSettings: Bool = false) { self.message = message; self.offersSettings = offersSettings }
    var errorDescription: String? { message }
}
