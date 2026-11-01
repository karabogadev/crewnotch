//
//  OpenCodeIntegration.swift
//  CrewNotch
//
//  OpenCode has no shell hooks; it loads JS plugins from its config folder.
//  CrewNotch drops its own plugin file there.
//

import Foundation

nonisolated struct OpenCodeIntegration: AgentIntegration {
    let agent = AgentKind.opencode

    private var configDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/opencode")
    }

    /// OpenCode loads `{plugin,plugins}/*.{js,ts}`; reuse a folder the user already has.
    private var pluginFile: URL {
        let plural = configDir.appendingPathComponent("plugins")
        let folder = FileManager.default.fileExists(atPath: plural.path) ? plural : configDir.appendingPathComponent("plugin")
        return folder.appendingPathComponent("crewnotch.js")
    }

    var setupNote: String? { "Restart OpenCode to load the plugin." }

    func isDetected() -> Bool {
        AgentDetection.binaryExists("opencode") || AgentDetection.exists(".config/opencode")
    }

    func isConnected() -> Bool {
        FileManager.default.fileExists(atPath: pluginFile.path)
    }

    func connect() throws {
        guard let bundled = Bundle.main.url(forResource: "crewnotch-opencode", withExtension: "js") else {
            throw IntegrationError.missingBundledScript
        }
        let source = try Data(contentsOf: bundled)
        if (try? Data(contentsOf: pluginFile)) == source { return }
        try FileManager.default.createDirectory(at: pluginFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try source.write(to: pluginFile, options: .atomic)
    }

    func disconnect() throws {
        try JSONConfigFile.remove(pluginFile)
    }
}

/// DeepSeek Harness is read from its session logs, so there is nothing to
/// install; connecting just turns the log watcher on.
nonisolated struct DeepSeekIntegration: AgentIntegration {
    let agent = AgentKind.deepseek

    func isDetected() -> Bool {
        AgentDetection.appInstalled(agent.appBundleIdentifiers()) || AgentDetection.exists(".dsh")
    }

    func isConnected() -> Bool {
        AppSettings.connectedAgents.contains(agent)
    }

    func connect() throws {}
    func disconnect() throws {}
}
