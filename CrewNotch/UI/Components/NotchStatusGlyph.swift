//
//  NotchStatusGlyph.swift
//  CrewNotch
//
//  The single status mark shown beside the closed notch.
//

import SwiftUI

enum CrewActivity: Equatable {
    case needsYou
    case working
    case finished
}

struct NotchStatusGlyph: View {
    let status: CrewActivity
    var size: CGFloat = 14
    @AppStorage(AppearanceKeys.accentMode) private var accent: AccentMode = .full

    var body: some View {
        switch status {
        case .working:
            WorkingIndicator(size: size)
        case .needsYou:
            AttentionPulse(size: size, color: accent.attentionColor)
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.black, accent.finishedColor)
        }
    }
}

/// Needs you: an amber dot that sends out a soft ring, like a ping.
struct AttentionPulse: View {
    var size: CGFloat = 14
    var color: Color = TerminalColors.amber

    var body: some View {
        TimelineView(.animation) { context in
            let progress = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
            ZStack {
                Circle()
                    .stroke(color, lineWidth: 1.2)
                    .frame(width: size * 0.45, height: size * 0.45)
                    .scaleEffect(1 + progress * 1.4)
                    .opacity(1 - progress)
                Circle()
                    .fill(color)
                    .frame(width: size * 0.45, height: size * 0.45)
            }
            .frame(width: size, height: size)
        }
    }
}
