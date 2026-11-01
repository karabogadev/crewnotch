//
//  NotchEffectsOverlay.swift
//  CrewNotch
//
//  Draws the current NotchEffects animation around the notch. Sized to the
//  notch; confetti and ripples spill out below it.
//

import SwiftUI

struct NotchEffectsOverlay: View {
    @ObservedObject var effects: NotchEffects

    var body: some View {
        GeometryReader { geometry in
            if let effect = effects.current {
                TimelineView(.animation) { context in
                    let progress = min(1, context.date.timeIntervalSince(effect.startedAt) / effect.duration)
                    switch effect.style {
                    case .glow:
                        GlowSweep(progress: progress, tint: effect.tint, size: geometry.size)
                    case .confetti:
                        ConfettiBurst(progress: progress, seed: effect.id.hashValue, size: geometry.size)
                    case .ripple:
                        NotchRipple(progress: progress, tint: effect.tint, size: geometry.size)
                    case .none, .bounce:
                        EmptyView()
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// A band of light sliding along the bottom edge of the notch.
private struct GlowSweep: View {
    let progress: Double
    let tint: Color
    let size: CGSize

    var body: some View {
        let eased = 0.5 - cos(progress * .pi) / 2
        let width = size.width * 0.45
        Capsule()
            .fill(LinearGradient(colors: [tint.opacity(0), tint, tint.opacity(0)], startPoint: .leading, endPoint: .trailing))
            .frame(width: width, height: 3)
            .blur(radius: 2.5)
            .shadow(color: tint.opacity(0.9), radius: 6)
            .position(x: -width / 2 + (size.width + width) * eased, y: size.height - 1.5)
            .opacity(progress < 0.85 ? 1 : (1 - progress) / 0.15)
    }
}

/// Small colored pieces bursting out from under the notch and falling away.
private struct ConfettiBurst: View {
    let progress: Double
    let seed: Int
    let size: CGSize

    private static let colors: [Color] = [
        Color(red: 1.00, green: 0.62, blue: 0.20),
        Color(red: 0.30, green: 0.85, blue: 0.45),
        Color(red: 0.35, green: 0.62, blue: 1.00),
        Color(red: 0.95, green: 0.40, blue: 0.55),
        .white,
    ]

    private struct Piece {
        let angle: Double
        let speed: Double
        let spin: Double
        let color: Color
        let isRound: Bool
    }

    private var pieces: [Piece] {
        var generator = SeededGenerator(seed: UInt64(truncatingIfNeeded: seed))
        return (0..<22).map { index in
            Piece(
                angle: Double.random(in: 0.15...(.pi - 0.15), using: &generator),
                speed: Double.random(in: 40...95, using: &generator),
                spin: Double.random(in: -540...540, using: &generator),
                color: Self.colors[index % Self.colors.count],
                isRound: index % 3 == 0
            )
        }
    }

    var body: some View {
        let origin = CGPoint(x: size.width / 2, y: size.height - 2)
        ZStack {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                let t = progress
                let x = origin.x + cos(piece.angle) * piece.speed * t * 1.6
                let y = origin.y + sin(piece.angle) * piece.speed * t + 70 * t * t
                Group {
                    if piece.isRound {
                        Circle().fill(piece.color).frame(width: 4, height: 4)
                    } else {
                        Rectangle().fill(piece.color).frame(width: 3, height: 6)
                    }
                }
                .rotationEffect(.degrees(piece.spin * t))
                .position(x: x, y: y)
                .opacity(1 - pow(t, 2))
            }
        }
    }
}

/// Soft rings expanding out from the notch's outline.
private struct NotchRipple: View {
    let progress: Double
    let tint: Color
    let size: CGSize

    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { ring in
                let local = max(0, min(1, progress * 1.25 - Double(ring) * 0.25))
                RoundedRectangle(cornerRadius: min(size.height, 30) / 2 + 6 * local, style: .continuous)
                    .stroke(tint, lineWidth: 1.6)
                    .frame(width: size.width + 28 * local, height: size.height + 18 * local)
                    .position(x: size.width / 2, y: size.height / 2 + 9 * local)
                    .opacity((1 - local) * (local > 0 ? 0.9 : 0))
            }
        }
    }
}

/// Deterministic random numbers so a burst looks the same on every frame.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
