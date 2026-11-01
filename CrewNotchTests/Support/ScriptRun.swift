//
//  ScriptRun.swift
//  CrewNotchTests
//
//  One run of a script shipped in the app bundle (`crewnotch-hook.py`,
//  `crewnotch-cli.py`), pointed at the test socket.
//

import Foundation

final class ScriptRun {
    private let process = Process()
    private let stdout = Pipe()
    private let exited: AsyncStream<Void>
    private let name: String

    init(script: String, arguments: [String], stdin: Data = Data()) throws {
        guard let path = Bundle.main.path(forResource: script, ofType: "py") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(script).py"])
        }
        name = ([script] + arguments).joined(separator: " ")
        // The interpreter CrewNotch installs its hooks with
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [path] + arguments
        process.currentDirectoryURL = Pipeline.workspace
        // A clean environment: nothing from the test host leaks into the script
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": NSHomeDirectory(),
            "CREWNOTCH_SOCKET": Pipeline.socketPath,
        ]
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        let input = Pipe()
        process.standardInput = input

        let (stream, continuation) = AsyncStream<Void>.makeStream()
        exited = stream
        process.terminationHandler = { _ in continuation.finish() }

        try process.run()
        input.fileHandleForWriting.write(stdin)
        try input.fileHandleForWriting.close()
    }

    /// Waits for the script to exit and returns what it printed.
    @discardableResult
    func finish(within timeout: Duration = .seconds(10)) async throws -> String {
        let exited = self.exited
        let finished = await withTaskGroup(of: Bool.self) { group in
            group.addTask { for await _ in exited {}; return !Task.isCancelled }
            group.addTask { try? await Task.sleep(for: timeout); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        guard finished else {
            process.terminate()
            throw PipelineError.scriptTimedOut(name)
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var exitCode: Int32 { process.terminationStatus }

    /// Kills the script the way a closed terminal would.
    func kill() { process.terminate() }
}
