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
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No sessions")
                .font(.system(size: 13 * textScale.factor, weight: .medium))
                .foregroundColor(.white.opacity(0.4))

            Text("Start Claude Code, Codex, Cursor or another connected agent")
                .font(.system(size: 11 * textScale.factor))
                .foregroundColor(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    @AppStorage("groupByProject") private var groupByProject = true

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
            LazyVStack(alignment: .leading, spacing: 2) {
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
            .padding(.vertical, 4)
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

struct InstanceRow: View {
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


    /// Whether we're showing the approval UI
    private var isWaitingForApproval: Bool {
        session.phase.isWaitingForApproval
    }

    /// Whether the pending request needs more than approve/deny, or can only
    /// be answered in the agent itself
    private var isInteractiveTool: Bool {
        guard let permission = session.activePermission else { return false }
        return permission.toolName == "AskUserQuestion" || !permission.canRespond
    }

    /// Short status word shown on the meta line
    private var statusWord: String {
        switch session.phase {
        case .processing: return "Working"
        case .compacting: return "Compacting"
        case .waitingForInput: return "Done"
        case .waitingForApproval: return "Needs you"
        case .idle: return "Idle"
        case .ended: return "Ended"
        }
    }

    private var statusColor: Color {
        switch session.phase {
        case .waitingForApproval: return TerminalColors.amber
        case .waitingForInput: return TerminalColors.green
        default: return .white.opacity(0.45)
        }
    }

    /// One-line preview: the pending request, else the latest message
    private var preview: String? {
        if isWaitingForApproval, let toolName = session.pendingToolName {
            let name = MCPToolFormatter.formatToolName(toolName)
            if toolName == "AskUserQuestion" { return "\(name): needs your input" }
            return [name, session.pendingToolInput].compactMap { $0 }.joined(separator: " ")
        }
        guard let message = session.lastMessage else { return nil }
        switch session.lastMessageRole {
        case "user": return "You: \(message)"
        case "tool": return [session.lastToolName.map(MCPToolFormatter.formatToolName), message].compactMap { $0 }.joined(separator: " ")
        default: return message
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            stateIndicator
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(titleOrder == .project ? session.projectName : session.displayTitle)
                        .font(.system(size: 13 * textScale.factor, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if session.usage.totalTokens > 0 {
                        Text(session.usage.formattedTotal)
                            .font(.system(size: 10 * textScale.factor, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }

                HStack(spacing: 5) {
                    AgentIcon(agent: session.agent, size: 11)
                        .help(session.agent.displayName)
                    Text(statusWord)
                        .foregroundColor(statusColor)
                    if let branch = GitBranch.name(for: session.cwd) {
                        Text("·").foregroundColor(.white.opacity(0.25))
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9 * textScale.factor))
                            .foregroundColor(.white.opacity(0.35))
                        Text(branch)
                            .foregroundColor(.white.opacity(0.45))
                    }
                    if let preview {
                        Text("·").foregroundColor(.white.opacity(0.25))
                        Text(preview)
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 11 * textScale.factor))
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            actions
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            // Double-click jumps to the agent's window; chat is one click on the bubble
            if SessionFocuser.canFocus(session) {
                onFocus()
            } else {
                onChat()
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isWaitingForApproval)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
        )
        .onHover { isHovered = $0 }
        .opacity(session.isIdle(afterMinutes: idleAfterMinutes) && !isHovered ? 0.55 : 1)
    }

    @ViewBuilder
    private var actions: some View {
        if isWaitingForApproval && isInteractiveTool {
            // Questions, or approvals only the agent can answer: jump to it
            if SessionFocuser.canFocus(session) {
                TerminalButton(
                    label: session.agent.isTerminalAgent ? "Terminal" : "Open",
                    icon: session.agent.isTerminalAgent ? "terminal" : "arrow.up.forward.app",
                    isEnabled: true,
                    onTap: { onFocus() }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        } else if isWaitingForApproval {
            InlineApprovalButtons(
                onChat: onChat,
                onApprove: onApprove,
                onReject: onReject
            )
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        } else if isHovered {
            HStack(spacing: 4) {
                IconButton(icon: "bubble.left") { onChat() }
                if SessionFocuser.canFocus(session) {
                    IconButton(icon: "arrow.up.forward.app") { onFocus() }
                }
                if session.phase == .idle || session.phase == .waitingForInput {
                    IconButton(icon: "archivebox") { onArchive() }
                }
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch session.phase {
        case .processing, .compacting:
            NotchStatusGlyph(status: .working, size: 13)
        case .waitingForApproval:
            NotchStatusGlyph(status: .needsYou, size: 13)
        case .waitingForInput:
            NotchStatusGlyph(status: .finished, size: 13)
        case .idle, .ended:
            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 6, height: 6)
        }
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

// MARK: - Inline Approval Buttons

/// Compact inline approval buttons with staggered animation
struct InlineApprovalButtons: View {
    @AppStorage(AppearanceKeys.textScale) private var textScale: TextScale = .standard
    let onChat: () -> Void
    let onApprove: () -> Void
    let onReject: () -> Void

    @State private var showChatButton = false
    @State private var showDenyButton = false
    @State private var showAllowButton = false

    var body: some View {
        HStack(spacing: 6) {
            // Chat button
            IconButton(icon: "bubble.left") {
                onChat()
            }
            .opacity(showChatButton ? 1 : 0)
            .scaleEffect(showChatButton ? 1 : 0.8)

            Button {
                onReject()
            } label: {
                Text("Deny")
                    .font(.system(size: 11 * textScale.factor, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(showDenyButton ? 1 : 0)
            .scaleEffect(showDenyButton ? 1 : 0.8)

            Button {
                onApprove()
            } label: {
                Text("Allow")
                    .font(.system(size: 11 * textScale.factor, weight: .medium))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.9))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(showAllowButton ? 1 : 0)
            .scaleEffect(showAllowButton ? 1 : 0.8)
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.0)) {
                showChatButton = true
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.05)) {
                showDenyButton = true
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.1)) {
                showAllowButton = true
            }
        }
    }
}

// MARK: - Icon Button

struct IconButton: View {
    @AppStorage(AppearanceKeys.textScale) private var textScale: TextScale = .standard
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11 * textScale.factor, weight: .medium))
                .foregroundColor(isHovered ? .white.opacity(0.8) : .white.opacity(0.4))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.white.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Compact Terminal Button (inline in description)

struct CompactTerminalButton: View {
    @AppStorage(AppearanceKeys.textScale) private var textScale: TextScale = .standard
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            if isEnabled {
                onTap()
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "terminal")
                    .font(.system(size: 8 * textScale.factor, weight: .medium))
                Text("Go to Terminal")
                    .font(.system(size: 10 * textScale.factor, weight: .medium))
            }
            .foregroundColor(isEnabled ? .white.opacity(0.9) : .white.opacity(0.3))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isEnabled ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Terminal Button

struct TerminalButton: View {
    @AppStorage(AppearanceKeys.textScale) private var textScale: TextScale = .standard
    var label = "Terminal"
    var icon = "terminal"
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            if isEnabled {
                onTap()
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9 * textScale.factor, weight: .medium))
                Text(label)
                    .font(.system(size: 11 * textScale.factor, weight: .medium))
            }
            .foregroundColor(isEnabled ? .black : .white.opacity(0.4))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isEnabled ? Color.white.opacity(0.95) : Color.white.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
