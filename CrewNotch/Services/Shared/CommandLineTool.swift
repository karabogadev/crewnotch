//
//  CommandLineTool.swift
//  CrewNotch
//
//  The `crewnotch` command (`crewnotch run -- npm test`). The script always
//  lives in ~/.crewnotch/bin; "Install" adds a link to it in a folder on
//  the PATH, never touching shell config files.
//

import Foundation

nonisolated enum CommandLineTool {
    static var url: URL {
        HookScript.directory.appendingPathComponent("crewnotch")
    }

    /// Folders tried for the link, in order: usually on everyone's PATH first,
    /// then the per-user ones (used only if they already exist).
    static var linkFolders: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", home + "/bin"]
    }

    /// Copies the bundled script into place when it is missing or outdated.
    static func install() throws {
        guard let bundled = Bundle.main.url(forResource: "crewnotch-cli", withExtension: "py") else {
            throw IntegrationError.missingBundledScript
        }
        let source = try Data(contentsOf: bundled)
        if (try? Data(contentsOf: url)) == source { return }
        try FileManager.default.createDirectory(at: HookScript.directory, withIntermediateDirectories: true)
        try source.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// Where `crewnotch` is linked on the PATH, if anywhere.
    static var linkedPath: String? {
        linkFolders.map { $0 + "/crewnotch" }.first { isOurLink($0) }
    }

    /// Links the command into the first writable PATH folder; returns the link's path.
    static func link() throws -> String {
        try install()
        let fm = FileManager.default
        for folder in linkFolders where fm.isWritableFile(atPath: folder) {
            let path = folder + "/crewnotch"
            if fm.fileExists(atPath: path) || (try? fm.destinationOfSymbolicLink(atPath: path)) != nil {
                guard isOurLink(path) else { continue }  // someone else's crewnotch: leave it
                return path
            }
            try fm.createSymbolicLink(atPath: path, withDestinationPath: url.path)
            return path
        }
        throw CocoaError(.fileWriteNoPermission)
    }

    static func unlink() {
        if let path = linkedPath { try? FileManager.default.removeItem(atPath: path) }
    }

    /// For shells where no folder could be used.
    static var aliasLine: String {
        "alias crewnotch=\"$HOME/.crewnotch/bin/crewnotch\""
    }

    private static func isOurLink(_ path: String) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) == url.path
    }
}
