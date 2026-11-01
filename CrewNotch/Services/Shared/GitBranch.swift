//
//  GitBranch.swift
//  CrewNotch
//
//  Current git branch of a working directory, read straight from .git/HEAD
//  (no git process) and cached briefly so list rows stay cheap.
//

import Foundation

@MainActor
enum GitBranch {
    private static var cache: [String: (branch: String?, readAt: Date)] = [:]
    private static let ttl: TimeInterval = 10

    static func name(for cwd: String) -> String? {
        if let entry = cache[cwd], Date().timeIntervalSince(entry.readAt) < ttl {
            return entry.branch
        }
        let branch = read(cwd: cwd)
        cache[cwd] = (branch, Date())
        return branch
    }

    private static func read(cwd: String) -> String? {
        var dir = URL(fileURLWithPath: cwd)
        for _ in 0..<12 {
            let dotGit = dir.appendingPathComponent(".git")
            if let head = headContents(dotGit: dotGit) {
                let prefix = "ref: refs/heads/"
                return head.hasPrefix(prefix) ? String(head.dropFirst(prefix.count)) : String(head.prefix(7))
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }

    /// Handles both a .git directory and a worktree's `.git` file ("gitdir: <path>").
    private static func headContents(dotGit: URL) -> String? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) else { return nil }
        var gitDir = dotGit
        if !isDirectory.boolValue {
            guard let pointer = try? String(contentsOf: dotGit, encoding: .utf8),
                  pointer.hasPrefix("gitdir:") else { return nil }
            let path = pointer.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            gitDir = URL(fileURLWithPath: path, relativeTo: dotGit.deletingLastPathComponent())
        }
        return (try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
