//
//  NoticeBanner.swift
//  CrewNotch
//
//  A short notice the notch drops down that isn't about one session,
//  such as a plan limit running low or resetting.
//

import SwiftUI

nonisolated struct NotchNotice: Equatable, Sendable {
    nonisolated enum Tone: Sendable { case info, warning, critical }

    let id: String
    let agent: AgentKind?
    let title: String
    let subtitle: String?
    let tone: Tone
}

struct NoticeBanner: View {
    let notice: NotchNotice
    let onOpen: () -> Void

    @State private var isHovered = false

    private var dotColor: Color {
        switch notice.tone {
        case .info: return TerminalColors.green
        case .warning: return TerminalColors.amber
        case .critical: return TerminalColors.red
        }
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                if let agent = notice.agent {
                    AgentIcon(agent: agent, size: 22)
                } else {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.system(size: 18))
                        .foregroundColor(.ink.opacity(0.8))
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Circle().fill(dotColor).frame(width: 6, height: 6)
                        Text(notice.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.ink)
                            .lineLimit(1)
                    }
                    if let subtitle = notice.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(.ink.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.ink.opacity(isHovered ? 0.9 : 0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
