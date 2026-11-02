//
//  ScreenSelector.swift
//  CrewNotch
//
//  Manages screen selection state and persistence
//

import AppKit
import Combine
import Foundation

/// Strategy for selecting which screen to use
enum ScreenSelectionMode: String, Codable {
    case automatic       // Prefer built-in display, fall back to main
    case specificScreen  // User selected a specific screen
}

/// Persistent identifier for a screen
struct ScreenIdentifier: Codable, Equatable, Hashable {
    let displayID: CGDirectDisplayID?
    let localizedName: String

    /// Create identifier from NSScreen
    init(screen: NSScreen) {
        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            self.displayID = screenNumber
        } else {
            self.displayID = nil
        }
        self.localizedName = screen.localizedName
    }

    /// Check if this identifier matches a given screen
    func matches(_ screen: NSScreen) -> Bool {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return localizedName == screen.localizedName
        }
        // Primary match: displayID (most reliable when connected)
        if let savedID = displayID, savedID == screenNumber {
            return true
        }
        // Fallback: name match (for reconnected displays with new IDs)
        return localizedName == screen.localizedName
    }
}

@MainActor
class ScreenSelector: ObservableObject {
    static let shared = ScreenSelector()

    // MARK: - Published State
    @Published private(set) var availableScreens: [NSScreen] = []
    @Published private(set) var selectedScreen: NSScreen?
    @Published var selectionMode: ScreenSelectionMode = .automatic
    /// Where the notch sits on each display without a camera housing
    /// (0 left, 0.5 middle, 1 right), keyed by `NSScreen.persistentID`
    @Published private(set) var positions: [String: Double] = [:]

    // MARK: - UserDefaults Keys
    private let modeKey = "screenSelectionMode"
    private let screenIdentifierKey = "selectedScreenIdentifier"
    private let positionsKey = "notchPositions"

    // MARK: - Private State
    private var savedIdentifier: ScreenIdentifier?

    private init() {
        loadPreferences()
        refreshScreens()
    }

    // MARK: - Public API

    /// Refresh the available screens list
    func refreshScreens() {
        availableScreens = NSScreen.screens
        selectedScreen = resolveSelectedScreen()
    }

    /// Select a specific screen
    func selectScreen(_ screen: NSScreen) {
        selectionMode = .specificScreen
        savedIdentifier = ScreenIdentifier(screen: screen)
        selectedScreen = screen
        savePreferences()
    }

    /// Reset to automatic selection
    func selectAutomatic() {
        selectionMode = .automatic
        savedIdentifier = nil
        selectedScreen = resolveSelectedScreen()
        savePreferences()
    }

    /// Check if a screen is currently selected
    func isSelected(_ screen: NSScreen) -> Bool {
        guard let selected = selectedScreen else { return false }
        return screen.displayID == selected.displayID
    }

    /// Where the notch sits on a display. One with a camera housing keeps it in the middle.
    func position(for screen: NSScreen) -> CGFloat {
        guard !screen.hasPhysicalNotch else { return 0.5 }
        return positions[screen.persistentID].map { CGFloat($0) } ?? 0.5
    }

    func setPosition(_ position: CGFloat, for screen: NSScreen) {
        guard !screen.hasPhysicalNotch else { return }
        positions[screen.persistentID] = Double(position)
        UserDefaults.standard.set(positions, forKey: positionsKey)
    }

    /// The position the Monitor preview shows: the chosen display's when it has
    /// no camera housing, else the first connected display without one
    var monitorPreviewPosition: CGFloat {
        let monitor = selectedScreen.flatMap { $0.hasPhysicalNotch ? nil : $0 }
            ?? availableScreens.first { !$0.hasPhysicalNotch }
        return monitor.map(position(for:)) ?? 0.5
    }

    // MARK: - Private Methods

    private func resolveSelectedScreen() -> NSScreen? {
        switch selectionMode {
        case .automatic:
            return NSScreen.builtin ?? NSScreen.main

        case .specificScreen:
            // Try to find the saved screen
            if let identifier = savedIdentifier,
               let match = availableScreens.first(where: { identifier.matches($0) }) {
                return match
            }
            // Saved screen not found - fall back to automatic
            return NSScreen.builtin ?? NSScreen.main
        }
    }

    private func loadPreferences() {
        if let modeString = UserDefaults.standard.string(forKey: modeKey),
           let mode = ScreenSelectionMode(rawValue: modeString) {
            selectionMode = mode
        }

        if let data = UserDefaults.standard.data(forKey: screenIdentifierKey),
           let identifier = try? JSONDecoder().decode(ScreenIdentifier.self, from: data) {
            savedIdentifier = identifier
        }

        positions = UserDefaults.standard.dictionary(forKey: positionsKey) as? [String: Double] ?? [:]
    }

    private func savePreferences() {
        UserDefaults.standard.set(selectionMode.rawValue, forKey: modeKey)

        if let identifier = savedIdentifier,
           let data = try? JSONEncoder().encode(identifier) {
            UserDefaults.standard.set(data, forKey: screenIdentifierKey)
        } else {
            UserDefaults.standard.removeObject(forKey: screenIdentifierKey)
        }
    }
}
