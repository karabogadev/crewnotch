//
//  UsagePane.swift
//  CrewNotch
//
//  Settings → Usage: how plan usage looks, which providers appear in which
//  order, and which metrics each provider shows.
//

import SwiftUI

struct UsagePane: View {
    @ObservedObject private var monitor = UsageMonitor.shared
    @AppStorage("showPlanUsage") private var showPlanUsage = true
    @AppStorage("usageStyle") private var usageStyle: UsageStyle = .line
    @AppStorage("usagePercentMode") private var percentMode: UsagePercentMode = .used
    @AppStorage("usageLimit") private var usageLimit: UsageLimitChoice = .mostUsed
    @AppStorage("usageOnlyWhileWorking") private var onlyWhileWorking = false
    @AppStorage("claudeUsageAllowed") private var claudeUsageAllowed = false
    @AppStorage(UsagePreferences.orderKey) private var orderStorage = ""
    @AppStorage(UsagePreferences.hiddenProvidersKey) private var hiddenStorage = ""
    @AppStorage(UsagePreferences.hiddenMetricsKey) private var metricsStorage = ""

    private var order: [AgentKind] {
        _ = orderStorage
        return UsagePreferences.order
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Show plan usage", isOn: $showPlanUsage)
                    Picker("Style", selection: $usageStyle) {
                        ForEach(UsageStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Percent shows", selection: $percentMode) {
                        ForEach(UsagePercentMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Limit to show", selection: $usageLimit) {
                        ForEach(UsageLimitChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .disabled(usageStyle == .bars)
                    Toggle("Only while an agent is working", isOn: $onlyWhileWorking)
                } header: {
                    Text("In the notch")
                } footer: {
                    Text(styleDescription).foregroundStyle(.secondary)
                }

                Section {
                    ForEach(order) { agent in
                        ProviderRow(agent: agent, usage: monitor.providers.first { $0.agent == agent }, hiddenStorage: $hiddenStorage)
                    }
                    .onMove { source, destination in
                        var reordered = order
                        reordered.move(fromOffsets: source, toOffset: destination)
                        UsagePreferences.order = reordered
                        orderStorage = UserDefaults.standard.string(forKey: UsagePreferences.orderKey) ?? ""
                    }
                } header: {
                    HStack {
                        Text("Providers")
                        Spacer()
                        Button("Reset") {
                            UsagePreferences.reset()
                            orderStorage = ""; hiddenStorage = ""; metricsStorage = ""
                        }
                        .buttonStyle(.link)
                    }
                } footer: {
                    Text("Drag to reorder. Turn a provider off to hide it, or open it to choose its metrics.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { claudeUsageAllowed },
                        set: { UsageMonitor.shared.setClaudeAllowed($0); claudeUsageAllowed = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Read Claude usage")
                            Text("Uses Claude Code's sign-in from the keychain. macOS asks once: choose Always Allow.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Access")
                } footer: {
                    Text("Codex usage comes from its local session files. Nothing leaves your Mac except Claude's own usage request to Anthropic.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }

    private var styleDescription: String {
        switch usageStyle {
        case .line: return "One line per provider with the limit you pick. Hover for every limit."
        case .bars: return "Every metric of every provider as its own bar."
        case .compact: return "All providers on a single line, each with a ring and a percentage."
        }
    }
}

private struct ProviderRow: View {
    let agent: AgentKind
    let usage: ProviderUsage?
    @Binding var hiddenStorage: String

    private var metricCount: Int { UsagePreferences.metrics(for: agent, live: usage).count }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
            AgentIcon(agent: agent, size: 20)
            NavigationLink {
                ProviderMetricsView(agent: agent, usage: usage)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.displayName)
                    Text("\(metricCount) metrics" + (usage?.plan.map { " · \($0)" } ?? ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle("", isOn: Binding(
                get: { _ = hiddenStorage; return UsagePreferences.isProviderShown(agent) },
                set: {
                    UsagePreferences.setProvider(agent, shown: $0)
                    hiddenStorage = UserDefaults.standard.string(forKey: UsagePreferences.hiddenProvidersKey) ?? ""
                }
            ))
            .labelsHidden()
        }
        .opacity(UsagePreferences.isProviderShown(agent) ? 1 : 0.55)
    }
}

private struct ProviderMetricsView: View {
    let agent: AgentKind
    let usage: ProviderUsage?
    @AppStorage(UsagePreferences.hiddenMetricsKey) private var metricsStorage = ""
    @AppStorage("usagePercentMode") private var percentMode: UsagePercentMode = .used

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    AgentIcon(agent: agent, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(agent.displayName).font(.title2.bold())
                        Text(usage?.plan ?? (usage == nil ? "No usage data yet" : "Plan usage"))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Metrics") {
                ForEach(UsagePreferences.metrics(for: agent, live: usage), id: \.self) { metric in
                    Toggle(isOn: Binding(
                        get: { _ = metricsStorage; return UsagePreferences.isMetricShown(metric, of: agent) },
                        set: {
                            UsagePreferences.setMetric(metric, of: agent, shown: $0)
                            metricsStorage = UserDefaults.standard.string(forKey: UsagePreferences.hiddenMetricsKey) ?? ""
                        }
                    )) {
                        HStack {
                            Text(metric)
                            Spacer()
                            Text(currentValue(of: metric)).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }

            if let error = usage?.error {
                Section("Status") {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(agent.displayName)
    }

    private func currentValue(of metric: String) -> String {
        guard let limit = usage?.limits.first(where: { $0.label == metric }) else { return "–" }
        let value = percentMode == .used ? limit.usedPercent : 100 - limit.usedPercent
        var text = "\(Int(value.rounded()))% \(percentMode.rawValue)"
        if let reset = limit.resetsAt { text += " · \(UsageFormat.timeUntil(reset))" }
        return text
    }
}
