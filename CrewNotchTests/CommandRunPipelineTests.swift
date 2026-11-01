//
//  CommandRunPipelineTests.swift
//  CrewNotchTests
//
//  `crewnotch run` shows a command in the notch while it runs and reports
//  how it ended.
//

import Foundation
import Testing
@testable import CrewNotch

extension EndToEnd {
    @Suite("crewnotch run")
    struct CommandRun {
        /// One row per terminal: the CLI's parent (here, the test host) names the
        /// session, so every test here shares it and starts by clearing it.
        let sessionId = "command:\(getpid())"

        init() async throws {
            try await Pipeline.start()
            await Pipeline.endSession(sessionId)
        }

        func run(_ arguments: String...) throws -> ScriptRun {
            try ScriptRun(script: "crewnotch-cli", arguments: ["run"] + arguments)
        }

        @Test("Working while it runs, then finished with its exit code")
        func failingCommand() async throws {
            let cli = try run("--title", "Unit tests", "--", "/bin/sh", "-c", "sleep 1; exit 3")

            let running = await Pipeline.waitFor(sessionId) { $0?.phase == .processing }
            #expect(running?.agent == .command)
            #expect(running?.conversationInfo.summary == "Unit tests")
            #expect(running?.conversationInfo.firstUserMessage == "/bin/sh -c 'sleep 1; exit 3'")

            try await cli.finish()
            #expect(cli.exitCode == 3)

            let done = await Pipeline.waitFor(sessionId) { $0?.phase == .waitingForInput }
            #expect(done?.conversationInfo.lastMessageRole == "assistant")
            #expect(done?.conversationInfo.lastMessage?.contains("3") == true)
        }

        @Test("A command that can't start reports 127")
        func missingCommand() async throws {
            let cli = try run("--", "/nonexistent/crewnotch-e2e-tool")
            try await cli.finish()
            #expect(cli.exitCode == 127)

            let done = await Pipeline.waitFor(sessionId) { $0?.phase == .waitingForInput }
            #expect(done?.conversationInfo.lastMessage?.contains("127") == true)
        }

        @Test("Hidden when command sessions are turned off")
        func hiddenWhenOff() async throws {
            try await Pipeline.with(FeatureKeys.showCommandSessions, false) {
                let cli = try run("--", "/usr/bin/true")
                try await cli.finish()
                #expect(cli.exitCode == 0)
                try await Pipeline.letSettle()
                #expect(await SessionStore.shared.session(for: sessionId) == nil)
            }
        }
    }
}
