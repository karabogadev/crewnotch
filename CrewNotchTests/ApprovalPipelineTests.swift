//
//  ApprovalPipelineTests.swift
//  CrewNotchTests
//
//  An agent asks for approval, the notch answers through ApprovalActions,
//  and the hook prints the decision in the agent's own format.
//

import Foundation
import Testing
@testable import CrewNotch

extension EndToEnd {
    @Suite("Approvals")
    struct Approvals {
        init() async throws { try await Pipeline.start() }

        nonisolated(unsafe) static let bash: [String: Any] = ["command": "npm test", "description": "Run the tests"]
        nonisolated(unsafe) static let suggestions: [[String: Any]] = [[
            "type": "addRules",
            "rules": [["toolName": "Bash", "ruleContent": "npm test:*"]],
            "behavior": "allow",
            "destination": "localSettings",
        ]]

        /// PreToolUse carries the tool_use_id; the PermissionRequest that
        /// follows has none, so the app pairs them by session, tool and input.
        /// Returns the blocked hook once the request shows in the notch.
        func ask(
            _ session: AgentSession, tool: String = "Bash", input: [String: Any] = bash,
            suggestions: [[String: Any]]? = suggestions,
            sourceLocation: SourceLocation = #_sourceLocation
        ) async throws -> (hook: ScriptRun, request: PermissionContext) {
            let toolUseId = "toolu_\(UUID().uuidString.prefix(8))"
            try await session.send("PreToolUse", ["tool_name": tool, "tool_input": input, "tool_use_id": toolUseId])
            var fields: [String: Any] = ["tool_name": tool, "tool_input": input]
            fields["permission_suggestions"] = suggestions
            let hook = try session.hook("PermissionRequest", fields)
            let request = try #require(await session.waitForRequest(), sourceLocation: sourceLocation)
            // A request shown read-only is passed on unpaired, so it has no id
            if request.canRespond {
                #expect(request.toolUseId == toolUseId, sourceLocation: sourceLocation)
            }
            return (hook, request)
        }

        /// The `decision` object the hook printed for the agent.
        func decisionPrinted(by hook: ScriptRun, sourceLocation: SourceLocation = #_sourceLocation) async throws -> [String: Any] {
            let output = try await hook.finish()
            let object = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]
            let specific = object?["hookSpecificOutput"] as? [String: Any]
            return try #require(specific?["decision"] as? [String: Any], "hook printed: \(output)", sourceLocation: sourceLocation)
        }

        /// Compares JSON-shaped values (dictionaries, arrays, strings, numbers).
        func jsonEqual(_ lhs: Any?, _ rhs: Any) -> Bool {
            guard let lhs else { return false }
            return (lhs as AnyObject).isEqual(rhs)
        }

        @Test("Allow once reaches Claude Code")
        func claudeAllowOnce() async throws {
            let session = AgentSession("claude")
            let (hook, request) = try await ask(session)
            #expect(request.canRespond)
            #expect(request.toolName == "Bash")

            ApprovalActions.approve(sessionId: session.sessionId, toolUseId: request.toolUseId)

            let decision = try await decisionPrinted(by: hook)
            #expect(decision["behavior"] as? String == "allow")
            #expect(decision["updatedPermissions"] == nil)
            await session.waitForPhase(.processing)
        }

        @Test("Deny carries the reason to Claude Code")
        func claudeDeny() async throws {
            let session = AgentSession("claude")
            let (hook, request) = try await ask(session)

            ApprovalActions.deny(sessionId: session.sessionId, toolUseId: request.toolUseId, reason: "Not on main")

            let decision = try await decisionPrinted(by: hook)
            #expect(decision["behavior"] as? String == "deny")
            #expect(decision["message"] as? String == "Not on main")
            await session.waitForPhase(.processing)
        }

        @Test("Always saves the rule Claude Code suggested")
        func claudeAlways() async throws {
            let session = AgentSession("claude")
            let (hook, request) = try await ask(session)

            ApprovalActions.approve(sessionId: session.sessionId, toolUseId: request.toolUseId, always: true)

            let decision = try await decisionPrinted(by: hook)
            #expect(decision["behavior"] as? String == "allow")
            #expect(jsonEqual(decision["updatedPermissions"], Self.suggestions))
        }

