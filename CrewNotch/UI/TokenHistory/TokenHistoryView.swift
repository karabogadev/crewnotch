//
//  TokenHistoryView.swift
//  CrewNotch
//
//  Tokens used per day (or per hour today) across agents, with the
//  estimated Claude API value and a shareable image of the card.
//

import AppKit
import Charts
import SwiftUI

struct TokenHistoryView: View {
    @State private var range: TokenHistoryRange = .month
    @State private var report: TokenHistoryReport?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            if let report {
                TokenHistoryCard(report: report)
            } else {
                ProgressView("Reading agent logs…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(28)
        .frame(minWidth: 640, minHeight: 560)
        .background(Color.black)
        .task(id: range) { await load() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title3)
            Text("Token history")
                .font(.title2.bold())
            if isLoading && report != nil {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Picker("Range", selection: $range) {
                ForEach(TokenHistoryRange.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Button(action: share) {
                Image(systemName: "square.and.arrow.up")
            }
            .help("Share as image")
            .disabled(report == nil)
        }
        .foregroundStyle(.white)
    }

    private func load() async {
        isLoading = true
        let range = self.range
        report = await TokenHistoryStore.shared.report(for: range)
        isLoading = false
    }

    /// Renders the card to a PNG and opens the share sheet.
    private func share() {
        guard let report else { return }
        let card = TokenHistoryCard(report: report)
            .padding(28)
            .frame(width: 720)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CrewNotch token history.png")
        try? png.write(to: url)

        guard let view = NSApp.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: CGRect(x: view.bounds.maxX - 60, y: view.bounds.maxY - 50, width: 1, height: 1), of: view, preferredEdge: .minY)
    }
}

/// The shareable part: totals, chart, per-agent breakdown and stats.
struct TokenHistoryCard: View {
    let report: TokenHistoryReport

    private var agents: [AgentKind] {
        report.totals.filter { $0.value > 0 }.sorted { $0.value > $1.value }.map(\.key)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(report.range.caption)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(TokenFormat.short(report.total))
                            .font(.system(size: 54, weight: .bold, design: .rounded))
                        Text("tokens")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Text(dateRange)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                if report.claudeValue > 0 {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("EST. API VALUE")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("≈ " + report.claudeValue.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("Claude at API rates")
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }

            chart
                .frame(height: 220)

            if !agents.isEmpty {
                HStack(spacing: 28) {
                    ForEach(agents) { agent in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                AgentIcon(agent: agent, size: 14)
                                Text(agent.displayName).foregroundStyle(.white.opacity(0.85))
                            }
                            Text(TokenFormat.short(report.totals[agent] ?? 0))
                                .font(.title3.bold())
                        }
                    }
                }
            }

            Divider().overlay(Color.white.opacity(0.15))

            HStack(alignment: .top) {
                stat(report.range.isHourly ? "PER ACTIVE HOUR" : "PER ACTIVE DAY", TokenFormat.short(report.perActiveBar))
                Spacer()
                stat(report.range.isHourly ? "BUSIEST HOUR" : "BUSIEST DAY",
                     TokenFormat.short(report.busiest?.total ?? 0),
                     detail: report.busiest.flatMap { $0.total > 0 ? label(for: $0.start) : nil })
                Spacer()
                stat(report.range.isHourly ? "ACTIVE HOURS" : "ACTIVE DAYS",
                     "\(report.activeBars.count)", detail: "of \(report.bars.count)")
            }
        }
        .foregroundStyle(.white)
    }

    private var chart: some View {
        Chart {
            ForEach(report.bars) { bar in
                ForEach(agents) { agent in
                    if let count = bar.tokens[agent], count > 0 {
                        BarMark(
                            x: .value("Time", bar.start, unit: report.range.isHourly ? .hour : .day),
                            y: .value("Tokens", count)
                        )
                        .foregroundStyle(by: .value("Agent", agent.displayName))
                        .cornerRadius(3)
                    }
                }
            }
        }
        .chartForegroundStyleScale(domain: agents.map(\.displayName), range: agents.map(\.chartColor))
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.12))
                AxisValueLabel {
                    if let count = value.as(Int.self) {
                        Text(TokenFormat.short(count)).font(.system(size: 10, design: .monospaced))
                    }
                }
                .foregroundStyle(Color.white.opacity(0.6))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: report.range.isHourly ? 6 : 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(label(for: date)).font(.system(size: 10, design: .monospaced))
                    }
                }
                .foregroundStyle(Color.white.opacity(0.6))
            }
        }
    }

    private func stat(_ title: String, _ value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.system(size: 26, weight: .bold, design: .rounded))
                if let detail {
                    Text(detail).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    private var dateRange: String {
        let format = Date.FormatStyle().day().month(.abbreviated)
        if report.range == .today { return report.rangeEnd.formatted(format) }
        return "\(report.rangeStart.formatted(format)) – \(report.rangeEnd.formatted(format))"
    }

    private func label(for date: Date) -> String {
        if report.range.isHourly { return date.formatted(.dateTime.hour()) }
        if Calendar.current.isDateInToday(date) { return "Today" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

nonisolated enum TokenFormat {
    /// 3.45B, 127.8M, 12.4K
    static func short(_ value: Int) -> String {
        let number = Double(value)
        switch number {
        case 1e9...: return String(format: "%.2fB", number / 1e9)
        case 1e6...: return String(format: "%.1fM", number / 1e6)
        case 1e3...: return String(format: "%.1fK", number / 1e3)
        default: return "\(value)"
        }
    }
}

extension AgentKind {
    /// Series color in charts
    var chartColor: Color {
        switch self {
        case .claude: return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: return Color(red: 0.45, green: 0.55, blue: 1.0)
        case .deepseek: return Color(red: 0.30, green: 0.42, blue: 0.99)
        case .gemini: return Color(red: 0.26, green: 0.47, blue: 0.96)
        case .antigravity: return Color(red: 0.2, green: 0.7, blue: 0.95)
        case .cursor: return Color(white: 0.85)
        case .opencode: return Color(white: 0.65)
        case .copilot: return Color(red: 0.55, green: 0.4, blue: 0.9)
        case .grok: return Color(white: 0.5)
        case .kiro: return Color(red: 0.55, green: 0.35, blue: 0.95)
        }
    }
}
