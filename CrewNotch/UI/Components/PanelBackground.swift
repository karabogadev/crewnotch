//
//  PanelBackground.swift
//  CrewNotch
//
//  The notch's fill: always solid black while closed (so it blends with the
//  hardware notch), and the chosen material and tint once opened.
//

import AppKit
import SwiftUI

struct PanelBackground: View {
    let isOpened: Bool
    @AppStorage(AppearanceKeys.material) private var material: PanelMaterial = .solid
    @AppStorage(AppearanceKeys.tint) private var tint: PanelTint = .black

    var body: some View {
        if !isOpened {
            Color.black
        } else {
            switch material {
            case .solid:
                tint.color
            case .smoked:
                ZStack {
                    BehindWindowBlur()
                    tint.color.opacity(0.8)
                }
            case .glassy:
                ZStack {
                    BehindWindowBlur()
                    tint.color.opacity(0.45)
                }
            }
        }
    }
}

/// Blurs whatever is behind the (transparent) notch window.
private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
