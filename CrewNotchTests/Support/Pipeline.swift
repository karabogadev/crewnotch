//
//  Pipeline.swift
//  CrewNotchTests
//
//  Runs the app's real event pipeline (HookSocketServer -> SessionStore via
//  SessionMonitor) on a private socket, and drives it with the hook scripts
//  shipped in the app bundle, exactly as an agent would.
//

import Foundation
import Testing
@testable import CrewNotch

/// Every end-to-end suite shares one socket server, one SessionStore and the
/// app's settings, so they run one test at a time.
@Suite(.serialized) struct EndToEnd {}

@MainActor
enum Pipeline {
    /// Short on purpose: AF_UNIX paths are limited to ~104 bytes.
    static let socketPath = NSTemporaryDirectory() + "crewnotch-e2e/s.sock"

    /// The folder every test session claims to work in.
    static let workspace: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("crewnotch-e2e-workspace")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// `AppSettings.Keys` is private, so its key is spelled out here.
    static let approveFromNotch = "approveFromNotch"

    /// The settings the pipeline reads, at the defaults the tests expect.
    static let baseline: [String: Any] = [
        approveFromNotch: true,
        FeatureKeys.showCommandSessions: true,
    ]

    private static var monitor: SessionMonitor?

    /// Starts the pipeline once per test run.
    static func start() async throws {
        if monitor == nil {
            // A socket left by the last run would pass for the server being up
            try? FileManager.default.removeItem(atPath: socketPath)
            applySettings(baseline)
            let monitor = SessionMonitor()
            monitor.startMonitoring(socketPath: socketPath)
            self.monitor = monitor
        }
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: socketPath) {
            guard clock.now < deadline else { throw PipelineError.serverDidNotStart }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Runs `body` with `key` overridden, then restores the baseline.
    static func with<T>(_ key: String, _ value: Any, _ body: () async throws -> T) async rethrows -> T {
        applySettings([key: value])
        defer { applySettings(baseline) }
        return try await body()
    }

    /// The test host shares the real app's defaults domain, so settings go in
    /// the argument domain: it wins over saved values and is never written to disk.
    private static func applySettings(_ values: [String: Any]) {
        var domain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        domain.merge(values) { $1 }
        UserDefaults.standard.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
    }

    /// Polls the store until `condition` holds; records an issue on timeout.
    @discardableResult
    static func waitFor(
        _ sessionId: String,
        timeout: Duration = .seconds(5),
        sourceLocation: SourceLocation = #_sourceLocation,
        until condition: (SessionState?) -> Bool
    ) async -> SessionState? {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        var state = await SessionStore.shared.session(for: sessionId)
        while !condition(state) {
            guard clock.now < deadline else {
                Issue.record("Timed out on session \(sessionId); phase: \(String(describing: state?.phase))", sourceLocation: sourceLocation)
                return state
            }
            try? await Task.sleep(for: .milliseconds(20))
            state = await SessionStore.shared.session(for: sessionId)
        }
        return state
    }

    static func endSession(_ sessionId: String) async {
        await SessionStore.shared.process(.sessionEnded(sessionId: sessionId))
    }

    /// Time for a message that should have been dropped to show up if it wasn't.
    /// The sender has already exited, so a few hundred ms is plenty.
    static func letSettle() async throws {
        try await Task.sleep(for: .milliseconds(300))
    }
}

enum PipelineError: Error {
    case serverDidNotStart
    case scriptTimedOut(String)
}
