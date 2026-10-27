import Foundation

extension ConfigProfileController {
    func hasInlineProviderRoot(in config: String) -> Bool {
        tomlEntries(in: config).contains { entry in
            entry.table.isEmpty && MoaTomlEditor.keyPathComponents(entry.key) == ["model_providers"]
        }
    }

    func validateProviderConfigForWrite(_ config: String) throws {
        guard !hasInlineProviderRoot(in: config) else {
            throw NSError(domain: "Moa", code: 422, userInfo: [NSLocalizedDescriptionKey:
                MoaL10n.text("Cannot switch providers while model_providers is an inline TOML table. Expand it into TOML tables first.")])
        }
    }

    func generateConfig(_ config: String, selecting profile: ConfigProfile) -> String {
        var output = config.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Self.defaultConfig : config
        let providerID = providerID(for: profile, in: output)
        let providerTable = MoaTomlEditor.keyPath(["model_providers", providerID])
        let extraProviderLines = providerExtraLines(in: output, table: providerTable)

        output = removeTomlTables(in: output) { MoaTomlEditor.keyPathComponents($0) == ["model_providers", providerID] }

        output = upsertRootTomlStringValue(in: output, key: "model_provider", value: providerID)
        if let model = profile.resolvedModel {
            output = upsertRootTomlStringValue(in: output, key: "model", value: model)
        }
        output = insertProviderBlock(providerBlock(for: profile, providerID: providerID, extraLines: extraProviderLines), into: output)
        return collapseTomlBlankLines(output)
    }

