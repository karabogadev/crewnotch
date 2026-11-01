//
//  ShortcutsSection.swift
//  CrewNotch
//
//  The keyboard shortcuts at the foot of the opened panel, folded into one
//  line until the user opens them. The choice is remembered.
//

import SwiftUI

struct ShortcutsSection: View {
    @AppStorage(FeatureKeys.shortcutsExpanded) private var isExpanded = false
    @AppStorage(FeatureKeys.panelShortcuts) private var panelShortcuts = true
    // Observed so the list follows a shortcut changed in Settings
    @AppStorage(FeatureKeys.hotkey) private var savedHotkey = ""
    @AppStorage(AppearanceKeys.textScale) private var textScale: TextScale = .standard

    private struct Item: Identifiable {
        let keys: String
        let action: LocalizedStringKey
        var id: String { keys }
    }

    private var items: [Item] {
        _ = savedHotkey
        var items: [Item] = []
        if let hotkey = Hotkey.saved {
            items.append(Item(keys: hotkey.displayString, action: "Open or close the notch"))
        }
        if panelShortcuts {
            items += [
                Item(keys: "⌘↩", action: "Allow"),
                Item(keys: "⌘⇧↩", action: "Always allow"),
                Item(keys: "⌘⌫", action: "Deny"),
                Item(keys: "1–9", action: "Pick an answer"),
            ]
        }
        items.append(Item(keys: "esc", action: "Close, or leave a chat"))
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Shortcuts")
                        .textCase(.uppercase)
                        .kerning(0.4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7.5 * textScale.factor, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    Spacer(minLength: 8)
                    if !isExpanded, let hotkey = Hotkey.saved {
                        Text(hotkey.displayString).foregroundColor(.ink.opacity(0.5))
                    }
                }
                .font(.system(size: 10 * textScale.factor, weight: .medium, design: .monospaced))
                .foregroundColor(.ink.opacity(0.55))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items) { item in
                        HStack(spacing: 12) {
                            Text(item.keys)
                                .font(.system(size: 10.5 * textScale.factor, weight: .medium, design: .monospaced))
                                .foregroundColor(.ink.opacity(0.85))
                                .frame(width: 64 * textScale.factor, alignment: .leading)
                            Text(item.action)
                                .font(.system(size: 11 * textScale.factor))
                                .foregroundColor(.ink.opacity(0.55))
                        }
                    }
                    if panelShortcuts {
                        Text("Answer keys work after you open the notch with a click or the shortcut.")
                            .font(.system(size: 10 * textScale.factor))
                            .foregroundColor(.ink.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .overlay(alignment: .top) { Hairline() }
    }
}
