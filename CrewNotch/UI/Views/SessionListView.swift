//
//  SessionListView.swift
//  CrewNotch
//
//  Minimal instances list matching Dynamic Island aesthetic
//

import Combine
import SwiftUI

struct SessionListView: View {
    @AppStorage(AppearanceKeys.textScale) private var textScale: TextScale = .standard
    @ObservedObject var sessionMonitor: SessionMonitor
    @ObservedObject var viewModel: NotchViewModel

    @ObservedObject private var usageMonitor = UsageMonitor.shared

    var body: some View {
        VStack(spacing: 0) {
            if sessionMonitor.instances.isEmpty {
                emptyState
            } else {
                instancesList
            }
            UsageFooter(
                monitor: usageMonitor,
                isAnyAgentBusy: sessionMonitor.instances.contains { $0.phase.isActive || $0.phase.isWaitingForApproval }
            )
            .reportHeight()
        }
        // Size the panel to its content instead of a fixed height
        .onPreferenceChange(ContentHeightKey.self) { height in
            if abs(viewModel.listContentHeight - height) > 1 {
                viewModel.listContentHeight = height
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            HStack(spacing: 5) {
                ForEach([Color(red: 1, green: 0.62, blue: 0.2), Color(red: 0.3, green: 0.85, blue: 0.45), Color(red: 0.35, green: 0.62, blue: 1)], id: \.self) { color in
                    Circle().fill(color.opacity(0.7)).frame(width: 6, height: 6)
                }
            }
            Text("No agents running")
                .font(.system(size: 13 * textScale.factor, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
            Text("Start Claude Code, Codex, Cursor or another connected agent")
                .font(.system(size: 11 * textScale.factor))
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .reportHeight()
    }

    // MARK: - Instances List

    /// Priority: active (approval/processing/compacting) > waitingForInput > idle
    /// Secondary sort: by last user message date (stable - doesn't change when agent responds)
    /// Note: approval requests stay in their date-based position to avoid layout shift
    @AppStorage(AppearanceKeys.idleAfterMinutes) private var idleAfterMinutes = 30
    @AppStorage(AppearanceKeys.hideIdleSessions) private var hideIdleSessions = false

    private var sortedInstances: [SessionState] {
        sessionMonitor.instances
            .filter { !(hideIdleSessions && $0.isIdle(afterMinutes: idleAfterMinutes)) }
            .sorted { a, b in
            let priorityA = a.isIdle(afterMinutes: idleAfterMinutes) ? 2 : phasePriority(a.phase)
            let priorityB = b.isIdle(afterMinutes: idleAfterMinutes) ? 2 : phasePriority(b.phase)
            if priorityA != priorityB {
                return priorityA < priorityB
            }
            // Sort by last user message date (more recent first)
            // Fall back to lastActivity if no user messages yet
            let dateA = a.lastUserMessageDate ?? a.lastActivity
            let dateB = b.lastUserMessageDate ?? b.lastActivity
            return dateA > dateB
        }
    }

    /// Lower number = higher priority
    /// Approval requests share priority with processing to maintain stable ordering
    private func phasePriority(_ phase: SessionPhase) -> Int {
        switch phase {
        case .waitingForApproval, .processing, .compacting: return 0
        case .waitingForInput: return 1
        case .idle, .ended: return 2
        }
    }

    @AppStorage("groupByProject") private var groupByProject = false

    /// Sessions grouped by project, groups ordered by their most urgent session
    /// (a single group when grouping is off)
    private var projectGroups: [(project: String, sessions: [SessionState])] {
        guard groupByProject else { return [("", sortedInstances)] }
        var order: [String] = []
        var groups: [String: [SessionState]] = [:]
        for session in sortedInstances {
            if groups[session.projectName] == nil { order.append(session.projectName) }
            groups[session.projectName, default: []].append(session)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    private var instancesList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(projectGroups, id: \.project) { group in
                    if groupByProject {
                        ProjectHeader(name: group.project, count: group.sessions.count)
                    }

                    ForEach(group.sessions) { session in
                        InstanceRow(
                            session: session,
                            onFocus: { focusSession(session) },
                            onChat: { openChat(session) },
                            onArchive: { archiveSession(session) },
                            onApprove: { approveSession(session) },
                            onReject: { rejectSession(session) }
                        )
                        .id(session.stableId)
                    }
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 6)
            .reportHeight()
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Actions

    private func focusSession(_ session: SessionState) {
        viewModel.notchClose()
        Task { await SessionFocuser.focus(session) }
    }

    private func openChat(_ session: SessionState) {
        viewModel.showChat(for: session)
    }

    private func approveSession(_ session: SessionState) {
        sessionMonitor.approvePermission(sessionId: session.sessionId)
    }

    private func rejectSession(_ session: SessionState) {
        sessionMonitor.denyPermission(sessionId: session.sessionId, reason: nil)
    }

    private func archiveSession(_ session: SessionState) {
        sessionMonitor.archiveSession(sessionId: session.sessionId)
    }
}

// MARK: - Instance Row

/// One session as a soft card: the agent's logo with a status dot, the title,
/// one quiet meta line, and actions that appear on hover.
struct InstanceRow: View {
    @ObservedObject private var replyHosts = ReplyHostCache.shared
    @AppStorage("groupByProject") private var groupByProject = false
    @AppStorage(AppearanceKeys.accentMode) private var accent: AccentMode = .full
    @AppStorage(AppearanceKeys.showSubagents) private var showSubagents = true
    @AppStorage(AppearanceKeys.titleOrder) private var titleOrder: TitleOrder = .conversation
    @AppStorage(AppearanceKeys.idleAfterMinutes) private var idleAfterMinutes = 30
    @AppStorage(AppearanceKeys.textScale) private var textScale: TextScale = .standard
    let session: SessionState
    let onFocus: () -> Void
    let onChat: () -> Void
    let onArchive: () -> Void
    let onApprove: () -> Void
    let onReject: () -> Void

    @State private var isHovered = false
    @State private var subagentsExpanded = false

    private var isWaitingForApproval: Bool { session.phase.isWaitingForApproval }

    /// The request needs more than approve/deny, or only the agent itself can answer it
    private var isInteractiveTool: Bool {
        guard let permission = session.activePermission else { return false }
        return permission.toolName == "AskUserQuestion" || !permission.canRespond
    }

    private var isIdle: Bool { session.isIdle(afterMinutes: idleAfterMinutes) }

    private var title: String {
        titleOrder == .project ? session.projectName : session.displayTitle
    }

    private var statusWord: String {
        switch session.phase {
        case .processing: return String(localized: "Working")
        case .compacting: return String(localized: "Compacting")
        case .waitingForInput: return String(localized: "Done")
        case .waitingForApproval: return String(localized: "Needs you")
        case .idle: return String(localized: "Idle")
        case .ended: return String(localized: "Ended")
        }
    }

    private var statusColor: Color {
        switch session.phase {
        case .waitingForApproval: return accent.attentionColor
        case .waitingForInput: return accent == .full ? TerminalColors.green.opacity(0.9) : .white.opacity(0.6)
        default: return .white.opacity(0.5)
        }
    }

    /// The project goes on the meta line unless a group header or the title already shows it
    private var showsProject: Bool {
        !groupByProject && titleOrder == .conversation && session.displayTitle != session.projectName
    }

    /// Chat is offered only where a reply can reach the agent's terminal
    private var canReply: Bool {
        guard session.agent.isTerminalAgent else { return false }
        if case .some(let host) = replyHosts.host(for: session) { return host != nil }
        return false
    }

    private var activeSubagents: [TaskContext] {
        guard showSubagents else { return [] }
        return session.subagentState.activeTasks.values.sorted { $0.startTime < $1.startTime }
    }

    private var cardFill: Color {
        if isWaitingForApproval { return accent.attentionColor.opacity(0.10) }
        return .white.opacity(isHovered ? 0.075 : 0.04)
    }

    private var cardStroke: Color {
        isWaitingForApproval ? accent.attentionColor.opacity(0.22) : .white.opacity(0.05)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                AgentAvatar(agent: session.agent, phase: session.phase, accent: accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13 * textScale.factor, weight: .medium))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)
                    metaLine
                }

                Spacer(minLength: 8)

                trailing
            }

            if isWaitingForApproval {
                approvalStrip
            }

            if subagentsExpanded && !activeSubagents.isEmpty {
                SubagentList(tasks: activeSubagents)
                    .padding(.leading, 41)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(cardFill))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(cardStroke, lineWidth: 0.5))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(count: 2) {
            // Double-click jumps to the agent's window; without one, open the chat
            if SessionFocuser.canFocus(session) { onFocus() } else { onChat() }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
        .opacity(isIdle && !isHovered ? 0.55 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isWaitingForApproval)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: subagentsExpanded)
        .task(id: session.pid) { await replyHosts.resolve(session) }
    }

    private var metaLine: some View {
        HStack(spacing: 5) {
            Text(statusWord).foregroundColor(statusColor)
            if showsProject {
                Text("·").foregroundColor(.white.opacity(0.25))
                Text(session.projectName).foregroundColor(.white.opacity(0.45))
            }
            if !activeSubagents.isEmpty {
                Text("·").foregroundColor(.white.opacity(0.25))
                Button {
                    subagentsExpanded.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Text("^[\(activeSubagents.count) subagent](inflect: true)")
                        Image(systemName: subagentsExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 7 * textScale.factor, weight: .bold))
                    }
                    .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 11 * textScale.factor))
        .lineLimit(1)
    }

