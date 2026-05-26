import Foundation

enum ConflictChoice: String, CaseIterable, Identifiable {
    case ours
    case theirs
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ours: "Ours"
        case .theirs: "Theirs"
        case .both: "Both"
        }
    }
}

struct ConflictBlock: Identifiable, Hashable {
    let id: Int
    let startLine: Int
    let endLine: Int
    let ours: String
    let theirs: String

    func resolvedText(choice: ConflictChoice) -> String {
        ConflictMarkerParser.replacementLines(for: self, choice: choice).joined(separator: "\n")
    }
}

enum ConflictMarkerParser {
    static func blocks(in text: String) -> [ConflictBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [ConflictBlock] = []
        var index = 0

        while index < lines.count {
            guard lines[index].hasPrefix("<<<<<<<") else {
                index += 1
                continue
            }

            let start = index
            index += 1
            var ours: [String] = []
            var theirs: [String] = []

            while index < lines.count && !lines[index].hasPrefix("=======") {
                ours.append(lines[index])
                index += 1
            }

            guard index < lines.count else { break }
            index += 1

            while index < lines.count && !lines[index].hasPrefix(">>>>>>>") {
                theirs.append(lines[index])
                index += 1
            }

            guard index < lines.count else { break }
            let end = index
            blocks.append(
                ConflictBlock(
                    id: blocks.count,
                    startLine: start + 1,
                    endLine: end + 1,
                    ours: ours.joined(separator: "\n"),
                    theirs: theirs.joined(separator: "\n")
                )
            )
            index += 1
        }

        return blocks
    }

    static func resolveFirst(in text: String, choice: ConflictChoice) -> String {
        resolve(in: text, blockID: 0, choice: choice)
    }

    static func resolve(in text: String, blockID: Int, choice: ConflictChoice) -> String {
        let lines = text.components(separatedBy: "\n")
        guard let block = blocks(in: text).first(where: { $0.id == blockID }) else { return text }
        let replacement = replacementLines(for: block, choice: choice)

        var next = Array(lines.prefix(block.startLine - 1))
        next.append(contentsOf: replacement)
        next.append(contentsOf: lines.dropFirst(block.endLine))
        return next.joined(separator: "\n")
    }

    static func resolveAll(in text: String, choice: ConflictChoice) -> String {
        let choices = Dictionary(uniqueKeysWithValues: blocks(in: text).map { ($0.id, choice) })
        return resolve(in: text, choicesByBlockID: choices)
    }

    static func resolve(in text: String, choicesByBlockID: [Int: ConflictChoice]) -> String {
        let lines = text.components(separatedBy: "\n")
        let parsedBlocks = blocks(in: text)
        guard !parsedBlocks.isEmpty else { return text }

        var next: [String] = []
        var lineIndex = 0
        for block in parsedBlocks {
            next.append(contentsOf: lines[lineIndex..<(block.startLine - 1)])
            if let choice = choicesByBlockID[block.id] {
                next.append(contentsOf: replacementLines(for: block, choice: choice))
            } else {
                next.append(contentsOf: lines[(block.startLine - 1)..<block.endLine])
            }
            lineIndex = block.endLine
        }
        next.append(contentsOf: lines[lineIndex...])
        return next.joined(separator: "\n")
    }

    static func replacementLines(for block: ConflictBlock, choice: ConflictChoice) -> [String] {
        let replacement: [String]
        switch choice {
        case .ours:
            replacement = block.ours.isEmpty ? [] : block.ours.components(separatedBy: "\n")
        case .theirs:
            replacement = block.theirs.isEmpty ? [] : block.theirs.components(separatedBy: "\n")
        case .both:
            replacement =
                (block.ours.isEmpty ? [] : block.ours.components(separatedBy: "\n")) +
                (block.theirs.isEmpty ? [] : block.theirs.components(separatedBy: "\n"))
        }
        return replacement
    }
}

enum EditorTextTools {
    static func replacing(_ text: String, find: String, replacement: String) -> String {
        guard !find.isEmpty else { return text }
        return text.replacingOccurrences(of: find, with: replacement)
    }

    static func linePreview(_ text: String, line: Int, radius: Int = 2) -> String {
        let lines = text.components(separatedBy: "\n")
        guard line > 0, line <= lines.count else { return "" }
        let lower = max(line - radius - 1, 0)
        let upper = min(line + radius - 1, lines.count - 1)
        return (lower...upper)
            .map { "\($0 + 1): \(lines[$0])" }
            .joined(separator: "\n")
    }

