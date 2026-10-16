import Foundation
import SwiftTreeSitter
import TreeSitterSwift

enum TreeSitterSyntaxHighlighter {
    static func highlightedLines(for text: String, path: String) -> [[SyntaxToken]]? {
        guard URL(fileURLWithPath: path).pathExtension.lowercased() == "swift" else {
            return nil
        }

        do {
            let parser = Parser()
            try parser.setLanguage(Language(tree_sitter_swift()))
            guard let tree = parser.parse(text), let root = tree.rootNode else {
                return nil
            }

            let spans = spans(in: root)
            guard !spans.isEmpty else { return nil }
            return apply(spans: spans, to: text)
        } catch {
            return nil
        }
    }

    private struct Span {
        let range: NSRange
        let kind: SyntaxTokenKind
        let depth: Int
    }

    private static func spans(in root: Node) -> [Span] {
        var output: [Span] = []

        func walk(_ node: Node, depth: Int) {
            if let type = node.nodeType,
               let kind = kind(for: type),
               node.range.length > 0 {
                output.append(Span(range: node.range, kind: kind, depth: depth))
            }

            for index in 0..<node.childCount {
                if let child = node.child(at: index) {
                    walk(child, depth: depth + 1)
                }
            }
        }

        walk(root, depth: 0)
        return output
            .sorted {
                if $0.range.location == $1.range.location {
                    return $0.depth > $1.depth
                }
                return $0.range.location < $1.range.location
            }
    }

    private static func kind(for nodeType: String) -> SyntaxTokenKind? {
        if nodeType.contains("comment") {
            return .comment
        }
        if nodeType.contains("string") || nodeType == "regex_literal" {
            return .string
        }
        if nodeType == "integer_literal" || nodeType == "float_literal" || nodeType == "real_literal" {
            return .number
        }
        if swiftKeywords.contains(nodeType) {
            return .keyword
        }
        return nil
    }

    private static let swiftKeywords: Set<String> = [
        "actor", "as", "associatedtype", "async", "await", "break", "case", "catch",
        "class", "continue", "default", "defer", "do", "else", "enum", "extension",
        "fallthrough", "false", "fileprivate", "for", "func", "guard", "if", "import",
        "in", "init", "inout", "internal", "is", "let", "nil", "open", "operator",
        "private", "protocol", "public", "rethrows", "return", "self", "static",
        "struct", "subscript", "super", "switch", "throw", "throws", "true", "try",
        "typealias", "var", "where", "while"
    ]

    private static func apply(spans: [Span], to text: String) -> [[SyntaxToken]] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var lineRanges: [NSRange] = []
        var cursor = 0
        for line in lines {
            let length = line.utf16.count
            lineRanges.append(NSRange(location: cursor, length: length))
            cursor += length + 1
        }

        return lines.enumerated().map { index, line in
            let lineRange = lineRanges[index]
            let lineSpans = spans.compactMap { span -> Span? in
                let intersection = NSIntersectionRange(lineRange, span.range)
                guard intersection.length > 0 else { return nil }
                return Span(
                    range: NSRange(location: intersection.location - lineRange.location, length: intersection.length),
                    kind: span.kind,
                    depth: span.depth
                )
            }
            return tokens(for: line, spans: lineSpans)
        }
    }

    private static func tokens(for line: String, spans: [Span]) -> [SyntaxToken] {
        guard !line.isEmpty else {
            return [SyntaxToken(text: " ", kind: .plain)]
        }

        let sortedSpans = spans.sorted {
            if $0.range.location == $1.range.location {
                return $0.depth > $1.depth
            }
            return $0.range.location < $1.range.location
        }

        var tokens: [SyntaxToken] = []
        var cursor = 0
        let utf16Count = line.utf16.count

        for span in sortedSpans {
            guard span.range.location >= cursor else { continue }
            if span.range.location > cursor {
                appendSubstring(line, range: NSRange(location: cursor, length: span.range.location - cursor), kind: .plain, to: &tokens)
            }
            appendSubstring(line, range: span.range, kind: span.kind, to: &tokens)
            cursor = span.range.location + span.range.length
        }

        if cursor < utf16Count {
            appendSubstring(line, range: NSRange(location: cursor, length: utf16Count - cursor), kind: .plain, to: &tokens)
        }

        return tokens.isEmpty ? [SyntaxToken(text: " ", kind: .plain)] : tokens
    }

    private static func appendSubstring(_ line: String, range: NSRange, kind: SyntaxTokenKind, to tokens: inout [SyntaxToken]) {
        guard range.length > 0,
              let stringRange = Range(range, in: line) else {
            return
        }

        let text = String(line[stringRange])
        if let last = tokens.last, last.kind == kind {
            tokens.removeLast()
            tokens.append(SyntaxToken(text: last.text + text, kind: kind))
        } else {
            tokens.append(SyntaxToken(text: text, kind: kind))
        }
    }
}
