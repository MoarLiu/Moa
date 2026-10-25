import Foundation

enum MoaTomlEditor {
    struct LineContext {
        let text: String
        let contentRange: Range<String.Index>
        let nextLineStart: String.Index
        let isStructural: Bool
        let isStatementStart: Bool
    }

    struct TableHeader {
        let name: String
        let isArray: Bool
        var contextName: String { isArray ? "[[\(name)]]" : name }
    }

    private enum MultilineString {
        case basic
        case literal
    }

    struct Entry {
        let table: String
        let key: String
        let value: String
        let lineRange: Range<String.Index>

        var path: String {
            table.isEmpty ? key : "\(table).\(key)"
        }

        var lineText: String {
            "\(key) = \(value)"
        }
    }

    static func entries(in text: String) -> [Entry] {
        var entries: [Entry] = []
        var currentTable = ""

        let starts = lineContexts(in: text).filter(\.isStatementStart)
        for (index, context) in starts.enumerated() {
            let line = context.text
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if context.isStructural, let header = tableHeader(from: trimmed) {
                currentTable = header.contextName
            } else {
                var end = index + 1 < starts.count ? starts[index + 1].contentRange.lowerBound : text.endIndex
                if end > context.contentRange.lowerBound, isLineBreak(text[text.index(before: end)]) { end = text.index(before: end) }
                let range = context.contentRange.lowerBound..<end
                if let keyValue = keyValue(from: String(text[range])) {
                    entries.append(Entry(table: currentTable, key: keyValue.key, value: keyValue.value, lineRange: range))
                }
            }
        }

        return entries
    }

    static func lineContexts(in text: String) -> [LineContext] {
        var contexts: [LineContext] = []
        var multiline: MultilineString?
        var arrayDepth = 0
        var lineStart = text.startIndex

        while lineStart < text.endIndex {
            let newline = text[lineStart...].firstIndex(where: isLineBreak)
            let lineEnd = newline ?? text.endIndex
            let nextLineStart = newline.map { text.index(after: $0) } ?? text.endIndex
            let line = String(text[lineStart..<lineEnd])
            let startedInsideMultiline = multiline != nil
            let startedInsideArray = arrayDepth > 0
            let sawMultilineDelimiter = updateMultilineState(for: line, state: &multiline, arrayDepth: &arrayDepth)
            contexts.append(LineContext(
                text: line,
                contentRange: lineStart..<lineEnd,
                nextLineStart: nextLineStart,
                isStructural: !startedInsideMultiline && !startedInsideArray && arrayDepth == 0 && multiline == nil && !sawMultilineDelimiter,
                isStatementStart: !startedInsideMultiline && !startedInsideArray
            ))
            lineStart = nextLineStart
        }

        if text.isEmpty || text.last.map(isLineBreak) == true {
            contexts.append(LineContext(
                text: "",
                contentRange: text.endIndex..<text.endIndex,
                nextLineStart: text.endIndex,
                isStructural: multiline == nil && arrayDepth == 0,
                isStatementStart: multiline == nil && arrayDepth == 0
            ))
        }
        return contexts
    }

    private static func isLineBreak(_ character: Character) -> Bool {
        character == "\n" || character == "\r\n"
    }

    private static func updateMultilineState(for line: String, state: inout MultilineString?, arrayDepth: inout Int) -> Bool {
        let characters = Array(line)
        var index = 0
        var quote: Character?
        var escaped = false
        var sawDelimiter = false
        var inValue = arrayDepth > 0

        func hasDelimiter(_ delimiter: [Character], at offset: Int) -> Bool {
            offset + delimiter.count <= characters.count
                && Array(characters[offset..<(offset + delimiter.count)]) == delimiter
        }

        while index < characters.count {
            if let multiline = state {
                let delimiter: [Character] = multiline == .basic ? ["\"", "\"", "\""] : ["'", "'", "'"]
                if hasDelimiter(delimiter, at: index), multiline == .literal || !isEscaped(characters, at: index) {
                    state = nil
                    sawDelimiter = true
                    index += 3
                } else {
                    index += 1
                }
                continue
            }

            if let currentQuote = quote {
                let character = characters[index]
                if currentQuote == "'" {
                    if character == "'" {
                        quote = nil
                    }
                } else if character == "\"" && !escaped {
                    quote = nil
                }
                if currentQuote == "\"" && character == "\\" && !escaped {
                    escaped = true
                } else {
                    escaped = false
                }
                index += 1
                continue
            }

            if hasDelimiter(["\"", "\"", "\""], at: index) {
                state = .basic
                sawDelimiter = true
                index += 3
            } else if hasDelimiter(["'", "'", "'"], at: index) {
                state = .literal
                sawDelimiter = true
                index += 3
            } else if characters[index] == "#" {
                break
            } else if characters[index] == "\"" || characters[index] == "'" {
                quote = characters[index]
                escaped = false
                index += 1
            } else {
                if characters[index] == "=" { inValue = true }
                if inValue {
                    if characters[index] == "[" { arrayDepth += 1 }
                    if characters[index] == "]" { arrayDepth = max(0, arrayDepth - 1) }
                }
                index += 1
            }
        }
        return sawDelimiter
    }

