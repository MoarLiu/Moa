import CryptoKit
import Foundation

enum DeepSeekError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let key): return MoaL10n.text(key) }
    }
}

struct DeepSeekLogin {
    let snapshot: String
    let fingerprint: String
}

/// A deliberately narrow, lossless editor for Harness's version-1 block YAML.
/// Only the account grant is interpreted. Other records and API-key refs stay
/// byte-for-byte intact. Ambiguous/unsupported YAML fails before any write.
struct DeepSeekCredentialDocument {
    static let accountKey = "deepseek-account-platform/default"
    private struct Entry {
        let key: String
        let value: String
        let line: Int
        let end: Int
        let indent: Int
    }
    private let lines: [String]
    private let newline: String
    private let roots: [Entry]
    private let records: Entry?
    private let entries: [Entry]
    let login: DeepSeekLogin?

    init(_ text: String) throws {
        newline = text.contains("\r\n") ? "\r\n" : "\n"
        lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard !text.contains("\t"), !text.contains("\0"), !text.replacingOccurrences(of: "\r\n", with: "").contains("\r") else { throw Self.unsupported }
        roots = try Self.mapping(lines, range: 0..<lines.count, indent: 0)
        if !roots.isEmpty {
            guard let version = roots.first(where: { $0.key == "version" }),
                  version.value == "1", version.end == version.line + 1 else { throw Self.unsupported }
        }
        records = roots.first { $0.key == "records" }
        if let records {
            guard records.value.isEmpty || records.value == "{}" else { throw Self.unsupported }
            entries = try Self.children(lines, of: records)
            guard records.value.isEmpty || entries.isEmpty else { throw Self.unsupported }
        } else { entries = [] }
        if let entry = entries.first(where: { $0.key == Self.accountKey }) {
            guard entry.value.isEmpty else { throw Self.unsupported }
            let fields = try Self.children(lines, of: entry)
            guard Set(fields.map(\.key)) == ["kind", "payload"],
                  let kind = fields.first(where: { $0.key == "kind" }),
                  kind.end == kind.line + 1,
                  try Self.scalar(kind.value) == "grant",
                  let payload = fields.first(where: { $0.key == "payload" }), payload.value.isEmpty else { throw Self.unsupported }
            let values = try Self.children(lines, of: payload)
            guard Set(values.map(\.key)) == ["version", "token", "issuer"],
                  values.allSatisfy({ $0.end == $0.line + 1 }),
                  values.first(where: { $0.key == "version" })?.value == "1" else { throw Self.unsupported }
            let decoded = try Dictionary(uniqueKeysWithValues: values.filter { $0.key != "version" }.map { ($0.key, try Self.scalar($0.value)) })
            guard let token = decoded["token"], !token.isEmpty,
                  token.utf8.allSatisfy({ $0 >= 0x21 && $0 <= 0x7e }),
                  decoded["issuer"] == "https://platform.deepseek.com" else { throw Self.unsupported }
            let snapshot = Self.reindent(Array(lines[entry.line..<entry.end]), from: entry.indent, to: 2).joined(separator: "\n") + "\n"
            let hash = SHA256.hash(data: Data((decoded["issuer"]! + "\n" + token).utf8)).map { String(format: "%02x", $0) }.joined()
            login = DeepSeekLogin(snapshot: snapshot, fingerprint: hash)
        } else { login = nil }
    }

    static func savedLogin(_ snapshot: String) throws -> DeepSeekLogin {
        let document = try Self("version: 1\nrecords:\n" + snapshot)
        guard Set(document.roots.map(\.key)) == ["version", "records"],
              document.entries.map(\.key) == [accountKey], let login = document.login else { throw unsupported }
        return login
    }

    func replacingLogin(with login: DeepSeekLogin?) throws -> String {
        if let login { _ = try Self.savedLogin(login.snapshot) }
        var next = lines
        let indent = entries.first?.indent ?? 2
        let replacement = login.map {
            Self.reindent($0.snapshot.components(separatedBy: "\n").dropLast().map { $0 }, from: 2, to: indent)
        } ?? []
        if let entry = entries.first(where: { $0.key == Self.accountKey }) {
            next.replaceSubrange(entry.line..<entry.end, with: replacement)
            if login == nil && entries.count == 1, let records { next[records.line] = "records: {}" }
        } else if let records {
            if login != nil && records.value == "{}" { next[records.line] = "records:" }
            next.insert(contentsOf: replacement, at: records.line + 1)
        } else if login != nil {
            if next.last == "" { next.removeLast() }
            if roots.isEmpty { next += ["version: 1"] }
            next += ["records:"] + replacement + [""]
        }
        let result = next.joined(separator: newline)
        let verified = try Self(result)
        guard verified.login?.fingerprint == login?.fingerprint else { throw Self.unsupported }
        return result
    }

