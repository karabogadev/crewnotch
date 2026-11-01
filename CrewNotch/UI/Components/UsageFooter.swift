//
//  UsageFooter.swift
//  CrewNotch
//
//  Plan usage at the bottom of the session list. The layout, the number
//  shown (used or left), the limit and the providers are all set in
//  Settings → Appearance. Hover any provider for every limit and reset time.
//

import SwiftUI

struct UsageFooter: View {
    @AppStorage(AppearanceKeys.textScale) private var textScale: TextScale = .standard
    @ObservedObject var monitor: UsageMonitor
    /// Whether any agent is working or waiting on you right now
    var isAnyAgentBusy: Bool

    @AppStorage("showPlanUsage") private var showPlanUsage = true
    @AppStorage("usageStyle") private var style: UsageStyle = .line
    @AppStorage("usageOnlyWhileWorking") private var onlyWhileWorking = false
    // Observed so the footer refreshes when Settings → Usage changes
    @AppStorage(UsagePreferences.hiddenProvidersKey) private var hiddenProviders = ""
    @AppStorage(UsagePreferences.hiddenMetricsKey) private var hiddenMetrics = ""
    @AppStorage(UsagePreferences.orderKey) private var providerOrder = ""
    @AppStorage("claudeUsageAllowed") private var claudeUsageAllowed = false

    private var visibleProviders: [ProviderUsage] {
        _ = (hiddenProviders, hiddenMetrics, providerOrder)
        // Providers with nothing to show (e.g. an expired sign-in) stay out of
        // the notch; Settings → Usage shows why.
        return UsagePreferences.apply(to: monitor.providers).filter { !$0.limits.isEmpty }
    }

    private var offerClaude: Bool {
        !claudeUsageAllowed && AppSettings.connectedAgents.contains(.claude)
    }

    private var isVisible: Bool {
        showPlanUsage && (!onlyWhileWorking || isAnyAgentBusy) && (!visibleProviders.isEmpty || offerClaude)
    }

    var body: some View {
        if isVisible {
            VStack(spacing: 4) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.bottom, 2)

                switch style {
                case .line:
                    ForEach(visibleProviders) { UsageLineRow(usage: $0) }
                case .bars:
                    ForEach(visibleProviders) { UsageBarsBlock(usage: $0) }
                case .compact:
                    UsageCompactRow(providers: visibleProviders)
                }

                if offerClaude {
                    HStack(spacing: 6) {
                        AgentIcon(agent: .claude, size: 12)
                        Text("Claude Code").foregroundColor(.white.opacity(0.6))
                        Spacer()
                        Button("Show usage") { monitor.setClaudeAllowed(true) }
                            .buttonStyle(.plain)
                            .foregroundColor(.white.opacity(0.8))
                            .help("Reads Claude Code's sign-in from the keychain. macOS asks once: choose Always Allow.")
                    }
                    .font(.system(size: 11 * textScale.factor, weight: .medium))
                    .padding(.horizontal, 10)
                }
            }
            .padding(.bottom, 6)
        }
    }
}

// MARK: - Shared formatting

private struct UsageNumbers {
    let mode: UsagePercentMode

    func shownPercent(_ limit: UsageLimit) -> Int {
        Int((mode == .used ? limit.usedPercent : 100 - limit.usedPercent).rounded())
    }

    /// Bars fill as usage grows, or drain like a battery when showing what's left.
    func barFraction(_ limit: UsageLimit) -> Double {
        (mode == .used ? limit.usedPercent : 100 - limit.usedPercent) / 100
    }

    func label(_ limit: UsageLimit) -> String {
        mode == .left ? String(localized: "\(shownPercent(limit))% left") : "\(shownPercent(limit))%"
    }
}

private func usageTooltip(_ usage: ProviderUsage, mode: UsagePercentMode) -> String {
    let numbers = UsageNumbers(mode: mode)
    var lines = usage.limits.map { limit in
        let percent = numbers.shownPercent(limit)
        var line = mode == .used
            ? String(localized: "\(limit.displayLabel): \(percent)% used")
            : String(localized: "\(limit.displayLabel): \(percent)% left")
        if let reset = limit.resetsAt, reset > Date() {
            line += String(localized: ", resets in \(UsageFormat.timeUntil(reset))")
        }
        return line
    }
    if let error = usage.error { lines.append(error) }
    lines.append(String(localized: "Updated \(usage.updatedAt.formatted(.relative(presentation: .named)))"))
    return lines.joined(separator: "\n")
}

// MARK: - Line

private struct UsageLineRow: View {
    @AppStorage(AppearanceKeys.textScale) private var textScale: TextScale = .standard
    let usage: ProviderUsage
    @AppStorage("usagePercentMode") private var mode: UsagePercentMode = .used
    @AppStorage("usageLimit") private var choice: UsageLimitChoice = .mostUsed

