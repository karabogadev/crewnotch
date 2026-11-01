//
//  UpdateController.swift
//  CrewNotch
//
//  Keeps CrewNotch up to date with Sparkle. The appcast lives on the website
//  (karabogadev.github.io/crewnotch/appcast.xml) and points at the notarized
//  DMG on GitHub Releases; each update is verified against the EdDSA key in
//  Info.plist before it's installed.
//

import AppKit
import Combine
import Sparkle

@MainActor
final class UpdateController: NSObject, ObservableObject {
    static let shared = UpdateController()

    @Published private(set) var canCheckForUpdates = false

    private var controller: SPUStandardUpdaterController!

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }

    private var updater: SPUUpdater { controller.updater }

    /// Call once at launch so scheduled checks start.
    func start() {}

    func checkForUpdates() {
        // An accessory app has no menu bar; bring the update window forward.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue; objectWillChange.send() }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set { updater.automaticallyDownloadsUpdates = newValue; objectWillChange.send() }
    }
}

extension UpdateController: SPUStandardUserDriverDelegate {
    /// CrewNotch runs in the background, so let Sparkle remind gently instead
    /// of popping a window over whatever the user is doing.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        Task { @MainActor in NSApp.activate(ignoringOtherApps: true) }
    }
}
