//
//  TerminalColors.swift
//  CrewNotch
//
//  Color palette for terminal-style UI
//

import AppKit
import SwiftUI

struct TerminalColors {
    // Darker on light surfaces so status words stay readable
    static let green = Color.dynamic(dark: NSColor(red: 0.4, green: 0.75, blue: 0.45, alpha: 1), light: NSColor(red: 0.1, green: 0.55, blue: 0.25, alpha: 1))
    static let amber = Color.dynamic(dark: NSColor(red: 1.0, green: 0.7, blue: 0.0, alpha: 1), light: NSColor(red: 0.78, green: 0.48, blue: 0.0, alpha: 1))
    static let red = Color(red: 1.0, green: 0.3, blue: 0.3)
    static let cyan = Color(red: 0.0, green: 0.8, blue: 0.8)
    static let blue = Color(red: 0.4, green: 0.6, blue: 1.0)
    static let magenta = Color(red: 0.8, green: 0.4, blue: 0.8)
    static let dim = Color.ink.opacity(0.4)
    static let dimmer = Color.ink.opacity(0.2)
    static let prompt = Color(red: 0.85, green: 0.47, blue: 0.34)  // #d97857
    static let background = Color.ink.opacity(0.05)
    static let backgroundHover = Color.ink.opacity(0.1)
}
