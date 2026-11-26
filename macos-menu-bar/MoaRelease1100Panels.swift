import AppKit
import SwiftUI

enum MoaRelease1100Panels {
    struct ClaudeCodeProviderInput {
        let name: String
        let baseURL: String
        let apiKey: String
        let model: String
        let smallFastModel: String?
    }

    struct ExportDataPackageOptions {
        let scope: MoaDataPackageScope
        let password: String?
    }

    static func showClaudeCodeProvider(
        editing existing: ClaudeCodeProviderProfile? = nil
    ) -> ClaudeCodeProviderInput? {
        var result: ClaudeCodeProviderInput?
        let title = existing == nil
            ? MoaL10n.text("Add Claude Code Provider")
            : MoaL10n.text("Edit Claude Code Provider")
        MoaGlassModalHost.runModal(width: 540, fallbackHeight: 540, title: title) {
            ClaudeCodeProviderFormView(
                title: title,
                existing: existing,
                onSave: { input in
                    result = input
                    MoaGlassModalHost.finish(.OK)
                },
                onCancel: {
                    MoaGlassModalHost.finish(.cancel)
                }
            )
        }
        return result
    }

    static func showExportDataPackageOptions() -> ExportDataPackageOptions? {
        var result: ExportDataPackageOptions?
        MoaGlassModalHost.runModal(width: 520, fallbackHeight: 460, title: MoaL10n.text("Export Moa Data Package")) {
            ExportDataPackageOptionsFormView(
                onContinue: { options in
                    result = options
                    MoaGlassModalHost.finish(.OK)
                },
                onCancel: {
                    MoaGlassModalHost.finish(.cancel)
                }
            )
        }
        return result
    }

    static func showImportPasswordPrompt(inspection: MoaDataPackageInspection) -> String? {
        var result: String?
        MoaGlassModalHost.runModal(width: 480, fallbackHeight: 300, title: MoaL10n.text("Unlock Encrypted Data Package")) {
            ImportPasswordFormView(
                inspection: inspection,
                onUnlock: { password in
                    result = password
                    MoaGlassModalHost.finish(.OK)
                },
                onCancel: {
                    MoaGlassModalHost.finish(.cancel)
                }
            )
        }
        return result
    }
}

private struct ClaudeCodeProviderFormView: View {
    let title: String
    let existing: ClaudeCodeProviderProfile?
    let onSave: (MoaRelease1100Panels.ClaudeCodeProviderInput) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var baseURL: String
    @State private var apiKey: String
    @State private var model: String
    @State private var smallFastModel: String
    @State private var statusText: String = ""

    init(
        title: String,
        existing: ClaudeCodeProviderProfile?,
        onSave: @escaping (MoaRelease1100Panels.ClaudeCodeProviderInput) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.existing = existing
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: existing?.name ?? "")
        _baseURL = State(initialValue: existing?.baseURL ?? "")
        _apiKey = State(initialValue: existing?.apiKey ?? "")
        _model = State(initialValue: existing?.model ?? ProviderConnectionTester.claudeDefaultTestModel)
        _smallFastModel = State(initialValue: existing?.smallFastModel ?? "")
    }

    var body: some View {
        MoaModalForm {
            MoaModalHeader(
                icon: "terminal.fill",
                title: title,
                message: MoaL10n.text("Applies only to Claude Code (~/.claude/settings.json env fields). Claude Desktop settings stay untouched.")
            )
        } fields: {
            VStack(alignment: .leading, spacing: 14) {
                field("Profile Name", placeholder: "Example: Relay Claude Code", text: $name)
                field("API Base URL", placeholder: "https://api.example.com", text: $baseURL)
                VStack(alignment: .leading, spacing: 6) {
                    MoaModalFieldLabel(text: MoaL10n.text("API Key"))
                    SecureField("sk-ant-...", text: $apiKey)
                        .moaModalFieldChrome()
                }
                field("Primary Model", placeholder: "claude-sonnet-4-6", text: $model)
                field("Small / Fast Model (Optional)", placeholder: "claude-haiku-4-5", text: $smallFastModel)

                Text(statusText.isEmpty ? " " : statusText)
                    .id("moa-form-status")
                    .preference(key: MoaFormStatusPreferenceKey.self, value: statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(MoaTheme.coral)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 16, alignment: .leading)
            }
        } footer: {
            HStack(spacing: 10) {
                Spacer()
                MoaModalButton(title: MoaL10n.text("Cancel"), action: onCancel)
                MoaModalButton(title: MoaL10n.text(existing == nil ? "Add" : "Save"), prominence: .prominent, keyEquivalent: "\r", action: save)
            }
        }
    }

    private func field(_ labelKey: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MoaModalFieldLabel(text: MoaL10n.text(labelKey))
            TextField(placeholder, text: text)
                .moaModalFieldChrome()
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedURL.isEmpty, !trimmedKey.isEmpty else {
            statusText = MoaL10n.text("Name, base URL, and API key are required.")
            return
        }
        guard (try? MoaProviderBaseURLPolicy.validate(trimmedURL)) != nil else {
            statusText = MoaL10n.text("Claude Code API Base URL must use https://; only localhost, 127.0.0.1, and ::1 may use http://.")
            return
        }
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSmall = smallFastModel.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(MoaRelease1100Panels.ClaudeCodeProviderInput(
            name: trimmedName,
            baseURL: trimmedURL,
            apiKey: trimmedKey,
            model: trimmedModel.isEmpty ? ProviderConnectionTester.claudeDefaultTestModel : trimmedModel,
            smallFastModel: trimmedSmall.isEmpty ? nil : trimmedSmall
        ))
    }
}

