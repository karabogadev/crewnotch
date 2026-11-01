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

    @State private var rotation: Double = 0
    @State private var pulse = false

    var body: some View {
        switch status {
        case .working:
            Circle()
                .trim(from: 0.12, to: 0.88)
                .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .frame(width: size - 3, height: size - 3)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }
        case .needsYou:
            ZStack {
                Circle()
                    .fill(TerminalColors.amber)
                    .frame(width: size, height: size)
                    .scaleEffect(pulse ? 1.0 : 0.86)
                Text("!")
                    .font(.system(size: size * 0.7, weight: .heavy, design: .rounded))
                    .foregroundColor(.black)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.black, TerminalColors.green)
        }
    }
}
