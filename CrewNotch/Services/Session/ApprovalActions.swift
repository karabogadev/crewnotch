//
//  ApprovalActions.swift
//  CrewNotch
//
//  Answers a pending request: allow (once or always), deny, or reply to
//  an AskUserQuestion. Shared by the session rows, the chat view and the
//  panel's keyboard shortcuts.
//
//  Every answer names the request it was meant for (`toolUseId`), taken when
//  the user clicked or pressed the key. If the session has moved on to a
//  different request in the meantime, nothing is answered.
//

import Foundation

@MainActor
enum ApprovalActions {
    /// Allows the request. `always` also saves the rule the agent suggested,
    /// so the same request won't ask again.
    static func approve(sessionId: String, toolUseId: String?, always: Bool = false) {
        Task {
            guard let permission = await pendingPermission(sessionId, expected: toolUseId) else { return }
            var response = HookResponse(decision: "allow", reason: nil)
            if always, let suggestions = permission.suggestions {
                response.updatedPermissions = suggestions
            }
            deliver(response, for: permission, sessionId: sessionId,
                    then: .permissionApproved(sessionId: sessionId, toolUseId: permission.toolUseId))
        }
    }

    static func deny(sessionId: String, toolUseId: String?, reason: String? = nil) {
        Task {
            guard let permission = await pendingPermission(sessionId, expected: toolUseId) else { return }
            deliver(HookResponse(decision: "deny", reason: reason), for: permission, sessionId: sessionId,
                    then: .permissionDenied(sessionId: sessionId, toolUseId: permission.toolUseId, reason: reason))
        }
    }

    /// Answers an AskUserQuestion: `answers` maps each question's text to the
    /// chosen label (several labels joined with ", ", or typed text).
    static func answer(sessionId: String, toolUseId: String?, answers: [String: String]) {
        Task {
            guard let permission = await pendingPermission(sessionId, expected: toolUseId),
                  permission.toolName == "AskUserQuestion" else { return }
            var input = permission.toolInput ?? [:]
            input["answers"] = AnyCodable(answers)
            var response = HookResponse(decision: "allow", reason: nil)
            response.updatedInput = input
            deliver(response, for: permission, sessionId: sessionId,
                    then: .permissionApproved(sessionId: sessionId, toolUseId: permission.toolUseId))
        }
    }

    /// The request keyboard shortcuts act on: the oldest one CrewNotch can answer.
    static func keyboardTarget(in sessions: [SessionState]) -> SessionState? {
        sessions
            .filter { $0.activePermission?.canRespond == true }
            .min { ($0.activePermission?.receivedAt ?? .distantFuture) < ($1.activePermission?.receivedAt ?? .distantFuture) }
    }

    /// Whether "Always" may be offered: the agent suggested a rule we can show,
    /// and the request isn't one we flag as risky (a broad rule there is a trap).
    static func offersAlways(_ permission: PermissionContext, cwd: String) -> Bool {
        AppSettings.offerAlwaysAllow && permission.suggestionSummary != nil && permission.riskWarnings(cwd: cwd).isEmpty
    }

    // MARK: - Helpers

    /// Sends the answer; the session only moves on once the hook really got it.
    private static func deliver(_ response: HookResponse, for permission: PermissionContext, sessionId: String, then event: SessionEvent) {
        let toolUseId = permission.toolUseId
        HookSocketServer.shared.respondToPermission(toolUseId: toolUseId, response: response) { delivered in
            Task {
                await SessionStore.shared.process(
                    delivered ? event : .permissionSocketFailed(sessionId: sessionId, toolUseId: toolUseId))
            }
        }
    }

    private static func pendingPermission(_ sessionId: String, expected toolUseId: String?) async -> PermissionContext? {
        guard let permission = await SessionStore.shared.session(for: sessionId)?.activePermission,
              toolUseId == nil || permission.toolUseId == toolUseId else { return nil }
        return permission
    }
}
