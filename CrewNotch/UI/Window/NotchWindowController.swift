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

        // Create view model
        self.viewModel = NotchViewModel(
            notchSize: notchSize,
            screenRect: screenFrame,
            windowHeight: windowHeight,
            position: ScreenSelector.shared.position(for: screen),
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

        // Mouse events reach the window only where they're ours:
        // - Opened: always, so buttons inside the panel work
        // - Closed: clicks pass through to the menu bar and apps, except on a
        //   display without a camera housing while the pointer is on the notch.
        //   There the menu bar runs under it (a moved notch can cover app menus),
        //   and pressing and holding it moves it.
        let hasPhysicalNotch = screen.hasPhysicalNotch
        Publishers.CombineLatest3(viewModel.$status, viewModel.$isHovering, viewModel.$isRepositioning)
            .receive(on: DispatchQueue.main)
            .sink { [weak notchWindow] status, hovering, moving in
                notchWindow?.ignoresMouseEvents = status != .opened && (hasPhysicalNotch || !(hovering || moving))
            }
            .store(in: &cancellables)

        if !hasPhysicalNotch {
            viewModel.onReposition = { position in
                ScreenSelector.shared.setPosition(position, for: screen)
            }
        }

        viewModel.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak viewModel] status in
                switch status {
                case .opened:
                    // Don't steal focus when opened by notification (task finished)
                    // Only a deliberate open takes keyboard focus; hovering or the
                    // launch animation must not swallow what you're typing elsewhere
                    if let viewModel, viewModel.openReason == .click || viewModel.openReason == .keyboard {
                        self?.takeFocus()
                    }
                case .closed, .popping:
                    PanelKeys.shared.deactivate()
                    self?.returnFocus()
                }
            }
            .store(in: &cancellables)

        // Follow the position dragged in Settings (on the next pass, once the
        // published dictionary holds the new value)
        ScreenSelector.shared.$positions
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                viewModel.moveNotch(to: ScreenSelector.shared.position(for: self.screen))
            }
            .store(in: &cancellables)

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
