//
//  AppearanceSettings.swift
//  CrewNotch
//
//  Options from Settings → Appearance. Views read them with @AppStorage
//  using the keys below; non-view code reads the static accessors.
//

import SwiftUI

nonisolated enum TextScale: String, CaseIterable, Identifiable {
    case small, standard, large

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var factor: CGFloat {
        switch self {
        case .small: return 0.9
        case .standard: return 1
        case .large: return 1.15
        }
    }
}

/// How the opened panel is painted. The closed notch always stays solid
/// black so it blends with the hardware notch.
nonisolated enum PanelMaterial: String, CaseIterable, Identifiable {
    case solid, smoked, glassy

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

nonisolated enum PanelTint: String, CaseIterable, Identifiable {
    case black, graphite, midnight, ocean, forest, plum

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .black: return .black
        case .graphite: return Color(red: 0.11, green: 0.11, blue: 0.12)
        case .midnight: return Color(red: 0.07, green: 0.09, blue: 0.15)
        case .ocean: return Color(red: 0.05, green: 0.12, blue: 0.13)
        case .forest: return Color(red: 0.07, green: 0.10, blue: 0.07)
        case .plum: return Color(red: 0.12, green: 0.07, blue: 0.12)
        }
    }
}

nonisolated enum IdleNotchBehavior: String, CaseIterable, Identifiable {
    case hide, showUsage

    var id: String { rawValue }
    var title: String { self == .hide ? "Hide the notch" : "Show plan usage" }
}

nonisolated enum TitleOrder: String, CaseIterable, Identifiable {
    case conversation, project

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

nonisolated enum AppearanceKeys {
    static let textScale = "textScale"
    static let material = "panelMaterial"
    static let tint = "panelTint"
    static let closedShowsWorking = "closedShowsWorking"
    static let closedShowsNotifications = "closedShowsNotifications"
    static let closedShowsUsage = "closedShowsUsage"
    static let idleNotch = "idleNotchBehavior"
    static let titleOrder = "titleOrder"
    /// Minutes after which a finished session counts as idle (0 = never)
    static let idleAfterMinutes = "idleAfterMinutes"
    static let hideIdleSessions = "hideIdleSessions"
    static let rowsAtOnce = "rowsAtOnce"

    static var rowsAtOnceValue: Int {
        UserDefaults.standard.object(forKey: rowsAtOnce) as? Int ?? 5
    }
}

extension SessionState {
    /// Idle for display: explicitly idle, or finished longer ago than the
    /// "Mark a session idle after" setting.
    func isIdle(afterMinutes minutes: Int, now: Date = Date()) -> Bool {
        if phase == .idle || phase == .ended { return true }
        guard minutes > 0, phase == .waitingForInput else { return false }
        return now.timeIntervalSince(lastActivity) > TimeInterval(minutes * 60)
    }
}
