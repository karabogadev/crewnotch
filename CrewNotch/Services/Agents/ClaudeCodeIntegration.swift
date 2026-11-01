//
//  ClaudeCodeIntegration.swift
//  CrewNotch
//
//  Connects Claude Code through hooks in its settings.json
//

import Foundation

nonisolated struct ClaudeCodeIntegration: AgentIntegration {
    let agent = AgentKind.claude

    func isDetected() -> Bool {
        FileManager.default.fileExists(atPath: ClaudePaths.claudeDir.path) || Self.claudeBinary() != nil
    }

    func isConnected() -> Bool {
        GroupedHooks.containsOurs((try? JSONConfigFile.load(ClaudePaths.settingsFile))?["hooks"] as? [String: Any])
    }

    func connect() throws {
        var json = try JSONConfigFile.load(ClaudePaths.settingsFile)
        let registrations = Self.registrations(for: Self.detectClaudeCodeVersion())
        json["hooks"] = GroupedHooks.installing(registrations, agent: agent, into: json["hooks"] as? [String: Any] ?? [:])
        try JSONConfigFile.save(json, to: ClaudePaths.settingsFile)
    }

    func disconnect() throws {
        var json = try JSONConfigFile.load(ClaudePaths.settingsFile)
        let remaining = GroupedHooks.removingOurs(from: json["hooks"] as? [String: Any] ?? [:])
        json["hooks"] = remaining.isEmpty ? nil : remaining
        try JSONConfigFile.save(json, to: ClaudePaths.settingsFile)
    }

    /// Hook events to register, limited to what the installed Claude Code knows:
    /// it rejects unknown hook keys, so without a detected version we stick to
    /// the baseline every version supports (#85).
    static func registrations(for version: ClaudeCodeVersion?) -> [GroupedHooks.Registration] {
        typealias R = GroupedHooks.Registration
        var events: [R] = [
            R(event: "UserPromptSubmit"),
            R(event: "PreToolUse", matcher: "*"),
            R(event: "PostToolUse", matcher: "*"),
            R(event: "PermissionRequest", matcher: "*", timeout: 86400),
            R(event: "Notification", matcher: "*"),
            R(event: "Stop"),
            R(event: "SubagentStop"),
            R(event: "SessionStart"),
            R(event: "SessionEnd"),
            R(event: "PreCompact", matcher: "auto"),
            R(event: "PreCompact", matcher: "manual"),
        ]
        guard let version else { return events }

        if version >= ClaudeCodeVersion(major: 2, minor: 0, patch: 0) {
            events.append(R(event: "PostToolUseFailure", matcher: "*"))
        }
        if version >= ClaudeCodeVersion(major: 2, minor: 0, patch: 43) {
            events.append(R(event: "SubagentStart"))
        }
        if version >= ClaudeCodeVersion(major: 2, minor: 1, patch: 76) {
            events.append(R(event: "PostCompact", matcher: "auto"))
            events.append(R(event: "PostCompact", matcher: "manual"))
        }
        if version >= ClaudeCodeVersion(major: 2, minor: 1, patch: 78) {
            events.append(R(event: "StopFailure"))
        }
        if version >= ClaudeCodeVersion(major: 2, minor: 1, patch: 88) {
            events.append(R(event: "PermissionDenied", matcher: "*"))
        }
        return events
    }

    private static func claudeBinary() -> String? {
        let candidates = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            NSHomeDirectory() + "/.claude/local/claude",
            NSHomeDirectory() + "/.local/bin/claude",
            "/usr/bin/claude",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Claude Code Version Detection

    /// Simple semantic version used to gate which hook events we register.
    /// Claude Code rejects unknown hook keys, so we must only register
    /// events the installed version knows about.
    struct ClaudeCodeVersion: Comparable {
        let major: Int
        let minor: Int
        let patch: Int

        static func < (lhs: ClaudeCodeVersion, rhs: ClaudeCodeVersion) -> Bool {
            (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }
    }

    /// Runs `claude --version` and parses the result. Returns nil on any
    /// failure (binary not found, non-zero exit, unparseable output).
    static func detectClaudeCodeVersion() -> ClaudeCodeVersion? {
        guard let claudePath = claudeBinary() else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            return parseClaudeCodeVersion(from: output)
        } catch {
            return nil
        }
    }

    /// Extracts the first `X.Y.Z` token from arbitrary version output.
    /// Accepts any prefix/suffix — works for "2.1.88", "v2.1.88", "claude 2.1.88 (...)" etc.
    static func parseClaudeCodeVersion(from text: String) -> ClaudeCodeVersion? {
        let pattern = #"(\d+)\.(\d+)\.(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges == 4,
              let majorRange = Range(match.range(at: 1), in: text),
              let minorRange = Range(match.range(at: 2), in: text),
              let patchRange = Range(match.range(at: 3), in: text),
              let major = Int(text[majorRange]),
              let minor = Int(text[minorRange]),
              let patch = Int(text[patchRange])
        else { return nil }
        return ClaudeCodeVersion(major: major, minor: minor, patch: patch)
    }
}
