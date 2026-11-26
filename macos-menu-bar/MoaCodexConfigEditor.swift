import Foundation

enum MoaCodexConfigEditor {
    static func removingExperimentalBearerTokens(from text: String) -> String {
        var outputLines: [String] = []
        var currentTable = ""
        var skippingValue = false
        for context in MoaTomlEditor.lineContexts(in: text) {
            let line = context.text
            if context.isStatementStart {
                skippingValue = false
                if context.isStructural, let header = MoaTomlEditor.tableHeader(from: line) {
                    currentTable = header.contextName
                } else {
                    skippingValue = isManagedRemovalLine(line, currentTable: currentTable)
                }
            }
            if !skippingValue { outputLines.append(line) }
        }
        return MoaTomlEditor.collapseBlankLines(outputLines.joined(separator: "\n"))
    }

    static func restoringOfficialMode(from text: String) -> String {
        let selectedProviderID = rootTomlStringValue(in: text, key: "model_provider")
        var outputLines: [String] = []
        var currentTable = ""
        var skippingProviderTable = false
        var skippingValue = false

        for context in MoaTomlEditor.lineContexts(in: text) {
            let line = context.text
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if context.isStatementStart {
                skippingValue = false
                if context.isStructural, let header = MoaTomlEditor.tableHeader(from: trimmed) {
                    currentTable = header.contextName
                    skippingProviderTable = isUnselectedMoaManagedProviderTable(
                        header.name, selectedProviderID: selectedProviderID
                    )
                    if skippingProviderTable { continue }
                } else if !skippingProviderTable {
                    skippingValue = isOfficialRestoreRemovalLine(
                        line, currentTable: currentTable, selectedProviderID: selectedProviderID
                    )
                }
            }

            if skippingProviderTable {
                if context.isStatementStart, trimmed.isEmpty || trimmed.hasPrefix("#") {
                    outputLines.append(line)
                }
                continue
            }

            if !skippingValue { outputLines.append(line) }
        }

        return MoaTomlEditor.collapseBlankLines(outputLines.joined(separator: "\n"))
    }

    /// Strips ALL credentials, bearer tokens, API keys, custom auth headers, sensitive env tables,
    /// inline provider blocks, and URL embedded secrets across EVERY table (active, inactive,
    /// Moa-managed, and third-party, including multiline triple-quoted strings) for `.configOnly`
    /// ("Settings & Prices Only") exports.
    static func strippingAllCredentials(from text: String) -> String {
        let contexts = MoaTomlEditor.lineContexts(in: text)
        var outputLines: [String] = []
        var currentTable = ""
        var skippingSensitiveTable = false

        var index = 0
        while index < contexts.count {
            let startContext = contexts[index]
            var nextIndex = index + 1
            while nextIndex < contexts.count && !contexts[nextIndex].isStatementStart {
                nextIndex += 1
            }
            let statementLines = contexts[index..<nextIndex].map(\.text)
            let firstTrimmed = startContext.text.trimmingCharacters(in: .whitespacesAndNewlines)

            if statementLines.count == 1,
               startContext.isStructural,
               let header = MoaTomlEditor.tableHeader(from: firstTrimmed) {
                currentTable = header.contextName
                skippingSensitiveTable = isSensitiveConfigOnlyTable(header.name)
                if !skippingSensitiveTable {
                    outputLines.append(startContext.text)
                }
                index = nextIndex
                continue
            }

            if skippingSensitiveTable {
                index = nextIndex
                continue
            }

            let fullStatement = statementLines.joined(separator: "\n")
            if let entry = MoaTomlEditor.keyValue(from: fullStatement) {
                if shouldStripConfigOnlyEntry(key: entry.key, value: entry.value, currentTable: currentTable) {
                    index = nextIndex
                    continue
                }
                let leadingWhitespace = String(startContext.text.prefix { $0 == " " || $0 == "\t" })
                if let sanitized = sanitizingConfigOnlyEntry(
                    leadingWhitespace: leadingWhitespace,
                    key: entry.key,
                    value: entry.value
                ) {
                    outputLines.append(sanitized)
                } else {
                    outputLines.append(contentsOf: statementLines.map { sanitizingEmbeddedURLs(inLine: $0) })
                }
            } else {
                outputLines.append(contentsOf: statementLines)
            }

            index = nextIndex
        }

        return MoaTomlEditor.collapseBlankLines(outputLines.joined(separator: "\n"))
    }

