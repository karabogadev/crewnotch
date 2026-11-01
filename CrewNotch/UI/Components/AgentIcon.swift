//
//  AgentIcon.swift
//  CrewNotch
//
//  The agent's own logo, used everywhere an agent is shown. Logos come from
//  LobeHub Icons (MIT, github.com/lobehub/lobe-icons); each is a trademark of
//  its owner and is used only to identify the integration.
//

import SwiftUI

struct AgentIcon: View {
    let agent: AgentKind
    var size: CGFloat = 14

    var body: some View {
        Image("agent-\(agent.rawValue)")
            .resizable()
            .renderingMode(agent.hasMonochromeLogo ? .template : .original)
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
    }
}

extension AgentKind {
    /// Single-color logos are tinted to match the surrounding text.
    var hasMonochromeLogo: Bool {
        switch self {
        case .cursor, .opencode, .copilot, .grok: return true
        default: return false
        }
    }
}
