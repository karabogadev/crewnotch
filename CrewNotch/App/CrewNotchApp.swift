//
//  CrewNotchApp.swift
//  CrewNotch
//
//  Dynamic Island for monitoring AI coding agents
//

import SwiftUI

@main
struct CrewNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // We use a completely custom window, so no default scene needed
        Settings {
            EmptyView()
        }
        .commands {
            // The menu bar shows while CrewNotch is in the Dock and in front;
            // its items open CrewNotch's own windows, not the empty scene above
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { UpdateController.shared.checkForUpdates() }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { AppWindows.showSettings() }
                    .keyboardShortcut(",")
                Button("Token history") { AppWindows.showTokenHistory() }
            }
            CommandGroup(replacing: .newItem) {}
        }
    }
}
