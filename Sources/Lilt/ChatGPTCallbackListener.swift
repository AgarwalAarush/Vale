import Foundation
import Network
import LiltCore

/// A short-lived HTTP listener bound exclusively to IPv4 loopback.
@MainActor final class ChatGPTCallbackListener {
    private var listener: NWListener?
    private var startup: CheckedContinuation<URL, Error>?
    private var response: CheckedContinuation<URL, Error>?
    private var pendingURL: URL?
    private var callbackURI: URL?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var timeout: Task<Void, Never>?
    private var finished = false
    var validatesCallback: ((URL) -> Bool)?

    func start() async throws -> URL {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        return try await withCheckedThrowingContinuation { continuation in
            startup = continuation
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in self?.stateChanged(state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in self?.accept(connection) }
            }
            listener.start(queue: .main)
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(600))
                guard !Task.isCancelled else { return }
                self?.stop(error: ChatGPTError("ChatGPT sign-in timed out. Continue with ChatGPT to try again."))
            }
        }
    }
    func waitForCallback() async throws -> URL {
        if let pendingURL { self.pendingURL = nil; return pendingURL }
        guard !finished else { throw CancellationError() }
        return try await withCheckedThrowingContinuation { response = $0 }
    }
    func cancel() { stop(error: CancellationError()) }
    private func stateChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener?.port, let url = URL(string: "http://127.0.0.1:\(port.rawValue)/auth/callback") else { stop(error: ChatGPTError("The local sign-in callback couldn’t be opened. Try again.")); return }
            callbackURI = url; let continuation = startup; startup = nil; continuation?.resume(returning: url)
        case .failed: stop(error: ChatGPTError("The local ChatGPT sign-in callback stopped. Try again."))
        case .cancelled: if !finished { stop(error: CancellationError()) }
        default: break
        }
    }
    private func accept(_ connection: NWConnection) {
        guard !finished, connections.count < 8 else { connection.cancel(); return }
        connections[ObjectIdentifier(connection)] = connection
        connection.start(queue: .main)
        read(connection, buffer: Data())
        Task { [weak self, weak connection] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, let connection, self.connections[ObjectIdentifier(connection)] != nil else { return }
            self.remove(connection)
        }
    }
    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self, weak connection] data, _, complete, error in
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection, !self.finished else { return }
                var combined = buffer; if let data { combined.append(data) }
                guard combined.count <= 16_384 else { self.answer(connection, code: "400 Bad Request", text: "Sign-in callback could not be read."); return }
                if combined.range(of: Data("\r\n\r\n".utf8)) != nil { self.handle(connection, data: combined) }
                else if complete || error != nil { self.remove(connection) }
                else { self.read(connection, buffer: combined) }
            }
        }
    }
    private func handle(_ connection: NWConnection, data: Data) {
        guard let request = String(data: data, encoding: .utf8), let line = request.components(separatedBy: "\r\n").first, let base = callbackURI else { remove(connection); return }
        let fields = line.split(separator: " ")
        guard fields.count == 3, fields[0] == "GET", fields[2] == "HTTP/1.1" || fields[2] == "HTTP/1.0", fields[1].hasPrefix("/auth/callback?"),
              let url = URL(string: "http://127.0.0.1:\(base.port!)" + fields[1]), url.host == "127.0.0.1", url.path == "/auth/callback" else {
            answer(connection, code: "404 Not Found", text: "This address is only for returning to Vale."); return
        }
        guard validatesCallback?(url) == true else {
            answer(connection, code: "400 Bad Request", text: "This sign-in callback could not be verified. Return to the ChatGPT sign-in page and try again.")
            return
        }
        answer(connection, code: "200 OK", text: "You can return to Vale. Your ChatGPT sign-in is being checked.")
        finished = true; timeout?.cancel(); timeout = nil; listener?.cancel(); listener = nil
        if let response { self.response = nil; response.resume(returning: url) } else { pendingURL = url }
        // The accepted connection gets its small reply; all other pending requests stop.
        for pending in connections.values where pending !== connection { pending.cancel() }
        connections = [ObjectIdentifier(connection): connection]
    }
    private func answer(_ connection: NWConnection, code: String, text: String) {
        let body = Data(text.utf8)
        let headers = "HTTP/1.1 \(code)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nPragma: no-cache\r\nConnection: close\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\n\r\n"
        connection.send(content: Data(headers.utf8) + body, completion: .contentProcessed { [weak self, weak connection] _ in
            Task { @MainActor [weak self, weak connection] in if let connection { self?.remove(connection) } }
        })
    }
    private func remove(_ connection: NWConnection) { connections.removeValue(forKey: ObjectIdentifier(connection)); connection.cancel() }
    private func stop(error: Error) {
        finished = true; timeout?.cancel(); timeout = nil; listener?.cancel(); listener = nil
        connections.values.forEach { $0.cancel() }; connections.removeAll()
        let starting = startup; startup = nil; starting?.resume(throwing: error)
        let awaiting = response; response = nil; awaiting?.resume(throwing: error)
    }
}
