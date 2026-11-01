//
//  NotchWindowController.swift
//  CrewNotch
//
//  Controls the notch window positioning and lifecycle
//

import AppKit
import Combine
import SwiftUI

class NotchWindowController: NSWindowController {
    let viewModel: NotchViewModel
    private let screen: NSScreen
    private var cancellables = Set<AnyCancellable>()

    init(screen: NSScreen, animateOnLaunch: Bool = true) {
        self.screen = screen

        let screenFrame = screen.frame
        let notchSize = screen.notchSize

        // Window covers full width at top, tall enough for largest content (chat view)
        let windowHeight: CGFloat = 750
        let windowFrame = NSRect(
            x: screenFrame.origin.x,
            y: screenFrame.maxY - windowHeight,
            width: screenFrame.width,
            height: windowHeight
        )

        // Device notch rect - positioned at center
        let deviceNotchRect = CGRect(
            x: (screenFrame.width - notchSize.width) / 2,
            y: 0,
            width: notchSize.width,
            height: notchSize.height
        )

        // Create view model
        self.viewModel = NotchViewModel(
            deviceNotchRect: deviceNotchRect,
            screenRect: screenFrame,
            windowHeight: windowHeight,
            hasPhysicalNotch: screen.hasPhysicalNotch
        )

        // Create the window
        let notchWindow = NotchPanel(
            contentRect: windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init(window: notchWindow)

        // Create the SwiftUI view with pass-through hosting
        let hostingController = NotchViewController(viewModel: viewModel)
        notchWindow.contentViewController = hostingController

        notchWindow.setFrame(windowFrame, display: true)

        // Dynamically toggle mouse event handling based on notch state:
        // - Closed: ignoresMouseEvents = true (clicks pass through to menu bar/apps)
        // - Opened: ignoresMouseEvents = false (buttons inside panel work)
        viewModel.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow, weak viewModel] status in
                switch status {
                case .opened:
                    // Accept mouse events when opened so buttons work
                    notchWindow?.ignoresMouseEvents = false
                    // Don't steal focus when opened by notification (task finished)
                    // Only a deliberate open takes keyboard focus; hovering or the
                    // launch animation must not swallow what you're typing elsewhere
                    if let viewModel, viewModel.openReason == .click || viewModel.openReason == .keyboard {
                        self?.takeFocus()
                    }
                case .closed, .popping:
                    // Ignore mouse events when closed so clicks pass through
                    notchWindow?.ignoresMouseEvents = true
                    PanelKeys.shared.deactivate()
                    self?.returnFocus()
                }
            }
            .store(in: &cancellables)

        // Start with ignoring mouse events (closed state)
        notchWindow.ignoresMouseEvents = true

        // Keep prompts and project names out of screen shares and recordings when asked to
        applySharingPreference()
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySharingPreference() }
            .store(in: &cancellables)

        // Perform boot animation after a brief delay (only on initial launch)
        if animateOnLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.viewModel.performBootAnimation()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Screen sharing

    /// `.none` leaves the panel out of screen sharing, recordings and screenshots.
    private func applySharingPreference() {
        let type: NSWindow.SharingType = AppSettings.hideFromScreenSharing ? .none : .readOnly
        if window?.sharingType != type { window?.sharingType = type }
    }

    // MARK: - Focus

    /// The app that had focus before the panel took it.
    private var previousApp: NSRunningApplication?

    /// Makes the panel the key window so its shortcuts and text fields work.
    func takeFocus() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != Foundation.ProcessInfo.processInfo.processIdentifier {
            previousApp = frontmost
        }
        NSApp.activate(ignoringOtherApps: false)
        window?.makeKey()
        let deliberate = viewModel.openReason == .click || viewModel.openReason == .keyboard
        PanelKeys.shared.activate(for: viewModel, panel: window, deliberate: deliberate)
    }

    var hasFocus: Bool {
        window?.isKeyWindow == true
    }

    /// Gives focus back to the previous app once the panel closes, unless
    /// one of CrewNotch's own windows (Settings, history) took over.
    private func returnFocus() {
        guard let app = previousApp else { return }
        previousApp = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let ownWindowShown = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
            guard NSApp.isActive, !ownWindowShown, !app.isTerminated else { return }
            app.activate()
        }
    }
}