    /// Time since the last activity; hover swaps it for actions.
    @ViewBuilder
    private var trailing: some View {
        if isHovered && !isWaitingForApproval {
            HStack(spacing: 2) {
                if canReply {
                    IconButton(icon: "bubble.left") { onChat() }
                }
                if SessionFocuser.canFocus(session) {
                    IconButton(icon: "arrow.up.forward") { onFocus() }
                }
                if session.phase == .idle || session.phase == .waitingForInput {
                    IconButton(icon: "xmark") { onArchive() }
                }
            }
            .transition(.opacity)
        } else {
            Text(RelativeTime.short(since: session.lastActivity))
                .font(.system(size: 11 * textScale.factor, weight: .regular, design: .rounded))
                .foregroundColor(.white.opacity(0.3))
                .monospacedDigit()
                .transition(.opacity)
        }
    }

    /// What the agent wants to run, with the way to answer it.
    private var approvalStrip: some View {
        HStack(spacing: 8) {
            if let toolName = session.pendingToolName {
                Text(MCPToolFormatter.formatToolName(toolName))
                    .font(.system(size: 11 * textScale.factor, weight: .semibold, design: .monospaced))
                    .foregroundColor(accent.attentionColor)
                if let input = session.pendingToolInput, toolName != "AskUserQuestion" {
                    Text(input)
                        .font(.system(size: 11 * textScale.factor, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if isInteractiveTool {
                if SessionFocuser.canFocus(session) {
                    SoftPill(title: session.agent.isTerminalAgent ? "Terminal" : "Open", prominent: true, action: onFocus)
                }
            } else {
                SoftPill(title: "Deny", prominent: false, action: onReject)
                SoftPill(title: "Allow", prominent: true, action: onApprove)
            }
        }
        .padding(.leading, 41)
    }
}

/// The agent's logo on a soft tile, with a small status dot in the corner.
private struct AgentAvatar: View {
    let agent: AgentKind
    let phase: SessionPhase
    let accent: AccentMode

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .frame(width: 30, height: 30)
                .overlay(AgentIcon(agent: agent, size: 17))
            StatusDot(phase: phase, accent: accent)
                .offset(x: 3, y: 3)
        }
        .help(agent.displayName)
    }
}

/// Working breathes, needing you pulses, finished and idle stay still.
private struct StatusDot: View {
    let phase: SessionPhase
    let accent: AccentMode

    private var color: Color {
        switch phase {
        case .processing, .compacting: return Color(red: 1.0, green: 0.62, blue: 0.25)
        case .waitingForApproval: return accent.attentionColor
        case .waitingForInput: return accent.finishedColor
        case .idle, .ended: return .white.opacity(0.3)
        }
    }

    private var isAnimated: Bool {
        phase.isActive || phase.isWaitingForApproval
    }

    var body: some View {
        TimelineView(.animation(paused: !isAnimated)) { context in
            let wave = isAnimated ? (sin(context.date.timeIntervalSinceReferenceDate * (phase.isWaitingForApproval ? 5 : 3)) + 1) / 2 : 1
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .opacity(isAnimated ? 0.55 + 0.45 * wave : 1)
                .background(Circle().stroke(Color.black, lineWidth: 2.5))
        }
    }
}

/// A rounded, low-contrast button used in cards.
struct SoftPill: View {
    let title: LocalizedStringKey
    let prominent: Bool
    let action: () -> Void

    @AppStorage(AppearanceKeys.textScale) private var textScale: TextScale = .standard
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11 * textScale.factor, weight: .semibold))
                .foregroundColor(prominent ? .black : .white.opacity(0.75))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(prominent ? Color.white.opacity(isHovered ? 1 : 0.88) : Color.white.opacity(isHovered ? 0.16 : 0.1)))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// "now", "4m", "2h", "3d" in the user's language.
