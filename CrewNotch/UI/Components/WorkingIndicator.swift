//
//  WorkingIndicator.swift
//  CrewNotch
//
//  The "agent is working" animation, in the style and colors picked in
//  Settings → Appearance. Used in the closed notch, session rows and previews.
//

import SwiftUI

enum WorkingIndicatorStyle: String, CaseIterable, Identifiable {
    case scanner, crewDots, ring, spark, equalizer, orbit, pulse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scanner: return String(localized: "Scanner")
        case .crewDots: return String(localized: "Crew dots")
        case .ring: return String(localized: "Ring")
        case .spark: return String(localized: "Spark")
        case .equalizer: return String(localized: "Equalizer")
        case .orbit: return String(localized: "Orbit")
        case .pulse: return String(localized: "Pulse")
        }
    }
}

enum WorkingIndicatorColor: String, CaseIterable, Identifiable {
    case crew, white

    var id: String { rawValue }
    var title: String { self == .crew ? String(localized: "Crew colors") : String(localized: "White") }
}

/// The working indicator as configured in Settings.
struct WorkingIndicator: View {
    var size: CGFloat = 14
    @AppStorage("workingIndicatorStyle") private var style: WorkingIndicatorStyle = .scanner
    @AppStorage("workingIndicatorColor") private var color: WorkingIndicatorColor = .crew

    var body: some View {
        WorkingIndicatorView(style: style, color: color, size: size)
    }
}

/// A specific indicator style, for previews in Settings.
struct WorkingIndicatorView: View {
    let style: WorkingIndicatorStyle
    let color: WorkingIndicatorColor
    var size: CGFloat = 14

    private static let crew: [Color] = [
        Color(red: 1.00, green: 0.62, blue: 0.20),
        Color(red: 0.30, green: 0.85, blue: 0.45),
        Color(red: 0.35, green: 0.62, blue: 1.00),
    ]

    private func tint(_ index: Int) -> Color {
        color == .crew ? Self.crew[index % Self.crew.count] : .white
    }

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            content(time: time)
                .frame(width: size * 1.2, height: size)
        }
    }

    @ViewBuilder
    private func content(time: Double) -> some View {
        switch style {
        case .scanner:
            // Three bars lit one after another, like a level meter settling
            HStack(spacing: size * 0.2) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = (time / 1.2 - Double(index) * 0.13).truncatingRemainder(dividingBy: 1)
                    let wave = (sin((phase < 0 ? phase + 1 : phase) * 2 * .pi - .pi / 2) + 1) / 2
                    RoundedRectangle(cornerRadius: size * 0.07)
                        .fill(color == .crew ? tint(index) : Color.ink)
                        .frame(width: size * 0.2, height: size)
                        .opacity(0.2 + 0.8 * wave)
                }
            }

        case .crewDots:
            HStack(spacing: size * 0.14) {
                ForEach(0..<3, id: \.self) { index in
                    let wave = (sin((time * 2.4 - Double(index) * 0.55) * .pi) + 1) / 2
                    Circle()
                        .fill(tint(index))
                        .frame(width: size * 0.26, height: size * 0.26)
                        .opacity(0.35 + 0.65 * wave)
                        .offset(y: -size * 0.14 * wave)
                }
            }

        case .ring:
            Circle()
                .trim(from: 0.12, to: 0.88)
                .stroke(
                    AngularGradient(colors: color == .crew ? Self.crew + [Self.crew[0]] : [.white.opacity(0.2), .white],
                                    center: .center),
                    style: StrokeStyle(lineWidth: size * 0.13, lineCap: .round)
                )
                .frame(width: size * 0.78, height: size * 0.78)
                .rotationEffect(.degrees(time.truncatingRemainder(dividingBy: 0.9) / 0.9 * 360))

        case .spark:
            let symbols = ["·", "✢", "✳", "∗", "✻", "✽"]
            let index = Int(time / 0.13) % symbols.count
            Text(symbols[index])
                .font(.system(size: size * 0.95, weight: .bold))
                .foregroundColor(color == .crew ? Self.crew[0] : .white)

        case .equalizer:
            HStack(alignment: .center, spacing: size * 0.1) {
                ForEach(0..<4, id: \.self) { index in
                    let level = (sin(time * 6 + Double(index) * 1.3) + 1) / 2
                    Capsule()
                        .fill(tint(index))
                        .frame(width: size * 0.14, height: size * (0.25 + 0.6 * level))
                }
            }

        case .orbit:
            let angle = time.truncatingRemainder(dividingBy: 1.1) / 1.1 * 2 * .pi
            ZStack {
                Circle()
                    .fill(tint(2).opacity(0.5))
                    .frame(width: size * 0.22, height: size * 0.22)
                ForEach(0..<2, id: \.self) { index in
                    let a = angle + Double(index) * .pi
                    Circle()
                        .fill(tint(index))
                        .frame(width: size * 0.22, height: size * 0.22)
                        .offset(x: cos(a) * size * 0.36, y: sin(a) * size * 0.36)
                }
            }

        case .pulse:
            let breath = (sin(time * 3.2) + 1) / 2
            ZStack {
                Circle()
                    .fill(tint(1).opacity(0.25 * (1 - breath)))
                    .frame(width: size * (0.45 + 0.45 * breath), height: size * (0.45 + 0.45 * breath))
                Circle()
                    .fill(tint(1))
                    .frame(width: size * 0.4, height: size * 0.4)
            }
        }
    }
}
