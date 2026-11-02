//
//  DisplayArrangement.swift
//  CrewNotch
//
//  Settings → General: the connected displays as macOS arranges them, with
//  the notch where it shows. Click a display to move the notch there; on one
//  without a camera housing, drag the notch along the top edge.
//

import AppKit
import SwiftUI

struct DisplayArrangement: View {
    @ObservedObject private var screens = ScreenSelector.shared

    var body: some View {
        GeometryReader { proxy in
            let map = ArrangementMap(frames: screens.availableScreens.map(\.frame), in: proxy.size)
            ZStack(alignment: .topLeading) {
                ForEach(screens.availableScreens, id: \.self) { screen in
                    let rect = map.rect(for: screen.frame)
                    DisplayTile(screens: screens, screen: screen, size: rect.size)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
        .frame(height: 140)
        .padding(.vertical, 4)
    }
}

/// Fits the displays' global frames into the view, centered, with up still up
private struct ArrangementMap {
    let union: CGRect
    let scale: CGFloat
    let origin: CGPoint

    init(frames: [CGRect], in size: CGSize) {
        union = frames.reduce(CGRect.null) { $0.union($1) }
        scale = union.isEmpty ? 0 : min(size.width / union.width, size.height / union.height)
        origin = CGPoint(x: (size.width - union.width * scale) / 2, y: (size.height - union.height * scale) / 2)
    }

    func rect(for frame: CGRect) -> CGRect {
        CGRect(
            x: origin.x + (frame.minX - union.minX) * scale,
            y: origin.y + (union.maxY - frame.maxY) * scale,
            width: frame.width * scale,
            height: frame.height * scale
        )
        .insetBy(dx: 2, dy: 2)
    }
}

private struct DisplayTile: View {
    @ObservedObject var screens: ScreenSelector
    let screen: NSScreen
    let size: CGSize

    /// The notch's center when the drag began, so it moves with the pointer instead of jumping to it
    @State private var dragStartX: CGFloat?
    @State private var isSnapped = false

    private var isSelected: Bool { screens.isSelected(screen) }
    private var canDrag: Bool { isSelected && !screen.hasPhysicalNotch }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 6, style: .continuous) }

    /// The notch at the tile's scale, kept big enough to see and grab
    private var notch: (width: CGFloat, height: CGFloat, margin: CGFloat) {
        let scale = size.width / max(screen.frame.width, 1)
        return (max(16, screen.notchSize.width * scale), max(5, screen.notchSize.height * scale), NotchGeometry.edgeMargin * scale)
    }

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(white: 0.34), Color(white: 0.2)], startPoint: .top, endPoint: .bottom)
            Rectangle().fill(.white.opacity(0.12)).frame(height: notch.height)

            if isSelected || screen.hasPhysicalNotch {
                UnevenRoundedRectangle(bottomLeadingRadius: notch.height / 2, bottomTrailingRadius: notch.height / 2, style: .continuous)
                    .fill(.black.opacity(isSelected ? 1 : 0.45))
                    .frame(width: notch.width, height: notch.height)
                    .notchAnchored(at: screens.position(for: screen), notchWidth: notch.width, margin: notch.margin)
            }

            Text(screen.localizedName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(isSelected ? 0.9 : 0.55))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 6)
                .padding(.top, notch.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(isSelected ? Color.accentColor : .white.opacity(0.12), lineWidth: isSelected ? 2 : 1))
        .contentShape(shape)
        .environment(\.colorScheme, .dark)
        .onTapGesture {
            screens.selectScreen(screen)
            AppDelegate.shared?.showNotchWhereChosen()
        }
        .gesture(DragGesture(minimumDistance: 1).onChanged(drag).onEnded { _ in endDrag() }, including: canDrag ? .all : .none)
        .pointerStyle(canDrag ? (dragStartX == nil ? .grabIdle : .grabActive) : isSelected ? .default : .link)
        .help(canDrag ? String(localized: "Drag to move the notch. It snaps to the middle.") : isSelected ? "" : String(localized: "Show the notch here"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(screen.localizedName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func drag(_ value: DragGesture.Value) {
        let n = notch
        let start = dragStartX ?? NotchGeometry.centerX(for: screens.position(for: screen), notchWidth: n.width, screenWidth: size.width, margin: n.margin)
        dragStartX = start
        var position = NotchGeometry.position(forCenterX: start + value.translation.width, notchWidth: n.width, screenWidth: size.width, margin: n.margin)
        let snapped = abs(position - 0.5) < 0.04
        if snapped { position = 0.5 }
        if snapped && !isSnapped {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        isSnapped = snapped
        screens.setPosition(position, for: screen)
    }

    private func endDrag() {
        dragStartX = nil
        isSnapped = false
        AppDelegate.shared?.showNotchWhereChosen()
    }
}