    static func lineRangePreview(_ text: String, startLine: Int, endLine: Int, radius: Int = 2) -> String {
        let lines = text.components(separatedBy: "\n")
        guard startLine > 0, startLine <= lines.count else { return "" }
        let lower = max(startLine - radius - 1, 0)
        let upper = min(max(endLine + radius - 1, lower), lines.count - 1)
        return (lower...upper)
            .map { "\($0 + 1): \(lines[$0])" }
            .joined(separator: "\n")
    }
}

enum SyntaxTokenKind: Equatable {
    case plain
    case keyword
    case string
    case number
    case comment
    case markup
    case diffAddition
    case diffDeletion
}

struct SyntaxToken: Equatable {
    let text: String
    let kind: SyntaxTokenKind
}

enum SyntaxHighlighter {
    static func highlightedLines(for text: String, path: String = "") -> [[SyntaxToken]] {
        if let treeSitterLines = TreeSitterSyntaxHighlighter.highlightedLines(for: text, path: path) {
            return treeSitterLines
        }

        var scanner = Scanner(path: path)
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { scanner.tokens(for: String($0)) }
    }

    static func tokens(for line: String, path: String = "") -> [SyntaxToken] {
        var scanner = Scanner(path: path)
        return scanner.tokens(for: line)
    }

    private struct Scanner {
        let path: String
        var blockCommentDepth = 0

        mutating func tokens(for line: String) -> [SyntaxToken] {
        guard !line.isEmpty else { return [SyntaxToken(text: " ", kind: .plain)] }
        if let specialTokens = specialLineTokens(for: line) {
            return specialTokens
        }
        let keywords = SyntaxHighlighter.keywords(for: path)
        var tokens: [SyntaxToken] = []
        var current = ""
        let characters = Array(line)
        var index = 0

        func append(_ text: String, _ kind: SyntaxTokenKind) {
            guard !text.isEmpty else { return }
            if tokens.last?.kind == kind {
                let previous = tokens.removeLast()
                tokens.append(SyntaxToken(text: previous.text + text, kind: kind))
            } else {
                tokens.append(SyntaxToken(text: text, kind: kind))
            }
        }

        func flushPlain() {
            append(current, .plain)
            current = ""
        }

        while index < characters.count {
            if blockCommentDepth > 0 {
                flushPlain()
                var comment = ""
                while index < characters.count {
                    if characters[index] == "/", nextCharacter(after: index, in: characters) == "*" {
                        comment.append("/*")
                        index += 2
                        blockCommentDepth += 1
                        continue
                    }
                    if characters[index] == "*", nextCharacter(after: index, in: characters) == "/" {
                        comment.append("*/")
                        index += 2
                        blockCommentDepth -= 1
                        if blockCommentDepth == 0 {
                            break
                        }
                        continue
                    }
                    comment.append(characters[index])
                    index += 1
                }
                append(comment, .comment)
                continue
            }

            let character = characters[index]
            if character == "/", nextCharacter(after: index, in: characters) == "/" {
                flushPlain()
                append(String(characters[index...]), .comment)
                break
            }

            if character == "#", line[..<line.index(line.startIndex, offsetBy: index)].trimmingCharacters(in: .whitespaces).isEmpty {
                flushPlain()
                append(String(characters[index...]), isMarkdown ? .markup : .comment)
                break
            }

            if character == "/", nextCharacter(after: index, in: characters) == "*" {
                flushPlain()
                var comment = "/*"
                index += 2
                blockCommentDepth = 1
                while index < characters.count {
                    if characters[index] == "/", nextCharacter(after: index, in: characters) == "*" {
                        comment.append("/*")
                        index += 2
                        blockCommentDepth += 1
                        continue
                    }
                    if characters[index] == "*", nextCharacter(after: index, in: characters) == "/" {
                        comment.append("*/")
                        index += 2
                        blockCommentDepth -= 1
                        if blockCommentDepth == 0 {
                            break
                        }
                        continue
                    }
                    comment.append(characters[index])
                    index += 1
                }
                append(comment, .comment)
                continue
            }

            if character == "\"" || character == "'" || character == "`" {
                flushPlain()
                let quote = character
                var stringValue = String(character)
                index += 1
                var escaped = false
                while index < characters.count {
                    let next = characters[index]
                    stringValue.append(next)
                    if next == quote && !escaped {
                        index += 1
                        break
                    }
                    escaped = next == "\\" && !escaped
                    if next != "\\" {
                        escaped = false
                    }
                    index += 1
                }
                append(stringValue, .string)
                continue
            }

            if character.isNumber {
                flushPlain()
                var number = String(character)
                index += 1
                while index < characters.count, characters[index].isNumber || characters[index] == "." || characters[index] == "_" {
                    number.append(characters[index])
                    index += 1
                }
                append(number, .number)
                continue
            }

            if character.isLetter || character == "_" {
                var word = String(character)
                index += 1
                while index < characters.count, characters[index].isLetter || characters[index].isNumber || characters[index] == "_" {
                    word.append(characters[index])
                    index += 1
                }
                if keywords.contains(word) {
                    flushPlain()
                    append(word, .keyword)
                } else {
                    current.append(word)
                }
                continue
            }

            current.append(character)
            index += 1
        }

        flushPlain()
        return tokens
    }

