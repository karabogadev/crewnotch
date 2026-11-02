//
//  NotchGeometry.swift
//  CrewNotch
//
//  Geometry calculations for the notch
//

import CoreGraphics
import Foundation

/// Pure geometry calculations for the notch
struct NotchGeometry: Sendable {
    let notchSize: CGSize
    let screenRect: CGRect
    let windowHeight: CGFloat
    /// Where the notch sits along the top edge: 0 left, 0.5 middle, 1 right.
    /// Displays with a camera housing always use the middle.
    var position: CGFloat = 0.5

    /// The notch in window coordinates (x from the screen's left edge)
    var deviceNotchRect: CGRect {
        let centerX = Self.centerX(for: position, notchWidth: notchSize.width, screenWidth: screenRect.width)
        return CGRect(x: centerX - notchSize.width / 2, y: 0, width: notchSize.width, height: notchSize.height)
    }

    /// The notch rect in screen coordinates (for hit testing with global mouse position)
    var notchScreenRect: CGRect {
        CGRect(
            x: screenRect.minX + deviceNotchRect.minX,
            y: screenRect.maxY - notchSize.height,
            width: notchSize.width,
            height: notchSize.height
        )
    }

    /// The panel as drawn: centered under the notch, kept on screen, and hanging
    /// from the top of the screen, sized from the view's own measurement.
    func panelScreenRect(for size: CGSize) -> CGRect {
        let x = Self.originX(width: size.width, centeredAt: deviceNotchRect.midX, screenWidth: screenRect.width)
        return CGRect(x: screenRect.minX + x, y: screenRect.maxY - size.height, width: size.width, height: size.height)
    }

    /// Check if a point is in the notch area (with padding for easier interaction)
    func isPointInNotch(_ point: CGPoint) -> Bool {
        notchScreenRect.insetBy(dx: -10, dy: -5).contains(point)
    }
}

// MARK: - Placement along the top edge

extension NotchGeometry {
    /// Room kept between the closed notch and the screen edge, so the agent
    /// logo and status that widen it while agents work still fit
    nonisolated static let edgeMargin: CGFloat = 80

    /// The notch's center for a position from 0 (leftmost) to 1 (rightmost)
    nonisolated static func centerX(for position: CGFloat, notchWidth: CGFloat, screenWidth: CGFloat, margin: CGFloat = edgeMargin) -> CGFloat {
        let range = centerRange(notchWidth: notchWidth, screenWidth: screenWidth, margin: margin)
        guard range.upperBound > range.lowerBound else { return screenWidth / 2 }
        return range.lowerBound + (range.upperBound - range.lowerBound) * min(max(position, 0), 1)
    }

    /// The position whose notch is centered at `centerX`, the inverse of `centerX(for:)`
    nonisolated static func position(forCenterX centerX: CGFloat, notchWidth: CGFloat, screenWidth: CGFloat, margin: CGFloat = edgeMargin) -> CGFloat {
        let range = centerRange(notchWidth: notchWidth, screenWidth: screenWidth, margin: margin)
        guard range.upperBound > range.lowerBound else { return 0.5 }
        return min(max((centerX - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    /// Left edge for something `width` wide centered at `centerX`, moved in to stay on screen
    nonisolated static func originX(width: CGFloat, centeredAt centerX: CGFloat, screenWidth: CGFloat) -> CGFloat {
        min(max(centerX - width / 2, 0), max(0, screenWidth - width))
    }

    nonisolated private static func centerRange(notchWidth: CGFloat, screenWidth: CGFloat, margin: CGFloat) -> ClosedRange<CGFloat> {
        let lower = notchWidth / 2 + margin
        return lower...max(lower, screenWidth - lower)
    }
}
