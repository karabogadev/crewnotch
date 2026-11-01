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
    @AppStorage(UsagePreferences.hiddenMetricsKey) private var hiddenMetrics = ""
    @AppStorage(UsagePreferences.orderKey) private var providerOrder = ""

    private var visibleProviders: [ProviderUsage] {
        _ = (hiddenMetrics, providerOrder)
        // Providers with nothing to show (e.g. an expired sign-in) stay out of
        // the notch; Settings → Usage shows why.
        return UsagePreferences.apply(to: monitor.providers).filter { !$0.limits.isEmpty }
    }

    private var isVisible: Bool {
        showPlanUsage && (!onlyWhileWorking || isAnyAgentBusy) && !visibleProviders.isEmpty
    }

    var body: some View {
        if isVisible {
            VStack(spacing: 9) {
                switch style {
                case .line:
                    ForEach(visibleProviders) { UsageLineRow(usage: $0) }
                case .bars:
                    ForEach(visibleProviders) { UsageBarsBlock(usage: $0) }
                case .compact:
                    UsageCompactRow(providers: visibleProviders)
                }

            }
            .padding(.top, 12)
            .padding(.bottom, 6)
            .overlay(alignment: .top) { Hairline() }
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
        if let pace = limit.pace() {
            line += pace.runsOutAt.map { String(localized: " · at this pace it runs out in \(UsageFormat.timeUntil($0))") }
                ?? String(localized: " · at this pace ~\(Int(pace.projectedPercent.rounded()))% by the reset")
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
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                AgentIcon(agent: usage.agent, size: 11)
                Text(usage.agent.displayName)
                    .foregroundColor(.ink.opacity(0.6))
                    .lineLimit(1)
                if let limit = usage.limit(for: choice) {
                    Text(limit.displayLabel).foregroundColor(.ink.opacity(0.45))
                }
            }
            .font(.system(size: 10 * textScale.factor, weight: .medium, design: .monospaced))
            .textCase(.uppercase)
            .kerning(0.4)
            .frame(width: 150 * textScale.factor, alignment: .leading)

            if let limit = usage.limit(for: choice) {
                UsageMeter(limit: limit, mode: mode)
                    .frame(height: 9)
                Text(numbers.label(limit))
                    .font(.system(size: 11 * textScale.factor, weight: .medium, design: .monospaced))
                    .foregroundColor(.ink.opacity(0.85))
                    .frame(minWidth: 34, alignment: .trailing)
                UsageOutlook(limit: limit)
                    .frame(minWidth: 52 * textScale.factor, alignment: .trailing)
            } else {
                Spacer(minLength: 0)
                if let error = usage.error {
                    Text(error).foregroundColor(.ink.opacity(0.45)).lineLimit(1)
                }
            }
        }
        .font(.system(size: 11 * textScale.factor, weight: .medium))
        .padding(.horizontal, 8)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                AgentIcon(agent: usage.agent, size: 11)
                Group {
                    Text(usage.agent.displayName).foregroundColor(.ink.opacity(0.7))
                    if let plan = usage.plan {
                        Text(plan).foregroundColor(.ink.opacity(0.45))
                    }
                }
                .font(.system(size: 10 * textScale.factor, weight: .medium, design: .monospaced))
                .textCase(.uppercase)
                .kerning(0.4)
                Spacer()
                if let error = usage.error, usage.limits.isEmpty {
                    Text(error).foregroundColor(.ink.opacity(0.45)).lineLimit(1)
                }
            }
            ForEach(usage.limits) { limit in
                HStack(spacing: 10) {
                    Text(limit.displayLabel)
                        .font(.system(size: 10 * textScale.factor, design: .monospaced))
                        .foregroundColor(.ink.opacity(0.5))
                        .lineLimit(1)
                        .frame(width: 74 * textScale.factor, alignment: .leading)
                    UsageMeter(limit: limit, mode: mode)
                        .frame(height: 8)
                    Text(numbers.label(limit))
                        .font(.system(size: 10 * textScale.factor, weight: .medium, design: .monospaced))
                        .foregroundColor(.ink.opacity(0.8))
                        .frame(minWidth: 56, alignment: .trailing)
                    UsageOutlook(limit: limit)
                        .frame(minWidth: 52 * textScale.factor, alignment: .trailing)
                }
                .font(.system(size: 10 * textScale.factor, weight: .medium))
            }
        }
        .font(.system(size: 11 * textScale.factor, weight: .medium))
        .padding(.horizontal, 8)
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
                            .foregroundColor(.ink.opacity(0.75))
                    } else {
                        Text("–").foregroundColor(.ink.opacity(0.35))
                    }
                }
                .help(usageTooltip(usage, mode: mode))
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11 * textScale.factor, weight: .medium))
        .padding(.horizontal, 8)
    }
}

// MARK: - Meters

private func usageColor(_ usedPercent: Double) -> Color {
    switch usedPercent {
    case ..<70: return .ink.opacity(0.82)
    case ..<90: return TerminalColors.amber
    default: return TerminalColors.red
    }
}

/// A row of ticks: what is used, a fainter run for where the pace leads by
/// the reset, then what is left. Drains instead when showing what's left.
private struct UsageMeter: View {
    let limit: UsageLimit
    let mode: UsagePercentMode

    var body: some View {
        let used = min(max(limit.usedPercent, 0), 100) / 100
        let projected = min(max(limit.pace()?.projectedPercent ?? 0, limit.usedPercent), 100) / 100
        // Used: solid up to now, faint up to the projection. Left: the faint run is what the pace will eat.
        let solidEnd = mode == .used ? used : 1 - projected
        let paceEnd = mode == .used ? projected : 1 - used
        let color = usageColor(limit.usedPercent)
        Canvas { context, size in
            let tick: CGFloat = 3, gap: CGFloat = 2
            let count = max(2, Int((size.width + gap) / (tick + gap)))
            let step = (size.width - tick) / CGFloat(count - 1)
            for index in 0..<count {
                let position = (Double(index) + 0.5) / Double(count)
                let fill = position <= solidEnd ? color : position <= paceEnd ? color.opacity(0.32) : Color.ink.opacity(0.1)
                let rect = CGRect(x: CGFloat(index) * step, y: 0, width: tick, height: size.height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(fill))
            }
        }
    }
}

/// The reset countdown, or when the limit runs out first at the current pace.
private struct UsageOutlook: View {
    let limit: UsageLimit
    @AppStorage(AppearanceKeys.textScale) private var textScale: TextScale = .standard

    var body: some View {
        Group {
            if let runsOut = limit.pace()?.runsOutAt {
                Text("out in \(UsageFormat.timeUntil(runsOut))")
                    .foregroundColor(limit.usedPercent >= 90 ? TerminalColors.red : TerminalColors.amber)
            } else if let reset = limit.resetsAt, reset > Date() {
                Text(UsageFormat.timeUntil(reset)).foregroundColor(.ink.opacity(0.5))
            } else {
                Text("")
            }
        }
        .font(.system(size: 10.5 * textScale.factor, design: .monospaced))
        .lineLimit(1)
    }
}

private struct UsageRing: View {
    let fraction: Double
    let usedPercent: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.ink.opacity(0.15), lineWidth: 2)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(usageColor(usedPercent), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// The thin rule between sections of the panel.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Color.ink.opacity(0.08)).frame(height: 1)
    }
}
