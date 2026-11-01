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
    @AppStorage(UsagePreferences.orderKey) private var orderStorage = ""
    @State private var available: [AgentKind: Bool] = [:]
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
                        ProviderRow(agent: agent, usage: monitor.providers.first { $0.agent == agent },
                                    isAvailable: available[agent] ?? true, monitor: monitor)
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
                            orderStorage = ""; metricsStorage = ""
                        }
                        .buttonStyle(.link)
                    }
                } footer: {
                    Text("Turn on the providers you use. Drag to reorder, or open one to choose its metrics.")
                        .foregroundStyle(.secondary)
                }

            }
            .formStyle(.grouped)
            .task {
                // Checking for sign-ins runs tools (security, sqlite3), so do it off the main thread
                available = await Task.detached {
                    Dictionary(uniqueKeysWithValues: UsageSources.all.map { ($0.agent, $0.isAvailable()) })
                }.value
            }
        }
    }

    private var styleDescription: String {
        switch usageStyle {
        case .line: return String(localized: "One line per provider with the limit you pick. Hover for every limit.")
        case .bars: return String(localized: "Every metric of every provider as its own bar.")
        case .compact: return String(localized: "All providers on a single line, each with a ring and a percentage.")
        }
    }
}

private struct ProviderRow: View {
    let agent: AgentKind
    let usage: ProviderUsage?
    let isAvailable: Bool
    @ObservedObject var monitor: UsageMonitor

    private var metricCount: Int { UsagePreferences.metrics(for: agent, live: usage).count }
    private var isOn: Bool { monitor.isEnabled(agent) }

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
                    subtitle
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!isOn)
            Toggle("", isOn: Binding(get: { isOn }, set: { monitor.setEnabled(agent, $0) }))
                .labelsHidden()
                .disabled(!isAvailable && !isOn)
        }
        .opacity(isOn || isAvailable ? 1 : 0.5)
    }

    @ViewBuilder
    private var subtitle: some View {
        if !isAvailable && !isOn {
            Text("Not signed in on this Mac")
        } else if !isOn {
            Text(UsageSources.source(for: agent)?.accessNote ?? "")
        } else if let error = usage?.error, usage?.limits.isEmpty ?? true {
            Text(error).foregroundStyle(.orange)
        } else {
            HStack(spacing: 4) {
                Text("^[\(metricCount) metric](inflect: true)")
                if let plan = usage?.plan { Text("· \(plan)") }
            }
        }
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
                            Text(UsageLimit.displayName(metric))
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
        var text = percentMode == .used
            ? String(localized: "\(Int(value.rounded()))% used")
            : String(localized: "\(Int(value.rounded()))% left")
        if let reset = limit.resetsAt { text += " · \(UsageFormat.timeUntil(reset))" }
        return text
    }
}