    private static func isEscaped(_ characters: [Character], at index: Int) -> Bool {
        guard index > 0 else {
            return false
        }
        var cursor = index - 1
        var backslashes = 0
        while characters[cursor] == "\\" {
            backslashes += 1
            guard cursor > 0 else {
                break
            }
            cursor -= 1
        }
        return backslashes % 2 == 1
    }

    static func tableName(from line: String) -> String? {
        guard let header = tableHeader(from: line), !header.isArray else { return nil }
        return header.name
    }

    static func tableHeader(from line: String) -> TableHeader? {
        let trimmed = trimInlineComment(from: line).trimmingCharacters(in: .whitespacesAndNewlines)
        let isArray = trimmed.hasPrefix("[[")
        let width = isArray ? 2 : 1
        guard trimmed.hasPrefix("["), trimmed.hasSuffix(isArray ? "]]" : "]"),
              trimmed.count > width * 2 else { return nil }
        let name = trimmed.dropFirst(width).dropLast(width).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : TableHeader(name: name, isArray: isArray)
    }

    static func keyValue(from line: String) -> (key: String, value: String)? {
        var quote: Character?
        var escaped = false
        var separator: String.Index?
        for index in line.indices {
            let character = line[index]
            if let current = quote {
                if character == current && !escaped { quote = nil }
                escaped = current == "\"" && character == "\\" && !escaped
            } else if character == "#" || isLineBreak(character) {
                return nil
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "=" {
                separator = index
                break
            }
        }
        guard let separator else { return nil }
        let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyPathComponents(key)?.isEmpty == false else { return nil }
        let remainder = String(line[line.index(after: separator)...])
        let value = trimInlineComment(from: remainder).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }

        return (key, value)
    }

