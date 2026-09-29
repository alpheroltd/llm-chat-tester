import Foundation

/// Grades with the tester's own Claude plan by running their installed Claude Code CLI headlessly (`claude -p`).
public struct ClaudeCodeJudge: JudgeRunner {
    public var cliPathOverride: String?

    public init(cliPathOverride: String? = nil) {
        self.cliPathOverride = cliPathOverride
    }

    public static func arguments(model: JudgeModel) -> [String] {
        [
            "-p",
            "--model", model.cliAlias,
            "--tools", "", // no tools: an instruction hidden in the reply can't make the judge do anything
            "--strict-mcp-config",
            "--disable-slash-commands",
            "--no-session-persistence",
            "--output-format", "json",
            "--json-schema", JudgePrompt.schemaJSON,
            "--system-prompt", JudgePrompt.system,
        ]
    }

    public func judge(_ request: JudgeRequest, model: JudgeModel) async throws -> JudgeVerdict {
        try request.validate()
        guard let path = await ClaudeCLI.locate(override: cliPathOverride) else { throw JudgeError.cliNotFound }
        let started = ContinuousClock.now
        // Run outside any project folder so no CLAUDE.md or MCP config is picked up.
        guard let result = await ClaudeCLI.run(
            path, Self.arguments(model: model),
            stdin: JudgePrompt.userMessage(for: request),
            currentDirectory: FileManager.default.temporaryDirectory
        ) else { throw JudgeError.cliFailed("couldn't start \(path)") }
        try Task.checkCancellation()
        var verdict = try Self.parse(stdout: result.stdout, stderr: result.stderr, exitCode: result.exitCode)
        verdict.model = model
        verdict.provider = .claudeCode
        if verdict.seconds == nil { verdict.seconds = (ContinuousClock.now - started).seconds }
        return verdict
    }

    /// Parses Claude Code's `--output-format json` envelope.
    public static func parse(stdout: String, stderr: String, exitCode: Int32) throws -> JudgeVerdict {
        struct Envelope: Decodable {
            let is_error: Bool?
            let result: String?
            let structured_output: JudgeVerdict?
            let total_cost_usd: Double?
            let duration_ms: Double?
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(stdout.utf8)) else {
            let message = (stderr.isEmpty ? stdout : stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            throw JudgeError.cliFailed("exit \(exitCode): \(message.isEmpty ? "no output" : String(message.prefix(400)))")
        }
        if envelope.is_error == true {
            throw JudgeError.cliFailed(String((envelope.result ?? "unknown error").prefix(400)))
        }
        guard var verdict = envelope.structured_output else {
            throw JudgeError.badOutput("no structured verdict in Claude Code's output")
        }
        verdict.costUsd = envelope.total_cost_usd
        verdict.seconds = envelope.duration_ms.map { $0 / 1000 }
        return JudgePrompt.normalised(verdict)
    }
}

extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
