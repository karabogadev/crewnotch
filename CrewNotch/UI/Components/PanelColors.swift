//
//  PanelColors.swift
//  CrewNotch
//
//  Colors that follow the panel's light or dark theme. They resolve against
//  the SwiftUI color scheme, so the closed notch (always dark) and the opened
//  panel (the chosen theme) can share the same views.
//

import AppKit
import SwiftUI

extension Color {
    /// A color with one value for dark surfaces and one for light ones.
    static func dynamic(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    /// Text, icons and hairlines on the panel: white on dark, near-black on light.
    static let ink = dynamic(dark: .white, light: NSColor(white: 0.08, alpha: 1))

    /// The panel's own surface, for text on bright pills and rings around dots.
    static let canvas = dynamic(dark: .black, light: NSColor(white: 0.98, alpha: 1))

    /// A slightly recessed strip, such as the chat input bar.
    static let recess = dynamic(dark: NSColor(white: 0, alpha: 0.2), light: NSColor(white: 0, alpha: 0.04))
}

/// Light, dark or follow the system, for the opened panel and the app's windows.
nonisolated enum PanelTheme: String, CaseIterable, Identifiable {
    case system, dark, light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return String(localized: "System")
        case .dark: return String(localized: "Dark")
        case .light: return String(localized: "Light")
        }
    }

    /// nil follows the system appearance.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

/// Applies the chosen theme to a window's content and keeps it in sync.
struct ThemedWindowContent<Content: View>: View {
    @AppStorage(AppearanceKeys.theme) private var theme: PanelTheme = .system
    let content: Content

    var body: some View {
        content.preferredColorScheme(theme.colorScheme)
    }
}
