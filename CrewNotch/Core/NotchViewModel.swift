//
//  NotchViewModel.swift
//  CrewNotch
//
//  State management for the dynamic island
//

import AppKit
import Combine
import SwiftUI

enum NotchStatus: Equatable {
    case closed
    case opened
    case popping
}

enum NotchOpenReason {
    case click
    case hover
    /// The global shortcut
    case keyboard
    case notification
    case boot
    case unknown
}

enum NotchContentType: Equatable {
    case instances
    case chat(SessionState)
    /// Short "Finished" notice for a session that just completed
    case banner(SessionState)
    /// Short notice not tied to a session (plan limits)
    case notice(NotchNotice)

    var id: String {
        switch self {
        case .instances: return "instances"
        case .chat(let session): return "chat-\(session.sessionId)"
        case .banner(let session): return "banner-\(session.sessionId)"
        case .notice(let notice): return "notice-\(notice.id)"
        }
    }
}

@MainActor
class NotchViewModel: ObservableObject {
    // MARK: - Published State

    @Published var status: NotchStatus = .closed
    @Published var openReason: NotchOpenReason = .unknown
    @Published var contentType: NotchContentType = .instances
    @Published var isHovering: Bool = false
    /// Measured height of the session list and usage footer
    @Published var listContentHeight: CGFloat = 0
    /// A request is waiting: its card (command, diff, question) gets room beyond the row limit
    @Published var showsRequest = false
    /// The opened panel's size as last drawn, for hit testing (zero until measured)
    var renderedPanelSize: CGSize = .zero

    /// Limits for dragging the session panel's size
    var panelWidthRange: ClosedRange<CGFloat> { 380...max(380, min(screenRect.width * 0.7, 900)) }
    var panelHeightRange: ClosedRange<CGFloat> { 200...(windowHeight - 10) }

    /// Where the opened panel is on screen: as drawn once measured, else as planned
    var openedPanelScreenRect: CGRect {
        let size = renderedPanelSize.height > deviceNotchRect.height ? renderedPanelSize : openedSize
        return geometry.panelScreenRect(for: size)
    }

    // MARK: - Geometry

    /// Published so the notch follows a position dragged in Settings
    @Published private(set) var geometry: NotchGeometry
    /// Pressed and held, the closed notch follows the pointer along the top edge
    @Published private(set) var isRepositioning = false
    /// Saves a position the notch was dragged to; set only where it can move
    /// (displays without a camera housing)
    var onReposition: ((CGFloat) -> Void)?
    let spacing: CGFloat = 12
    let hasPhysicalNotch: Bool

    var deviceNotchRect: CGRect { geometry.deviceNotchRect }
    var screenRect: CGRect { geometry.screenRect }
    var windowHeight: CGFloat { geometry.windowHeight }

    /// Dynamic opened size based on content type
    var openedSize: CGSize {
        switch contentType {
        case .chat:
            // Large size for chat view
            return CGSize(
                width: min(screenRect.width * 0.5, 600),
                height: 580
            )
        case .instances:
            // Fit the content, up to the height the user dragged to or the chosen
            // number of rows (the list scrolls past that)
            let defaults = UserDefaults.standard
            let customWidth = CGFloat(defaults.double(forKey: AppearanceKeys.panelWidth))
            let customHeight = CGFloat(defaults.double(forKey: AppearanceKeys.panelHeight))
            let rows = min(max(AppearanceKeys.rowsAtOnceValue, 3), 10)
            let cap = customHeight > 0 ? customHeight : CGFloat(rows) * 52 + 110
            let maxHeight = min(cap + (showsRequest ? 260 : 0), panelHeightRange.upperBound)
            let fitted = deviceNotchRect.height + listContentHeight + 26
            let width = customWidth > 0 ? customWidth.clamped(to: panelWidthRange) : min(screenRect.width * 0.4, 480)
            return CGSize(
                width: width,
                height: listContentHeight > 0 ? min(maxHeight, max(150, fitted)) : maxHeight
            )
        case .banner, .notice:
            return CGSize(
                width: min(screenRect.width * 0.32, 400),
                height: deviceNotchRect.height + 64
            )
        }
    }

