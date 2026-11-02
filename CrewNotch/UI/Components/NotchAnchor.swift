//
//  NotchAnchor.swift
//  CrewNotch
//
//  Hangs a view from the top edge, centered under the notch's position and
//  moved in where it would run off the side. The notch window and the
//  Settings preview both use it, so they place the notch the same way.
//

import SwiftUI

struct NotchAnchor: Layout {
    /// 0 left, 0.5 middle, 1 right
    var position: CGFloat
    /// Width of the closed notch, which the position is measured with
    var notchWidth: CGFloat
    var margin: CGFloat = NotchGeometry.edgeMargin

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let centerX = NotchGeometry.centerX(for: position, notchWidth: notchWidth, screenWidth: bounds.width, margin: margin)
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(bounds.size))
            let x = NotchGeometry.originX(width: size.width, centeredAt: centerX, screenWidth: bounds.width)
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(size))
        }
    }
}

extension View {
    func notchAnchored(at position: CGFloat, notchWidth: CGFloat, margin: CGFloat = NotchGeometry.edgeMargin) -> some View {
        NotchAnchor(position: position, notchWidth: notchWidth, margin: margin) { self }
    }
}
