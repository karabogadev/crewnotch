//
//  KeepAwakeButton.swift
//  CrewNotch
//
//  Hourglass toggle for Keep Awake in the opened notch header.
//

import SwiftUI

struct KeepAwakeButton: View {
    @ObservedObject var controller: KeepAwakeController
    @State private var isHovered = false

    private var color: Color {
        switch controller.state {
        case .active: return TerminalColors.green
        case .paused: return TerminalColors.amber
        case .off: return .ink.opacity(isHovered ? 0.8 : 0.5)
        }
    }

    private var helpText: String {
        switch controller.state {
        case .active(let until):
            return String(localized: "Keep Awake is on until \(until.formatted(date: .omitted, time: .shortened)). Agents keep running while the display sleeps. Click to turn off.")
        case .paused(let reason):
            return String(localized: "Keep Awake is paused: \(reason). Click to turn off.")
        case .off:
            return String(localized: "Keep Awake: keep agents running while the display sleeps")
        }
    }

    var body: some View {
        Button {
            controller.toggle()
        } label: {
            Image(systemName: controller.isEnabled ? "hourglass.circle.fill" : "hourglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(helpText)
    }
}
