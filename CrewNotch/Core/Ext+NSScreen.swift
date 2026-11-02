//
//  Ext+NSScreen.swift
//  CrewNotch
//
//  Extensions for NSScreen to detect notch and built-in display
//

import AppKit

extension NSScreen {
    /// Returns the size of the notch on this screen (pixel-perfect using macOS APIs)
    var notchSize: CGSize {
        guard safeAreaInsets.top > 0 else {
            // No camera housing: MacBook-notch width, but only as tall as the
            // menu bar, which windows already stay below (24 pt when it hides)
            return CGSize(width: 224, height: max(24, frame.maxY - visibleFrame.maxY))
        }

        let notchHeight = safeAreaInsets.top
        let fullWidth = frame.width
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0

        guard leftPadding > 0, rightPadding > 0 else {
            // Fallback if auxiliary areas unavailable
            return CGSize(width: 180, height: notchHeight)
        }

        // +4 to match boring.notch's calculation for proper alignment
        let notchWidth = fullWidth - leftPadding - rightPadding + 4
        return CGSize(width: notchWidth, height: notchHeight)
    }

    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// Names the same display across reconnects and restarts, unlike `displayID`
    var persistentID: String {
        if let displayID, let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
           let string = CFUUIDCreateString(nil, uuid) {
            return string as String
        }
        return localizedName
    }

    /// Whether this is the built-in display
    var isBuiltinDisplay: Bool {
        guard let displayID else { return false }
        return CGDisplayIsBuiltin(displayID) != 0
    }

    /// The built-in display (with notch on newer MacBooks)
    static var builtin: NSScreen? {
        if let builtin = screens.first(where: { $0.isBuiltinDisplay }) {
            return builtin
        }
        return NSScreen.main
    }

    /// Whether this screen has a physical notch (camera housing)
    var hasPhysicalNotch: Bool {
        safeAreaInsets.top > 0
    }
}
