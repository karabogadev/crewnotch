import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowManager: WindowManager?
    private var screenObserver: ScreenObserver?

    static var shared: AppDelegate?

    var windowController: NotchWindowController? {
        windowManager?.windowController
    }

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // As a test host the app stays inert: no socket, no hook installs, no
        // window, and no quitting because the real CrewNotch is running.
        if Foundation.ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        if !ensureSingleInstance() {
            NSApplication.shared.terminate(nil)
            return
        }

        AgentRegistry.shared.start()
        try? CommandLineTool.install()
        KeepAwakeController.shared.start()
        UsageMonitor.shared.start()
        UsageAlerts.shared.start()
        AttentionCenter.shared.start()
        RecentSessions.shared.start()
        UpdateController.shared.start()
        DeepSeekMonitor.start()
        DockPresence.apply()

        windowManager = WindowManager()
        _ = windowManager?.setupNotchWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            NotchEffects.shared.play(.launch)
        }

        screenObserver = ScreenObserver { [weak self] in
            self?.handleScreenChange()
        }

        if !AppSettings.hasCompletedOnboarding {
            AppWindows.showOnboarding()
        }

        GlobalHotkey.shared.onPress = { [weak self] in self?.toggleNotchFromKeyboard() }
        GlobalHotkey.shared.registerSaved()
    }

    /// The global shortcut opens the notch with focus, focuses a panel that
    /// popped open by itself, or closes it.
    func toggleNotchFromKeyboard() {
        guard let controller = windowController else { return }
        let viewModel = controller.viewModel
        switch viewModel.status {
        case .opened where !controller.hasFocus:
            controller.takeFocus()
            PanelKeys.shared.arm()
        case .opened where !PanelKeys.shared.approvalsArmed:
            // Opened by hovering: the shortcut makes the approval keys live
            PanelKeys.shared.arm()
        case .opened:
            viewModel.notchClose()
        case .closed, .popping:
            viewModel.notchOpen(reason: .keyboard)
        }
    }

    // MARK: - Dock

    /// Clicking the Dock icon brings back an open window, or opens Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // The notch panel always counts as visible, so `flag` can't tell
        if !AppWindows.showOpenWindow() { AppWindows.showSettings() }
        return false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: String(localized: "Settings…"), action: #selector(openSettings), keyEquivalent: "")
        menu.addItem(withTitle: String(localized: "Token history"), action: #selector(openTokenHistory), keyEquivalent: "")
        menu.addItem(withTitle: String(localized: "Check for Updates…"), action: #selector(checkForUpdates), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func openSettings() { AppWindows.showSettings() }
    @objc private func openTokenHistory() { AppWindows.showTokenHistory() }
    @objc private func checkForUpdates() { UpdateController.shared.checkForUpdates() }

    private func handleScreenChange() {
        _ = windowManager?.setupNotchWindow()
    }

    /// Settings changed where the notch goes: move it there now, without the
    /// screen-change debounce, and flash it so you can spot it.
    func showNotchWhereChosen() {
        _ = windowManager?.setupNotchWindow()
        // A rebuilt window has to be on screen before the effect starts
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let tint = NotchMoment.launch.tint
            NotchEffects.shared.play(.glow, tint: tint)
            NotchEffects.shared.play(.bounce, tint: tint)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        screenObserver = nil
    }

    private func ensureSingleInstance() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.karabogadev.CrewNotch"
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID
        }

        if runningApps.count > 1 {
            if let existingApp = runningApps.first(where: { $0.processIdentifier != getpid() }) {
                existingApp.activate()
            }
            return false
        }

        return true
    }
}
