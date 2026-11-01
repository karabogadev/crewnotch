//
//  TerminalMessenger.swift
//  CrewNotch
//
//  Sends a reply typed in the notch to the terminal session running the
//  agent: through tmux when the agent runs inside it, otherwise through the
//  terminal app's own scripting (Ghostty, Terminal, iTerm2). macOS asks once
//  for permission to control the terminal.
//

import AppKit
import Combine
import os.log

enum ReplyHost: Equatable {
    case tmux
    case ghostty
    case terminal
    case iTerm

    var appName: String {
        switch self {
        case .tmux: return "tmux"
        case .ghostty: return "Ghostty"
        case .terminal: return "Terminal"
        case .iTerm: return "iTerm2"
        }
    }

    fileprivate static func forBundle(_ identifier: String?) -> ReplyHost? {
        switch identifier {
        case "com.mitchellh.ghostty": return .ghostty
        case "com.apple.Terminal": return .terminal
        case "com.googlecode.iterm2": return .iTerm
        default: return nil
        }
    }
}

enum TerminalMessenger {
    private static let logger = Logger(subsystem: "com.karabogadev.crewnotch", category: "Reply")
    private static let scriptQueue = DispatchQueue(label: "com.karabogadev.crewnotch.reply")

    /// Where a reply to this session can be delivered, if anywhere.
    @MainActor
    static func host(for session: SessionState) async -> ReplyHost? {
        guard session.agent.isTerminalAgent, let pid = session.pid else { return nil }
        if session.isInTmux && session.tty != nil { return .tmux }

        let tree = await Task.detached { ProcessTreeBuilder.shared.buildTree() }.value
        guard let terminalPid = ProcessTreeBuilder.shared.findTerminalPid(forProcess: pid, tree: tree) else { return nil }
        let app = NSRunningApplication(processIdentifier: pid_t(terminalPid))
        return ReplyHost.forBundle(app?.bundleIdentifier)
    }

    /// Types `text` into the session's terminal and presses Return.
    /// Returns false when the terminal couldn't be reached (or permission was denied).
    static func send(_ text: String, to session: SessionState, via host: ReplyHost) async -> Bool {
        let script: String
        switch host {
        case .tmux:
            return false  // handled by the tmux path in ChatView
        case .ghostty:
            script = ghosttyScript(text: text, cwd: session.cwd, titleHint: session.displayTitle)
        case .terminal:
            guard let tty = session.tty else { return false }
            script = terminalScript(text: text, tty: tty)
        case .iTerm:
            guard let tty = session.tty else { return false }
            script = iTermScript(text: text, tty: tty)
        }
        return await run(script)
    }

    // MARK: - Scripts

    /// Ghostty terminals don't expose a tty, so match the agent's working
    /// directory, preferring a terminal whose title matches the conversation.
    private static func ghosttyScript(text: String, cwd: String, titleHint: String) -> String {
        """
        tell application id "com.mitchellh.ghostty"
            set matches to (every terminal whose working directory is "\(escape(cwd))")
            if (count of matches) is 0 then return false
            set target to item 1 of matches
            repeat with t in matches
                if name of t contains "\(escape(String(titleHint.prefix(24))))" then set target to t
            end repeat
            input text "\(escape(text))" to target
            send key "enter" to target
            return true
        end tell
        """
    }

    private static func terminalScript(text: String, tty: String) -> String {
        """
        tell application id "com.apple.Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "/dev/\(escape(tty))" then
                        do script "\(escape(singleLine(text)))" in t
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """
    }

    private static func iTermScript(text: String, tty: String) -> String {
        """
        tell application id "com.googlecode.iterm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "/dev/\(escape(tty))" then
                            tell s to write text "\(escape(singleLine(text)))"
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """
    }

    // MARK: - Running

    private static func run(_ source: String) async -> Bool {
        await withCheckedContinuation { continuation in
            scriptQueue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error {
                    logger.error("Reply script failed: \(error, privacy: .public)")
                }
                continuation.resume(returning: result?.booleanValue ?? false)
            }
        }
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Terminal and iTerm2 submit at the first newline, so send one line.
    private static func singleLine(_ text: String) -> String {
        text.components(separatedBy: .newlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// Remembers which sessions can be replied to, so rows only offer the chat
/// button where a reply can actually be delivered.
@MainActor
final class ReplyHostCache: ObservableObject {
    static let shared = ReplyHostCache()

    @Published private(set) var hosts: [String: ReplyHost?] = [:]

    private init() {}

    /// nil while unknown; `.some(nil)` when the session can't be replied to
    func host(for session: SessionState) -> ReplyHost?? {
        hosts[key(session)]
    }

    func resolve(_ session: SessionState) async {
        let key = key(session)
        guard hosts[key] == nil else { return }
        hosts[key] = .some(await TerminalMessenger.host(for: session))
    }

    private func key(_ session: SessionState) -> String {
        "\(session.sessionId)-\(session.pid ?? 0)-\(session.isInTmux)"
    }
}