    // MARK: - Animation

    var animation: Animation {
        .easeOut(duration: 0.25)
    }

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private let events = EventMonitors.shared
    private var hoverTimer: DispatchWorkItem?
    /// A press on the closed notch that may become a move: where it started and the notch's center then
    private var press: (location: CGPoint, centerX: CGFloat)?
    private var holdTimer: DispatchWorkItem?
    private var isSnapped = false

    // MARK: - Initialization

    init(notchSize: CGSize, screenRect: CGRect, windowHeight: CGFloat, position: CGFloat, hasPhysicalNotch: Bool) {
        self.geometry = NotchGeometry(
            notchSize: notchSize,
            screenRect: screenRect,
            windowHeight: windowHeight,
            position: position
        )
        self.hasPhysicalNotch = hasPhysicalNotch
        setupEventHandlers()
    }

    /// Moves the notch along the top edge (0 left, 0.5 middle, 1 right)
    func moveNotch(to position: CGFloat) {
        guard position != geometry.position else { return }
        geometry.position = position
    }

    // MARK: - Event Handling

    private func setupEventHandlers() {
        events.mouseLocation
            .throttle(for: .milliseconds(50), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] location in
                self?.handleMouseMove(location)
            }
            .store(in: &cancellables)

        events.mouseDown
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleMouseDown()
            }
            .store(in: &cancellables)

        events.mouseDragged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                self?.handleMouseDragged(location)
            }
            .store(in: &cancellables)

        events.mouseUp
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleMouseUp()
            }
            .store(in: &cancellables)
    }

    /// Whether we're in chat mode (sticky behavior)
    private var isInChatMode: Bool {
        if case .chat = contentType { return true }
        return false
    }

    /// The chat session we're viewing (persists across close/open)
    private var currentChatSession: SessionState?

    private func handleMouseMove(_ location: CGPoint) {
        let inNotch = geometry.isPointInNotch(location)
        let inOpened = status == .opened && openedPanelScreenRect.contains(location)

        let newHovering = inNotch || inOpened

        // Only update if changed to prevent unnecessary re-renders
        guard newHovering != isHovering else { return }

        isHovering = newHovering

        // Cancel any pending hover timer
        hoverTimer?.cancel()
        hoverTimer = nil

        // Start hover timer to auto-expand after 1 second
        if isHovering && (status == .closed || status == .popping) {
            let workItem = DispatchWorkItem { [weak self] in
                // Holding the notch to move it isn't hovering
                guard let self = self, self.isHovering, self.press == nil else { return }
                self.notchOpen(reason: .hover)
            }
            hoverTimer = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
        }
    }

    private func handleMouseDown() {
        let location = NSEvent.mouseLocation

        switch status {
        case .opened:
            if !openedPanelScreenRect.contains(location) {
                notchClose()
                // Re-post the click so it reaches the window/app behind us
                repostClickAt(location)
            } else if geometry.notchScreenRect.contains(location) {
                // Clicking notch while opened - only close if NOT in chat mode
                if !isInChatMode {
                    notchClose()
                }
            }
        case .closed, .popping:
            guard geometry.isPointInNotch(location) else { return }
            if onReposition == nil {
                notchOpen(reason: .click)
            } else {
                // Movable: a click opens on release, so a press can still become a move
                press = (location, geometry.deviceNotchRect.midX)
                let hold = DispatchWorkItem { [weak self] in self?.startRepositioning() }
                holdTimer = hold
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: hold)
            }
        }
    }

    // MARK: - Moving the notch

    private func handleMouseDragged(_ location: CGPoint) {
        guard let press else { return }
        if !isRepositioning {
            // Dragging right away moves it too, without waiting for the hold
            guard abs(location.x - press.location.x) > 4 else { return }
            startRepositioning()
        }

        var centerX = press.centerX + location.x - press.location.x
        let snapped = abs(centerX - screenRect.width / 2) < 16
        if snapped { centerX = screenRect.width / 2 }
        if snapped && !isSnapped {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        isSnapped = snapped

        let position = NotchGeometry.position(forCenterX: centerX, notchWidth: geometry.notchSize.width, screenWidth: screenRect.width)
        moveNotch(to: position)
        onReposition?(position)
    }

    private func handleMouseUp() {
        guard press != nil else { return }
        let wasClick = !isRepositioning
        press = nil
        holdTimer?.cancel()
        holdTimer = nil
        isRepositioning = false
        isSnapped = false
        if wasClick, status != .opened { notchOpen(reason: .click) }
    }

    private func startRepositioning() {
        guard press != nil, !isRepositioning else { return }
        holdTimer?.cancel()
        hoverTimer?.cancel()
        isRepositioning = true
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    /// Re-posts a mouse click at the given screen location so it reaches windows behind us
    private func repostClickAt(_ location: CGPoint) {
        // Small delay to let the window's ignoresMouseEvents update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // CGEvent coordinates start at the primary display's top-left corner
            guard let primary = NSScreen.screens.first else { return }
            let cgPoint = CGPoint(x: location.x, y: primary.frame.maxY - location.y)

            // Create and post mouse down event
            if let mouseDown = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDown,
                mouseCursorPosition: cgPoint,
                mouseButton: .left
            ) {
                mouseDown.post(tap: .cghidEventTap)
            }

            // Create and post mouse up event
            if let mouseUp = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseUp,
                mouseCursorPosition: cgPoint,
                mouseButton: .left
            ) {
                mouseUp.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - Actions

    func notchOpen(reason: NotchOpenReason = .unknown) {
        openReason = reason
        status = .opened

        // Don't restore chat on notification - show instances list instead
        if reason == .notification {
            currentChatSession = nil
            return
        }

        // Restore chat session if we had one open before
        if let chatSession = currentChatSession {
            // Avoid unnecessary updates if already showing this chat
            if case .chat(let current) = contentType, current.sessionId == chatSession.sessionId {
                return
            }
            contentType = .chat(chatSession)
        }
    }

    func notchClose() {
        // Save chat session before closing if in chat mode
        if case .chat(let session) = contentType {
            currentChatSession = session
        }
        status = .closed
        contentType = .instances
    }

    /// Drops the notch open with a "Finished" notice, then closes it again
    /// unless the pointer is over it.
    func showBanner(for session: SessionState, duration: TimeInterval = 4) {
        guard status == .closed else { return }
        contentType = .banner(session)
        openReason = .notification
        status = .opened
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, case .banner = self.contentType, !self.isHovering else { return }
            self.notchClose()
        }
    }

    /// Drops the notch open with a notice, then closes it again unless the pointer is over it.
    func showNotice(_ notice: NotchNotice, duration: TimeInterval = 5) {
        guard status == .closed else { return }
        contentType = .notice(notice)
        openReason = .notification
        status = .opened
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, case .notice = self.contentType, !self.isHovering else { return }
            self.notchClose()
        }
    }

    func notchPop() {
        guard status == .closed else { return }
        status = .popping
    }

    func notchUnpop() {
        guard status == .popping else { return }
        status = .closed
    }

    func showChat(for session: SessionState) {
        // Avoid unnecessary updates if already showing this chat
        if case .chat(let current) = contentType, current.sessionId == session.sessionId {
            return
        }
        contentType = .chat(session)
    }

    /// Go back to instances list and clear saved chat state
    func exitChat() {
        currentChatSession = nil
        contentType = .instances
    }

    /// Perform boot animation: expand briefly then collapse
    func performBootAnimation() {
        notchOpen(reason: .boot)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, self.openReason == .boot else { return }
            self.notchClose()
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
