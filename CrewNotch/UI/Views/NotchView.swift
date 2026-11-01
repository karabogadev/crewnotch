//
//  NotchView.swift
//  CrewNotch
//
//  The main dynamic island SwiftUI view with accurate notch shape
//

import AppKit
import CoreGraphics
import SwiftUI

// Corner radius constants
private let cornerRadiusInsets = (
    opened: (top: CGFloat(19), bottom: CGFloat(24)),
    closed: (top: CGFloat(6), bottom: CGFloat(14))
)

struct NotchView: View {
    @ObservedObject var viewModel: NotchViewModel
    @StateObject private var sessionMonitor = SessionMonitor()
    @StateObject private var activityCoordinator = NotchActivityCoordinator.shared
    @ObservedObject private var keepAwake = KeepAwakeController.shared
    @ObservedObject private var effects = NotchEffects.shared
    @State private var bounceScale: CGFloat = 1
    @ObservedObject private var usageMonitor = UsageMonitor.shared
    @AppStorage(AppearanceKeys.closedShowsWorking) private var closedShowsWorking = true
    @AppStorage(AppearanceKeys.closedShowsNotifications) private var closedShowsNotifications = true
    @AppStorage(AppearanceKeys.closedShowsUsage) private var closedShowsUsage = false
    @AppStorage(AppearanceKeys.idleNotch) private var idleNotch: IdleNotchBehavior = .hide
    @AppStorage("usagePercentMode") private var usagePercentMode: UsagePercentMode = .used
    @State private var previousPendingIds: Set<String> = []
    @State private var previousWaitingForInputIds: Set<String> = []
    // Keyed by sessionId, not stableId: the pid in stableId can change between
    // events of one session, which made a finished turn sound twice.
    @State private var waitingForInputTimestamps: [String: Date] = [:]  // sessionId -> when it entered waitingForInput
    @State private var isVisible: Bool = false
    @State private var isHovering: Bool = false

    @Namespace private var activityNamespace

    /// Whether any Claude session is currently processing or compacting
    private var isAnyProcessing: Bool {
        sessionMonitor.instances.contains { $0.phase == .processing || $0.phase == .compacting }
    }

    /// Whether any Claude session has a pending permission request
    private var hasPendingPermission: Bool {
        sessionMonitor.instances.contains { $0.phase.isWaitingForApproval }
    }

    /// Whether any Claude session is waiting for user input (done/ready state) within the display window
    private var hasWaitingForInput: Bool {
        let now = Date()
        let displayDuration: TimeInterval = 30  // Show checkmark for 30 seconds

        return sessionMonitor.instances.contains { session in
            guard session.phase == .waitingForInput else { return false }
            // Only show if within the 30-second display window
            if let enteredAt = waitingForInputTimestamps[session.sessionId] {
                return now.timeIntervalSince(enteredAt) < displayDuration
            }
            return false
        }
    }

    /// Overall crew state for the closed notch: needs you > working > just finished
    /// (filtered by the "While closed" settings)
    private var crewActivity: CrewActivity? {
        if hasPendingPermission && closedShowsNotifications { return .needsYou }
        if isAnyProcessing && closedShowsWorking { return .working }
        if hasWaitingForInput && closedShowsNotifications { return .finished }
        return nil
    }

    /// The first visible provider's limit closest to running out
    private var headlineUsage: (agent: AgentKind, limit: UsageLimit)? {
        guard AppSettings.showPlanUsage else { return nil }
        return UsagePreferences.apply(to: usageMonitor.providers)
            .lazy.compactMap { usage in usage.headline.map { (usage.agent, $0) } }.first
    }

    /// Quiet notch: nothing going on, but the user wants plan usage shown
    private var showsQuietUsage: Bool {
        crewActivity == nil && idleNotch == .showUsage && headlineUsage != nil
    }

    /// Whether the usage percentage appears beside the status in the closed notch
    private var showsClosedUsage: Bool {
        headlineUsage != nil && (showsQuietUsage || (closedShowsUsage && crewActivity != nil))
    }