enum RelativeTime {
    private static let formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = [.day, .hour, .minute]
        return formatter
    }()

    static func short(since date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return String(localized: "now") }
        return formatter.string(from: interval) ?? ""
    }
}

// MARK: - Project Header

private struct ProjectHeader: View {
    @AppStorage(AppearanceKeys.textScale) private var textScale: TextScale = .standard
    let name: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 11 * textScale.factor, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
            Text("\(count)")
                .font(.system(size: 10 * textScale.factor, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.leading, 10)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}

// MARK: - Icon Button

struct IconButton: View {
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(.white.opacity(isHovered ? 0.85 : 0.45))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(isHovered ? 0.12 : 0.06)))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Subagent List

/// Subagents a session is delegating to, shown under its row when expanded.
private struct SubagentList: View {
    let tasks: [TaskContext]
    @AppStorage(AppearanceKeys.textScale) private var textScale: TextScale = .standard

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(tasks, id: \.taskToolId) { task in
                HStack(spacing: 6) {
                    WorkingIndicator(size: 9)
                    Text(task.description ?? "Subagent")
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                    if let last = task.subagentTools.last {
                        Text("· \(MCPToolFormatter.formatToolName(last.name))")
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text("^[\(task.subagentTools.count) tool](inflect: true)")
                        .foregroundColor(.white.opacity(0.3))
                }
                .font(.system(size: 10.5 * textScale.factor))
            }
        }
    }
}

// MARK: - Content height

/// Sums the heights of the list's parts so the panel can fit its content.
struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
}

private extension View {
    func reportHeight() -> some View {
        background(GeometryReader { Color.clear.preference(key: ContentHeightKey.self, value: $0.size.height) })
    }
}
