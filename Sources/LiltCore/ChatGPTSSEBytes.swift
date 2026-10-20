import Foundation

/// Preserves SSE's empty records; Foundation's AsyncBytes.lines removes them.
public struct ChatGPTSSEByteFramer {
    private var line = Data()
    private var previousWasCR = false
    private var firstLine = true
    private let maximumLineBytes: Int
    public init(maximumLineBytes: Int = 2_097_152) { self.maximumLineBytes = maximumLineBytes }
    public mutating func consume(_ byte: UInt8) throws -> String? {
        if previousWasCR {
            previousWasCR = false
            if byte == 10 { return nil }
        }
        if byte == 13 || byte == 10 {
            previousWasCR = byte == 13
            return try takeLine()
        }
        guard line.count < maximumLineBytes else { throw ChatGPTError("The response exceeded the safe reading limit. Try a shorter question.") }
        line.append(byte)
        return nil
    }
    public mutating func finish() throws -> String? { line.isEmpty ? nil : try takeLine() }
    private mutating func takeLine() throws -> String {
        if firstLine, line.starts(with: [0xef, 0xbb, 0xbf]) { line.removeFirst(3) }
        firstLine = false
        guard let value = String(data: line, encoding: .utf8) else { throw ChatGPTError("The ChatGPT response contained unreadable text. Your question is saved; try again.") }
        line.removeAll(keepingCapacity: true)
        return value
    }
}

public struct ChatGPTStreamedReply {
    public let reply: TutorReply
    public let usedWebSearch: Bool
}

public enum ChatGPTSSEBytes {
    /// The production AsyncBytes and disposable async byte fixtures use this identical adapter.
    @MainActor public static func read<Bytes: AsyncSequence>(_ bytes: Bytes, check: () throws -> Void = {}) async throws -> ChatGPTStreamedReply where Bytes.Element == UInt8 {
        var framer = ChatGPTSSEByteFramer()
        var response = ChatGPTResponseStream()
        for try await byte in bytes {
            try Task.checkCancellation()
            try check()
            if let line = try framer.consume(byte) { try response.consume(line: line) }
        }
        try Task.checkCancellation(); try check()
        if let line = try framer.finish() { try response.consume(line: line) }
        guard !response.hasPendingEvent else { throw ChatGPTError("The connection ended inside a ChatGPT stream event. Your question is saved; try again.") }
        let reply = try response.finish()
        return ChatGPTStreamedReply(reply: reply, usedWebSearch: response.usedWebSearch)
    }
}
