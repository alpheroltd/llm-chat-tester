import Foundation
import TesterCore

/// Saves chat sessions as JSON files in Application Support, one file per session.
struct SessionStore {
    let directory: URL

    init() {
        // Launch argument `-sessionsPath <dir>` lets UI tests use a scratch folder.
        if let override = UserDefaults.standard.string(forKey: "sessionsPath"), !override.isEmpty {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: "LLM Chat Tester/sessions", directoryHint: .isDirectory)
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func url(for id: UUID) -> URL { directory.appending(path: "\(id.uuidString).json") }

    func save(_ session: ChatSession) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(session).write(to: url(for: session.id), options: .atomic)
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    /// All saved sessions, newest first. Unreadable files are skipped.
    func all() -> [ChatSession] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? Self.decoder.decode(ChatSession.self, from: Data(contentsOf: $0)) }
            .sorted { $0.updated > $1.updated }
    }
}
