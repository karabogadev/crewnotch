//
//  AgentKind.swift
//  CrewNotch
//
//  The coding agents CrewNotch can monitor and what each one supports.
//

import Foundation

nonisolated enum AgentKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case claude
    case codex
    case cursor
    case gemini
    case antigravity
    case deepseek
    case opencode
    case copilot
    case grok
    case kiro

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .gemini: return "Gemini CLI"
        case .antigravity: return "Antigravity"
        case .deepseek: return "DeepSeek Harness"
        case .opencode: return "OpenCode"
        case .copilot: return "Copilot CLI"
        case .grok: return "Grok"
        case .kiro: return "Kiro"
        }
    }

    /// Claude Code is the only agent whose JSONL transcript we parse for
    /// full chat history; other agents build their history from hook events.
    var hasClaudeTranscript: Bool {
        self == .claude
    }

    /// Whether an approval prompt can be answered from the notch: the agent
    /// asks CrewNotch only when it would prompt, and takes the answer.
    var supportsApproval: Bool {
        self == .claude || self == .codex || self == .opencode
    }

    /// Agents that live in a terminal (focus goes to the terminal/tmux pane)
    /// rather than in their own app window.
    var isTerminalAgent: Bool {
        switch self {
        case .cursor, .antigravity, .deepseek: return false
        default: return true
        }
    }

    /// Bundle identifiers of the agent's desktop app, most specific first.
    /// `surface` distinguishes front ends of the same agent (Antigravity app vs IDE).
    func appBundleIdentifiers(surface: String? = nil) -> [String] {
        switch self {
        case .cursor:
            return ["com.todesktop.230313mzl4w4u92"]
        case .antigravity:
            return surface == "ide"
                ? ["com.google.antigravity-ide", "com.google.antigravity"]
                : ["com.google.antigravity", "com.google.antigravity-ide"]
        case .deepseek:
            return ["com.deepseek.dsh"]
        default:
            return []
        }
    }
}
