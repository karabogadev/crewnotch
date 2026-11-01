//
//  KeepAwakeController.swift
//  CrewNotch
//
//  Keeps the Mac from idle-sleeping so agents keep working while the
//  display sleeps or the screen is locked. Closing the lid still sleeps.
//
//  Safety limits: only on power adapter (optional), released below a
//  battery threshold, and switched off after a maximum duration.
//

import Combine
import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import os.log

@MainActor
final class KeepAwakeController: ObservableObject {
    static let shared = KeepAwakeController()

    enum State: Equatable {
        case off
        case active(until: Date)
        /// Enabled, but a safety limit currently lets the Mac sleep
        case paused(reason: String)
    }

    @Published private(set) var state: State = .off

    var isEnabled: Bool { AppSettings.keepAwakeEnabled }

    private var assertionID: IOPMAssertionID = 0
    private var enabledAt: Date?
    private var powerSource: CFRunLoopSource?
    private var timer: Timer?
    private static let logger = Logger(subsystem: "com.karabogadev.crewnotch", category: "KeepAwake")

    private init() {}

    /// Call once at launch. Re-arms Keep Awake if it was left on.
    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let controller = Unmanaged<KeepAwakeController>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { controller.evaluate() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        if isEnabled { enabledAt = Date() }
        evaluate()
    }

    func setEnabled(_ enabled: Bool) {
        AppSettings.keepAwakeEnabled = enabled
        enabledAt = enabled ? Date() : nil
        evaluate()
    }

    func toggle() {
        setEnabled(!isEnabled)
    }

    // MARK: - Evaluation

    private func evaluate() {
        guard isEnabled, let enabledAt else {
            apply(.off)
            return
        }

        let deadline = enabledAt.addingTimeInterval(TimeInterval(AppSettings.keepAwakeMaxHours) * 3600)
        if Date() >= deadline {
            Self.logger.info("Keep Awake reached its time limit")
            AppSettings.keepAwakeEnabled = false
            self.enabledAt = nil
            apply(.off)
            return
        }

        let power = PowerStatus.current()
        if AppSettings.keepAwakeRequiresAdapter && !power.onAdapter {
            apply(.paused(reason: String(localized: "On battery")))
        } else if let level = power.batteryPercent, !power.onAdapter, level < AppSettings.keepAwakeMinBattery {
            apply(.paused(reason: String(localized: "Battery below \(AppSettings.keepAwakeMinBattery)%")))
        } else {
            apply(.active(until: deadline))
        }
    }

    private func apply(_ newState: State) {
        if case .active = newState {
            holdAssertion()
        } else {
            releaseAssertion()
        }
        if state != newState { state = newState }
    }

    private func holdAssertion() {
        guard assertionID == 0 else { return }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "CrewNotch keeps your coding agents running" as CFString,
            &assertionID
        )
        if result != kIOReturnSuccess {
            Self.logger.error("Failed to create power assertion: \(result)")
            assertionID = 0
        }
    }

    private func releaseAssertion() {
        guard assertionID != 0 else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }
}

// MARK: - Power status

private struct PowerStatus {
    var onAdapter: Bool
    var batteryPercent: Int?

    static func current() -> PowerStatus {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return PowerStatus(onAdapter: true, batteryPercent: nil)
        }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let onAdapter = providing != kIOPSBatteryPowerValue

        var percent: Int?
        if let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                      description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                      let current = description[kIOPSCurrentCapacityKey] as? Int,
                      let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
                percent = current * 100 / max
            }
        }
        // Desktops have no battery: treat as always on adapter.
        return PowerStatus(onAdapter: onAdapter || percent == nil, batteryPercent: percent)
    }
}