    private var headlineUsageText: String {
        guard let limit = headlineUsage?.limit else { return "" }
        let value = usagePercentMode == .used ? limit.usedPercent : 100 - limit.usedPercent
        return "\(Int(value.rounded()))%"
    }

    /// The session whose agent the closed notch shows: the one that matters most right now
    private var leadSession: SessionState? {
        let sessions = sessionMonitor.instances
        return sessions.first { $0.phase.isWaitingForApproval }
            ?? sessions.filter { $0.phase.isActive }.max { $0.lastActivity < $1.lastActivity }
            ?? sessions.filter { $0.phase == .waitingForInput }.max { $0.lastActivity < $1.lastActivity }
    }

    /// Agents that are working or need you, shown as a count next to the lead agent
    private var busyCount: Int {
        sessionMonitor.instances.filter { $0.phase.isActive || $0.phase.isWaitingForApproval }.count
    }

    /// One-line summary for the opened header, e.g. "2 working · 1 needs you"
    private var crewSummary: String {
        let sessions = sessionMonitor.instances
        let needsYou = sessions.filter { $0.phase.isWaitingForApproval }.count
        let working = sessions.filter { $0.phase.isActive }.count
        let done = sessions.filter { $0.phase == .waitingForInput }.count
        var parts: [String] = []
        if needsYou > 0 { parts.append(String(localized: "\(needsYou) needs you")) }
        if working > 0 { parts.append(String(localized: "\(working) working")) }
        if done > 0 { parts.append(String(localized: "\(done) done")) }
        if parts.isEmpty { return sessions.isEmpty ? String(localized: "No agents running") : String(localized: "All quiet") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Sizing

    private var closedNotchSize: CGSize {
        CGSize(
            width: viewModel.deviceNotchRect.width,
            height: viewModel.deviceNotchRect.height
        )
    }

    /// Extra width for expanding activities (like Dynamic Island)
    private var expansionWidth: CGFloat {
        guard showClosedActivity else { return 0 }
        return 2 * max(0, closedNotchSize.height - 12) + 20 + countBadgeWidth + usageWidth
    }

    /// Extra room on the right for the usage percentage
    private var usageWidth: CGFloat {
        showsClosedUsage ? 28 : 0
    }

    /// Extra room on the left for the "+N" badge when several agents are busy
    private var countBadgeWidth: CGFloat {
        busyCount > 1 ? 16 : 0
    }

    private var notchSize: CGSize {
        switch viewModel.status {
        case .closed, .popping:
            return closedNotchSize
        case .opened:
            return viewModel.openedSize
        }
    }

    /// Width of the closed content (notch + any expansion)
    private var closedContentWidth: CGFloat {
        closedNotchSize.width + expansionWidth
    }

    // MARK: - Corner Radii

    private var topCornerRadius: CGFloat {
        viewModel.status == .opened
            ? cornerRadiusInsets.opened.top
            : cornerRadiusInsets.closed.top
    }

    private var bottomCornerRadius: CGFloat {
        viewModel.status == .opened
            ? cornerRadiusInsets.opened.bottom
            : cornerRadiusInsets.closed.bottom
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )
    }

    // Animation springs
    private let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
    private let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)

    // MARK: - Body

    @AppStorage(AppearanceKeys.theme) private var theme: PanelTheme = .system
    @Environment(\.colorScheme) private var systemScheme

    private var panelScheme: ColorScheme { theme.colorScheme ?? systemScheme }

