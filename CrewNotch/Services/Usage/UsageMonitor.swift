//
//  UsageMonitor.swift
//  CrewNotch
//
//  Keeps plan usage fresh for every provider the user turned on in
//  Settings → Usage. Each source refreshes on its own interval; a failure
//  keeps the last good numbers and records why.
//

import Combine
import Foundation

@MainActor
final class UsageMonitor: ObservableObject {
    static let shared = UsageMonitor()

    @Published private(set) var providers: [ProviderUsage] = []
    @Published private(set) var enabled: Set<AgentKind> = UsageMonitor.loadEnabled()

    private var lastFetch: [AgentKind: Date] = [:]
    private var inFlight: Set<AgentKind> = []
    private var timer: Timer?

    private static let enabledKey = "usageEnabledProviders"

    private init() {}

    func start() {
        guard timer == nil else { return }
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in UsageMonitor.shared.tick() }
        }
    }

    func isEnabled(_ agent: AgentKind) -> Bool { enabled.contains(agent) }

    /// Turning a provider on is the user's consent to read its sign-in.
    func setEnabled(_ agent: AgentKind, _ on: Bool) {
        if on { enabled.insert(agent) } else { enabled.remove(agent) }
        UserDefaults.standard.set(enabled.map(\.rawValue).sorted(), forKey: Self.enabledKey)
        if on {
            refresh(agent)
        } else {
            providers.removeAll { $0.agent == agent }
            lastFetch[agent] = nil
        }
    }

    /// Kept for the onboarding and footer shortcuts.
    func setClaudeAllowed(_ allowed: Bool) {
        AppSettings.claudeUsageAllowed = allowed
        setEnabled(.claude, allowed)
    }

    func refresh(_ agent: AgentKind) {
        guard AppSettings.showPlanUsage, enabled.contains(agent), !inFlight.contains(agent),
              let source = UsageSources.source(for: agent) else { return }
        inFlight.insert(agent)
        lastFetch[agent] = Date()
        Task {
            defer { inFlight.remove(agent) }
            do {
                update(try await source.fetch())
            } catch {
                var usage = providers.first { $0.agent == agent }
                    ?? ProviderUsage(agent: agent, plan: nil, limits: [], updatedAt: Date())
                usage.error = error.localizedDescription
                update(usage)
            }
        }
    }

    private func tick() {
        let now = Date()
        for source in UsageSources.all where enabled.contains(source.agent) {
            let due = lastFetch[source.agent].map { now.timeIntervalSince($0) >= source.refreshInterval } ?? true
            if due { refresh(source.agent) }
        }
    }

    private func update(_ usage: ProviderUsage) {
        guard enabled.contains(usage.agent) else { return }
        if let index = providers.firstIndex(where: { $0.agent == usage.agent }) {
            providers[index] = usage
        } else {
            providers.append(usage)
        }
    }

    /// Only Codex (local files, no prompt) is on by default. Providers that read
    /// a keychain sign-in stay off until the user turns them on.
    private static func loadEnabled() -> Set<AgentKind> {
        if let saved = UserDefaults.standard.array(forKey: enabledKey) as? [String] {
            return Set(saved.compactMap(AgentKind.init(rawValue:)))
        }
        return [.codex]
    }
}
