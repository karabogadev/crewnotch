//
//  AgentSession.swift
//  CrewNotchTests
//
//  A fake agent session: sends that agent's own hook payloads through
//  `crewnotch-hook.py --agent <agent>` and reads the result from SessionStore.
//

import Foundation
import Testing
@testable import CrewNotch

@MainActor
struct AgentSession {
    let agent: String
    /// The id the agent itself uses.
    let rawId: String
    /// Which payload key carries the id (agents name it differently).
    let idKey: String

    /// The id CrewNotch stores: Claude's as is, everyone else's namespaced.
    var sessionId: String { agent == "claude" ? rawId : "\(agent):\(rawId)" }

    init(_ agent: String, idKey: String = "session_id", rawId: String = UUID().uuidString.lowercased()) {
        self.agent = agent
        self.idKey = idKey
        self.rawId = rawId
    }

    var state: SessionState? {
        get async { await SessionStore.shared.session(for: sessionId) }
    }

    /// Sends one hook event and waits until the store has applied it.
    @discardableResult
    func send(_ event: String, _ fields: [String: Any] = [:], sourceLocation: SourceLocation = #_sourceLocation) async throws -> SessionState? {
        let sent = Date()
        try await hook(event, fields).finish()
        return await Pipeline.waitFor(sessionId, sourceLocation: sourceLocation) { ($0?.lastActivity ?? .distantPast) > sent }
    }

    /// Sends an event that ends the session and waits until it is gone.
    func end(_ event: String = "SessionEnd", sourceLocation: SourceLocation = #_sourceLocation) async throws {
        try await hook(event).finish()
        await Pipeline.waitFor(sessionId, sourceLocation: sourceLocation) { $0 == nil }
    }

    /// Starts a hook without waiting for it: approval requests block until answered.
    func hook(_ event: String, _ fields: [String: Any] = [:]) throws -> ScriptRun {
        var payload = fields
        payload[idKey] = rawId
        payload["cwd"] = Pipeline.workspace.path
        let stdin = try JSONSerialization.data(withJSONObject: payload)
        return try ScriptRun(script: "crewnotch-hook", arguments: ["--agent", agent, "--event", event], stdin: stdin)
    }

    /// Waits until the session shows an approval request.
    @discardableResult
    func waitForRequest(sourceLocation: SourceLocation = #_sourceLocation) async -> PermissionContext? {
        await Pipeline.waitFor(sessionId, sourceLocation: sourceLocation) { $0?.activePermission != nil }?.activePermission
    }

    func waitForPhase(_ phase: SessionPhase, sourceLocation: SourceLocation = #_sourceLocation) async {
        await Pipeline.waitFor(sessionId, sourceLocation: sourceLocation) { $0?.phase == phase }
    }
}