    private static func isSensitiveConfigOnlyTable(_ tableName: String) -> Bool {
        let components = (MoaTomlEditor.keyPathComponents(tableName) ?? [tableName])
            .map { MoaTomlEditor.unquotedKey($0).lowercased() }
        return components.contains { component in
            component == "env"
                || component == "headers"
                || component == "http_headers"
                || component == "env_http_headers"
                || component == "auth"
                || component == "credentials"
                || component.contains("secret")
                || component.contains("token")
        }
    }

    private static func shouldStripConfigOnlyEntry(key: String, value: String, currentTable: String) -> Bool {
        let components = (MoaTomlEditor.keyPathComponents(key) ?? [key])
            .map { MoaTomlEditor.unquotedKey($0).lowercased() }

        // Inline model_providers table at root may embed bearer tokens or headers.
        if currentTable.isEmpty, components.first == "model_providers" {
            return true
        }

        let sensitiveFragments = [
            "token", "secret", "password", "passwd", "api_key", "apikey",
            "authorization", "credential", "private_key", "cookie", "bearer",
            "http_headers", "env_http_headers", "headers", "access_key", "client_secret"
        ]
        for component in components {
            if component == "auth" || component == "key" || component == "env" {
                return true
            }
            if sensitiveFragments.contains(where: { component.contains($0) }) {
                return true
            }
        }

        let valueLower = value.lowercased()
        let trimmedValue = MoaTomlEditor.trimInlineComment(from: value).trimmingCharacters(in: .whitespacesAndNewlines)
        if valueLower.contains("bearer ")
            || valueLower.contains("experimental_bearer_token")
            || valueLower.contains("authorization") {
            return true
        }
        // Inline tables containing secret/key/token fields must be stripped wholesale.
        if trimmedValue.hasPrefix("{") {
            let inlineSecretFragments = ["api_key", "apikey", "token", "secret", "password", "passwd", "credential", "cookie"]
            if inlineSecretFragments.contains(where: { valueLower.contains($0) }) {
                return true
            }
        }

        return false
    }

    private static func sanitizingConfigOnlyEntry(
        leadingWhitespace: String,
        key: String,
        value: String
    ) -> String? {
        let trimmedValue = MoaTomlEditor.trimInlineComment(from: value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decoded = MoaTomlEditor.decodedString(trimmedValue) else {
            return nil
        }
        let trimmedDecoded = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyLower = MoaTomlEditor.unquotedKey(key).lowercased()
        let isURLKey = keyLower.contains("url") || keyLower.contains("endpoint")
        let looksLikeURL = trimmedDecoded.lowercased().hasPrefix("http://")
            || trimmedDecoded.lowercased().hasPrefix("https://")
        guard isURLKey || looksLikeURL else {
            return nil
        }
        let sanitized = MoaDataPackageCrypto.sanitizedURLString(trimmedDecoded)
        guard sanitized != decoded else {
            return nil
        }
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(leadingWhitespace)\(trimmedKey) = \(MoaTomlEditor.quotedString(sanitized))"
    }

    private static func sanitizingEmbeddedURLs(inLine line: String) -> String {
        guard line.contains("://"),
              let regex = try? NSRegularExpression(pattern: #"https?://[^\s"'`<>\]\)}]+"#, options: [.caseInsensitive]) else {
            return line
        }
        let nsLine = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
        guard !matches.isEmpty else { return line }
        var result = line
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let raw = String(result[range])
            let clean = MoaDataPackageCrypto.sanitizedURLString(raw)
            if clean != raw {
                result.replaceSubrange(range, with: clean)
            }
        }
        return result
    }

