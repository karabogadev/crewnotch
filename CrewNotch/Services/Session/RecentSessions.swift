//
//  RecentSessions.swift
//  CrewNotch
//
//  The last few sessions that ended, so one click can pick a conversation
//  back up in a terminal with the agent's own resume command.
//

import AppKit
import Combine

nonisolated struct RecentSession: Codable, Identifiable, Equatable, Sendable {
    let sessionId: String
    let agent: AgentKind
    let cwd: String
    let title: String
    let endedAt: Date
    /// Terminal app the session ran in, when known.
    var terminalBundleId: String?

    var id: String { sessionId }

    var projectName: String { URL(fileURLWithPath: cwd).lastPathComponent }

    /// The agent's own id, without CrewNotch's "agent:" prefix.
    private var agentSessionId: String {
        let prefix = agent.rawValue + ":"
        return sessionId.hasPrefix(prefix) ? String(sessionId.dropFirst(prefix.count)) : sessionId
    }

    /// The command that reopens the conversation, run from its project folder.
    var resumeCommand: String? {
        // Control characters would act as keystrokes when typed into a terminal
        let unsafe = CharacterSet.controlCharacters
        guard cwd.unicodeScalars.allSatisfy({ !unsafe.contains($0) }),
              agentSessionId.unicodeScalars.allSatisfy({ !unsafe.contains($0) }) else { return nil }
        let id = HookScript.shellQuote(agentSessionId)
        let resume: String
        switch agent {
        case .claude: resume = "claude --resume \(id)"
        case .codex: resume = "codex resume \(id)"
        case .gemini: resume = "gemini --resume \(id)"
        case .opencode: resume = "opencode --session \(id)"
        case .copilot: resume = "copilot --resume=\(id)"
        default: return nil
        }
        return "cd -- \(HookScript.shellQuote(cwd)) && \(resume)"
    }

    static func canResume(_ agent: AgentKind) -> Bool {
        [.claude, .codex, .gemini, .opencode, .copilot].contains(agent)
    }
}

@MainActor
final class RecentSessions: ObservableObject {
    static let shared = RecentSessions()

    @Published private(set) var items: [RecentSession]

    private static let storageKey = "recentSessions"
    private static let limit = 5
    private var live: [String: SessionState] = [:]
    private var terminals: [String: String] = [:]
    private var cancellable: AnyCancellable?

    private init() {
        items = UserDefaults.standard.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([RecentSession].self, from: $0) } ?? []
    }

    func start() {
        guard cancellable == nil else { return }
        cancellable = SessionStore.shared.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.sessionsChanged($0) }
    }

    func forget(_ item: RecentSession) {
        items.removeAll { $0.id == item.id }
        save()
    }

    // MARK: - Tracking

    private func sessionsChanged(_ sessions: [SessionState]) {
        let current = Dictionary(sessions.map { ($0.sessionId, $0) }, uniquingKeysWith: { _, new in new })
        var changed = false

        for (id, session) in live where current[id] == nil {
            if let recent = recent(from: session) {
                items.removeAll { $0.id == id }
                items.insert(recent, at: 0)
                changed = true
            }
            terminals[id] = nil
        }
        // A resumed conversation is live again
        let before = items.count
        items.removeAll { current[$0.id] != nil }
        changed = changed || items.count != before

        for session in sessions where terminals[session.sessionId] == nil && RecentSession.canResume(session.agent) {
            rememberTerminal(of: session)
        }

        live = current
        if items.count > Self.limit {
            items = Array(items.prefix(Self.limit))
            changed = true
        }
        if changed { save() }
    }

    private func recent(from session: SessionState) -> RecentSession? {
        guard RecentSession.canResume(session.agent),
              session.firstUserMessage != nil || session.lastUserMessageDate != nil || session.chatItems.contains(where: \.isUserMessage) else {
            return nil  // never talked to: nothing to resume
        }
        return RecentSession(
            sessionId: session.sessionId,
            agent: session.agent,
            cwd: session.cwd,
            title: session.displayTitle,
            endedAt: Date(),
            terminalBundleId: terminals[session.sessionId]
        )
    }

    /// Notes which terminal app hosts the session while it is still running.
    private func rememberTerminal(of session: SessionState) {
        guard let pid = session.pid else { return }
        terminals[session.sessionId] = ""
        let sessionId = session.sessionId
        Task {
            let bundle = await Task.detached { () -> String? in
                let tree = ProcessTreeBuilder.shared.buildTree()
                guard let terminalPid = ProcessTreeBuilder.shared.findTerminalPid(forProcess: pid, tree: tree) else { return nil }
                return NSRunningApplication(processIdentifier: pid_t(terminalPid))?.bundleIdentifier
            }.value
            if let bundle, terminals[sessionId] != nil { terminals[sessionId] = bundle }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

private extension ChatHistoryItem {
    var isUserMessage: Bool {
        if case .user = type { return true }
        return false
    }
}
