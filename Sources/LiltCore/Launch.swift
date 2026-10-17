import Foundation

public enum LaunchSelection {
    /// Newest unfinished chat. `sessions` is ordered with the most recently updated chat first.
    public static func resumeID(in sessions:[LearningSession])->UUID? {
        sessions.first { !$0.completed }?.id
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
