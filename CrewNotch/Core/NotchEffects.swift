//
//  NotchEffects.swift
//  CrewNotch
//
//  Short animations around the notch for key moments (launch, opening,
//  an agent finishing, an agent needing you). The style of each moment and
//  the overall speed are chosen in Settings → Appearance.
//

import Combine
import SwiftUI

enum NotchMoment: String, CaseIterable, Identifiable {
    case launch, open, finished, needsYou

    var id: String { rawValue }

    var title: String {
        switch self {
        case .launch: return String(localized: "App launch")
        case .open: return String(localized: "Notch opens")
        case .finished: return String(localized: "Agent finished")
        case .needsYou: return String(localized: "Agent needs you")
        }
    }

    var defaultStyle: NotchEffectStyle {
        switch self {
        case .launch: return .glow
        case .open: return .none
        case .finished: return .none
        case .needsYou: return .glow
        }
    }

    var tint: Color {
        switch self {
        case .launch, .open: return Color(red: 0.35, green: 0.62, blue: 1.0)
        case .finished: return TerminalColors.green
        case .needsYou: return TerminalColors.amber
        }
    }

    var settingsKey: String { "animation.\(rawValue)" }
}

enum NotchEffectStyle: String, CaseIterable, Identifiable {
    case none, glow, confetti, ripple, bounce

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return String(localized: "None")
        case .glow: return String(localized: "Glow sweep")
        case .confetti: return String(localized: "Confetti")
        case .ripple: return String(localized: "Ripple")
        case .bounce: return String(localized: "Bounce")
        }
    }

    /// Base duration at normal speed
    var duration: TimeInterval {
        switch self {
        case .none: return 0
        case .glow: return 1.1
        case .confetti: return 1.6
        case .ripple: return 1.2
        case .bounce: return 0.45
        }
    }
}

enum NotchEffectSpeed: String, CaseIterable, Identifiable {
    case slow, normal, fast

    var id: String { rawValue }
    var title: String {
        switch self {
        case .slow: return String(localized: "Slow")
        case .normal: return String(localized: "Normal")
        case .fast: return String(localized: "Fast")
        }
    }

    var multiplier: Double {
        switch self {
        case .slow: return 1.5
        case .normal: return 1
        case .fast: return 0.65
        }
    }
}

@MainActor
final class NotchEffects: ObservableObject {
    static let shared = NotchEffects()

    struct Effect: Equatable {
        let id = UUID()
        let style: NotchEffectStyle
        let tint: Color
        let startedAt = Date()
        let duration: TimeInterval
    }

    @Published private(set) var current: Effect?
    /// Incremented to trigger the bounce spring in NotchView
    @Published private(set) var bounceCount = 0

    private init() {}

    static func style(for moment: NotchMoment) -> NotchEffectStyle {
        UserDefaults.standard.string(forKey: moment.settingsKey).flatMap(NotchEffectStyle.init(rawValue:)) ?? moment.defaultStyle
    }

    static var speed: NotchEffectSpeed {
        UserDefaults.standard.string(forKey: "animationSpeed").flatMap(NotchEffectSpeed.init(rawValue:)) ?? .normal
    }

    func play(_ moment: NotchMoment) {
        play(Self.style(for: moment), tint: moment.tint)
    }

    func play(_ style: NotchEffectStyle, tint: Color) {
        guard style != .none else { return }
        if style == .bounce {
            bounceCount += 1
            return
        }
        let effect = Effect(style: style, tint: tint, duration: style.duration * Self.speed.multiplier)
        current = effect
        DispatchQueue.main.asyncAfter(deadline: .now() + effect.duration + 0.05) { [weak self] in
            if self?.current == effect { self?.current = nil }
        }
    }
}