    private static var unsupported: DeepSeekError {
        .message("DeepSeek credentials use an unsupported or invalid format. Update Moa before saving or switching accounts.")
    }

    private static func content(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespaces)
    }
    private static func significant(_ line: String) -> Bool {
        let text = content(line)
        return !text.isEmpty && !text.hasPrefix("#")
    }
    private static func children(_ lines: [String], of parent: Entry) throws -> [Entry] {
        let range = (parent.line + 1)..<parent.end
        guard let first = range.first(where: { significant(lines[$0]) }) else { return [] }
        let indent = lines[first].prefix(while: { $0 == " " }).count
        guard indent > parent.indent else { throw unsupported }
        return try mapping(lines, range: range, indent: indent)
    }
    private static func mapping(_ lines: [String], range: Range<Int>, indent: Int) throws -> [Entry] {
        var starts: [(String, String, Int)] = []
        for index in range where significant(lines[index]) {
            let line = lines[index]
            let actual = line.prefix(while: { $0 == " " }).count
            guard actual >= indent else { throw unsupported }
            guard actual == indent else {
                guard !starts.isEmpty else { throw unsupported }
                continue
            }
            let (key, value) = try pair(String(line.dropFirst(indent)))
            guard key != "<<", !starts.contains(where: { $0.0 == key }) else { throw unsupported }
            starts.append((key, value, index))
        }
        return starts.enumerated().map { offset, item in
            var end = offset + 1 < starts.count ? starts[offset + 1].2 : range.upperBound
            while end > item.2 + 1 && !significant(lines[end - 1]) { end -= 1 }
            return Entry(key: item.0, value: item.1, line: item.2, end: end, indent: indent)
        }
    }
    private static func pair(_ text: String) throws -> (String, String) {
        var quote: Character?
        var escaped = false
        for index in text.indices {
            let character = text[index]
            if escaped { escaped = false; continue }
            if quote == "\"" && character == "\\" { escaped = true; continue }
            if let active = quote {
                if character == active { quote = nil }
            } else if character == "\"" || character == "'" { quote = character }
            else if character == ":" {
                let after = text.index(after: index)
                guard after == text.endIndex || text[after].isWhitespace else { continue }
                let key = try scalar(String(text[..<index]))
                guard !key.isEmpty else { throw unsupported }
                return (key, stripComment(String(text[after...])))
            }
        }
        throw unsupported
    }
    private static func stripComment(_ text: String) -> String {
        var quote: Character?
        var escaped = false
        for index in text.indices {
            let ch = text[index]
            if escaped { escaped = false; continue }
            if quote == "\"" && ch == "\\" { escaped = true; continue }
            if let active = quote { if ch == active { quote = nil } }
            else if ch == "\"" || ch == "'" { quote = ch }
            else if ch == "#" && (index == text.startIndex || text[text.index(before: index)].isWhitespace) {
                return content(String(text[..<index]))
            }
        }
        return content(text)
    }
    private static func scalar(_ raw: String) throws -> String {
        let value = stripComment(raw)
        if value.hasPrefix("\"") {
            guard let data = value.data(using: .utf8), let decoded = try? JSONDecoder().decode(String.self, from: data) else { throw unsupported }
            return decoded
        }
        if value.hasPrefix("'") {
            guard value.count >= 2, value.hasSuffix("'") else { throw unsupported }
            let body = String(value.dropFirst().dropLast())
            guard !body.replacingOccurrences(of: "''", with: "").contains("'") else { throw unsupported }
            return body.replacingOccurrences(of: "''", with: "'")
        }
        guard !value.isEmpty, !"&*!{|[>".contains(value.first!), !value.contains(": ") else { throw unsupported }
        // YAML core-schema booleans/null/numbers are not token strings. The
        // Harness serializer quotes a token consisting solely of such a value.
        let lower = value.lowercased()
        guard !["null", "~", "true", "false", ".nan", ".inf", "+.inf", "-.inf"].contains(lower),
              value.range(of: #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$|^[+-]?0[xXoO][0-9a-fA-F]+$"#, options: .regularExpression) == nil else { throw unsupported }
        return value
    }
    private static func reindent(_ lines: [String], from: Int, to: Int) -> [String] {
        lines.map { $0.isEmpty ? "" : String(repeating: " ", count: to) + $0.dropFirst(from) }
    }
}
