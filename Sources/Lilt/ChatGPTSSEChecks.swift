import Foundation
import LiltCore

@MainActor enum ChatGPTSSEChecks {
    static func run() async -> [String: Bool] {
        guard CommandLine.arguments.contains("--self-test") || CommandLine.arguments.contains("--integration-test") else { return [:] }
        var results: [String: Bool] = [:]
        let expected = "Generated café — 你好 👋"
        do {
            let reply = try String(data: JSONEncoder().encode(TutorReply(text: expected)), encoding: .utf8)!
            let delta: [String: Any] = ["type": "response.output_text.delta", "delta": reply]
            let complete: [String: Any] = ["type": "response.completed", "response": ["status": "completed", "output": [["type": "web_search_call", "status": "completed"], ["type": "message", "content": [["type": "output_text", "text": reply]]]]]]
            for (name, newline) in [("LF", "\n"), ("CRLF", "\r\n"), ("CR", "\r")] {
                let stream = "\u{feff}: generated comment" + newline + newline + (try event(["type": "response.created"], newline: newline)) + (try event(delta, newline: newline)) + (try event(complete, newline: newline)) + "data: [DONE]" + newline + newline
                let parsed = try await ChatGPTSSEBytes.read(ChatGPTFixtureAsyncBytes(data: Data(stream.utf8), chunkSizes: [1, 2, 7, 3]))
                results["chatGPTAsyncBytesPreserve\(name)BlankRecordsAndSplitUTF8"] = parsed.reply.text == expected && parsed.usedWebSearch
            }
            // Multiple data fields are joined by one LF inside a single SSE record.
            let completedJSON = try json(complete)
            let split = completedJSON.firstIndex(of: ",")!
            let multiline = "data: " + completedJSON[...split] + "\r\n" + "data: " + completedJSON[completedJSON.index(after: split)...] + "\r\n\r\n"
            let parsed = try await ChatGPTSSEBytes.read(ChatGPTFixtureAsyncBytes(data: Data(multiline.utf8), chunkSizes: [2, 1]))
            results["chatGPTAsyncBytesPreserveMultilineEventData"] = parsed.reply.text == expected
            let failed: [String: Any] = ["type": "response.failed", "response": ["error": ["code": "subscription_sharing_usage_limit_exceeded"]]]
            let late = try event(delta) + event(complete) + event(failed)
            do { _ = try await ChatGPTSSEBytes.read(ChatGPTFixtureAsyncBytes(data: Data(late.utf8), chunkSizes: [1, 4])); results["chatGPTAsyncBytesRejectLateFailureAfterCompletedEvent"] = false }
            catch { results["chatGPTAsyncBytesRejectLateFailureAfterCompletedEvent"] = (error as? ChatGPTError)?.code == "subscription_sharing_usage_limit_exceeded" }
            let partial = try event(delta)
            do { _ = try await ChatGPTSSEBytes.read(ChatGPTFixtureAsyncBytes(data: Data(partial.utf8), chunkSizes: [3])); results["chatGPTAsyncBytesRejectEOFWithoutCompleted"] = false }
            catch { results["chatGPTAsyncBytesRejectEOFWithoutCompleted"] = true }
            let unterminated = "data: " + (try json(complete)) + "\n"
            do { _ = try await ChatGPTSSEBytes.read(ChatGPTFixtureAsyncBytes(data: Data(unterminated.utf8), chunkSizes: [1, 2])); results["chatGPTAsyncBytesRejectUnterminatedCompletedRecord"] = false }
            catch { results["chatGPTAsyncBytesRejectUnterminatedCompletedRecord"] = true }
            do { _ = try await ChatGPTSSEBytes.read(ChatGPTFixtureAsyncBytes(data: Data(partial.utf8), chunkSizes: [3], throwsAtEnd: true)); results["chatGPTAsyncBytesRejectTransportInterruption"] = false }
            catch { results["chatGPTAsyncBytesRejectTransportInterruption"] = (error as? URLError)?.code == .networkConnectionLost }
            let incomplete = try event(delta) + event(["type": "response.incomplete", "response": [:]])
            do { _ = try await ChatGPTSSEBytes.read(ChatGPTFixtureAsyncBytes(data: Data(incomplete.utf8), chunkSizes: [3, 1])); results["chatGPTAsyncBytesRejectIncompleteTerminalEvent"] = false }
            catch { results["chatGPTAsyncBytesRejectIncompleteTerminalEvent"] = true }
            let invalidUTF8 = Data("data: ".utf8) + Data([0xff, 10, 10])
            do { _ = try await ChatGPTSSEBytes.read(ChatGPTFixtureAsyncBytes(data: invalidUTF8, chunkSizes: [1])); results["chatGPTAsyncBytesRejectInvalidUTF8"] = false }
            catch { results["chatGPTAsyncBytesRejectInvalidUTF8"] = true }
        } catch { results["chatGPTAsyncByteFixtureSetupCompleted"] = false }
        return results
    }
    private static func json(_ value: [String: Any]) throws -> String { String(data: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), encoding: .utf8)! }
    private static func event(_ value: [String: Any], newline: String = "\n") throws -> String { "data: " + (try json(value)) + newline + newline }
}

/// Yields byte-by-byte and suspends at arbitrary chunk boundaries, including inside UTF-8 scalars/CRLF.
private struct ChatGPTFixtureAsyncBytes: AsyncSequence {
    typealias Element = UInt8
    let data: Data
    let chunkSizes: [Int]
    var throwsAtEnd = false
    func makeAsyncIterator() -> Iterator { Iterator(bytes: Array(data), chunkSizes: chunkSizes, throwsAtEnd: throwsAtEnd) }
    struct Iterator: AsyncIteratorProtocol {
        let bytes: [UInt8]
        let chunkSizes: [Int]
        let throwsAtEnd: Bool
        var offset = 0
        var chunkIndex = 0
        var remaining = 0
        mutating func next() async throws -> UInt8? {
            if offset == bytes.count {
                if throwsAtEnd { throw URLError(.networkConnectionLost) }
                return nil
            }
            if remaining == 0 {
                await Task.yield()
                remaining = chunkSizes[chunkIndex % chunkSizes.count]; chunkIndex += 1
            }
            let byte = bytes[offset]; offset += 1; remaining -= 1
            return byte
        }
    }
}
