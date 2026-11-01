//
//  TerminalLauncher.swift
//  CrewNotch
//
//  Opens a new terminal window running a command (resuming a session).
//  Terminal and iTerm2 are driven over AppleScript, Ghostty through its
//  command-line options.
//

import AppKit

@MainActor
enum TerminalLauncher {
    private static let bundleIds: [ResumeTerminal: String] = [
        .terminal: "com.apple.Terminal",
        .iTerm: "com.googlecode.iterm2",
        .ghostty: "com.mitchellh.ghostty",
    ]

    /// Runs `command` in a new window of the chosen terminal. Returns false
    /// when it couldn't be started (the caller can copy the command instead).
    static func run(_ command: String, preferred: ResumeTerminal, sessionTerminal: String?) async -> Bool {
        switch terminal(preferred: preferred, sessionTerminal: sessionTerminal) {
        case .iTerm: return await runScript(iTermScript(command))
        case .ghostty: return runInGhostty(command)
        default: return await runScript(terminalScript(command))
        }
    }

    /// The chosen terminal, else the one the session ran in, else Terminal.
    private static func terminal(preferred: ResumeTerminal, sessionTerminal: String?) -> ResumeTerminal {
        let installed: (ResumeTerminal) -> Bool = { choice in
            bundleIds[choice].flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) } != nil
        }
        if preferred != .automatic, installed(preferred) { return preferred }
        if let sessionTerminal, let match = bundleIds.first(where: { $0.value == sessionTerminal })?.key, installed(match) {
            return match
        }
        return .terminal
    }

    private static func terminalScript(_ command: String) -> String {
        """
        tell application id "com.apple.Terminal"
            activate
            do script "\(escape(command))"
        end tell
        return true
        """
    }

    private static func iTermScript(_ command: String) -> String {
        """
        tell application id "com.googlecode.iterm2"
            activate
            set newWindow to (create window with default profile)
            tell current session of newWindow to write text "\(escape(command))"
        end tell
        return true
        """
    }

    /// Ghostty: a new window whose shell runs the command, then stays open.
    private static func runInGhostty(_ command: String) -> Bool {
        let shell = Foundation.ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        // Interactive login shell, so PATH additions from .zshrc (nvm, bun, …) are there
        process.arguments = ["-na", "Ghostty", "--args", "-e", shell, "-lic", "\(command); exec \(HookScript.shellQuote(shell)) -l"]
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    /// NSAppleScript runs on one serial queue, like the reply scripts.
    private static let scriptQueue = DispatchQueue(label: "com.karabogadev.crewnotch.launch")

    private static func runScript(_ source: String) async -> Bool {
        await withCheckedContinuation { continuation in
            scriptQueue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                continuation.resume(returning: error == nil && result != nil)
            }
        }
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
