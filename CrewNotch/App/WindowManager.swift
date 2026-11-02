//
//  WindowManager.swift
//  CrewNotch
//
//  Manages the notch window lifecycle
//

import AppKit
import os.log

/// Logger for window management
private let logger = Logger(subsystem: "com.karabogadev.crewnotch", category: "Window")

class WindowManager {
    private(set) var windowController: NotchWindowController?
    private var isInitialLaunch = true
    /// What the current window was built for: another display of the same size
    /// (or one back with a new ID) or a menu bar of another height needs a new one
    private var currentScreen: (id: String, frame: NSRect, notchSize: CGSize)?

    /// Set up or recreate the notch window
    func setupNotchWindow() -> NotchWindowController? {
        // Use ScreenSelector for screen selection
        let screenSelector = ScreenSelector.shared
        screenSelector.refreshScreens()

        guard let screen = screenSelector.selectedScreen else {
            logger.warning("No screen found")
            return nil
        }

        // Skip recreation if screen hasn't meaningfully changed
        let built = (id: screen.persistentID, frame: screen.frame, notchSize: screen.notchSize)
        if let existingController = windowController,
           let current = currentScreen,
           current.id == built.id, current.frame == built.frame, current.notchSize == built.notchSize {
            logger.debug("Screen unchanged, skipping window recreation")
            return existingController
        }

        // Only animate on initial app launch, not on screen changes
        let shouldAnimate = isInitialLaunch
        isInitialLaunch = false

        if let existingController = windowController {
            existingController.window?.orderOut(nil)
            existingController.window?.close()
            windowController = nil
        }

        currentScreen = built
        windowController = NotchWindowController(screen: screen, animateOnLaunch: shouldAnimate)
        windowController?.showWindow(nil)

        return windowController
    }
}
