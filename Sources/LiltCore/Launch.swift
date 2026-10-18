import Foundation

public struct ResumeTarget: Equatable, Sendable {
    /// The chat to open. This is already the chat id.
    public var chatID: UUID
    public init(chatID: UUID) { self.chatID = chatID }
}

public enum LaunchSelection {
    /// Newest unfinished chat. `sessions` is ordered with the most recently updated chat first.
    public static func resumeID(in sessions:[LearningSession])->UUID? {
        sessions.first { !$0.completed }?.id
    }
    /// The value to open. It is the chat id itself.
    public static func target(in sessions:[LearningSession]) -> ResumeTarget? {
        resumeID(in: sessions).map { ResumeTarget(chatID: $0) }
    }
    /// Close chat hides the windows. It does not finish the session, so the next launch can resume it.
    public static func chatAfterClose(_ chat:LearningSession)->LearningSession {
        var chat=chat
        chat.completed=false
        return chat
    }
}

public enum CodexLocator {
    public static func candidatePaths(home:URL,customPath:String?,environmentPath:String?)->[String] {
        var paths:[String]=[]
        func add(_ value:String?) {
            guard let value else { return }
            let trimmed=value.trimmingCharacters(in:.whitespacesAndNewlines)
            guard !trimmed.isEmpty,!paths.contains(trimmed) else { return }
            paths.append(trimmed)
        }
        add(customPath)
        add(home.appendingPathComponent(".local/bin/codex").path)
        add("/opt/homebrew/bin/codex")
        add("/usr/local/bin/codex")
        add("/Applications/Codex.app/Contents/Resources/codex")
        if let environmentPath {
            for entry in environmentPath.split(separator:":") {
                let directory=entry.trimmingCharacters(in:.whitespaces)
                guard !directory.isEmpty else { continue }
                add(URL(fileURLWithPath:String(directory)).appendingPathComponent("codex").path)
            }
        }
        return paths
    }
    /// Last non-empty line from `command -v`, when it is one absolute path.
    public static func shellExecutable(from output:String)->String? {
        let lines=output.split(whereSeparator:\.isNewline).map{String($0).trimmingCharacters(in:.whitespaces)}.filter{!$0.isEmpty}
        guard let line=lines.last,line.hasPrefix("/"),line.count<=1024,!line.contains("\0") else { return nil }
        return line
    }
}

public struct CodexSignInNotice: Equatable, Sendable {
    public var title: String
    public var detail: String
    public init(title: String, detail: String) { self.title = title; self.detail = detail }
    public static func beforeFirstSend(executableFound: Bool) -> CodexSignInNotice {
        if executableFound {
            return CodexSignInNotice(
                title: "Replies use your Codex sign-in",
                detail: "Vale answers through the Codex CLI on this Mac. Run codex login in Terminal if you haven’t signed in. You can type before you do."
            )
        }
        return CodexSignInNotice(
            title: "Codex sign-in is required for a reply",
            detail: "Install the Codex CLI and run codex login, or choose it in Settings. You can keep typing either way."
        )
    }
}

public enum LaunchPresentation {
    public static func presentsCoach(hasActiveChat: Bool, hasError: Bool) -> Bool {
        hasActiveChat || hasError
    }
}

public enum CodexStartup {
    public enum Next: Equatable { case start, wait, missing }
    /// A launch that has not found Codex yet should wait for the lookup already in flight.
    /// Starting immediately reports that Codex is missing and never asks for the answer.
    public static func next(executableFound: Bool, lookupPending: Bool) -> Next {
        if executableFound { return .start }
        return lookupPending ? .wait : .missing
    }
}