    static func trimInlineComment(from value: String) -> String {
        let characters = Array(value)
        var result = ""
        var quote: Character?
        var multiline = false
        var escaped = false
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if let current = quote {
                if multiline, character == current, (current == "'" || !isEscaped(characters, at: index)) {
                    var end = index
                    while end < characters.count, characters[end] == current { end += 1 }
                    if end - index >= 3 {
                        let count = min(5, end - index)
                        result += String(characters[index..<(index + count)])
                        index += count
                        quote = nil
                        multiline = false
                        continue
                    }
                } else if !multiline, character == current, !escaped {
                    quote = nil
                }
                result.append(character)
                escaped = !multiline && current == "\"" && character == "\\" && !escaped
            } else if character == "#" {
                while index < characters.count, !isLineBreak(characters[index]) { index += 1 }
                continue
            } else if character == "\"" || character == "'" {
                quote = character
                escaped = false
                multiline = index + 2 < characters.count && characters[index + 1] == character && characters[index + 2] == character
                let count = multiline ? 3 : 1
                result += String(characters[index..<(index + count)])
                index += count
                continue
            } else {
                result.append(character)
            }
            index += 1
        }
        return result
    }

    static func collapseBlankLines(_ text: String) -> String {
        let contexts = lineContexts(in: text)
        guard let firstContent = contexts.firstIndex(where: { !isStructuralBlank($0) }),
              let lastContent = contexts.lastIndex(where: { !isStructuralBlank($0) })
        else {
            return ""
        }

        var output: [String] = []
        var previousWasStructuralBlank = false
        for context in contexts[firstContent...lastContent] {
            let isBlank = isStructuralBlank(context)
            if isBlank && previousWasStructuralBlank {
                continue
            }
            output.append(context.text)
            previousWasStructuralBlank = isBlank
        }
        return output.joined(separator: "\n")
    }

    static func collapseBlankLinesBeforeTables(_ text: String) -> String {
        let output = collapseBlankLines(text)

        var lines: [String] = []
        for context in lineContexts(in: output) {
            let trimmed = context.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if context.isStructural,
               tableName(from: trimmed) != nil,
               let previousLine = lines.last,
               !previousLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("")
            }
            lines.append(context.text)
        }
        return collapseBlankLines(lines.joined(separator: "\n"))
    }

    private static func isStructuralBlank(_ context: LineContext) -> Bool {
        context.isStructural && context.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func stringValue(in text: String, table: String, key: String) -> String? {
        guard let entry = entries(in: text).first(where: { matches($0, table: table, key: key) }) else {
            return nil
        }
        return decodedString(entry.value)
    }

    static func upsertingString(_ value: String, in text: String, table: String, key: String) -> String {
        var output = text
        if let entry = entries(in: text).first(where: { matches($0, table: table, key: key) }) {
            output.replaceSubrange(entry.lineRange, with: "\(entry.key) = \(quotedString(value))")
            return output
        }

        let contexts = lineContexts(in: text)
        let headers = contexts.filter {
            let line = $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return $0.isStructural && tableHeader(from: line) != nil
        }
        var insertion: String.Index?
        if table.isEmpty {
            insertion = headers.first?.contentRange.lowerBound ?? text.endIndex
        } else if let index = headers.firstIndex(where: { keyPathComponents(tableName(from: $0.text) ?? "") == keyPathComponents(table) }) {
            insertion = headers.dropFirst(index + 1).first?.contentRange.lowerBound ?? text.endIndex
        }
        if let insertion {
            let prefix = insertion == output.startIndex || output[output.index(before: insertion)] == "\n" ? "" : "\n"
            output.insert(contentsOf: "\(prefix)\(key) = \(quotedString(value))\n", at: insertion)
        } else {
            if !output.isEmpty, !output.hasSuffix("\n") { output.append("\n") }
            output.append("\n[\(table)]\n\(key) = \(quotedString(value))\n")
        }
        return output
    }

    private static func matches(_ entry: Entry, table: String, key: String) -> Bool {
        guard let tablePath = keyPathComponents(entry.table), let keyPath = keyPathComponents(entry.key),
              let target = keyPathComponents(table) else { return false }
        return tablePath + keyPath == target + [key]
    }

    static func unquotedKey(_ value: String) -> String {
        decodedString(value) ?? value
    }

    static func keyPathComponents(_ raw: String) -> [String]? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return [] }
        var parts: [String] = []
        var start = text.startIndex
        var quote: Character?
        var escaped = false
        for index in text.indices {
            let character = text[index]
            if let current = quote {
                if character == current && !escaped { quote = nil }
                escaped = current == "\"" && character == "\\" && !escaped
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "." {
                parts.append(String(text[start..<index]))
                start = text.index(after: index)
            }
        }
        guard quote == nil else { return nil }
        parts.append(String(text[start...]))
        var decoded: [String] = []
        for part in parts {
            let key = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if key.hasPrefix("\"") || key.hasPrefix("'") {
                guard !key.contains("\n"), !key.hasPrefix("\"\"\""), !key.hasPrefix("'''"), let value = decodedString(key) else { return nil }
                decoded.append(value)
            } else {
                guard isBareKey(key) else { return nil }
                decoded.append(key)
            }
        }
        return decoded
    }

    static func keyPath(_ components: [String]) -> String {
        components.map { isBareKey($0) ? $0 : quotedString($0) }.joined(separator: ".")
    }

    private static func isBareKey(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy {
            (48...57).contains($0.value) || (65...90).contains($0.value) || (97...122).contains($0.value) || $0 == "_" || $0 == "-"
        }
    }

    private static func decodedString(_ raw: String) -> String? {
        guard let quote = raw.first, quote == "\"" || quote == "'" else { return nil }
        let delimiter = String(repeating: String(quote), count: 3)
        let multiline = raw.hasPrefix(delimiter)
        let width = multiline ? 3 : 1
        guard raw.count >= width * 2, raw.hasSuffix(multiline ? delimiter : String(quote)) else { return nil }
        var content = String(raw.dropFirst(width).dropLast(width))
        if multiline {
            content = content.replacingOccurrences(of: "\r\n", with: "\n")
            if content.hasPrefix("\n") { content.removeFirst() }
        }
        if quote == "'" { return content }
        let characters = Array(content)
        var decoded = ""
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character != "\\" { decoded.append(character); index += 1; continue }
            index += 1
            guard index < characters.count else { return nil }
            let escaped = characters[index]
            if multiline, escaped.isWhitespace {
                let start = index
                while index < characters.count, characters[index].isWhitespace { index += 1 }
                guard characters[start..<index].contains("\n") else { return nil }
                continue
            }
            switch escaped {
            case "b": decoded.append("\u{08}")
            case "t": decoded.append("\t")
            case "n": decoded.append("\n")
            case "f": decoded.append("\u{0C}")
            case "r": decoded.append("\r")
            case "\"": decoded.append("\"")
            case "\\": decoded.append("\\")
            case "u", "U":
                let width = escaped == "u" ? 4 : 8
                guard index + width < characters.count,
                      let value = UInt32(String(characters[(index + 1)...(index + width)]), radix: 16),
                      let scalar = UnicodeScalar(value) else { return nil }
                decoded.unicodeScalars.append(scalar)
                index += width
            default: return nil
            }
            index += 1
        }
        return decoded
    }

    static func quotedString(_ value: String) -> String {
        "\"\(escapedStringContent(value))\""
    }

    static func escapedStringContent(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    static func unquoteString(_ raw: String) -> String {
        var value = raw
        if value.count >= 2 {
            let quote = value.first
            value.removeFirst()
            value.removeLast()
            guard quote == "\"" else {
                return value
            }
        }

        var output = ""
        var isEscaped = false
        for character in value {
            if isEscaped {
                switch character {
                case "b":
                    output.append("\u{08}")
                case "t":
                    output.append("\t")
                case "n":
                    output.append("\n")
                case "f":
                    output.append("\u{0C}")
                case "r":
                    output.append("\r")
                case "\"":
                    output.append("\"")
                case "\\":
                    output.append("\\")
                default:
                    output.append("\\")
                    output.append(character)
                }
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else {
                output.append(character)
            }
        }

        if isEscaped {
            output.append("\\")
        }
        return output
    }
}
