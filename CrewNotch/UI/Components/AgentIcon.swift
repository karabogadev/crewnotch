//
//  AgentIcon.swift
//  CrewNotch
//
//  Small badge identifying which agent a session belongs to. Desktop agents
//  use their installed app's icon; terminal agents get a monogram.
//

import AppKit
import SwiftUI

struct AgentIcon: View {
    let agent: AgentKind
    var size: CGFloat = 14

    var body: some View {
        if let image = AgentIconCache.appIcon(for: agent) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(agent.badgeColor)
                .frame(width: size, height: size)
                .overlay(
                    Text(agent.monogram)
                        .font(.system(size: size * 0.52, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.5)
                )
        }
    }
}

@MainActor
private enum AgentIconCache {
    private static var icons: [AgentKind: NSImage?] = [:]

    static func appIcon(for agent: AgentKind) -> NSImage? {
        if let cached = icons[agent] { return cached }
        let icon = agent.appBundleIdentifiers()
            .lazy
            .compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .first
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        icons[agent] = icon
        return icon
    }
}

extension AgentKind {
    var monogram: String {
        switch self {
        case .claude: return "C"
        case .codex: return "Cx"
        case .cursor: return "Cu"
        case .gemini: return "G"
        case .antigravity: return "A"
        case .deepseek: return "D"
        case .opencode: return "O"
        case .copilot: return "Co"
        case .grok: return "X"
        case .kiro: return "K"
        }
    }

    var badgeColor: Color {
        switch self {
        case .claude: return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: return Color(white: 0.22)
        case .cursor: return Color(white: 0.3)
        case .gemini: return Color(red: 0.26, green: 0.47, blue: 0.96)
        case .antigravity: return Color(red: 0.2, green: 0.55, blue: 0.95)
        case .deepseek: return Color(red: 0.3, green: 0.42, blue: 0.99)
        case .opencode: return Color(white: 0.35)
        case .copilot: return Color(red: 0.45, green: 0.3, blue: 0.85)
        case .grok: return Color(white: 0.15)
        case .kiro: return Color(red: 0.5, green: 0.32, blue: 0.95)
        }
    }
}
