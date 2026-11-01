//
//  FinishedBanner.swift
//  CrewNotch
//
//  The short notice the notch drops down when an agent finishes a turn.
//  Clicking it jumps back to the session.
//

import SwiftUI

struct FinishedBanner: View {
    let session: SessionState
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                AgentIcon(agent: session.agent, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Circle().fill(TerminalColors.green).frame(width: 6, height: 6)
                        Text("Finished")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Text(session.displayTitle == session.projectName ? session.projectName : "\(session.projectName) · \(session.displayTitle)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                HStack(spacing: 3) {
                    Text("Open")
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(isHovered ? 1 : 0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
