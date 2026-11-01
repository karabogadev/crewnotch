//
//  AgentRegistry.swift
//  CrewNotch
//
//  Tracks which agents are installed and connected, and connects or
//  disconnects them. Config edits run off the main thread.
//

import Combine
import Foundation
import os.log

@MainActor
final class AgentRegistry: ObservableObject {
    static let shared = AgentRegistry()

    struct Status: Equatable {
        var isDetected = false
        var isConnected = false
        var error: String?
    }

    @Published private(set) var statuses: [AgentKind: Status] = [:]

    nonisolated private static let logger = Logger(subsystem: "com.karabogadev.crewnotch", category: "Agents")

    private init() {}

    func status(for agent: AgentKind) -> Status {
        statuses[agent] ?? Status()
    }

    /// On launch: refresh the hook script and re-apply every connected
    /// integration so commands always point at the current script.
    func start() {
        Task {
            _ = await Self.run {
                try HookScript.install()
                for agent in AppSettings.connectedAgents {
                    try? AgentIntegrations.all[agent]?.connect()
                }
            }
            await refresh()
        }
    }

    func refresh() async {
        let snapshot: [AgentKind: Status] = await Task.detached {
            var result: [AgentKind: Status] = [:]
            for (agent, integration) in AgentIntegrations.all {
                result[agent] = Status(isDetected: integration.isDetected(), isConnected: integration.isConnected())
            }
            return result
        }.value
        for (agent, status) in snapshot {
            statuses[agent] = Status(isDetected: status.isDetected, isConnected: status.isConnected, error: statuses[agent]?.error)
        }
    }

    func connect(_ agent: AgentKind) async {
        await change(agent, connect: true)
    }

    func disconnect(_ agent: AgentKind) async {
        await change(agent, connect: false)
    }

    private func change(_ agent: AgentKind, connect: Bool) async {
        guard let integration = AgentIntegrations.all[agent] else { return }
        let error = await Self.run {
            try HookScript.install()
            if connect { try integration.connect() } else { try integration.disconnect() }
        }
        if error == nil {
            var connected = AppSettings.connectedAgents
            if connect { connected.insert(agent) } else { connected.remove(agent) }
            AppSettings.connectedAgents = connected
        }
        statuses[agent, default: Status()].error = error
        await refresh()
    }

    /// Runs file work in the background and returns a user-facing error message.
    private static func run(_ work: @escaping @Sendable () throws -> Void) async -> String? {
        await Task.detached {
            do {
                try work()
                return nil
            } catch {
                logger.error("Agent integration failed: \(error.localizedDescription, privacy: .public)")
                return error.localizedDescription
            }
        }.value
    }
}
