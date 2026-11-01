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
    @ObservedObject private var recents = RecentSessions.shared
    @AppStorage(FeatureKeys.showRecentSessions) private var showRecentSessions = true

    private var showsRecents: Bool { showRecentSessions && !recents.items.isEmpty }

    private var hasRequest: Bool { sessionMonitor.instances.contains { $0.phase.isWaitingForApproval } }

    var body: some View {
        VStack(spacing: 0) {
            if sessionMonitor.instances.isEmpty {
                emptyState
                if showsRecents {
                    RecentSessionsSection(recents: recents, onResumed: { viewModel.notchClose() })
                        .padding(.bottom, 6)
                        .reportHeight()
                }
            } else {
                instancesList
            }
            UsageFooter(
                monitor: usageMonitor,
                isAnyAgentBusy: sessionMonitor.instances.contains { $0.phase.isActive || $0.phase.isWaitingForApproval }
            )
            .reportHeight()
        }
        .onChange(of: hasRequest, initial: true) { _, value in
            if viewModel.showsRequest != value { viewModel.showsRequest = value }
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
                .foregroundColor(.ink.opacity(0.55))
            Text("Start Claude Code, Codex, Cursor or another connected agent")
                .font(.system(size: 11 * textScale.factor))
                .foregroundColor(.ink.opacity(0.3))
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
            VStack(alignment: .leading, spacing: 0) {
                ForEach(projectGroups, id: \.project) { group in
                    if groupByProject {
                        ProjectHeader(name: group.project, count: group.sessions.count)
                    }

                    ForEach(group.sessions) { session in
                        InstanceRow(
                            session: session,
                            isKeyboardTarget: session.sessionId == keyboardTargetId,
                            onFocus: { focusSession(session) },
                            onChat: { openChat(session) },
                            onArchive: { archiveSession(session) },
                            onApprove: { approveSession(session) },
                            onApproveAlways: { sessionMonitor.approvePermission(sessionId: session.sessionId, toolUseId: session.pendingToolId, always: true) },
                            onReject: { rejectSession(session) },
                            onAnswer: { answers in sessionMonitor.answerQuestion(sessionId: session.sessionId, toolUseId: session.pendingToolId, answers: answers) }
                        )
                        .id(session.stableId)
                    }
                }

                if showsRecents {
                    RecentSessionsSection(recents: recents, onResumed: { viewModel.notchClose() })
                        .padding(.vertical, 8)
                        .overlay(alignment: .top) { Hairline() }
                }
            }
            .padding(.bottom, 4)
            .reportHeight()
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @AppStorage(FeatureKeys.panelShortcuts) private var panelShortcuts = true

    /// The request ⌘↩ / ⌘⌫ act on, marked with a shortcut hint
    private var keyboardTargetId: String? {
        guard panelShortcuts else { return nil }
        return ApprovalActions.keyboardTarget(in: sessionMonitor.instances)?.sessionId
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
        sessionMonitor.approvePermission(sessionId: session.sessionId, toolUseId: session.pendingToolId)
    }

    private func rejectSession(_ session: SessionState) {
        sessionMonitor.denyPermission(sessionId: session.sessionId, toolUseId: session.pendingToolId, reason: nil)
    }

    private func archiveSession(_ session: SessionState) {
        sessionMonitor.archiveSession(sessionId: session.sessionId)
    }
}

// MARK: - Instance Row

/// One session as a row of an instrument: a status lamp, the agent's logo, the
/// title over one monospaced meta line, and the turn's time. Rows are divided
/// by hairlines; a request opens a plate under the row with the way to answer it.
struct InstanceRow: View {
    @ObservedObject private var replyHosts = ReplyHostCache.shared
    @AppStorage("groupByProject") private var groupByProject = false
    @AppStorage(AppearanceKeys.accentMode) private var accent: AccentMode = .full
    @AppStorage(AppearanceKeys.showSubagents) private var showSubagents = true
    @AppStorage(AppearanceKeys.titleOrder) private var titleOrder: TitleOrder = .conversation
    @AppStorage(AppearanceKeys.idleAfterMinutes) private var idleAfterMinutes = 30
    @AppStorage(AppearanceKeys.textScale) private var textScale: TextScale = .standard
    @AppStorage(FeatureKeys.showApprovalDetails) private var showApprovalDetails = true
    @AppStorage(FeatureKeys.warnRiskyCommands) private var warnRiskyCommands = true
    @AppStorage(FeatureKeys.showGitBranch) private var showGitBranch = true
    @AppStorage(FeatureKeys.showTaskProgress) private var showTaskProgress = true
    @AppStorage(FeatureKeys.contextFill) private var contextFill: ContextFillDisplay = .aboveHalf
    @AppStorage(FeatureKeys.stalledAfterMinutes) private var stalledAfterMinutes = 10
    @AppStorage(FeatureKeys.offerAlwaysAllow) private var offerAlwaysAllow = true
    @AppStorage(FeatureKeys.answerQuestionsInNotch) private var answerQuestionsInNotch = true
    let session: SessionState
    var isKeyboardTarget = false
    let onFocus: () -> Void
    let onChat: () -> Void
    let onArchive: () -> Void
    let onApprove: () -> Void
    var onApproveAlways: () -> Void = {}
    let onReject: () -> Void
    var onAnswer: ([String: String]) -> Void = { _ in }

    @State private var isHovered = false
    @State private var subagentsExpanded = false

    /// Lamp, gap, logo, gap: where the title starts, so plates line up with it
    private static let contentInset: CGFloat = 7 + 12 + 18 + 12

    private var isWaitingForApproval: Bool { session.phase.isWaitingForApproval }

    /// The agent's multiple-choice question, when it can be answered here
    private var answerableQuestions: [AgentQuestion]? {
        guard answerQuestionsInNotch, let permission = session.activePermission,
              permission.toolName == "AskUserQuestion", permission.canRespond else { return nil }
        let questions = AgentQuestion.parse(permission.rawInput)
        return questions.isEmpty ? nil : questions
    }

    /// The request needs more than approve/deny, or only the agent itself can answer it
    private var isInteractiveTool: Bool {
        guard let permission = session.activePermission else { return false }
        if answerableQuestions != nil { return false }
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
        case .waitingForInput: return accent.finishedColor
        case .processing, .compacting: return .ink.opacity(0.85)
        default: return .ink.opacity(0.5)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                // Lamp and logo sit on the title's line, however many lines follow
                StatusLamp(phase: session.phase, accent: accent)
                    .frame(height: 16 * textScale.factor)
                AgentIcon(agent: session.agent, size: 18)
                    .frame(height: 16 * textScale.factor)
                    .help(session.agent.displayName)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13 * textScale.factor, weight: .semibold))
                        .foregroundColor(.ink.opacity(0.94))
                        .lineLimit(1)
                    TimelineView(.periodic(from: .now, by: 30)) { timeline in
                        metaLine(now: timeline.date)
                    }
                    if let progress = visibleProgress {
                        TaskProgressLine(progress: progress)
                            .padding(.top, 4)
                    }
                }

                Spacer(minLength: 8)

                trailing
                    .frame(height: 16 * textScale.factor)
            }

            if isWaitingForApproval {
                Group {
                    if let questions = answerableQuestions {
                        QuestionCard(
                            questions: questions,
                            showsShortcuts: isKeyboardTarget,
                            onSubmit: onAnswer,
                            onOpenAgent: SessionFocuser.canFocus(session) ? onFocus : nil
                        )
                        .id(session.activePermission?.toolUseId)
                    } else {
                        approvalPlate
                    }
                }
                .padding(.leading, Self.contentInset)
            }

            if subagentsExpanded && !activeSubagents.isEmpty {
                SubagentList(tasks: activeSubagents)
                    .padding(.leading, Self.contentInset)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.ink.opacity(isHovered ? 0.045 : 0)))
        .overlay(alignment: .top) { Hairline() }
        .contentShape(Rectangle())
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

    // MARK: - Row extras

    /// Working, but nothing has happened for a while: maybe stuck.
    private func isStalled(now: Date) -> Bool {
        // A command reports only start and end, and a long tool call is legitimately quiet
        guard stalledAfterMinutes > 0, session.phase.isActive, session.agent != .command,
              session.toolTracker.inProgress.isEmpty else { return false }
        return now.timeIntervalSince(session.lastActivity) >= Double(stalledAfterMinutes) * 60
    }

    private var branch: String? {
        guard showGitBranch, let name = session.gitBranch, !name.isEmpty else { return nil }
        return name.count > 28 ? String(name.prefix(27)) + "…" : name
    }

    private var visibleContext: ContextUsage? {
        guard let threshold = contextFill.threshold, let usage = session.contextUsage,
              usage.fraction >= threshold else { return nil }
        return usage
    }

    private var visibleProgress: TaskProgress? {
        guard showTaskProgress, let progress = session.taskProgress else { return nil }
        // A completed list stays only while the agent is still wrapping up
        return progress.isFinished && !session.phase.isActive ? nil : progress
    }

    private func metaLine(now: Date) -> some View {
        let stalled = isStalled(now: now)
        return HStack(spacing: 8) {
            Group {
                if stalled {
                    Text("Quiet for \(RelativeTime.short(since: session.lastActivity, now: now))")
                        .foregroundColor(TerminalColors.amber)
                        .help("No activity for a while. If the agent is stuck, clear the session.")
                } else {
                    Text(statusWord).foregroundColor(statusColor)
                }
            }
            .textCase(.uppercase)
            .kerning(0.6)

            if showsProject {
                Text(session.projectName).foregroundColor(.ink.opacity(0.5))
            }
            if let branch {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 8.5 * textScale.factor, weight: .semibold))
                    Text(branch)
                }
                .foregroundColor(.ink.opacity(0.5))
            }
            if let context = visibleContext {
                ContextFillBadge(usage: context)
            }
            if !activeSubagents.isEmpty {
                Button {
                    subagentsExpanded.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Text("^[\(activeSubagents.count) subagent](inflect: true)")
                        Image(systemName: subagentsExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 7 * textScale.factor, weight: .bold))
                    }
                    .foregroundColor(.ink.opacity(0.65))
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 10.5 * textScale.factor, design: .monospaced))
        .lineLimit(1)
    }

    /// A stopwatch while the agent works, otherwise the time since it last did
    /// anything; hover swaps it for actions.
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
                if session.phase == .idle || session.phase == .waitingForInput || isStalled(now: Date()) {
                    IconButton(icon: "xmark") { onArchive() }
                        .help(session.phase.isActive ? "Clear this session" : "Remove")
                }
            }
            .transition(.opacity)
        } else if (session.phase.isActive || isWaitingForApproval), let started = session.turnStartedAt {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(Stopwatch.format(timeline.date.timeIntervalSince(started)))
                    .font(.system(size: 11 * textScale.factor, design: .monospaced))
                    .foregroundColor(.ink.opacity(0.8))
            }
            .help("Time in this turn")
            .transition(.opacity)
        } else {
            Text(RelativeTime.short(since: session.lastActivity))
                .font(.system(size: 11 * textScale.factor, design: .monospaced))
                .foregroundColor(.ink.opacity(0.5))
                .transition(.opacity)
        }
    }

    // MARK: - Request plate

    private var riskWarnings: [String] {
        guard warnRiskyCommands, let permission = session.activePermission else { return [] }
        return permission.riskWarnings(cwd: session.cwd)
    }

    /// The full request replaces the one-line summary
    private var showsDetailBlock: Bool {
        showApprovalDetails && session.activePermission?.toolInput?.isEmpty == false
    }

    /// The working folder, shortened to ~ for the plate's corner
    private var shortCwd: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return session.cwd.hasPrefix(home) ? "~" + session.cwd.dropFirst(home.count) : session.cwd
    }

    /// What the agent wants to run, then the keys to answer it.
    private var approvalPlate: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let toolName = session.pendingToolName {
                        Text(MCPToolFormatter.formatToolName(toolName))
                            .font(.system(size: 10 * textScale.factor, weight: .semibold, design: .monospaced))
                            .textCase(.uppercase)
                            .kerning(0.6)
                            .foregroundColor(accent.attentionColor)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(shortCwd)
                        .font(.system(size: 10 * textScale.factor, design: .monospaced))
                        .foregroundColor(.ink.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                if let permission = session.activePermission, permission.toolName != "AskUserQuestion",
                   showApprovalDetails || (warnRiskyCommands && !riskWarnings.isEmpty) {
                    ApprovalDetailView(
                        context: permission,
                        cwd: session.cwd,
                        showsDetails: showApprovalDetails,
                        showsWarnings: warnRiskyCommands,
                        alwaysRule: ApprovalActions.offersAlways(permission, cwd: session.cwd) ? permission.suggestionSummary : nil,
                        inPlate: true
                    )
                }
                if let input = session.pendingToolInput, session.pendingToolName != "AskUserQuestion", !showsDetailBlock {
                    Text(input)
                        .font(.system(size: 12 * textScale.factor, design: .monospaced))
                        .foregroundColor(.ink.opacity(0.9))
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 11)

            HStack(spacing: 6) {
                if isInteractiveTool {
                    Spacer(minLength: 0)
                    if SessionFocuser.canFocus(session) {
                        SoftPill(title: session.agent.isTerminalAgent ? "Terminal" : "Open", prominent: true, action: onFocus)
                    }
                } else {
                    SoftPill(title: "Deny", prominent: false, hint: isKeyboardTarget ? "⌘⌫" : nil, action: onReject)
                    Spacer(minLength: 0)
                    if let permission = session.activePermission, ApprovalActions.offersAlways(permission, cwd: session.cwd),
                       let rule = permission.suggestionSummary {
                        SoftPill(title: "Always", prominent: false, hint: isKeyboardTarget ? "⌘⇧↩" : nil, action: onApproveAlways)
                            .help(String(localized: "Allow and don't ask again: \(rule)"))
                    }
                    SoftPill(title: "Allow", prominent: true, hint: isKeyboardTarget ? "⌘↩" : nil, action: onApprove)
                }
            }
            .padding(8)
            .background(Color.ink.opacity(0.025))
            .overlay(alignment: .top) { Hairline() }
        }
        .background(Color.recess)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(riskWarnings.isEmpty ? Color.ink.opacity(0.12) : TerminalColors.red.opacity(0.5), lineWidth: 1)
        )
    }
}

