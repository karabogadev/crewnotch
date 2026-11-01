//
//  CommandRisk.swift
//  CrewNotch
//
//  Spots approval requests worth a second look before clicking Allow:
//  destructive shell commands and edits to sensitive files or files
//  outside the project. Purely advisory; it never blocks anything.
//

import Foundation

nonisolated enum CommandRisk {
    /// Plain-language warnings for a tool call, most serious first.
    static func warnings(toolName: String, input: [String: Any], cwd: String?) -> [String] {
        var found: [String] = []
        if let command = shellCommand(from: input) {
            found += commandWarnings(command)
        }
        if let path = editedPath(toolName: toolName, input: input) {
            found += pathWarnings(path, cwd: cwd)
        }
        var seen = Set<String>()
        return found.filter { seen.insert($0).inserted }
    }

    // MARK: - Shell commands

    private struct Rule {
        let pattern: String
        let caseInsensitive: Bool
        let message: () -> String

        init(_ pattern: String, caseInsensitive: Bool = false, _ message: @escaping () -> String) {
            self.pattern = pattern
            self.caseInsensitive = caseInsensitive
            self.message = message
        }
    }

    /// Start of a command: the beginning, or after a separator, pipe or subshell.
    private static let start = #"(?:^|[;&|(`]\s*|\$\(\s*|\bxargs\s+|\bthen\s+|\bdo\s+)"#

    private static let rules: [Rule] = [
        Rule(start + #"(?:sudo\s+)?rm\s+(?:-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)\b"#) { String(localized: "Deletes files and folders recursively") },
        Rule(start + #"(?:sudo\s+)?rm\s+-[a-zA-Z]*f"#) { String(localized: "Force-deletes files") },
        Rule(start + #"sudo\s"#) { String(localized: "Runs with administrator rights (sudo)") },
        Rule(#"\bgit\s+push\b[^;&|]*(?:\s--force(?:-with-lease)?\b|\s-[a-zA-Z]*f\b|\s\+[^\s]+)"#) { String(localized: "Force-pushes, which can overwrite the remote history") },
        Rule(#"\bgit\s+reset\b[^;&|]*--hard\b"#) { String(localized: "Discards uncommitted changes (git reset --hard)") },
        Rule(#"\bgit\s+clean\s+-[a-zA-Z]*f"#) { String(localized: "Deletes untracked files (git clean)") },
        Rule(#"\bgit\s+(?:checkout|restore)\s+(?:--\s+)?\.(?:\s|$)"#) { String(localized: "Discards local changes") },
        Rule(#"\bgit\s+branch\s+-D\b"#) { String(localized: "Deletes a branch") },
        Rule(#"\bgit\s+(?:stash\s+(?:drop|clear)|filter-branch|filter-repo)\b"#) { String(localized: "Rewrites or drops git history") },
        Rule(start + #"(?:sudo\s+)?(?:chmod|chown)\s+-[a-zA-Z]*R"#) { String(localized: "Changes permissions recursively") },
        Rule(#"\bchmod\s+(?:-[a-zA-Z]+\s+)*0?777\b"#) { String(localized: "Makes files writable by everyone") },
        Rule(start + #"(?:sudo\s+)?dd\s[^;&|]*\bof="#) { String(localized: "Writes raw data with dd") },
        Rule(#"\bmkfs\b|\bdiskutil\s+(?:erase\w*|reformat|partitionDisk|zeroDisk)\b"#) { String(localized: "Erases a disk") },
        Rule(#">\s*/dev/(?:r?disk|sd|nvme)"#) { String(localized: "Writes directly to a disk") },
        Rule(#"\b(?:curl|wget)\b[^|;&]*\|\s*(?:sudo\s+)?(?:sh|bash|zsh|fish|python3?|node|ruby|perl)\b"#) { String(localized: "Runs a script downloaded from the internet") },
        Rule(#"\b(?:drop\s+(?:table|database|schema)|truncate\s+table)\b"#, caseInsensitive: true) { String(localized: "Deletes database data") },
        Rule(#"\bdelete\s+from\s+\w+\s*(?:;|$)"#, caseInsensitive: true) { String(localized: "Deletes every row of a table") },
        Rule(start + #"(?:sudo\s+)?(?:kill\s+-(?:9|KILL)\b|killall\b|pkill\b)"#) { String(localized: "Kills running processes") },
        Rule(#"\b(?:npm|pnpm|yarn|bun)\s+publish\b|\bcargo\s+publish\b|\btwine\s+upload\b|\bgem\s+push\b"#) { String(localized: "Publishes a package") },
        Rule(#"\bgh\s+(?:repo|release)\s+delete\b"#) { String(localized: "Deletes on GitHub") },
        Rule(#"\b(?:shutdown|reboot|halt)\b|\bsystemsetup\b|\bcsrutil\b|\bnvram\b"#) { String(localized: "Changes system settings or restarts the Mac") },
        Rule(#"\bdefaults\s+delete\b|\blaunchctl\s+(?:unload|remove|bootout)\b"#) { String(localized: "Removes system configuration") },
    ]

    private static let compiled: [(NSRegularExpression, () -> String)] = rules.compactMap { rule in
        let options: NSRegularExpression.Options = rule.caseInsensitive ? [.caseInsensitive, .anchorsMatchLines] : [.anchorsMatchLines]
        guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: options) else { return nil }
        return (regex, rule.message)
    }

    static func commandWarnings(_ command: String) -> [String] {
        let range = NSRange(command.startIndex..., in: command)
        var messages = compiled.compactMap { regex, message in
            regex.firstMatch(in: command, range: range) != nil ? message() : nil
        }
        // "rm -rf" is one warning, not two
        let recursive = String(localized: "Deletes files and folders recursively")
        if messages.contains(recursive) { messages.removeAll { $0 == String(localized: "Force-deletes files") } }
        messages += sensitivePathsTouched(by: command).map { String(localized: "Touches \($0)") }
        return messages
    }

    /// Sensitive locations a command writes to, deletes or prints.
    private static func sensitivePathsTouched(by command: String) -> [String] {
        let interesting = #"(?:rm|mv|cp|cat|tee|chmod|chown|truncate|>|>>)"#
        var names: [String] = []
        for (pattern, name) in sensitiveCommandTargets {
            let full = interesting + #"[^;&|]*"# + pattern
            if command.range(of: full, options: .regularExpression) != nil {
                names.append(name)
            }
        }
        if names.contains("~/.ssh") { names.removeAll { $0 == "SSH keys" } }
        return names
    }

    private static let sensitiveCommandTargets: [(String, String)] = [
        (#"~?/?\.ssh\b"#, "~/.ssh"),
        (#"~?/?\.aws\b"#, "~/.aws"),
        (#"~?/?\.gnupg\b"#, "~/.gnupg"),
        (#"(?:^|[\s/])\.env(?:\.[\w.-]+)?\b"#, ".env"),
        (#"\bid_(?:rsa|ed25519|ecdsa)\b"#, "SSH keys"),
    ]

    // MARK: - File edits

    private static let editingTools: Set<String> = ["Write", "Edit", "MultiEdit", "NotebookEdit", "write_file", "replace", "edit", "write"]

    private static func editedPath(toolName: String, input: [String: Any]) -> String? {
        guard editingTools.contains(toolName) || toolName.lowercased().contains("write") || toolName.lowercased().contains("edit") else {
            return nil
        }
        for key in ["file_path", "notebook_path", "path", "filePath", "absolute_path"] {
            if let value = input[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    static func pathWarnings(_ rawPath: String, cwd: String?) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var path = rawPath
        if path.hasPrefix("~") { path = home + path.dropFirst() }
        if !path.hasPrefix("/"), let cwd { path = (cwd as NSString).appendingPathComponent(path) }
        path = (path as NSString).standardizingPath

        var messages: [String] = []
        let name = (path as NSString).lastPathComponent
        let sensitive = [
            "/.ssh/", "/.aws/", "/.gnupg/", "/.kube/", "/.docker/config.json",
            "/Library/LaunchAgents/", "/Library/LaunchDaemons/",
        ]
        let shellFiles: Set<String> = [".zshrc", ".zprofile", ".bashrc", ".bash_profile", ".profile", ".gitconfig", ".npmrc", ".netrc"]
        if sensitive.contains(where: { path.contains($0) }) || path.hasPrefix("/etc/") || path.hasPrefix("/private/etc/")
            || (shellFiles.contains(name) && (path as NSString).deletingLastPathComponent == home) {
            messages.append(String(localized: "Edits a sensitive file (\(name))"))
        } else if name == ".env" || name.hasPrefix(".env.") {
            messages.append(String(localized: "Edits a secrets file (\(name))"))
        }

        if let cwd, !cwd.isEmpty {
            let root = (cwd as NSString).standardizingPath
            let temporary = ["/tmp/", "/private/tmp/", "/private/var/folders/", "/var/folders/"]
            let inside = path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
            if !inside && !temporary.contains(where: { path.hasPrefix($0) }) && messages.isEmpty {
                messages.append(String(localized: "Edits a file outside the project"))
            }
        }
        return messages
    }

    // MARK: - Input helpers

    /// The shell command of a tool call: a string, or an argv array where
    /// `bash -lc "<script>"` shows just the script.
    static func shellCommand(from input: [String: Any]) -> String? {
        if let command = input["command"] as? String, !command.isEmpty { return command }
        if let argv = (input["command"] ?? input["cmd"] ?? input["argv"]) as? [Any] {
            let parts = argv.compactMap { $0 as? String }
            if parts.count >= 3, ["bash", "sh", "zsh", "/bin/bash", "/bin/sh", "/bin/zsh"].contains(parts[0]),
               parts[1].hasPrefix("-"), parts[1].contains("c") {
                return parts[2...].joined(separator: " ")
            }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }
        if let command = input["cmd"] as? String, !command.isEmpty { return command }
        return nil
    }
}