    static func providerBlock(
        providerID: String,
        displayName: String? = nil,
        baseURL: String,
        apiKey: String,
        extraLines: [String]
    ) -> String {
        ([
            "[\(MoaTomlEditor.keyPath(["model_providers", providerID]))]",
            "name = \(MoaTomlEditor.quotedString(displayName ?? providerID))",
            "base_url = \(MoaTomlEditor.quotedString(baseURL))",
            "experimental_bearer_token = \(MoaTomlEditor.quotedString(apiKey))",
            #"wire_api = "responses""#,
            "requires_openai_auth = true"
        ] + extraLines).joined(separator: "\n")
    }

    private static func isManagedRemovalLine(_ line: String, currentTable: String) -> Bool {
        if currentTable.isEmpty {
            return isOfficialModeRootRemovedLine(line)
        }
        guard isMoaManagedProviderTable(currentTable), MoaTomlEditor.keyPathComponents(currentTable)?.count == 2 else {
            return false
        }
        return isMoaProviderRemovedLine(line)
    }

    private static func isMoaProviderRemovedLine(_ line: String) -> Bool {
        guard let entry = MoaTomlEditor.keyValue(from: line) else { return false }
        let key = MoaTomlEditor.unquotedKey(entry.key)
        return key == "experimental_bearer_token" || key == "base_url"
    }

    private static func isMoaManagedProviderTable(_ tableName: String) -> Bool {
        providerID(fromTable: tableName)?.hasPrefix("moa-") == true
    }

    private static func isUnselectedMoaManagedProviderTable(_ tableName: String, selectedProviderID: String?) -> Bool {
        guard isMoaManagedProviderTable(tableName) else {
            return false
        }
        guard let selectedProviderID,
              let providerID = providerID(fromTable: tableName)
        else {
            return true
        }
        return providerID != selectedProviderID
    }

    private static func isOfficialRestoreRemovalLine(
        _ line: String,
        currentTable: String,
        selectedProviderID: String?
    ) -> Bool {
        if currentTable.isEmpty {
            return isOfficialModeRootRemovedLine(line)
        }
        if isMoaManagedProviderTable(currentTable) {
            guard MoaTomlEditor.keyPathComponents(currentTable)?.count == 2 else { return false }
            return isMoaProviderRemovedLine(line)
        }
        guard isSelectedProviderTable(currentTable, selectedProviderID: selectedProviderID) else {
            return false
        }
        return isMoaProviderRemovedLine(line)
    }

    private static func isSelectedProviderTable(_ tableName: String, selectedProviderID: String?) -> Bool {
        guard MoaTomlEditor.keyPathComponents(tableName)?.count == 2 else { return false }
        guard let providerID = providerID(fromTable: tableName) else {
            return false
        }
        guard let selectedProviderID else {
            return false
        }
        return providerID == selectedProviderID
    }

    private static func providerID(fromTable tableName: String) -> String? {
        guard let components = MoaTomlEditor.keyPathComponents(tableName), components.count >= 2,
              components[0] == "model_providers", !components[1].isEmpty else { return nil }
        return components[1]
    }

    private static func rootTomlStringValue(in text: String, key: String) -> String? {
        MoaTomlEditor.stringValue(in: text, table: "", key: key)
    }

    private static func isOfficialModeRootRemovedLine(_ line: String) -> Bool {
        guard let entry = MoaTomlEditor.keyValue(from: line) else { return false }
        let key = MoaTomlEditor.unquotedKey(entry.key)
        return [
            "model",
            "experimental_bearer_token",
            "base_url"
        ].contains(key)
    }

}