private struct ExportDataPackageOptionsFormView: View {
    let onContinue: (MoaRelease1100Panels.ExportDataPackageOptions) -> Void
    let onCancel: () -> Void

    @State private var scope: MoaDataPackageScope = .fullBackup
    @State private var encryptPackage: Bool = true
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var statusText: String = ""

    var body: some View {
        MoaModalForm {
            MoaModalHeader(
                icon: "lock.doc.fill",
                title: MoaL10n.text("Export Moa Data Package"),
                message: MoaL10n.text("Choose what to include and whether to encrypt the archive with AES-256-GCM (Schema 3).")
            )
        } fields: {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    MoaModalFieldLabel(text: MoaL10n.text("Export Scope"))
                    Picker(MoaL10n.text("Export Scope"), selection: $scope) {
                        ForEach(MoaDataPackageScope.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    .font(.system(size: 12))
                }

                Divider()

                Toggle(MoaL10n.text("Encrypt package with a password (Recommended)"), isOn: $encryptPackage)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 13, weight: .medium))

                if encryptPackage {
                    VStack(alignment: .leading, spacing: 6) {
                        MoaModalFieldLabel(text: MoaL10n.text("Encryption Password"))
                        SecureField(MoaL10n.text("Enter password"), text: $password)
                            .moaModalFieldChrome()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        MoaModalFieldLabel(text: MoaL10n.text("Confirm Password"))
                        SecureField(MoaL10n.text("Re-enter password"), text: $confirmPassword)
                            .moaModalFieldChrome()
                    }
                } else {
                    Text(MoaL10n.text("Unencrypted ZIP (Schema 2): store only in a trusted location."))
                        .font(.system(size: 11))
                        .foregroundStyle(MoaTheme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(statusText.isEmpty ? " " : statusText)
                    .id("moa-form-status")
                    .preference(key: MoaFormStatusPreferenceKey.self, value: statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(MoaTheme.coral)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 16, alignment: .leading)
            }
        } footer: {
            HStack(spacing: 10) {
                Spacer()
                MoaModalButton(title: MoaL10n.text("Cancel"), action: onCancel)
                MoaModalButton(title: MoaL10n.text("Export"), prominence: .prominent, keyEquivalent: "\r", action: submit)
            }
        }
    }

    private func submit() {
        if encryptPackage {
            guard !password.isEmpty else {
                statusText = MoaL10n.text("Enter a non-empty password.")
                return
            }
            guard password == confirmPassword else {
                statusText = MoaL10n.text("Passwords do not match.")
                return
            }
            onContinue(.init(scope: scope, password: password))
        } else {
            onContinue(.init(scope: scope, password: nil))
        }
    }
}

private struct ImportPasswordFormView: View {
    let inspection: MoaDataPackageInspection
    let onUnlock: (String) -> Void
    let onCancel: () -> Void

    @State private var password: String = ""
    @State private var statusText: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        MoaModalForm {
            MoaModalHeader(
                icon: "key.fill",
                title: MoaL10n.text("Unlock Encrypted Data Package"),
                message: MoaL10n.format("Schema 3 encrypted archive (Moa %@ · %@). Enter the password used during export.", inspection.appVersion, inspection.scope.title)
            )
        } fields: {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    MoaModalFieldLabel(text: MoaL10n.text("Password"))
                    SecureField(MoaL10n.text("Enter password"), text: $password)
                        .moaModalFieldChrome()
                        .focused($focused)
                        .onSubmit(submit)
                }
                Text(statusText.isEmpty ? " " : statusText)
                    .id("moa-form-status")
                    .preference(key: MoaFormStatusPreferenceKey.self, value: statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(MoaTheme.coral)
                    .frame(minHeight: 16, alignment: .leading)
            }
        } footer: {
            HStack(spacing: 10) {
                Spacer()
                MoaModalButton(title: MoaL10n.text("Cancel"), action: onCancel)
                MoaModalButton(title: MoaL10n.text("Unlock & Import"), prominence: .prominent, keyEquivalent: "\r", action: submit)
            }
        }
        .onAppear { focused = true }
    }

    private func submit() {
        guard !password.isEmpty else {
            statusText = MoaL10n.text("Enter a non-empty password.")
            return
        }
        onUnlock(password)
    }
}
