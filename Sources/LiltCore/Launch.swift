import Foundation

public enum LaunchSelection {
    /// Newest unfinished chat. `sessions` is ordered with the most recently updated chat first.
    public static func resumeID(in sessions:[LearningSession])->UUID? {
        sessions.first { !$0.completed }?.id
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

/// Shown on an empty coach, before the first send. Not a setup gate: typing stays available.
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
