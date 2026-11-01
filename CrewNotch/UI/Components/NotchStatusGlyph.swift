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

    var body: some View {
        switch status {
        case .working:
            CrewDots(size: size)
        case .needsYou:
            AttentionPulse(size: size)
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.black, TerminalColors.green)
        }
    }
}

/// Working: the three dots from the CrewNotch logo rising and brightening
/// one after another, like a crew taking turns.
struct CrewDots: View {
    var size: CGFloat = 14

    private static let colors: [Color] = [
        Color(red: 1.00, green: 0.62, blue: 0.20),
        Color(red: 0.30, green: 0.85, blue: 0.45),
        Color(red: 0.35, green: 0.62, blue: 1.00),
    ]

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: size * 0.14) {
                ForEach(0..<3, id: \.self) { index in
                    let wave = (sin((time * 2.4 - Double(index) * 0.55) * .pi) + 1) / 2
                    Circle()
                        .fill(Self.colors[index])
                        .frame(width: size * 0.26, height: size * 0.26)
                        .opacity(0.35 + 0.65 * wave)
                        .offset(y: -size * 0.14 * wave)
                }
            }
            .frame(width: size * 1.2, height: size)
        }
    }
}

/// Needs you: an amber dot that sends out a soft ring, like a ping.
struct AttentionPulse: View {
    var size: CGFloat = 14

    var body: some View {
        TimelineView(.animation) { context in
            let progress = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
            ZStack {
                Circle()
                    .stroke(TerminalColors.amber, lineWidth: 1.2)
                    .frame(width: size * 0.45, height: size * 0.45)
                    .scaleEffect(1 + progress * 1.4)
                    .opacity(1 - progress)
                Circle()
                    .fill(TerminalColors.amber)
                    .frame(width: size * 0.45, height: size * 0.45)
            }
            .frame(width: size, height: size)
        }
    }
}
