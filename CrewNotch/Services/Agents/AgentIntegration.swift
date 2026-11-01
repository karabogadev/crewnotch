//
//  AgentIntegration.swift
//  CrewNotch
//
//  How CrewNotch connects to each coding agent: detection, and adding or
//  removing its hooks in the agent's own configuration.
//

import Foundation

nonisolated protocol AgentIntegration: Sendable {
    var agent: AgentKind { get }
    /// Whether the agent is installed on this Mac.
    func isDetected() -> Bool
    /// Whether CrewNotch's hooks are registered with the agent.
    func isConnected() -> Bool
    func connect() throws
    func disconnect() throws
    /// Extra step the user has to take in the agent after connecting, if any.
    var setupNote: String? { get }
}

nonisolated extension AgentIntegration {
    var setupNote: String? { nil }
}

nonisolated enum AgentIntegrations {
    static let all: [AgentKind: any AgentIntegration] = {
        let list: [any AgentIntegration] = [
            ClaudeCodeIntegration(),
            CodexIntegration(),
            CursorIntegration(),
            GeminiIntegration(),
            AntigravityIntegration(),
            DeepSeekIntegration(),
            OpenCodeIntegration(),
            CopilotIntegration(),
            GrokIntegration(),
            KiroIntegration(),
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.agent, $0) })
    }()
}

nonisolated private let home = FileManager.default.homeDirectoryForCurrentUser

// MARK: - Codex

/// ~/.codex/hooks.json, same shape as Claude Code's hooks.
nonisolated struct CodexIntegration: AgentIntegration {
    let agent = AgentKind.codex
    private var file: URL { home.appendingPathComponent(".codex/hooks.json") }

    var setupNote: String? {
        "Codex asks you to review new hooks the next time it starts. Choose \u{201C}Trust all and continue\u{201D}."
    }

    func isDetected() -> Bool {
        AgentDetection.binaryExists("codex") || AgentDetection.exists(".codex")
    }

    func isConnected() -> Bool {
        GroupedHooks.containsOurs((try? JSONConfigFile.load(file))?["hooks"] as? [String: Any])
    }

    func connect() throws {
        var json = try JSONConfigFile.load(file)
        let tool = ["PreToolUse", "PostToolUse"].map { GroupedHooks.Registration(event: $0, matcher: "*") }
        let lifecycle = ["SessionStart", "UserPromptSubmit", "Stop", "Interrupt", "SessionEnd",
                         "SubagentStart", "SubagentStop", "PreCompact", "PostCompact"]
            .map { GroupedHooks.Registration(event: $0) }
        let approval = GroupedHooks.Registration(event: "PermissionRequest", matcher: "*", timeout: 3600)
        json["hooks"] = GroupedHooks.installing(lifecycle + tool + [approval], agent: agent, into: json["hooks"] as? [String: Any] ?? [:])
        try JSONConfigFile.save(json, to: file)
    }

    func disconnect() throws {
        var json = try JSONConfigFile.load(file)
        json["hooks"] = GroupedHooks.removingOurs(from: json["hooks"] as? [String: Any] ?? [:])
        try JSONConfigFile.save(json, to: file)
    }
}

// MARK: - Gemini CLI

/// "hooks" in ~/.gemini/settings.json.
nonisolated struct GeminiIntegration: AgentIntegration {
    let agent = AgentKind.gemini
    private var file: URL { home.appendingPathComponent(".gemini/settings.json") }

    func isDetected() -> Bool {
        AgentDetection.binaryExists("gemini") || AgentDetection.exists(".gemini/settings.json")
    }

    func isConnected() -> Bool {
        GroupedHooks.containsOurs((try? JSONConfigFile.load(file))?["hooks"] as? [String: Any])
    }

    func connect() throws {
        var json = try JSONConfigFile.load(file)
        let events = ["SessionStart", "BeforeAgent", "BeforeTool", "AfterTool", "Notification",
                      "AfterAgent", "PreCompress", "SessionEnd"]
        let registrations = events.map {
            GroupedHooks.Registration(event: $0, timeout: 5000, extra: ["name": "crewnotch"])
        }
        json["hooks"] = GroupedHooks.installing(registrations, agent: agent, into: json["hooks"] as? [String: Any] ?? [:])
        try JSONConfigFile.save(json, to: file)
    }

    func disconnect() throws {
        var json = try JSONConfigFile.load(file)
        let remaining = GroupedHooks.removingOurs(from: json["hooks"] as? [String: Any] ?? [:])
        json["hooks"] = remaining.isEmpty ? nil : remaining
        try JSONConfigFile.save(json, to: file)
    }
}

