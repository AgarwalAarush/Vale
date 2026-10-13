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
    private(set) var usedWebSearch=false
    private var process: Process?
    private var timeout: DispatchWorkItem?
    private var completion: ((Result<TutorReply, Error>) -> Void)?
    private var work: URL?
    var executable: String? {
        let custom = UserDefaults.standard.string(forKey: "codexPath")
        return [custom, "/usr/local/bin/codex", "/opt/homebrew/bin/codex", "/Applications/Codex.app/Contents/Resources/codex"].compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    var resources: URL {
        let bundled = Bundle.main.resourceURL!
        if FileManager.default.fileExists(atPath: bundled.appendingPathComponent("tutor.md").path) { return bundled }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
    }
    func ask(prompt: String, images: [Data] = [], search: Bool = false, completion: @escaping (Result<TutorReply, Error>) -> Void) {
        cancel()
        usedWebSearch=false
        guard let executable else { completion(.failure(AppError("Codex wasn’t found. Open Settings to choose the Codex executable."))); return }
        self.completion = completion
        do {
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("lilt-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            self.work = work
            let output = work.appendingPathComponent("reply.json")
            let process = Process(); process.executableURL = URL(fileURLWithPath: executable)
            var args = ["exec", "--ignore-user-config", "--ignore-rules", "--skip-git-repo-check", "--ephemeral", "--sandbox", "read-only", "--json", "--color", "never", "-C", work.path]
            for option in ["approval_policy=\"never\"", "forced_login_method=\"chatgpt\"", "model_reasoning_effort=\"low\"", "features.shell_tool=false", "features.unified_exec=false", "features.apps=false", "features.plugins=false", "features.browser_use=false", "features.computer_use=false", "features.multi_agent=false", "features.memories=false", "features.hooks=false", "features.image_generation=false", "features.skill_search=false", "features.skip_host_skill_discovery=true", "features.code_mode_host=false", "features.view_image=false", "features.shell_snapshot=false"] { args += ["-c", option] }
            args += ["-c", "web_search=\"\(search ? "live" : "disabled")\"", "-c", "features.standalone_web_search=\(search)", "-c", "features.code_mode_host=\(search)"]
            args += ["-c", "model_instructions_file=\"\(resources.appendingPathComponent("tutor.md").path)\""]
            let model = UserDefaults.standard.string(forKey: "model") ?? ""
            if !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { args += ["-m", model] }
            args += ["--output-schema", resources.appendingPathComponent("reply.schema.json").path, "-o", output.path]
            for (index,image) in images.enumerated() { let file = work.appendingPathComponent("context-\(index).png"); try image.write(to:file); args += ["--image",file.path] }
            args += ["-"]
            process.arguments = args
            var env: [String: String] = [:]
            for key in ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL", "CODEX_HOME", "SSL_CERT_FILE", "SSL_CERT_DIR", "HTTPS_PROXY", "HTTP_PROXY", "ALL_PROXY", "NO_PROXY"] { if let value = ProcessInfo.processInfo.environment[key] { env[key] = value } }
            env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
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
                    if finished.terminationStatus == 0 {
                        do { self.finish(.success(try TutorReply.decode(Data(contentsOf: output)))) }
                        catch { self.finish(.failure(AppError("The assistant returned an unreadable reply. Your question is saved; try again."))) }
                    } else { self.finish(.failure(AppError("The connection stopped. Check your Codex sign-in or plan usage, then retry."))) }
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
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
