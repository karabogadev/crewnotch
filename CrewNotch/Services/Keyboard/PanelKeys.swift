//
//  PanelKeys.swift
//  CrewNotch
//
//  Keyboard shortcuts while the notch panel has focus: ⌘↩ allow,
//  ⌘⇧↩ always allow, ⌘⌫ deny, 1–9 pick an answer, ⎋ close. They act on
//  the oldest request CrewNotch can answer, which the panel marks.
//

import AppKit
import Carbon.HIToolbox
import Combine

@MainActor
final class PanelKeys {
    static let shared = PanelKeys()

    private var monitor: Any?
    private weak var viewModel: NotchViewModel?
    private weak var panel: NSWindow?
    private var sessions: [SessionState] = []
    private var cancellable: AnyCancellable?

    /// The request the keys would act on, and since when it has been the one shown
    private var targetId: String?
    private var targetShownAt = Date.distantPast
    /// A request must have been on screen this long before a chord answers it
    private let targetDelay: TimeInterval = 0.4

    /// Approval keys only work after a deliberate open (click or shortcut),
    /// never when the panel slid open under a resting pointer.
    private(set) var approvalsArmed = false
    private var armedAt = Date.distantPast
    /// Keys pressed this soon after arming were meant for another app.
    private let armingDelay: TimeInterval = 0.5

    private init() {
        cancellable = SessionStore.shared.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.sessionsChanged($0) }
    }

    private func sessionsChanged(_ sessions: [SessionState]) {
        self.sessions = sessions
        let id = ApprovalActions.keyboardTarget(in: sessions)?.activePermission?.toolUseId
        if id != targetId {
            targetId = id
            targetShownAt = Date()
        }
    }

    func activate(for viewModel: NotchViewModel, panel: NSWindow?, deliberate: Bool) {
        self.viewModel = viewModel
        self.panel = panel
        if deliberate { arm() } else { approvalsArmed = false }
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func deactivate() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        approvalsArmed = false
    }

    /// Turns on the approval keys (the panel was opened on purpose).
    func arm() {
        approvalsArmed = true
        armedAt = Date()
    }

    /// Returns true when the key press was used.
    private func handle(_ event: NSEvent) -> Bool {
        // Only keys typed into the notch panel itself, never another CrewNotch window
        guard let viewModel, viewModel.status == .opened, let panel, event.window === panel else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = Int(event.keyCode)

        if key == kVK_Escape && flags.isEmpty {
            if isEditingText { return false }  // let the text field give up focus first
            if case .chat = viewModel.contentType { viewModel.exitChat() } else { viewModel.notchClose() }
            return true
        }

        // A held key repeats; a repeat must never answer the next request in line
        guard !event.isARepeat, !isEditingText,
              AppSettings.panelShortcuts, approvalsArmed, Date().timeIntervalSince(armedAt) >= armingDelay,
              let target = ApprovalActions.keyboardTarget(in: sessions),
              let permission = target.activePermission,
              permission.toolUseId == targetId, Date().timeIntervalSince(targetShownAt) >= targetDelay,
              isVisible(target, in: viewModel) else { return false }
        let isQuestion = permission.toolName == "AskUserQuestion"

        switch (key, flags) {
        case (kVK_Return, [.command]), (kVK_ANSI_KeypadEnter, [.command]):
            guard !isQuestion else { return false }  // the question card's Send handles it
            ApprovalActions.approve(sessionId: target.sessionId, toolUseId: permission.toolUseId)
            return true
        case (kVK_Return, [.command, .shift]), (kVK_ANSI_KeypadEnter, [.command, .shift]):
            guard !isQuestion, ApprovalActions.offersAlways(permission, cwd: target.cwd) else { return false }
            ApprovalActions.approve(sessionId: target.sessionId, toolUseId: permission.toolUseId, always: true)
            return true
        case (kVK_Delete, [.command]):
            ApprovalActions.deny(sessionId: target.sessionId, toolUseId: permission.toolUseId)
            return true
        default:
            break
        }

        // 1–9 answers a single multiple-choice question
        guard flags.isEmpty, isQuestion, AppSettings.answerQuestionsInNotch,
              let digit = Self.digit(for: key) else { return false }
        let questions = AgentQuestion.parse(permission.rawInput)
        guard AgentQuestion.isOneClick(questions), questions[0].options.indices.contains(digit - 1) else { return false }
        ApprovalActions.answer(sessionId: target.sessionId, toolUseId: permission.toolUseId,
                               answers: [questions[0].text: questions[0].options[digit - 1].label])
        return true
    }

    /// Only answer a request the user can see: the list, or that session's chat.
    private func isVisible(_ target: SessionState, in viewModel: NotchViewModel) -> Bool {
        switch viewModel.contentType {
        case .instances: return true
        case .chat(let session): return session.sessionId == target.sessionId
        case .banner, .notice: return false
        }
    }

    private var isEditingText: Bool {
        NSApp.keyWindow?.firstResponder is NSText
    }

    private static func digit(for keyCode: Int) -> Int? {
        let keys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        let keypad = [kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4, kVK_ANSI_Keypad5,
                      kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8, kVK_ANSI_Keypad9]
        if let index = keys.firstIndex(of: keyCode) ?? keypad.firstIndex(of: keyCode) { return index + 1 }
        return nil
    }
}