        private func nextCharacter(after index: Int, in characters: [Character]) -> Character? {
            let nextIndex = index + 1
            guard nextIndex < characters.count else { return nil }
            return characters[nextIndex]
        }

        private var fileExtension: String {
            URL(fileURLWithPath: path).pathExtension.lowercased()
        }

        private var isMarkdown: Bool {
            ["md", "markdown"].contains(fileExtension)
        }

        private func specialLineTokens(for line: String) -> [SyntaxToken]? {
            if ["diff", "patch"].contains(fileExtension) {
                if line.hasPrefix("+") && !line.hasPrefix("+++") {
                    return [SyntaxToken(text: line, kind: .diffAddition)]
                }
                if line.hasPrefix("-") && !line.hasPrefix("---") {
                    return [SyntaxToken(text: line, kind: .diffDeletion)]
                }
                if line.hasPrefix("@@") || line.hasPrefix("diff ") || line.hasPrefix("index ") || line.hasPrefix("---") || line.hasPrefix("+++") {
                    return [SyntaxToken(text: line, kind: .markup)]
                }
            }

            if isMarkdown {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") || trimmed.hasPrefix(">") || trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    return [SyntaxToken(text: line, kind: .markup)]
                }
            }

            if ["html", "htm", "xml", "plist", "svg"].contains(fileExtension),
               line.trimmingCharacters(in: .whitespaces).hasPrefix("<") {
                return markupTokens(for: line)
            }

            return nil
        }

        private func markupTokens(for line: String) -> [SyntaxToken] {
            let characters = Array(line)
            var tokens: [SyntaxToken] = []
            var current = ""
            var index = 0

            func append(_ text: String, _ kind: SyntaxTokenKind) {
                guard !text.isEmpty else { return }
                tokens.append(SyntaxToken(text: text, kind: kind))
            }

            while index < characters.count {
                let character = characters[index]
                if character == "<" {
                    append(current, .plain)
                    current = ""
                    var tag = "<"
                    index += 1
                    while index < characters.count {
                        tag.append(characters[index])
                        if characters[index] == ">" {
                            index += 1
                            break
                        }
                        index += 1
                    }
                    append(tag, .markup)
                    continue
                }
                current.append(character)
                index += 1
            }

            append(current, .plain)
            return tokens.isEmpty ? [SyntaxToken(text: " ", kind: .plain)] : tokens
        }
    }

    private static func keywords(for path: String) -> Set<String> {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "swift":
            return ["actor", "await", "case", "catch", "class", "enum", "extension", "for", "func", "guard", "if", "import", "in", "let", "private", "public", "return", "struct", "switch", "throw", "throws", "try", "var", "while"]
        case "kt", "kts":
            return ["class", "data", "else", "for", "fun", "if", "import", "interface", "internal", "object", "package", "private", "public", "return", "sealed", "val", "var", "when", "while"]
        case "js", "jsx", "ts", "tsx":
            return ["async", "await", "case", "catch", "class", "const", "else", "export", "for", "from", "function", "if", "import", "interface", "let", "private", "public", "return", "switch", "throw", "try", "type", "var", "while"]
        case "py":
            return ["as", "async", "await", "class", "def", "elif", "else", "except", "for", "from", "if", "import", "in", "lambda", "pass", "raise", "return", "try", "while", "with", "yield"]
        case "json", "jsonc":
            return ["false", "null", "true"]
        default:
            return ["async", "await", "case", "class", "const", "data", "else", "enum", "for", "func", "function", "fun", "guard", "if", "import", "interface", "let", "object", "package", "private", "public", "return", "struct", "switch", "try", "type", "val", "var", "while"]
        }
    }
}