    var body: some View {
        ZStack(alignment: .top) {
            // Outer container does NOT receive hits - only the notch content does
            VStack(spacing: 0) {
                notchLayout
                    .frame(
                        maxWidth: viewModel.status == .opened ? notchSize.width : nil,
                        alignment: .top
                    )
                    .padding(
                        .horizontal,
                        viewModel.status == .opened
                            ? cornerRadiusInsets.opened.top
                            : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], viewModel.status == .opened ? 12 : 0)
                    .background(PanelBackground(isOpened: viewModel.status == .opened))
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(viewModel.status == .opened ? Color.canvas : .black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .overlay { NotchEffectsOverlay(effects: effects) }
                    .scaleEffect(bounceScale, anchor: .top)
                    .shadow(
                        color: (viewModel.status == .opened || isHovering) ? .black.opacity(panelScheme == .light && viewModel.status == .opened ? 0.25 : 0.7) : .clear,
                        radius: 6
                    )
                    .frame(
                        maxWidth: viewModel.status == .opened ? notchSize.width : nil,
                        maxHeight: viewModel.status == .opened ? notchSize.height : nil,
                        alignment: .top
                    )
                    .animation(viewModel.status == .opened ? openAnimation : closeAnimation, value: viewModel.status)
                    .animation(openAnimation, value: notchSize) // Animate container size changes between content types
                    .animation(.smooth, value: activityCoordinator.expandingActivity)
                    .animation(.smooth, value: hasPendingPermission)
                    .animation(.smooth, value: hasWaitingForInput)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                            isHovering = hovering
                        }
                    }
                    .onTapGesture {
                        if viewModel.status != .opened {
                            viewModel.notchOpen(reason: .click)
                        }
                    }
            }
        }
        .opacity(isVisible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The closed notch sits on the camera housing, so only the opened panel takes the theme
        .environment(\.colorScheme, viewModel.status == .opened ? panelScheme : .dark)
        // The notch is anchored to the hardware cutout, so it never mirrors
        .environment(\.layoutDirection, .leftToRight)
        .onAppear {
            sessionMonitor.startMonitoring()
            // On non-notched devices, keep visible so users have a target to interact with
            if !viewModel.hasPhysicalNotch {
                isVisible = true
            }
        }
        .onChange(of: viewModel.status) { oldStatus, newStatus in
            handleStatusChange(from: oldStatus, to: newStatus)
        }
        .onChange(of: effects.current) { _, effect in
            // Effects must be visible even when the notch would otherwise hide
            if effect != nil { isVisible = true } else { handleProcessingChange() }
        }
        .onChange(of: showsQuietUsage) { _, _ in handleProcessingChange() }
        .onChange(of: effects.bounceCount) { _, _ in
            let speed = NotchEffects.speed.multiplier
            withAnimation(.spring(response: 0.18 * speed, dampingFraction: 0.45)) { bounceScale = 1.08 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16 * speed) {
                withAnimation(.spring(response: 0.3 * speed, dampingFraction: 0.5)) { bounceScale = 1 }
            }
        }
        .onChange(of: sessionMonitor.pendingInstances) { _, sessions in
            handlePendingSessionsChange(sessions)
        }
        .onChange(of: sessionMonitor.instances) { _, instances in
            handleProcessingChange()
            handleWaitingForInputChange(instances)
        }
    }

    // MARK: - Notch Layout

    /// Whether to show the expanded closed state (processing, pending permission, or waiting for input)
    private var showClosedActivity: Bool {
        crewActivity != nil || showsQuietUsage
    }

    @ViewBuilder
    private var notchLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row - always present, contains crab and spinner that persist across states
            headerRow
                .frame(height: max(24, closedNotchSize.height))

            // Main content only when opened
            if viewModel.status == .opened {
                contentView
                    .frame(width: notchSize.width - 24) // Fixed width to prevent reflow
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.8, anchor: .top)
                                .combined(with: .opacity)
                                .animation(.smooth(duration: 0.35)),
                            removal: .opacity.animation(.easeOut(duration: 0.15))
                        )
                    )
            }
        }
    }

    // MARK: - Header Row (persists across states)

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: 0) {
            // Left side - lead agent + optional busy count (visible when processing, pending, or waiting for input)
            if showClosedActivity, viewModel.status != .opened,
               let leadAgent = crewActivity != nil ? leadSession?.agent : headlineUsage?.agent {
                HStack(spacing: 3) {
                    AgentIcon(agent: leadAgent, size: 14)
                        .matchedGeometryEffect(id: "lead-agent", in: activityNamespace, isSource: showClosedActivity)

                    if busyCount > 1 && crewActivity != nil && viewModel.status != .opened {
                        Text("+\(busyCount - 1)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundColor(.ink.opacity(0.6))
                    }
                }
                .frame(width: viewModel.status == .opened ? nil : sideWidth + countBadgeWidth)
                .padding(.leading, viewModel.status == .opened ? 8 : 0)
            }

            // Center content
            if viewModel.status == .opened {
                // Opened: show header content
                openedHeaderContent
            } else if !showClosedActivity {
                // Closed without activity: empty space
                Rectangle()
                    .fill(.clear)
                    .frame(width: closedNotchSize.width - 20)
            } else {
                // Closed with activity: black spacer (with optional bounce)
                Rectangle()
                    .fill(.black)
                    .frame(width: closedNotchSize.width - cornerRadiusInsets.closed.top)
            }

            // Right side - unified status glyph for crew activity
            if showClosedActivity, viewModel.status != .opened {
                HStack(spacing: 4) {
                    if showsClosedUsage && viewModel.status != .opened {
                        Text(headlineUsageText)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.ink.opacity(0.7))
                    }
                    if let activity = crewActivity {
                        NotchStatusGlyph(status: activity)
                            .id(activity)
                    }
                }
                    .matchedGeometryEffect(id: "status", in: activityNamespace, isSource: showClosedActivity)
                    .frame(width: viewModel.status == .opened ? 20 : sideWidth + usageWidth)
                    .padding(.trailing, viewModel.status == .opened ? 0 : 4)
            }
        }
        .frame(height: closedNotchSize.height)
    }

    private var sideWidth: CGFloat {
        max(0, closedNotchSize.height - 12) + 10
    }

    // MARK: - Opened Header Content

    @ViewBuilder
    private var openedHeaderContent: some View {
        HStack(spacing: 12) {
            Text(crewSummary)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.ink.opacity(0.55))
                .lineLimit(1)
                .padding(.leading, 8)

            Spacer()

            Button {
                viewModel.notchClose()
                AppWindows.showTokenHistory()
            } label: {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.ink.opacity(0.4))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Token history")

            KeepAwakeButton(controller: keepAwake)

            // Settings
            Button {
                viewModel.notchClose()
                AppWindows.showSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.ink.opacity(0.4))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .help("Settings")
            .buttonStyle(.plain)
        }
    }

    // MARK: - Content View (Opened State)

    @ViewBuilder
    private var contentView: some View {
        Group {
            switch viewModel.contentType {
            case .instances:
                SessionListView(
                    sessionMonitor: sessionMonitor,
                    viewModel: viewModel
                )
            case .banner(let session):
                FinishedBanner(session: session) {
                    viewModel.notchClose()
                    Task { await SessionFocuser.focus(session) }
                }
            case .notice(let notice):
                NoticeBanner(notice: notice) {
                    viewModel.contentType = .instances
                }
            case .chat(let session):
                ChatView(
                    sessionId: session.sessionId,
                    initialSession: session,
                    sessionMonitor: sessionMonitor,
                    viewModel: viewModel
                )
                // Force a fresh ChatView when switching sessions — otherwise
                // @State (history, session, scroll position) leaks from the
                // previous session and the view shows the wrong conversation.
                // Keyed on sessionId only (not the whole SessionState) so
                // per-event updates still reuse the view.
                .id(session.sessionId)
            }
        }
        .frame(width: notchSize.width - 24) // Fixed width to prevent text reflow
    }

    // MARK: - Event Handlers

    private func handleProcessingChange() {
        if isAnyProcessing || hasPendingPermission {
            // Show claude activity when processing or waiting for permission
            activityCoordinator.showActivity(type: .claude)
            isVisible = true
        } else if hasWaitingForInput || showsQuietUsage {
            // Keep visible for waiting-for-input (or the quiet usage notch) without the spinner
            activityCoordinator.hideActivity()
            isVisible = true
        } else {
            // Hide activity when done
            activityCoordinator.hideActivity()

            // Delay hiding the notch until animation completes
            // Don't hide on non-notched devices - users need a visible target
            if viewModel.status == .closed && viewModel.hasPhysicalNotch {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if !isAnyProcessing && !hasPendingPermission && !hasWaitingForInput && !showsQuietUsage && viewModel.status == .closed {
                        isVisible = false
                    }
                }
            }
        }
    }

    private func handleStatusChange(from oldStatus: NotchStatus, to newStatus: NotchStatus) {
        if newStatus == .opened && oldStatus != .opened {
            effects.play(.open)
        }
        switch newStatus {
        case .opened, .popping:
            isVisible = true
            // Clear waiting-for-input timestamps only when manually opened (user acknowledged)
            if viewModel.openReason == .click || viewModel.openReason == .hover || viewModel.openReason == .keyboard {
                waitingForInputTimestamps.removeAll()
            }
        case .closed:
            // Don't hide on non-notched devices - users need a visible target
            guard viewModel.hasPhysicalNotch else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if viewModel.status == .closed && !isAnyProcessing && !hasPendingPermission && !hasWaitingForInput && !showsQuietUsage && !activityCoordinator.expandingActivity.show {
                    isVisible = false
                }
            }
        }
    }

    private func handlePendingSessionsChange(_ sessions: [SessionState]) {
        let currentIds = Set(sessions.map { $0.sessionId })
        let newPendingIds = currentIds.subtracting(previousPendingIds)

        if !newPendingIds.isEmpty {
            effects.play(.needsYou)
            let isQuestion = sessions.contains { newPendingIds.contains($0.sessionId) && $0.pendingToolName == "AskUserQuestion" }
            AppSettings.play(isQuestion ? AppSettings.questionSound : AppSettings.attentionSound)
            if AppSettings.openNotchOnRequest &&
               viewModel.status == .closed &&
               !TerminalVisibilityDetector.isTerminalVisibleOnCurrentSpace() {
                viewModel.notchOpen(reason: .notification)
            }
        }

        previousPendingIds = currentIds
    }

    private func handleWaitingForInputChange(_ instances: [SessionState]) {
        // Get sessions that are now waiting for input
        let waitingForInputSessions = instances.filter { $0.phase == .waitingForInput }
        let currentIds = Set(waitingForInputSessions.map { $0.sessionId })
        let newWaitingIds = currentIds.subtracting(previousWaitingForInputIds)

        // Track timestamps for newly waiting sessions
        let now = Date()
        for session in waitingForInputSessions where newWaitingIds.contains(session.sessionId) {
            waitingForInputTimestamps[session.sessionId] = now
        }

        // Clean up timestamps for sessions no longer waiting
        let staleIds = Set(waitingForInputTimestamps.keys).subtracting(currentIds)
        for staleId in staleIds {
            waitingForInputTimestamps.removeValue(forKey: staleId)
        }

        // Bounce the notch when a session newly enters waitingForInput state
        if !newWaitingIds.isEmpty {
            // Get the sessions that just entered waitingForInput
            let newlyWaitingSessions = waitingForInputSessions.filter { newWaitingIds.contains($0.sessionId) }

            // Sound and banner only for sessions the user isn't already looking at
            Task {
                guard await shouldPlayNotificationSound(for: newlyWaitingSessions) else { return }
                AppSettings.play(AppSettings.notificationSound)
                if AppSettings.showFinishedBanner, let session = newlyWaitingSessions.first {
                    viewModel.showBanner(for: session)
                }
            }

            effects.play(.finished)

            // Schedule hiding the checkmark after 30 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [self] in
                // Trigger a UI update to re-evaluate hasWaitingForInput
                handleProcessingChange()
            }
        }

        previousWaitingForInputIds = currentIds
    }

    /// Determine if notification sound should play for the given sessions
    /// Returns true if ANY session is not actively focused
    private func shouldPlayNotificationSound(for sessions: [SessionState]) async -> Bool {
        for session in sessions where !(await SessionFocuser.isFocused(session)) {
            return true
        }

        return false
    }
}