    var body: some View {
        let numbers = UsageNumbers(mode: mode)
        HStack(spacing: 6) {
            AgentIcon(agent: usage.agent, size: 12)
            Text(usage.agent.displayName).foregroundColor(.white.opacity(0.6))
            if let plan = usage.plan {
                Text(plan).foregroundColor(.white.opacity(0.3))
            }
            Spacer(minLength: 8)

            if let limit = usage.limit(for: choice) {
                if choice == .mostUsed {
                    Text(limit.displayLabel).foregroundColor(.white.opacity(0.3))
                }
                UsageBar(fraction: numbers.barFraction(limit), usedPercent: limit.usedPercent)
                    .frame(width: 56, height: 4)
                Text(numbers.label(limit))
                    .font(.system(size: 11 * textScale.factor, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.75))
                    .frame(minWidth: 32, alignment: .trailing)
                if let reset = limit.resetsAt, reset > Date() {
                    Text(UsageFormat.timeUntil(reset))
                        .foregroundColor(.white.opacity(0.3))
                        .frame(minWidth: 44, alignment: .trailing)
                }
            } else if let error = usage.error {
                Text(error).foregroundColor(.white.opacity(0.35)).lineLimit(1)
            }
        }
        .font(.system(size: 11 * textScale.factor, weight: .medium))
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .help(usageTooltip(usage, mode: mode))
    }
}

// MARK: - Bars

private struct UsageBarsBlock: View {
    @AppStorage(AppearanceKeys.textScale) private var textScale: TextScale = .standard
    let usage: ProviderUsage
    @AppStorage("usagePercentMode") private var mode: UsagePercentMode = .used

    var body: some View {
        let numbers = UsageNumbers(mode: mode)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                AgentIcon(agent: usage.agent, size: 12)
                Text(usage.agent.displayName).foregroundColor(.white.opacity(0.7))
                if let plan = usage.plan {
                    Text(plan).foregroundColor(.white.opacity(0.3))
                }
                Spacer()
                if let error = usage.error, usage.limits.isEmpty {
                    Text(error).foregroundColor(.white.opacity(0.35)).lineLimit(1)
                }
            }
            ForEach(usage.limits) { limit in
                HStack(spacing: 8) {
                    Text(limit.displayLabel)
                        .foregroundColor(.white.opacity(0.45))
                        .frame(width: 74, alignment: .leading)
                    UsageBar(fraction: numbers.barFraction(limit), usedPercent: limit.usedPercent)
                        .frame(height: 4)
                    Text(numbers.label(limit))
                        .font(.system(size: 10 * textScale.factor, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(minWidth: 56, alignment: .trailing)
                    Text(limit.resetsAt.flatMap { $0 > Date() ? UsageFormat.timeUntil($0) : nil } ?? "")
                        .foregroundColor(.white.opacity(0.3))
                        .frame(width: 44, alignment: .trailing)
                }
                .font(.system(size: 10 * textScale.factor, weight: .medium))
            }
        }
        .font(.system(size: 11 * textScale.factor, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .help(usageTooltip(usage, mode: mode))
    }
}

// MARK: - Compact

private struct UsageCompactRow: View {
    @AppStorage(AppearanceKeys.textScale) private var textScale: TextScale = .standard
    let providers: [ProviderUsage]
    @AppStorage("usagePercentMode") private var mode: UsagePercentMode = .used
    @AppStorage("usageLimit") private var choice: UsageLimitChoice = .mostUsed

    var body: some View {
        let numbers = UsageNumbers(mode: mode)
        HStack(spacing: 14) {
            ForEach(providers) { usage in
                HStack(spacing: 5) {
                    AgentIcon(agent: usage.agent, size: 12)
                    if let limit = usage.limit(for: choice) {
                        UsageRing(fraction: numbers.barFraction(limit), usedPercent: limit.usedPercent)
                            .frame(width: 11, height: 11)
                        Text(numbers.label(limit))
                            .font(.system(size: 11 * textScale.factor, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.75))
                    } else {
                        Text("–").foregroundColor(.white.opacity(0.35))
                    }
                }
                .help(usageTooltip(usage, mode: mode))
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11 * textScale.factor, weight: .medium))
        .padding(.horizontal, 10)
    }
}

// MARK: - Meters

private func usageColor(_ usedPercent: Double) -> Color {
    switch usedPercent {
    case ..<70: return .white.opacity(0.75)
    case ..<90: return TerminalColors.amber
    default: return Color(red: 0.95, green: 0.35, blue: 0.3)
    }
}

private struct UsageBar: View {
    let fraction: Double
    let usedPercent: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(usageColor(usedPercent))
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
    }
}

private struct UsageRing: View {
    let fraction: Double
    let usedPercent: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 2)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(usageColor(usedPercent), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
