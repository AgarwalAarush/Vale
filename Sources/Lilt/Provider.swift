import Foundation
import LiltCore

/// Direct ChatGPT-plan provider. There is no CLI, API-key, or execution-tool path.
@MainActor final class TutorProvider {
    var fixtureReply: ((String, [Data], Bool, @escaping (Result<TutorReply, Error>) -> Void) -> Void)?
    private(set) var usedWebSearch = false
    let account: ChatGPTAccount
    private var task: Task<Void, Never>?
    private var requestID = UUID()
    private var accountObserver: NSObjectProtocol?
    init(account: ChatGPTAccount? = nil) {
        self.account = account ?? .shared
        accountObserver = NotificationCenter.default.addObserver(forName: ChatGPTAccount.connectionWillChange, object: self.account, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
    }
    deinit { if let accountObserver { NotificationCenter.default.removeObserver(accountObserver) } }

    func ask(prompt: String, images: [Data] = [], search: Bool = false, completion: @escaping (Result<TutorReply, Error>) -> Void) {
        cancel(); usedWebSearch = false
        if let fixtureReply, CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--integration-test") {
            fixtureReply(prompt, images, search, completion); return
        }
        let id = requestID
        let epoch = account.requestEpoch
        task = Task { [weak self] in
            guard let self else { return }
            var receivedHTTP: HTTPURLResponse?
            do {
                let session = try await self.account.usableSession()
                try self.checkRequest(id, epoch: epoch)
                var model = self.account.selectedModel
                if model == nil {
                    let models = try await ChatGPTHTTP.shared.models(accessToken: session.accessToken)
                    try self.checkRequest(id, epoch: epoch)
                    model = models.first { $0.id == self.account.selectedModelID } ?? models.first
                }
                guard let model else { throw AppError("No eligible ChatGPT model is available. Check your account and workspace in Settings.", offersSettings: true) }
                guard let resources = InstructionFile.directory(bundleResources: Bundle.main.resourceURL, workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)) else { throw AppError("The assistant’s instructions are missing. Reinstall Vale and try again.") }
                let instructions = try String(contentsOf: resources.appendingPathComponent("tutor.md"), encoding: .utf8)
                let schema = try Data(contentsOf: resources.appendingPathComponent("reply.schema.json"))
                let body = try ChatGPTResponses.request(model: model, instructions: instructions, prompt: prompt, images: images, search: search, schema: schema)
                var request = URLRequest(url: URL(string: ChatGPTOAuth.resource + "/responses")!)
                request.httpMethod = "POST"; request.httpBody = body
                request.setValue("Bearer " + session.accessToken, forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                let (bytes, response) = try await ChatGPTHTTP.shared.session.bytes(for: request)
                try self.checkRequest(id, epoch: epoch)
                guard let http = response as? HTTPURLResponse else { throw AppError("ChatGPT’s response couldn’t be verified. Try again.") }
                receivedHTTP = http
                guard (200..<300).contains(http.statusCode) else {
                    var data = Data()
                    for try await byte in bytes { data.append(byte); if data.count >= 65_536 { break } }
                    throw ChatGPTHTTP.failure(http, data: data)
                }
                guard http.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("text/event-stream") == true else { throw AppError("ChatGPT didn’t return a response stream. Your question is saved; try again.") }
                var stream = ChatGPTResponseStream()
                for try await line in bytes.lines {
                    try self.checkRequest(id, epoch: epoch)
                    try stream.consume(line: line)
                }
                let reply = try stream.finish()
                try self.checkRequest(id, epoch: epoch)
                self.usedWebSearch = search && stream.usedWebSearch
                self.task = nil; completion(.success(reply))
            } catch {
                guard self.requestID == id, self.account.requestEpoch == epoch, !Task.isCancelled else { return }
                self.task = nil
                let message = (error as? ChatGPTError)?.message ?? (error as? AppError)?.message ?? "The ChatGPT connection stopped. Your question is saved; check your connection and try again."
                var diagnostic = error as? ChatGPTError
                if let original = diagnostic, original.status == nil, let http = receivedHTTP {
                    diagnostic = ChatGPTError(original.message, code: original.code, status: http.statusCode, requestID: http.value(forHTTPHeaderField: "x-request-id") ?? http.value(forHTTPHeaderField: "openai-request-id"), responseBodyShape: original.responseBodyShape, parameter: original.parameter)
                }
                completion(.failure(AppError(message, offersSettings: error is ChatGPTError || (error as? AppError)?.offersSettings == true, diagnostic: diagnostic)))
            }
        }
    }
    private func checkRequest(_ id: UUID, epoch: UUID) throws {
        try Task.checkCancellation()
        guard requestID == id, account.requestEpoch == epoch else { throw CancellationError() }
    }
    func ask(prompt: String, image: Data?, completion: @escaping (Result<TutorReply, Error>) -> Void) { ask(prompt: prompt, images: image.map { [$0] } ?? [], completion: completion) }
    func cancel() { requestID = UUID(); task?.cancel(); task = nil }
}

struct AppError: LocalizedError {
    let message: String
    var offersSettings = false
    let diagnostic: ChatGPTError?
    init(_ message: String, offersSettings: Bool = false, diagnostic: ChatGPTError? = nil) { self.message = message; self.offersSettings = offersSettings; self.diagnostic = diagnostic }
    var errorDescription: String? { message }
}