/// "3/7 · Writing tests" behind one segment per task.
private struct TaskProgressLine: View {
    let progress: TaskProgress
    @AppStorage(AppearanceKeys.textScale) private var textScale: TextScale = .standard

    var body: some View {
        HStack(spacing: 10) {
            if progress.total <= 12 {
                HStack(spacing: 2) {
                    ForEach(0..<progress.total, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(segmentColor(index))
                            .frame(width: progress.total > 8 ? 9 : 13, height: 4)
                    }
                }
            } else {
                Capsule()
                    .fill(Color.ink.opacity(0.12))
                    .frame(width: 84, height: 4)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.ink.opacity(0.85))
                            .frame(width: max(4, 84 * progress.fraction), height: 4)
                    }
            }
            HStack(spacing: 6) {
                Text("\(progress.completed)/\(progress.total)")
                    .foregroundColor(.ink.opacity(0.85))
                if let current = progress.currentTitle, !progress.isFinished {
                    Text(current)
                        .foregroundColor(.ink.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .font(.system(size: 10.5 * textScale.factor, design: .monospaced))
        }
        .animation(.easeOut(duration: 0.25), value: progress.completed)
    }

    private func segmentColor(_ index: Int) -> Color {
        if index < progress.completed { return .ink.opacity(0.85) }
        if index == progress.completed && !progress.isFinished { return .ink.opacity(0.4) }
        return .ink.opacity(0.12)
    }
}

/// A small ring and percentage for how full the context window is.
private struct ContextFillBadge: View {
    let usage: ContextUsage
    @AppStorage(AppearanceKeys.textScale) private var textScale: TextScale = .standard

