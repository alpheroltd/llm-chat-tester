import Foundation

/// Finds and checks the tester's own Claude Code CLI.
/// Apps launched from the Dock don't inherit the shell's PATH, so we look in the usual install locations.
public enum ClaudeCLI {
    public static func candidatePaths(home: String = NSHomeDirectory()) -> [String] {
        [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.claude/local/claude",
        ]
    }

    /// Returns the path to `claude`, preferring an explicit override, then known locations, then a login shell lookup.
    public static func locate(override: String? = nil) async -> String? {
        let fm = FileManager.default
        if let override, !override.isEmpty {
            return fm.isExecutableFile(atPath: override) ? override : nil
        }
        if let found = candidatePaths().first(where: fm.isExecutableFile(atPath:)) { return found }
        let result = await run("/bin/zsh", ["-lc", "command -v claude"])
        let path = result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty || !fm.isExecutableFile(atPath: path) ? nil : path
    }

    /// e.g. "2.1.283 (Claude Code)", or nil if it can't be run.
    public static func version(at path: String) async -> String? {
        guard let result = await run(path, ["--version"]), result.exitCode == 0 else { return nil }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public struct ProcessResult: Sendable {
        public let exitCode: Int32
        public let stdout: String
        public let stderr: String
    }

    /// Runs a program without a shell and collects its output.
    public static func run(
        _ executable: String,
        _ arguments: [String],
        stdin: String? = nil,
        currentDirectory: URL? = nil
    ) async -> ProcessResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        let out = Pipe(), err = Pipe(), input = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = input
        // Drain both pipes while the process runs, so large output can't fill the pipe buffer and deadlock it.
        let stdoutBuffer = LockedData(), stderrBuffer = LockedData()
        out.fileHandleForReading.readabilityHandler = { stdoutBuffer.append($0.availableData) }
        err.fileHandleForReading.readabilityHandler = { stderrBuffer.append($0.availableData) }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<ProcessResult?, Never>) in
                process.terminationHandler = { p in
                    out.fileHandleForReading.readabilityHandler = nil
                    err.fileHandleForReading.readabilityHandler = nil
                    stdoutBuffer.append(out.fileHandleForReading.readDataToEndOfFile())
                    stderrBuffer.append(err.fileHandleForReading.readDataToEndOfFile())
                    continuation.resume(returning: ProcessResult(
                        exitCode: p.terminationStatus,
                        stdout: String(decoding: stdoutBuffer.data, as: UTF8.self),
                        stderr: String(decoding: stderrBuffer.data, as: UTF8.self)))
                }
                do {
                    try process.run()
                    if let stdin { input.fileHandleForWriting.write(Data(stdin.utf8)) }
                    try? input.fileHandleForWriting.close()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(returning: nil)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}

/// Thread-safe byte buffer for collecting pipe output from background callbacks.
final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.withLock { storage.append(chunk) }
    }

    var data: Data { lock.withLock { storage } }
}
