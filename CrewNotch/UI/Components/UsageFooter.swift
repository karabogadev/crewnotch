//
//  UsageFooter.swift
//  CrewNotch
//
//  Plan usage at the bottom of the session list: one line per provider
//  with its most-used limit. Hover for every limit and reset time.
//

import SwiftUI

struct UsageFooter: View {
    @ObservedObject var monitor: UsageMonitor

    private var offerClaude: Bool {
        !AppSettings.claudeUsageAllowed && AppSettings.connectedAgents.contains(.claude)
    }

    var body: some View {
        if AppSettings.showPlanUsage && (!monitor.providers.isEmpty || offerClaude) {
            VStack(spacing: 4) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.bottom, 2)

                ForEach(monitor.providers) { usage in
                    UsageRow(usage: usage)
                }

                if offerClaude {
                    HStack(spacing: 6) {
                        AgentIcon(agent: .claude, size: 12)
                        Text("Claude Code")
                            .foregroundColor(.white.opacity(0.6))
                        Spacer()
                        Button("Show usage") {
                            monitor.setClaudeAllowed(true)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white.opacity(0.8))
                        .help("Reads Claude Code's sign-in from the keychain. macOS asks once: choose Always Allow.")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                }
            }
            .padding(.bottom, 6)
        }
    }
}

private struct UsageRow: View {
    let usage: ProviderUsage

    private var tooltip: String {
        var lines = usage.limits.map { limit in
            var line = "\(limit.label): \(Int(limit.usedPercent.rounded()))% used"
            if let reset = limit.resetsAt { line += ", resets in \(UsageFormat.timeUntil(reset))" }
            return line
        }
        if let error = usage.error { lines.append(error) }
        lines.append("Updated \(usage.updatedAt.formatted(.relative(presentation: .named)))")
        return lines.joined(separator: "\n")
    }

    var body: some View {
        HStack(spacing: 6) {
            AgentIcon(agent: usage.agent, size: 12)
            Text(usage.agent.displayName)
                .foregroundColor(.white.opacity(0.6))
            if let plan = usage.plan {
                Text(plan)
                    .foregroundColor(.white.opacity(0.3))
            }
            Spacer(minLength: 8)

            if let limit = usage.headline {
                UsageBar(fraction: limit.usedPercent / 100)
                    .frame(width: 56, height: 4)
                Text("\(Int(limit.usedPercent.rounded()))%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.75))
                    .frame(minWidth: 32, alignment: .trailing)
                if let reset = limit.resetsAt {
                    Text(UsageFormat.timeUntil(reset))
                        .foregroundColor(.white.opacity(0.3))
                        .frame(minWidth: 44, alignment: .trailing)
                }
            } else if let error = usage.error {
                Text(error)
                    .foregroundColor(.white.opacity(0.35))
                    .lineLimit(1)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .help(tooltip)
    }
}

private struct UsageBar: View {
    let fraction: Double

    private var color: Color {
        switch fraction {
        case ..<0.7: return .white.opacity(0.75)
        case ..<0.9: return TerminalColors.amber
        default: return Color(red: 0.95, green: 0.35, blue: 0.3)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(color)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
    }
}
