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
