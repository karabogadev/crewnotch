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
    }
}
