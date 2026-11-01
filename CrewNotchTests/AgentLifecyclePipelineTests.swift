//
//  AgentLifecyclePipelineTests.swift
//  CrewNotchTests
//
//  Each hook agent sends a whole turn in its own event names and payload
//  shapes: prompt, tool call, tool result, stop, end. The notch must follow.
//

import Foundation
import Testing
@testable import CrewNotch

/// One agent's turn, as its hooks would report it.
struct AgentTurn: Sendable, CustomTestStringConvertible {
    typealias Fields = [String: any Sendable]

    struct Step: Sendable {
        let event: String
        var fields: Fields = [:]
    }

    let agent: String
    var idKey = "session_id"
    let prompt: Step
    let tool: Step
    let toolDone: Step
    /// What the notch shows as the last tool; nil when the agent reports no tool start.
    let toolName: String?
    let stop: Step
    /// Whether `stop` carries the agent's reply ("Done").
    var stopsWithReply = true
    /// Nil for agents with no session-end hook.
    var end: String? = "SessionEnd"

    var testDescription: String { agent }

    static let promptText = "Add pagination to the orders list"

    static let all: [AgentTurn] = {
        let prompt: Fields = ["prompt": promptText]
        func shell(_ name: String, id: String? = nil) -> Fields {
            var fields: Fields = ["tool_name": name, "tool_input": ["command": "ls"]]
            fields["tool_use_id"] = id
            return fields
        }
        return [
            AgentTurn(
                agent: "claude",
                prompt: Step(event: "UserPromptSubmit", fields: prompt),
                tool: Step(event: "PreToolUse", fields: shell("Bash", id: "toolu_1")),
                toolDone: Step(event: "PostToolUse", fields: shell("Bash", id: "toolu_1")),
                toolName: "Bash",
                stop: Step(event: "Stop", fields: ["last_assistant_message": "Done"])),
            AgentTurn(
                agent: "codex",
                prompt: Step(event: "UserPromptSubmit", fields: prompt),
                tool: Step(event: "PreToolUse", fields: shell("shell", id: "call_1")),
                toolDone: Step(event: "PostToolUse", fields: shell("shell", id: "call_1")),
                toolName: "shell",
                stop: Step(event: "Stop", fields: ["last_assistant_message": "Done"])),
            AgentTurn(
                agent: "gemini",
                prompt: Step(event: "BeforeAgent", fields: prompt),
                tool: Step(event: "BeforeTool", fields: shell("run_shell_command")),
                toolDone: Step(event: "AfterTool", fields: shell("run_shell_command")),
                toolName: "run_shell_command",
                stop: Step(event: "AfterAgent", fields: ["prompt_response": "Done"])),
            AgentTurn(
                agent: "cursor", idKey: "conversation_id",
                prompt: Step(event: "beforeSubmitPrompt", fields: prompt),
                tool: Step(event: "preToolUse", fields: shell("Shell", id: "t1")),
                toolDone: Step(event: "postToolUse", fields: shell("Shell", id: "t1")),
                toolName: "Shell",
                stop: Step(event: "stop", fields: ["status": "completed"]),
                stopsWithReply: false,
                end: "sessionEnd"),
            AgentTurn(
                agent: "copilot", idKey: "sessionId",
                prompt: Step(event: "userPromptSubmitted", fields: prompt),
                // Copilot sends tool arguments as a JSON string
                tool: Step(event: "preToolUse", fields: ["toolName": "bash", "toolArgs": #"{"command":"ls"}"#]),
                toolDone: Step(event: "postToolUse", fields: ["toolName": "bash", "toolArgs": #"{"command":"ls"}"#]),
                toolName: "bash",
                stop: Step(event: "agentStop"),
                stopsWithReply: false,
                end: "sessionEnd"),
            AgentTurn(
                agent: "grok",
                prompt: Step(event: "UserPromptSubmit", fields: prompt),
                tool: Step(event: "PreToolUse", fields: shell("bash", id: "g1")),
                toolDone: Step(event: "PostToolUse", fields: shell("bash", id: "g1")),
                toolName: "bash",
                stop: Step(event: "Stop", fields: ["lastAssistantMessage": "Done"])),
            AgentTurn(
                agent: "kiro",
                prompt: Step(event: "userPromptSubmit", fields: prompt),
                tool: Step(event: "preToolUse", fields: shell("execute_bash")),
                toolDone: Step(event: "postToolUse", fields: shell("execute_bash")),
                toolName: "execute_bash",
                stop: Step(event: "stop", fields: ["assistant_response": "Done"])),
            AgentTurn(
                agent: "antigravity", idKey: "conversationId",
                prompt: Step(event: "PreInvocation", fields: ["invocationNum": 1, "lastUserInput": promptText]),
                // Later model calls in the same turn read as tool progress
                tool: Step(event: "PreInvocation", fields: ["invocationNum": 2]),
                toolDone: Step(event: "PostToolUse", fields: ["toolCall": ["name": "run_command", "args": ["CommandLine": "ls"]]]),
                toolName: nil,
                stop: Step(event: "Stop", fields: ["terminationReason": "COMPLETED"]),
                stopsWithReply: false,
                end: nil),
        ]
    }()
}

extension EndToEnd {
    @Suite("Agent lifecycle")
    struct AgentLifecycle {
        init() async throws { try await Pipeline.start() }

        @Test("A whole turn moves the session through its phases", arguments: AgentTurn.all)
        func turn(_ turn: AgentTurn) async throws {
            let session = AgentSession(turn.agent, idKey: turn.idKey)
            func send(_ step: AgentTurn.Step) async throws -> SessionState {
                try #require(try await session.send(step.event, step.fields))
            }

            let started = try await send(turn.prompt)
            #expect(started.sessionId == session.sessionId)
            #expect(started.agent.rawValue == turn.agent)
            #expect(started.phase == .processing)
            #expect(started.cwd == Pipeline.workspace.path)
            #expect(started.turnStartedAt != nil)

            let working = try await send(turn.tool)
            #expect(working.phase == .processing)
            #expect(try await send(turn.toolDone).phase == .processing)
            let done = try await send(turn.stop)
            #expect(done.phase == .waitingForInput)

            if started.agent.hasClaudeTranscript {
                // Claude's chat comes from its transcript; the hooks place the tool call
                #expect(working.chatItems.contains { $0.id == "toolu_1" })
            } else {
                // Everyone else's chat is built from the hook payloads
                #expect(started.conversationInfo.firstUserMessage == AgentTurn.promptText)
                if let toolName = turn.toolName {
                    #expect(working.conversationInfo.lastToolName == toolName)
                    #expect(working.conversationInfo.lastMessage == "ls")
                }
                if turn.stopsWithReply {
                    #expect(done.conversationInfo.lastMessage == "Done")
                    #expect(done.conversationInfo.lastMessageRole == "assistant")
                }
            }

            if let end = turn.end {
                try await session.end(end)
            } else {
                await Pipeline.endSession(session.sessionId)
            }
        }

        @Test("Background work after a turn leaves the session done")
        func backgroundEventsKeepPhase() async throws {
            let session = AgentSession("claude")
            try await session.send("UserPromptSubmit", ["prompt": "Summarize"])
            try await session.send("Stop")

            // Claude Code's recap agent and idle compaction fire after Stop
            #expect(try await session.send("SubagentStart")?.phase == .waitingForInput)
            #expect(try await session.send("PreCompact")?.phase == .waitingForInput)
            #expect(try await session.send("PostCompact")?.phase == .waitingForInput)
            try await session.end()
        }

        @Test("Compacting mid-turn shows, then the turn carries on")
        func compactingMidTurn() async throws {
            let session = AgentSession("claude")
            try await session.send("UserPromptSubmit", ["prompt": "Refactor"])
            #expect(try await session.send("PreCompact")?.phase == .compacting)
            #expect(try await session.send("UserPromptSubmit", ["prompt": "Continue"])?.phase == .processing)
            try await session.end()
        }

        @Test("The same id from two agents gives two sessions")
        func namespacedIds() async throws {
            let claude = AgentSession("claude")
            let codex = AgentSession("codex", rawId: claude.rawId)

            #expect(try await claude.send("UserPromptSubmit", ["prompt": "One"])?.agent == .claude)
            #expect(try await codex.send("UserPromptSubmit", ["prompt": "Two"])?.agent == .codex)
            #expect(codex.sessionId == "codex:\(claude.rawId)")
            #expect(await claude.state?.agent == .claude)

            try await claude.end()
            try await codex.end()
        }

        @Test("Cursor's copies of Claude hooks are dropped")
        func replayedHooksDropped() async throws {
            // Cursor also runs hooks registered for Claude Code; its payload gives it away
            let session = AgentSession("claude")
            let hook = try session.hook("UserPromptSubmit", ["prompt": "Hi", "cursor_version": "2.0"])
            #expect(try await hook.finish() == "")
            try await Pipeline.letSettle()
            #expect(await session.state == nil)
        }
    }
}