    func providerID(for profile: ConfigProfile, in config: String) -> String {
        let selected = rootTomlStringValue(in: config, key: "model_provider")
        if let selected, !selected.isEmpty, selected != "openai",
           !hasDottedProviderEntries(selected, in: config) {
            return selected
        }

        // A missing selector means the built-in provider, not the first stored
        // provider. Dotted assignments also define their table implicitly, so
        // adding an explicit table of the same name would make TOML invalid.
        let occupied = providerIDsDefined(in: config)
        var candidate = "moa-custom"
        var suffix = 2
        while occupied.contains(candidate) {
            candidate = "moa-custom-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func providerIDsDefined(in config: String) -> Set<String> {
        var ids = Set<String>()
        for table in tomlTableNames(in: config) {
            guard let parts = MoaTomlEditor.keyPathComponents(table),
                  parts.count >= 2, parts[0] == "model_providers" else { continue }
            ids.insert(parts[1])
        }
        for entry in tomlEntries(in: config) {
            let table = MoaTomlEditor.keyPathComponents(entry.table) ?? []
            guard let key = MoaTomlEditor.keyPathComponents(entry.key) else { continue }
            let parts = table + key
            guard parts.count >= 2, parts[0] == "model_providers" else { continue }
            ids.insert(parts[1])
        }
        return ids
    }

    private func hasDottedProviderEntries(_ id: String, in config: String) -> Bool {
        tomlEntries(in: config).contains { entry in
            let table = MoaTomlEditor.keyPathComponents(entry.table) ?? []
            guard let key = MoaTomlEditor.keyPathComponents(entry.key) else { return false }
            let parts = table + key
            return table.count < 2 && parts.count >= 2
                && parts[0] == "model_providers" && parts[1] == id
        }
    }

    static func providerIdentifierSlug(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        let scalars = value.lowercased().unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        return String(scalars)
            .split(separator: "_", omittingEmptySubsequences: true)
            .joined(separator: "_")
    }

    func syncedMoaConfig() throws -> String {
        var moaConfig = (try? String(contentsOf: moaConfigURL, encoding: .utf8)) ?? Self.defaultConfig
        guard fileManager.fileExists(atPath: codexConfigURL.path) else { return moaConfig }
        let codexConfig = try String(contentsOf: codexConfigURL, encoding: .utf8)

        let syncedConfig = syncConfigStructure(from: codexConfig, into: moaConfig)
        if syncedConfig != moaConfig {
            moaConfig = syncedConfig
            try writeText(moaConfig, to: moaConfigURL)
        }

        return moaConfig
    }

    func syncConfigStructure(from codexConfig: String, into moaConfig: String) -> String {
        // The live client owns all settings except the provider selected by the
        // explicit apply operation. Replaying the Moa snapshot resurrects deleted
        // settings and overwrites current desktop preferences.
        // Keep the original text, including unknown tables and multiline values.
        codexConfig
    }

    typealias TomlEntry = MoaTomlEditor.Entry

    func tomlEntries(in text: String) -> [TomlEntry] {
        MoaTomlEditor.entries(in: text)
    }

    func parseTomlTableName(from line: String) -> String? {
        MoaTomlEditor.tableName(from: line)
    }

    func parseTomlKeyValue(from line: String) -> (key: String, value: String)? {
        MoaTomlEditor.keyValue(from: line)
    }

    func trimTomlInlineComment(from value: String) -> String {
        MoaTomlEditor.trimInlineComment(from: value)
    }

    func appendTomlEntry(_ entry: TomlEntry, to text: String) -> String {
        var output = text
        if !output.hasSuffix("\n") {
            output.append("\n")
        }

        if entry.table.isEmpty {
            let insertion = tomlRootInsertionIndex(in: output)
            let prefix = insertion > output.startIndex && output[output.index(before: insertion)] == "\n" ? "" : "\n"
            output.insert(contentsOf: "\(prefix)\(entry.lineText)\n", at: insertion)
            return output
        }

        if !tomlHasTable(entry.table, in: output) {
            output.append("\n[\(entry.table)]\n")
            output.append("\(entry.lineText)\n")
            return output
        }

        let insertion = tomlTableInsertionIndex(for: entry.table, in: output) ?? output.endIndex
        let prefix = insertion > output.startIndex && output[output.index(before: insertion)] == "\n" ? "" : "\n"
        output.insert(contentsOf: "\(prefix)\(entry.lineText)\n", at: insertion)
        return output
    }

    func tomlRootInsertionIndex(in text: String) -> String.Index {
        var insertionIndex = text.endIndex

        for context in MoaTomlEditor.lineContexts(in: text) {
            let line = context.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if context.isStructural, MoaTomlEditor.tableHeader(from: line) != nil {
                return context.contentRange.lowerBound
            }
            insertionIndex = context.nextLineStart
        }

        return insertionIndex
    }

    func tomlHasTable(_ table: String, in text: String) -> Bool {
        tomlTableNames(in: text).contains { MoaTomlEditor.keyPathComponents($0) == MoaTomlEditor.keyPathComponents(table) }
    }

    func tomlTableInsertionIndex(for table: String, in text: String) -> String.Index? {
        var currentTable = ""
        var foundTable = false
        var insertionIndex: String.Index?
        for context in MoaTomlEditor.lineContexts(in: text) {
            let line = context.text.trimmingCharacters(in: .whitespacesAndNewlines)

            if context.isStructural, let header = MoaTomlEditor.tableHeader(from: line) {
                let tableName = header.contextName
                if foundTable && tableName != currentTable {
                    return context.contentRange.lowerBound
                }

                currentTable = tableName
                if !header.isArray, MoaTomlEditor.keyPathComponents(tableName) == MoaTomlEditor.keyPathComponents(table) {
                    foundTable = true
                    insertionIndex = context.nextLineStart
                }
            } else if foundTable {
                insertionIndex = context.nextLineStart
            }
        }

        return foundTable ? insertionIndex : nil
    }

    func replaceTomlEntry(_ entry: TomlEntry, with value: String, in text: String) -> String {
        var output = text
        if let range = Range(NSRange(entry.lineRange, in: text), in: output) {
            output.replaceSubrange(range, with: "\(entry.key) = \(value)")
        }
        return output
    }

    func isMarketplaceLastUpdated(_ path: String) -> Bool {
        path.hasPrefix("marketplaces.") && path.hasSuffix(".last_updated")
    }

    func isMoaManagedConfigPath(_ path: String) -> Bool {
        path == "model_provider"
            || path.hasPrefix("model_providers.")
    }

    func rootTomlStringValue(in text: String, key: String) -> String? {
        tomlStringValue(in: text, table: "", key: key)
    }

    func tomlStringValue(in text: String, table: String, key: String) -> String? {
        MoaTomlEditor.stringValue(in: text, table: table, key: key)
    }

    func providerID(fromTable table: String) -> String? {
        guard let components = MoaTomlEditor.keyPathComponents(table), components.count == 2,
              components[0] == "model_providers", !components[1].isEmpty else { return nil }
        return components[1]
    }

    func providerTableIDs(in text: String) -> [String] {
        var ids: [String] = []
        var seen = Set<String>()

        for table in tomlTableNames(in: text) {
            guard let id = providerID(fromTable: table), !seen.contains(id) else {
                continue
            }
            ids.append(id)
            seen.insert(id)
        }

        return ids
    }

    func tomlTableNames(in text: String) -> [String] {
        MoaTomlEditor.lineContexts(in: text).compactMap { context in
            guard context.isStructural else { return nil }
            return parseTomlTableName(from: context.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    func providerExtraLines(in text: String, table: String) -> [String] {
        let managedKeys: Set<String> = ["name", "base_url", "experimental_bearer_token", "wire_api", "requires_openai_auth"]
        var currentTable = ""
        var skippingManagedValue = false
        var lines: [String] = []
        for context in MoaTomlEditor.lineContexts(in: text) {
            let trimmed = context.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if context.isStructural, let header = MoaTomlEditor.tableHeader(from: trimmed) {
                currentTable = header.contextName
                skippingManagedValue = false
                continue
            }
            guard MoaTomlEditor.keyPathComponents(currentTable) == MoaTomlEditor.keyPathComponents(table) else { continue }
            if context.isStatementStart {
                skippingManagedValue = parseTomlKeyValue(from: context.text).map {
                    managedKeys.contains(MoaTomlEditor.unquotedKey($0.key))
                } ?? false
            }
            if !skippingManagedValue { lines.append(context.text) }
        }
        return lines
    }

    func providerBlock(for profile: ConfigProfile, providerID: String, extraLines: [String]) -> String {
        MoaCodexConfigEditor.providerBlock(
            providerID: providerID,
            displayName: nil,
            baseURL: profile.baseURL,
            apiKey: profile.apiKey,
            extraLines: extraLines
        )
    }

    func removeProviderTables(from text: String) -> String {
        removeTomlTables(in: text) { providerID(fromTable: $0) != nil }
    }

    func removeTomlTables(in text: String, where shouldRemove: (String) -> Bool) -> String {
        var outputLines: [String] = []
        var skipping = false

        for context in MoaTomlEditor.lineContexts(in: text) {
            let line = context.text
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if context.isStructural {
                if let header = MoaTomlEditor.tableHeader(from: trimmed) {
                    skipping = shouldRemove(header.name)
                }
            }

            if !skipping {
                outputLines.append(line)
            }
        }

        return collapseTomlBlankLines(outputLines.joined(separator: "\n"))
    }

    func insertProviderBlock(_ providerBlock: String, into text: String) -> String {
        guard !providerBlock.isEmpty else {
            return text
        }

        var output = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let insertion = tomlTableInsertionIndex(for: "features", in: output) ?? output.endIndex

        if insertion == output.endIndex {
            if !output.hasSuffix("\n") {
                output.append("\n")
            }
            if !output.hasSuffix("\n\n") {
                output.append("\n")
            }
            output.append(providerBlock)
            return output
        }

        let prefix: String
        let beforeInsertion = output[..<insertion]
        if beforeInsertion.hasSuffix("\n\n") {
            prefix = ""
        } else if beforeInsertion.hasSuffix("\n") {
            prefix = "\n"
        } else {
            prefix = "\n\n"
        }

        let suffix = output[insertion...].hasPrefix("\n") ? "" : "\n"
        output.insert(contentsOf: "\(prefix)\(providerBlock)\n\(suffix)", at: insertion)
        return output
    }

    func collapseTomlBlankLines(_ text: String) -> String {
        MoaTomlEditor.collapseBlankLinesBeforeTables(text)
    }

    func tomlTableBlockRange(for table: String, in text: String) -> Range<String.Index>? {
        var tableStart: String.Index?

        for context in MoaTomlEditor.lineContexts(in: text) where context.isStructural {
            let line = context.text.trimmingCharacters(in: .whitespacesAndNewlines)

            if let tableName = parseTomlTableName(from: line) {
                if let start = tableStart, tableName != table {
                    return start..<context.contentRange.lowerBound
                }

                if tableName == table {
                    tableStart = context.contentRange.lowerBound
                }
            }
        }

        if let start = tableStart {
            return start..<text.endIndex
        }

        return nil
    }

    func firstTomlStringValue(in text: String, key: String) -> String? {
        guard let entry = tomlEntries(in: text).first(where: { $0.key == key }) else {
            return nil
        }
        let raw = entry.value
        guard (raw.hasPrefix("\"") && raw.hasSuffix("\""))
                || (raw.hasPrefix("'") && raw.hasSuffix("'"))
        else {
            return nil
        }
        return unquoteTomlString(raw)
    }

    func upsertRootTomlStringValue(in text: String, key: String, value: String) -> String {
        MoaTomlEditor.upsertingString(value, in: text, table: "", key: key)
    }

    func tomlQuoted(_ value: String) -> String {
        MoaTomlEditor.quotedString(value)
    }

    func unquoteTomlString(_ raw: String) -> String {
        MoaTomlEditor.unquoteString(raw)
    }
}
