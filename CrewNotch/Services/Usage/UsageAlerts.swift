//
//  UsageAlerts.swift
//  CrewNotch
//
//  Tells you when a plan limit runs low and when it resets. Each limit's
//  last announced level is remembered, so an alert comes once per
//  crossing, not on every refresh or launch.
//

import Combine
import Foundation

@MainActor
final class UsageAlerts {
    static let shared = UsageAlerts()

    private enum Level: Int { case normal = 0, warning, critical }

    private struct Memory: Codable {
        var level: Int
        var resetsAt: Double?
    }

    private static let storageKey = "usageAlertMemory"
    private var memory: [String: Memory]
    private var cancellable: AnyCancellable?

    private init() {
        memory = (UserDefaults.standard.data(forKey: Self.storageKey))
            .flatMap { try? JSONDecoder().decode([String: Memory].self, from: $0) } ?? [:]
    }

    func start() {
        guard cancellable == nil else { return }
        cancellable = UsageMonitor.shared.$providers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.check($0) }
    }

    private func check(_ providers: [ProviderUsage]) {
        let warn = Double(AppSettings.usageWarnPercent)
        let critical = Double(max(AppSettings.usageCriticalPercent, AppSettings.usageWarnPercent + 1))
        var changed = false

        for provider in providers where provider.error == nil {
            for limit in provider.limits {
                let key = "\(provider.agent.rawValue).\(limit.label)"
                let level: Level = limit.usedPercent >= critical ? .critical : limit.usedPercent >= warn ? .warning : .normal
                let resetsAt = limit.resetsAt?.timeIntervalSince1970
                guard let previous = memory[key] else {
                    // First sighting: remember quietly
                    memory[key] = Memory(level: level.rawValue, resetsAt: resetsAt)
                    changed = true
                    continue
                }

                // A new window (resetsAt moved on) or usage well under the
                // threshold lowers the level; a dip by a point or two doesn't,
                // so a limit hovering at 80% doesn't announce itself again and again.
                let windowReset = previous.resetsAt != nil && resetsAt != nil && resetsAt! > previous.resetsAt! + 60
                let previousThreshold = previous.level >= Level.critical.rawValue ? critical : warn
                let wellBelow = limit.usedPercent < previousThreshold - 5
                var stored = previous.level
                if level.rawValue > previous.level {
                    announceLow(provider: provider, limit: limit, critical: level == .critical)
                    stored = level.rawValue
                } else if level.rawValue < previous.level && (windowReset || wellBelow) {
                    if level == .normal && (windowReset || limit.usedPercent < warn - 10) {
                        announceReset(provider: provider, limit: limit)
                    }
                    stored = level.rawValue
                }
                if previous.level != stored || previous.resetsAt != resetsAt {
                    memory[key] = Memory(level: stored, resetsAt: resetsAt)
                    changed = true
                }
            }
        }

        if changed, let data = try? JSONEncoder().encode(memory) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    // MARK: - Announcing

    private func announceLow(provider: ProviderUsage, limit: UsageLimit, critical: Bool) {
        let percent = Int(limit.usedPercent.rounded())
        let title = String(localized: "\(provider.agent.displayName) \(limit.displayLabel): \(percent)% used")
        var subtitle: String?
        if let resetsAt = limit.resetsAt {
            subtitle = String(localized: "Resets \(resetsAt.formatted(.relative(presentation: .named)))")
        }
        announce(NotchNotice(id: "low-\(provider.agent.rawValue)-\(limit.label)", agent: provider.agent, title: title,
                             subtitle: subtitle, tone: critical ? .critical : .warning),
                 playsSound: critical)
    }

    private func announceReset(provider: ProviderUsage, limit: UsageLimit) {
        guard AppSettings.usageResetAlerts else { return }
        let title = String(localized: "\(provider.agent.displayName) \(limit.displayLabel) limit reset")
        announce(NotchNotice(id: "reset-\(provider.agent.rawValue)-\(limit.label)", agent: provider.agent, title: title,
                             subtitle: String(localized: "Back to work."), tone: .info),
                 playsSound: false)
    }

    private func announce(_ notice: NotchNotice, playsSound: Bool) {
        guard AppSettings.usageAlerts else { return }
        if playsSound { AppSettings.play(AppSettings.attentionSound) }
        AppDelegate.shared?.windowController?.viewModel.showNotice(notice)
        AttentionCenter.shared.post(AttentionAlert(kind: .usage, title: notice.title, detail: notice.subtitle))
    }
}