// MARK: - Cursor

/// ~/.cursor/hooks.json: `{ "version": 1, "hooks": { "<event>": [ { "command": ... } ] } }`.
nonisolated struct CursorIntegration: AgentIntegration {
    let agent = AgentKind.cursor
    private var file: URL { home.appendingPathComponent(".cursor/hooks.json") }
    private static let events = ["sessionStart", "beforeSubmitPrompt", "preToolUse", "postToolUse",
                                 "postToolUseFailure", "afterAgentResponse", "subagentStart",
                                 "subagentStop", "preCompact", "stop", "sessionEnd"]

    func isDetected() -> Bool {
        AgentDetection.appInstalled(agent.appBundleIdentifiers()) || AgentDetection.exists(".cursor")
    }

    func isConnected() -> Bool {
        JSONConfigFile.contains(file, HookScript.marker)
    }

    func connect() throws {
        var json = try JSONConfigFile.load(file)
        var hooks = removingOurs(json["hooks"] as? [String: Any] ?? [:])
        for event in Self.events {
            let existing = hooks[event] as? [[String: Any]] ?? []
            hooks[event] = existing + [["command": HookScript.command(agent: agent, event: event)]]
        }
        json["version"] = json["version"] ?? 1
        json["hooks"] = hooks
        try JSONConfigFile.save(json, to: file)
    }

    func disconnect() throws {
        var json = try JSONConfigFile.load(file)
        json["hooks"] = removingOurs(json["hooks"] as? [String: Any] ?? [:])
        try JSONConfigFile.save(json, to: file)
    }

    private func removingOurs(_ hooks: [String: Any]) -> [String: Any] {
        hooks.compactMapValues { value in
            guard let handlers = value as? [[String: Any]] else { return value }
            let kept = handlers.filter { !GroupedHooks.isOurs($0) }
            return kept.isEmpty ? nil : kept
        }
    }
}

// MARK: - Antigravity

/// A named "crewnotch" hook in Antigravity's global ~/.gemini/config/hooks.json.
/// PreToolUse is deliberately not registered: answering it would bypass the
/// user's approval prompt.
nonisolated struct AntigravityIntegration: AgentIntegration {
    let agent = AgentKind.antigravity
    private var file: URL { home.appendingPathComponent(".gemini/config/hooks.json") }
    private static let hookName = "crewnotch"

    var setupNote: String? { "Restart Antigravity to load the hooks." }

    func isDetected() -> Bool {
        AgentDetection.appInstalled(agent.appBundleIdentifiers()) || AgentDetection.exists(".gemini/antigravity")
    }

    func isConnected() -> Bool {
        ((try? JSONConfigFile.load(file))?[Self.hookName]) != nil
    }

    func connect() throws {
        var json = try JSONConfigFile.load(file)
        func handler(_ event: String) -> [String: Any] {
            ["type": "command", "command": HookScript.command(agent: agent, event: event), "timeout": 5]
        }
        json[Self.hookName] = [
            "enabled": true,
            "SessionStart": [handler("SessionStart")],
            "PreInvocation": [handler("PreInvocation")],
            "PostToolUse": [["matcher": "*", "hooks": [handler("PostToolUse")]]],
            "Stop": [handler("Stop")],
        ] as [String: Any]
        try JSONConfigFile.save(json, to: file)
    }

    func disconnect() throws {
        var json = try JSONConfigFile.load(file)
        json[Self.hookName] = nil
        try JSONConfigFile.save(json, to: file)
    }
}

