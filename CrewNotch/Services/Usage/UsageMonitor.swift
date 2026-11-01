//
//  UsageMonitor.swift
//  CrewNotch
//
//  Keeps provider plan usage fresh for the notch: Codex from local session
//  files every minute, Claude from its usage API every five minutes (only
//  once the user allows reading Claude Code's sign-in).
//

import Combine
import Foundation

@MainActor
final class UsageMonitor: ObservableObject {
    static let shared = UsageMonitor()

    @Published private(set) var providers: [ProviderUsage] = []

    private var codexTimer: Timer?
    private var claudeTimer: Timer?

    private init() {}

    func start() {
        guard codexTimer == nil else { return }
        refreshCodex()
        refreshClaude()
        codexTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in UsageMonitor.shared.refreshCodex() }
        }
        claudeTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { @MainActor in UsageMonitor.shared.refreshClaude() }
        }
    }

    /// Called when the user allows (or stops) reading Claude Code's sign-in.
    func setClaudeAllowed(_ allowed: Bool) {
        AppSettings.claudeUsageAllowed = allowed
        if allowed {
            refreshClaude()
        } else {
            providers.removeAll { $0.agent == .claude }
        }
    }

    private func refreshCodex() {
        guard AppSettings.showPlanUsage else { return }
        Task {
            let usage = await Task.detached { CodexUsageReader.read() }.value
            if let usage { update(usage) }
        }
    }

    private func refreshClaude() {
        guard AppSettings.showPlanUsage, AppSettings.claudeUsageAllowed else { return }
        Task {
            do {
                update(try await ClaudeUsageClient.fetch())
            } catch {
                // Keep the last good numbers; just surface why they're not updating.
                var usage = providers.first { $0.agent == .claude }
                    ?? ProviderUsage(agent: .claude, plan: nil, limits: [], updatedAt: Date())
                usage.error = error.localizedDescription
                update(usage)
            }
        }
    }

    private func update(_ usage: ProviderUsage) {
        if let index = providers.firstIndex(where: { $0.agent == usage.agent }) {
            providers[index] = usage
        } else {
            providers.append(usage)
            providers.sort { $0.agent.rawValue < $1.agent.rawValue }
        }
    }
}
