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
    private var sessions: [SessionState] = []
    private var cancellable: AnyCancellable?

    private init() {
        cancellable = SessionStore.shared.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.sessions = $0 }
    }

    func activate(for viewModel: NotchViewModel) {
        self.viewModel = viewModel
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func deactivate() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Returns true when the key press was used.
    private func handle(_ event: NSEvent) -> Bool {
        guard let viewModel, viewModel.status == .opened else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = Int(event.keyCode)

        if key == kVK_Escape && flags.isEmpty {
            if isEditingText { return false }  // let the text field give up focus first
            if case .chat = viewModel.contentType { viewModel.exitChat() } else { viewModel.notchClose() }
            return true
        }

        guard AppSettings.panelShortcuts, let target = ApprovalActions.keyboardTarget(in: sessions),
              let permission = target.activePermission else { return false }
        let isQuestion = permission.toolName == "AskUserQuestion"

        switch (key, flags) {
        case (kVK_Return, [.command]), (kVK_ANSI_KeypadEnter, [.command]):
            guard !isQuestion else { return false }  // the question card's Send handles it
            ApprovalActions.approve(sessionId: target.sessionId)
            return true
        case (kVK_Return, [.command, .shift]), (kVK_ANSI_KeypadEnter, [.command, .shift]):
            guard !isQuestion, AppSettings.offerAlwaysAllow, permission.suggestions != nil else { return false }
            ApprovalActions.approve(sessionId: target.sessionId, always: true)
            return true
        case (kVK_Delete, [.command]):
            guard !isEditingText else { return false }
            ApprovalActions.deny(sessionId: target.sessionId)
            return true
        default:
            break
        }

        // 1–9 answers a single multiple-choice question
        guard flags.isEmpty, !isEditingText, isQuestion, AppSettings.answerQuestionsInNotch,
              let digit = Self.digit(for: key) else { return false }
        let questions = AgentQuestion.parse(permission.rawInput)
        guard AgentQuestion.isOneClick(questions), questions[0].options.indices.contains(digit - 1) else { return false }
        ApprovalActions.answer(sessionId: target.sessionId, answers: [questions[0].text: questions[0].options[digit - 1].label])
        return true
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