        @Test("AskUserQuestion answers travel as updatedInput")
        func claudeQuestion() async throws {
            let session = AgentSession("claude")
            let questions: [[String: Any]] = [[
                "question": "Which database?",
                "header": "Database",
                "multiSelect": false,
                "options": [["label": "Postgres", "description": "Server"], ["label": "SQLite", "description": "File"]],
            ]]
            let (hook, request) = try await ask(
                session, tool: "AskUserQuestion", input: ["questions": questions], suggestions: nil)

            ApprovalActions.answer(sessionId: session.sessionId, toolUseId: request.toolUseId, answers: ["Which database?": "Postgres"])

            let decision = try await decisionPrinted(by: hook)
            #expect(decision["behavior"] as? String == "allow")
            let input = try #require(decision["updatedInput"] as? [String: Any])
            #expect(jsonEqual(input["answers"], ["Which database?": "Postgres"]))
            #expect(jsonEqual(input["questions"], questions))
        }

        @Test("Codex gets a bare decision, even for Always")
        func codexAlways() async throws {
            let session = AgentSession("codex")
            let (hook, request) = try await ask(session)
            #expect(request.canRespond)

            ApprovalActions.approve(sessionId: session.sessionId, toolUseId: request.toolUseId, always: true)

            let decision = try await decisionPrinted(by: hook)
            #expect(decision["behavior"] as? String == "allow")
            #expect(decision["updatedPermissions"] == nil)
            #expect(decision["updatedInput"] == nil)
        }

        @Test("An answer meant for another request is ignored")
        func staleAnswer() async throws {
            let session = AgentSession("claude")
            let (hook, request) = try await ask(session)

            ApprovalActions.approve(sessionId: session.sessionId, toolUseId: "toolu_stale")
            try await Pipeline.letSettle()
            #expect(await session.state?.activePermission?.toolUseId == request.toolUseId)

            ApprovalActions.deny(sessionId: session.sessionId, toolUseId: request.toolUseId)
            #expect(try await decisionPrinted(by: hook)["behavior"] as? String == "deny")
        }

        @Test("Stop answered in the terminal releases the waiting hook")
        func stopCancelsRequest() async throws {
            let session = AgentSession("claude")
            let (hook, _) = try await ask(session)

            try await session.send("Stop", ["last_assistant_message": "Done"])

            // No decision: Claude Code keeps its own answer
            #expect(try await hook.finish() == "")
            #expect(await session.state?.phase == .waitingForInput)
        }

        @Test("With approving from the notch off, requests are only shown")
        func approvalsOff() async throws {
            try await Pipeline.with(Pipeline.approveFromNotch, false) {
                let session = AgentSession("claude")
                let (hook, request) = try await ask(session)

                #expect(try await hook.finish(within: .seconds(3)) == "")
                #expect(!request.canRespond)
            }
        }

        @Test("Agents without an approval hook show requests read-only")
        func observeOnlyAgent() async throws {
            let session = AgentSession("gemini")
            let hook = try session.hook("Notification", [
                "notification_type": "ToolPermission",
                "message": "Allow shell command?",
                "details": ["toolName": "run_shell_command", "args": ["command": "rm -rf build"]],
            ])
            // Gemini's hook never waits for an answer
            #expect(try await hook.finish(within: .seconds(3)) == "{}")

            let state = await Pipeline.waitFor(session.sessionId) { $0?.activePermission != nil }
            let request = try #require(state?.activePermission)
            #expect(request.toolName == "run_shell_command")
            #expect(!request.canRespond)
        }

        @Test("A hook that died is noticed when answering")
        func hookDied() async throws {
            let session = AgentSession("claude")
            let (hook, request) = try await ask(session)

            hook.kill()
            try await hook.finish()
            ApprovalActions.approve(sessionId: session.sessionId, toolUseId: request.toolUseId)

            await session.waitForPhase(.idle)
        }
    }
}
