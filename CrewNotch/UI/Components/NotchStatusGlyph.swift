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
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.82, weight: .bold))
                .foregroundStyle(accent.finishedColor)
                .frame(width: size, height: size)
        }
    }
}

/// Needs you: a small square lamp that breathes.
struct AttentionPulse: View {
    var size: CGFloat = 14
    var color: Color = TerminalColors.amber

    var body: some View {
        TimelineView(.animation) { context in
            let wave = (sin(context.date.timeIntervalSinceReferenceDate * 4.2) + 1) / 2
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .fill(color)
                .frame(width: size * 0.6, height: size * 0.6)
                .opacity(0.45 + 0.55 * wave)
                .frame(width: size, height: size)
        }
    }
}
