import Foundation

/// A block of Markdown. SwiftUI only renders *inline* Markdown (bold, italic, code, links), so lesson text
/// is split into blocks here and each block's inline text is styled by `AttributedString(markdown:)`.
public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullets([String])
    case numbered([String])
    /// `> ` lines. Callouts are quotes starting with **Tip:**, **Note:**, **Warning:** etc.
    case quote(String)
    case code(language: String, text: String)
    case image(alt: String, path: String)
    case divider
}

public enum MarkdownParser {
    private static let numberedPrefix = try! NSRegularExpression(pattern: #"^\d+[.)]\s+"#)
    private static let imageLine = try! NSRegularExpression(pattern: #"^!\[([^\]]*)\]\(([^)\s]+)\)$"#)

    public static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var numbered: [String] = []
        var quote: [String] = []
        var code: [String]?
        var codeLanguage = ""

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] }
            if !bullets.isEmpty { blocks.append(.bullets(bullets)); bullets = [] }
            if !numbered.isEmpty { blocks.append(.numbered(numbered)); numbered = [] }
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: "\n"))); quote = [] }
        }

        for rawLine in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            // Inside a fenced code block, keep lines as they are until the closing fence.
            if code != nil {
                if rawLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    blocks.append(.code(language: codeLanguage, text: code!.joined(separator: "\n")))
                    code = nil
                } else {
                    code!.append(rawLine)
                }
                continue
            }

            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let range = NSRange(line.startIndex..., in: line)

            if line.hasPrefix("```") {
                flush()
                codeLanguage = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                code = []
            } else if line.isEmpty {
                flush()
            } else if let level = headingLevel(line) {
                flush()
                blocks.append(.heading(level: level, text: String(line.dropFirst(level + 1)).trimmingCharacters(in: .whitespaces)))
            } else if line == "---" || line == "***" {
                flush()
                blocks.append(.divider)
            } else if let match = imageLine.firstMatch(in: line, range: range),
                      let alt = Range(match.range(at: 1), in: line), let path = Range(match.range(at: 2), in: line) {
                flush()
                blocks.append(.image(alt: String(line[alt]), path: String(line[path])))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if bullets.isEmpty { flush() }
                bullets.append(String(line.dropFirst(2)))
            } else if let match = numberedPrefix.firstMatch(in: line, range: range), let prefix = Range(match.range, in: line) {
                if numbered.isEmpty { flush() }
                numbered.append(String(line[prefix.upperBound...]))
            } else if line.hasPrefix(">") {
                if quote.isEmpty { flush() }
                quote.append(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
            } else if !bullets.isEmpty || !numbered.isEmpty {
                // A wrapped continuation line belongs to the previous list item.
                if !bullets.isEmpty { bullets[bullets.count - 1] += " " + line } else { numbered[numbered.count - 1] += " " + line }
            } else if !quote.isEmpty {
                quote[quote.count - 1] += " " + line
            } else {
                paragraph.append(line)
            }
        }
        if let code { blocks.append(.code(language: codeLanguage, text: code.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    private static func headingLevel(_ line: String) -> Int? {
        for level in 1...3 where line.hasPrefix(String(repeating: "#", count: level) + " ") { return level }
        return nil
    }

    /// Images referenced in the Markdown, for the content check.
    public static func imagePaths(in markdown: String) -> [String] {
        parse(markdown).compactMap { if case .image(_, let path) = $0 { path } else { nil } }
    }
}
