//
//  DockPresence.swift
//  CrewNotch
//
//  Whether CrewNotch shows in the Dock (with a menu bar and ⌘Q while in
//  front) or lives only in the notch. Info.plist keeps LSUIElement, so a
//  user who hides it never sees the Dock icon flash at launch.
//

import AppKit

@MainActor
enum DockPresence {
    static func apply() {
        let policy: NSApplication.ActivationPolicy = AppSettings.showInDock ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // Leaving the Dock deactivates the app; keep the window the user is in in front
        if policy == .accessory {
            DispatchQueue.main.async { AppWindows.showOpenWindow() }
        }
    }
}