    private var color: Color {
        if usage.fraction >= 0.9 { return TerminalColors.red }
        if usage.fraction >= 0.8 { return TerminalColors.amber }
        return .ink.opacity(0.5)
    }

    var body: some View {
        HStack(spacing: 3) {
            ZStack {
                Circle().stroke(Color.ink.opacity(0.15), lineWidth: 1.6)
                Circle()
                    .trim(from: 0, to: usage.fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 8 * textScale.factor, height: 8 * textScale.factor)
            Text("\(Int((usage.fraction * 100).rounded()))%")
        }
        .foregroundColor(color)
        .help(String(localized: "Context: \(Self.tokens(usage.usedTokens)) of \(Self.tokens(usage.windowTokens)) tokens"))
    }

    static func tokens(_ count: Int) -> String {
        count >= 1_000_000 ? String(format: "%.1fM", Double(count) / 1_000_000)
            : count >= 1000 ? "\(count / 1000)K" : "\(count)"
    }
}

/// A small square lamp: working breathes, needing you is lit, finished is
/// green, idle is an empty outline.
private struct StatusLamp: View {
    let phase: SessionPhase
    let accent: AccentMode

    private var color: Color {
        switch phase {
        case .processing, .compacting: return .ink
        case .waitingForApproval: return accent.attentionColor
        case .waitingForInput: return accent.finishedColor
        case .idle, .ended: return .ink.opacity(0.45)
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        TimelineView(.animation(paused: !phase.isActive)) { context in
            let wave = (sin(context.date.timeIntervalSinceReferenceDate * 3.4) + 1) / 2
            Group {
                if phase == .idle || phase == .ended {
                    shape.strokeBorder(color, lineWidth: 1)
                } else {
                    shape.fill(color)
                }
            }
            .frame(width: 7, height: 7)
            .opacity(phase.isActive ? 0.3 + 0.7 * wave : 1)
        }
    }
}

/// A key you press: a low-contrast cap with a lip, the shortcut beside the label.
struct SoftPill: View {
    let title: LocalizedStringKey
    let prominent: Bool
    /// Keyboard shortcut shown faintly after the title
    var hint: String? = nil
    let action: () -> Void

