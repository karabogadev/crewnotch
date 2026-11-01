//
//  SessionFocuser.swift
//  CrewNotch
//
//  Brings a session's window to the front: the agent's own app for desktop
//  agents, the tmux pane (via yabai) or terminal app for terminal agents.
//

import AppKit

@MainActor
enum SessionFocuser {
    static func canFocus(_ session: SessionState) -> Bool {
        !session.agent.isTerminalAgent || session.pid != nil
    }

    static func focus(_ session: SessionState) async {
        if !session.agent.isTerminalAgent {
            activateApp(for: session)
            return
        }
        guard let pid = session.pid else { return }

        if session.isInTmux, await WindowFinder.shared.isYabaiAvailable(),
           await YabaiController.shared.focusWindow(forClaudePid: pid) {
            return
        }

        let tree = ProcessTreeBuilder.shared.buildTree()
        if let terminalPid = ProcessTreeBuilder.shared.findTerminalPid(forProcess: pid, tree: tree) {
            NSRunningApplication(processIdentifier: pid_t(terminalPid))?.activate()
        }
    }

    /// Whether the user is already looking at this session.
    static func isFocused(_ session: SessionState) async -> Bool {
        if !session.agent.isTerminalAgent {
            let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            return frontmost.map(session.agent.appBundleIdentifiers(surface: session.sourceApp).contains) ?? false
        }
        guard let pid = session.pid else { return false }
        return await TerminalVisibilityDetector.isSessionFocused(sessionPid: pid)
    }

    private static func activateApp(for session: SessionState) {
        let identifiers = session.agent.appBundleIdentifiers(surface: session.sourceApp)
        for identifier in identifiers {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first {
                app.activate()
                return
            }
        }
        if let identifier = identifiers.first,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
