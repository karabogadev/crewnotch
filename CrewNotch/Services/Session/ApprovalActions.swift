//
//  ApprovalActions.swift
//  CrewNotch
//
//  Answers a pending request: allow (once or always), deny, or reply to
//  an AskUserQuestion. Shared by the session rows, the chat view and the
//  panel's keyboard shortcuts.
//

import Foundation

@MainActor
enum ApprovalActions {
    /// Allows the session's pending request. `always` also saves the rule the
    /// agent suggested, so the same request won't ask again.
    static func approve(sessionId: String, always: Bool = false) {
        Task {
            guard let permission = await pendingPermission(sessionId) else { return }
            var response = HookResponse(decision: "allow", reason: nil)
            if always, let suggestions = permission.suggestions {
                response.updatedPermissions = suggestions
            }
            HookSocketServer.shared.respondToPermission(toolUseId: permission.toolUseId, response: response)
            await SessionStore.shared.process(.permissionApproved(sessionId: sessionId, toolUseId: permission.toolUseId))
        }
    }

    static func deny(sessionId: String, reason: String? = nil) {
        Task {
            guard let permission = await pendingPermission(sessionId) else { return }
            HookSocketServer.shared.respondToPermission(toolUseId: permission.toolUseId, decision: "deny", reason: reason)
            await SessionStore.shared.process(.permissionDenied(sessionId: sessionId, toolUseId: permission.toolUseId, reason: reason))
        }
    }

    /// Answers an AskUserQuestion: `answers` maps each question's text to the
    /// chosen label (several labels joined with ", ", or typed text).
    static func answer(sessionId: String, answers: [String: String]) {
        Task {
            guard let permission = await pendingPermission(sessionId),
                  permission.toolName == "AskUserQuestion" else { return }
            var input = permission.toolInput ?? [:]
            input["answers"] = AnyCodable(answers)
            var response = HookResponse(decision: "allow", reason: nil)
            response.updatedInput = input
            HookSocketServer.shared.respondToPermission(toolUseId: permission.toolUseId, response: response)
            await SessionStore.shared.process(.permissionApproved(sessionId: sessionId, toolUseId: permission.toolUseId))
        }
    }

    /// The request keyboard shortcuts act on: the oldest one CrewNotch can answer.
    static func keyboardTarget(in sessions: [SessionState]) -> SessionState? {
        sessions
            .filter { $0.activePermission?.canRespond == true }
            .min { ($0.activePermission?.receivedAt ?? .distantFuture) < ($1.activePermission?.receivedAt ?? .distantFuture) }
    }

    private static func pendingPermission(_ sessionId: String) async -> PermissionContext? {
        await SessionStore.shared.session(for: sessionId)?.activePermission
    }
}
