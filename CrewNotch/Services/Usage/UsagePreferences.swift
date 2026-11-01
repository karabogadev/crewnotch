//
//  UsagePreferences.swift
//  CrewNotch
//
//  Which providers and metrics the usage footer shows, and in what order.
//  Edited in Settings → Usage.
//

import Foundation

nonisolated enum UsagePreferences {
    /// Providers that have a usage source
    static var providers: [AgentKind] { UsageSources.all.map(\.agent) }

    private static let defaults = UserDefaults.standard
    static let orderKey = "usageProviderOrder"
    static let hiddenMetricsKey = "hiddenUsageMetrics"

    // MARK: Order

    static var order: [AgentKind] {
        get {
            let saved = (defaults.string(forKey: orderKey) ?? "").split(separator: ",").compactMap { AgentKind(rawValue: String($0)) }
            return saved.filter(providers.contains) + providers.filter { !saved.contains($0) }
        }
        set { defaults.set(newValue.map(\.rawValue).joined(separator: ","), forKey: orderKey) }
    }

    // MARK: Visibility

    static func isMetricShown(_ metric: String, of agent: AgentKind) -> Bool {
        !set(for: hiddenMetricsKey).contains("\(agent.rawValue).\(metric)")
    }

    static func setMetric(_ metric: String, of agent: AgentKind, shown: Bool) {
        update(hiddenMetricsKey, "\(agent.rawValue).\(metric)", hidden: !shown)
    }

    /// Restores every metric and the default order.
    static func reset() {
        [orderKey, hiddenMetricsKey].forEach(defaults.removeObject(forKey:))
    }

    // MARK: Metrics

    /// Metrics a provider can report: the known ones plus any it has sent.
    static func metrics(for agent: AgentKind, live: ProviderUsage?) -> [String] {
        let known: [String]
        switch agent {
        case .claude: known = ["Session", "Weekly", "Sonnet", "Extra usage"]
        case .codex: known = ["Session", "Weekly"]
        case .antigravity: known = []  // one metric per model the account offers
        case .cursor: known = ["Total usage", "Auto usage", "API usage"]
        case .copilot: known = ["Premium requests", "Chat", "Completions"]
        case .grok: known = ["Weekly"]
        case .opencode: known = ["Session", "Weekly", "Monthly"]
        case .kiro: known = ["Credits"]
        default: known = []
        }
        let extra = (live?.limits.map(\.label) ?? []).filter { !known.contains($0) }
        return known + extra
    }

    /// Turned-on providers in the user's order, each with only its visible metrics.
    static func apply(to providers: [ProviderUsage]) -> [ProviderUsage] {
        order.compactMap { agent in
            guard var usage = providers.first(where: { $0.agent == agent }) else { return nil }
            usage.limits = usage.limits.filter { isMetricShown($0.label, of: agent) }
            return usage
        }
    }

    // MARK: Storage

    private static func set(for key: String) -> Set<String> {
        Set((defaults.string(forKey: key) ?? "").split(separator: ",").map(String.init))
    }

    private static func update(_ key: String, _ value: String, hidden: Bool) {
        var values = set(for: key)
        if hidden { values.insert(value) } else { values.remove(value) }
        defaults.set(values.sorted().joined(separator: ","), forKey: key)
    }
}
