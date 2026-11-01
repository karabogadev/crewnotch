//
//  AppWindows.swift
//  CrewNotch
//
//  Regular windows (Settings, onboarding) for an app that otherwise lives
//  only in the notch. Each window is created once and brought forward.
//

import AppKit
import SwiftUI

@MainActor
enum AppWindows {
    private static var settings: NSWindow?
    private static var onboarding: NSWindow?
    private static var tokenHistory: NSWindow?

    static func showSettings(pane: SettingsPane = .general) {
        SettingsNavigation.shared.pane = pane
        present(&settings, title: "CrewNotch Settings", size: NSSize(width: 760, height: 560)) {
            SettingsView()
        }
    }

    static func showTokenHistory() {
        present(&tokenHistory, title: "Token history", size: NSSize(width: 720, height: 640)) {
            TokenHistoryView()
        }
    }

    static func showOnboarding() {
        present(&onboarding, title: "Welcome to CrewNotch", size: NSSize(width: 640, height: 560), resizable: false) {
            OnboardingView { closeOnboarding() }
        }
    }

    static func closeOnboarding() {
        onboarding?.close()
        onboarding = nil
    }

    private static func present<Content: View>(
        _ slot: inout NSWindow?,
        title: String,
        size: NSSize,
        resizable: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        if slot == nil {
            var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            if resizable { style.insert(.resizable) }
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: style,
                backing: .buffered,
                defer: false
            )
            window.title = title
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: content().preferredColorScheme(.dark))
            window.setContentSize(size)
            window.center()
            slot = window
        }
        NSApp.activate(ignoringOtherApps: true)
        slot?.makeKeyAndOrderFront(nil)
    }
}