    @AppStorage(AppearanceKeys.textScale) private var textScale: TextScale = .standard
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title)
                if let hint {
                    Text(hint)
                        .font(.system(size: 10 * textScale.factor, weight: .medium, design: .monospaced))
                        .opacity(0.55)
                }
            }
            .font(.system(size: 11.5 * textScale.factor, weight: .semibold))
            .foregroundColor(prominent ? .canvas : .ink.opacity(0.85))
            .padding(.horizontal, prominent ? 12 : 10)
            .frame(height: 28 * textScale.factor)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(prominent ? Color.ink.opacity(isHovered ? 1 : 0.92) : Color.ink.opacity(isHovered ? 0.14 : 0.08))
                    // The lip under the cap
                    .shadow(color: .ink.opacity(prominent ? 0.35 : 0.14), radius: 0, x: 0, y: 1.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.ink.opacity(prominent ? 0 : 0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// "4:12", "1:04:12": time in the current turn.
enum Stopwatch {
    static func format(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        let hours = seconds / 3600, minutes = (seconds % 3600) / 60, rest = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
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
                .foregroundColor(.ink.opacity(0.55))
            Text("\(count)")
                .font(.system(size: 10 * textScale.factor, weight: .medium, design: .rounded))
                .foregroundColor(.ink.opacity(0.3))
        }
        .padding(.leading, 8)
        .padding(.top, 12)
        .padding(.bottom, 6)
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
                .foregroundColor(.ink.opacity(isHovered ? 0.85 : 0.45))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.ink.opacity(isHovered ? 0.12 : 0.06)))
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
                        .foregroundColor(.ink.opacity(0.75))
                        .lineLimit(1)
                    if let last = task.subagentTools.last {
                        Text("· \(MCPToolFormatter.formatToolName(last.name))")
                            .foregroundColor(.ink.opacity(0.4))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text("^[\(task.subagentTools.count) tool](inflect: true)")
                        .foregroundColor(.ink.opacity(0.3))
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
