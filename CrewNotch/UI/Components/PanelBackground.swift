//
//  PanelBackground.swift
//  CrewNotch
//
//  The notch's fill: always solid black while closed (so it blends with the
//  hardware notch), and the chosen material, tint and theme once opened.
//

import AppKit
import SwiftUI

struct PanelBackground: View {
    let isOpened: Bool
    @AppStorage(AppearanceKeys.material) private var material: PanelMaterial = .solid
    @AppStorage(AppearanceKeys.tint) private var tint: PanelTint = .black
    @Environment(\.colorScheme) private var colorScheme

    private var fill: Color { colorScheme == .light ? tint.lightColor : tint.color }

    var body: some View {
        if !isOpened {
            Color.black
        } else {
            switch material {
            case .solid:
                fill
            case .smoked:
                ZStack {
                    BehindWindowBlur(dark: colorScheme == .dark)
                    fill.opacity(0.8)
                }
            case .glassy:
                ZStack {
                    BehindWindowBlur(dark: colorScheme == .dark)
                    fill.opacity(0.45)
                }
            }
        }
    }
}

/// Blurs whatever is behind the (transparent) notch window.
private struct BehindWindowBlur: NSViewRepresentable {
    let dark: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }
}