// MARK: - Copilot CLI

/// CrewNotch's own file in ~/.copilot/hooks/. Approvals are observed through
/// `notification` because `permissionRequest` fires for every permission
/// check, including ones Copilot would allow on its own.
nonisolated struct CopilotIntegration: AgentIntegration {
    let agent = AgentKind.copilot
    private var file: URL { home.appendingPathComponent(".copilot/hooks/crewnotch.json") }
    private static let events = ["sessionStart", "userPromptSubmitted", "preToolUse", "postToolUse",
                                 "postToolUseFailure", "notification", "agentStop", "subagentStart",
                                 "subagentStop", "preCompact", "sessionEnd"]

    func isDetected() -> Bool {
        AgentDetection.binaryExists("copilot") || AgentDetection.exists(".copilot")
    }

    func isConnected() -> Bool {
        FileManager.default.fileExists(atPath: file.path)
    }

    func connect() throws {
        var hooks: [String: Any] = [:]
        for event in Self.events {
            hooks[event] = [["type": "command", "bash": HookScript.command(agent: agent, event: event), "timeoutSec": 10]]
        }
        try JSONConfigFile.save(["version": 1, "hooks": hooks], to: file)
    }

    func disconnect() throws {
        try JSONConfigFile.remove(file)
    }
}

// MARK: - Grok

/// CrewNotch's own file in ~/.grok/hooks/ (Claude Code format).
nonisolated struct GrokIntegration: AgentIntegration {
    let agent = AgentKind.grok
    private var file: URL { home.appendingPathComponent(".grok/hooks/crewnotch.json") }

    func isDetected() -> Bool {
        AgentDetection.exists(".grok")
    }

    func isConnected() -> Bool {
        FileManager.default.fileExists(atPath: file.path)
    }

    func connect() throws {
        let tool = ["PreToolUse", "PostToolUse", "PostToolUseFailure"].map { GroupedHooks.Registration(event: $0, matcher: "*") }
        let lifecycle = ["SessionStart", "UserPromptSubmit", "Notification", "Stop", "StopCancelled",
                         "StopFailure", "SubagentStart", "SubagentStop", "PreCompact", "SessionEnd"]
            .map { GroupedHooks.Registration(event: $0) }
        let hooks = GroupedHooks.installing(lifecycle + tool, agent: agent, into: [:])
        try JSONConfigFile.save(["hooks": hooks], to: file)
    }

    func disconnect() throws {
        try JSONConfigFile.remove(file)
    }
}

// MARK: - Kiro

/// CrewNotch's own global hook file in ~/.kiro/hooks/. Kiro only reads it with
/// the v3 agent engine; the default engine keeps hooks inside agent configs.
nonisolated struct KiroIntegration: AgentIntegration {
    let agent = AgentKind.kiro
    private var file: URL { home.appendingPathComponent(".kiro/hooks/crewnotch.json") }

    var setupNote: String? { "Kiro runs global hooks with the v3 engine: start it with kiro-cli chat --v3." }

    func isDetected() -> Bool {
        AgentDetection.binaryExists("kiro-cli") || AgentDetection.exists(".kiro")
    }

    func isConnected() -> Bool {
        FileManager.default.fileExists(atPath: file.path)
    }

    func connect() throws {
        let triggers = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "SessionEnd"]
        let hooks: [[String: Any]] = triggers.map { trigger in
            [
                "name": "crewnotch-\(trigger)",
                "trigger": trigger,
                "action": ["type": "command", "command": HookScript.command(agent: agent, event: trigger)],
                "timeout": 10,
            ]
        }
        try JSONConfigFile.save(["version": "v1", "hooks": hooks], to: file)
    }

    func disconnect() throws {
        try JSONConfigFile.remove(file)
    }
}
