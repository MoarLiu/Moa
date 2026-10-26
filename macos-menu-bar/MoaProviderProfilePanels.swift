import AppKit
import Foundation
import SwiftUI

enum MoaProviderProfilePanels {
    static func showOfficialAccountName(
        title: String,
        message: String,
        buttonTitle: String,
        initialName: String
    ) -> String? {
        var result: String?
        MoaGlassModalHost.runModal(width: 480, fallbackHeight: 270, title: title) {
            CodexOfficialAccountNameFormView(
                title: title,
                message: message,
                buttonTitle: buttonTitle,
                initialName: initialName,
                onSave: { name in
                    result = name
                    NSApp.stopModal(withCode: .OK)
                },
                onCancel: {
                    NSApp.stopModal(withCode: .cancel)
                }
            )
        }
        return result
    }

    static func showAddCodexProfile() -> (name: String, baseURL: String, apiKey: String)? {
        showCodexProfilePanel(
            title: MoaL10n.text("Add Codex Config"),
            message: MoaL10n.text("Add a Codex provider profile. Moa will use it when switching configs."),
            buttonTitle: MoaL10n.text("Add"),
            initialProfile: nil
        )
    }

    static func showAddCodexPresetProfile(_ preset: MoaProviderPreset) -> (name: String, baseURL: String, apiKey: String)? {
        showCodexProfilePanel(
            title: MoaL10n.format("Add %@", preset.name),
            message: MoaL10n.text("Add a Responses-compatible provider preset for Codex. Moa will configure Codex directly and will not translate the upstream protocol."),
            buttonTitle: MoaL10n.text("Add"),
            initial: CodexProfileFormView.Initial(preset: preset)
        )
    }

    static func showEditCodexProfile(for profile: ConfigProfile) -> (name: String, baseURL: String, apiKey: String)? {
        showCodexProfilePanel(
            title: MoaL10n.text("Edit Codex Config"),
            message: MoaL10n.text("Update this Codex provider profile. Moa will apply the saved config right away."),
            buttonTitle: MoaL10n.text("Save"),
            initialProfile: profile
        )
    }

    static func showAddClaudeDesktopProvider() -> (name: String, baseURL: String, apiKey: String, models: [String], oneMModels: [String])? {
        showClaudeDesktopProviderPanel(
            title: MoaL10n.text("Add Claude Desktop Provider"),
            message: MoaL10n.text("Add a direct 3P provider for Claude Desktop. Moa writes Claude Desktop's 3P profile only."),
            buttonTitle: MoaL10n.text("Add"),
            initialProfile: nil
        )
    }

    static func showEditClaudeDesktopProvider(
        for profile: ClaudeDesktopProviderProfile
    ) -> (name: String, baseURL: String, apiKey: String, models: [String], oneMModels: [String])? {
        showClaudeDesktopProviderPanel(
            title: MoaL10n.text("Edit Claude Desktop Provider"),
            message: MoaL10n.text("Update this direct 3P provider. Moa will apply the saved Claude Desktop profile right away."),
            buttonTitle: MoaL10n.text("Save"),
            initialProfile: profile
        )
    }

    private static func showCodexProfilePanel(
        title: String,
        message: String,
        buttonTitle: String,
        initialProfile: ConfigProfile?
    ) -> (name: String, baseURL: String, apiKey: String)? {
        let initial: CodexProfileFormView.Initial? = initialProfile.map {
            CodexProfileFormView.Initial(profile: $0)
        }
        return showCodexProfilePanel(
            title: title,
            message: message,
            buttonTitle: buttonTitle,
            initial: initial
        )
    }

    private static func showCodexProfilePanel(
        title: String,
        message: String,
        buttonTitle: String,
        initial: CodexProfileFormView.Initial?
    ) -> (name: String, baseURL: String, apiKey: String)? {
        var result: (name: String, baseURL: String, apiKey: String)?

        MoaGlassModalHost.runModal(width: 560, fallbackHeight: 560, title: title) {
            CodexProfileFormView(
                title: title,
                message: message,
                buttonTitle: buttonTitle,
                initial: initial,
                onSave: { name, baseURL, apiKey in
                    result = (name, baseURL, apiKey)
                    NSApp.stopModal(withCode: .OK)
                },
                onCancel: {
                    NSApp.stopModal(withCode: .cancel)
                }
            )
        }

        return result
    }

    private static func showClaudeDesktopProviderPanel(
        title: String,
        message: String,
        buttonTitle: String,
        initialProfile: ClaudeDesktopProviderProfile?
    ) -> (name: String, baseURL: String, apiKey: String, models: [String], oneMModels: [String])? {
        var result: (name: String, baseURL: String, apiKey: String, models: [String], oneMModels: [String])?
        let initial: ClaudeProviderFormView.Initial? = initialProfile.map { profile in
            let oneMModelSet = Set(profile.enabledOneMModels)
            let modelsText = profile.models
                .map { oneMModelSet.contains($0) ? "\($0)[1M]" : $0 }
                .joined(separator: ", ")
            return ClaudeProviderFormView.Initial(
                name: profile.name,
                baseURL: profile.baseURL,
                apiKey: profile.apiKey,
                modelsText: modelsText
            )
        }

        MoaGlassModalHost.runModal(width: 560, fallbackHeight: 640, title: title) {
            ClaudeProviderFormView(
                title: title,
                message: message,
                buttonTitle: buttonTitle,
                initial: initial,
                onSave: { name, baseURL, apiKey, models, oneMModels in
                    result = (name, baseURL, apiKey, models, oneMModels)
                    NSApp.stopModal(withCode: .OK)
                },
                onCancel: {
                    NSApp.stopModal(withCode: .cancel)
                }
            )
        }

        return result
    }
}

// MARK: - Codex official account form

private struct CodexOfficialAccountNameFormView: View {
    let title: String
    let message: String
    let buttonTitle: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var statusText: String = ""
    @State private var statusTone: MoaFormStatusTone = .neutral
    @FocusState private var nameFocused: Bool

    init(
        title: String,
        message: String,
        buttonTitle: String,
        initialName: String,
        onSave: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.buttonTitle = buttonTitle
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MoaModalHeader(icon: "person.crop.circle.badge.checkmark", title: title, message: message)

            VStack(alignment: .leading, spacing: 7) {
                MoaModalFieldLabel(text: MoaL10n.text("Account Name"))
                TextField(MoaL10n.text("Example: OpenAI Personal"), text: $name)
                    .moaModalFieldChrome()
                    .focused($nameFocused)
            }

            Text(statusText.isEmpty ? " " : statusText)
                .font(.system(size: 12))
                .foregroundStyle(statusTone.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 16, alignment: .leading)

            HStack(spacing: 10) {
                Spacer()
                Button(MoaL10n.text("Cancel"), action: onCancel)
                    .frame(minWidth: 78)
                    .controlSize(.regular)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button(buttonTitle, action: save)
                    .frame(minWidth: 88)
                    .controlSize(.regular)
                    .buttonStyle(.borderedProminent)
                    .tint(MoaTheme.tint)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .moaModalFormBody()
        .onAppear { nameFocused = true }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusText = MoaL10n.text("Account name is required.")
            statusTone = .error
            return
        }
        onSave(trimmed)
    }
}

// MARK: - Codex form

private struct CodexProfileFormView: View {
    struct Initial {
        let name: String
        let baseURL: String
        let apiKey: String

        init(name: String, baseURL: String, apiKey: String) {
            self.name = name
            self.baseURL = baseURL
            self.apiKey = apiKey
        }

        static func directDefault() -> Initial {
            Initial(
                name: "",
                baseURL: "",
                apiKey: ""
            )
        }

        init(profile: ConfigProfile) {
            name = profile.name
            baseURL = profile.baseURL
            apiKey = profile.apiKey
        }

        init(preset: MoaProviderPreset) {
            name = preset.name
            baseURL = preset.baseURL
            apiKey = ""
        }
    }

    let title: String
    let message: String
    let buttonTitle: String
    let onSave: (String, String, String) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var apiKey: String
    @State private var baseURL: String
    @State private var statusText: String = ""
    @State private var statusTone: MoaFormStatusTone = .neutral
    @State private var isTesting = false
    @FocusState private var nameFocused: Bool

    init(
        title: String,
        message: String,
        buttonTitle: String,
        initial: Initial?,
        onSave: @escaping (String, String, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.buttonTitle = buttonTitle
        self.onSave = onSave
        self.onCancel = onCancel
        let resolved = initial ?? .directDefault()
        _name = State(initialValue: resolved.name)
        _baseURL = State(initialValue: resolved.baseURL)
        _apiKey = State(initialValue: resolved.apiKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MoaModalHeader(icon: "gearshape.fill", title: title, message: message)

            VStack(alignment: .leading, spacing: 7) {
                MoaModalFieldLabel(text: MoaL10n.text("Config Name"))
                TextField(MoaL10n.text("Example: One"), text: $name)
                    .moaModalFieldChrome()
                    .focused($nameFocused)
            }

            VStack(alignment: .leading, spacing: 7) {
                MoaModalFieldLabel(text: MoaL10n.text("API Key"))
                SecureField(MoaL10n.text("Paste your API key"), text: $apiKey)
                    .moaModalFieldChrome()
            }

            VStack(alignment: .leading, spacing: 7) {
                MoaModalFieldLabel(text: MoaL10n.text("API Base URL"))
                TextField("https://your-api-endpoint.com/v1", text: $baseURL)
                    .moaModalFieldChrome()
                Text(MoaProviderBaseURLPolicy.visibleGuidance)
                    .font(.system(size: 12))
                    .foregroundStyle(MoaTheme.amber)
                    .fixedSize(horizontal: false, vertical: true)
                Text(MoaL10n.text("Use an endpoint compatible with OpenAI Responses format."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(statusText.isEmpty ? " " : statusText)
                .font(.system(size: 12))
                .foregroundStyle(statusTone.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 16, alignment: .leading)

            HStack(spacing: 10) {
                Spacer()
                Button(MoaL10n.text("Cancel"), action: onCancel)
                    .frame(minWidth: 78)
                    .controlSize(.regular)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button(MoaL10n.text("Test Connection"), action: testConnection)
                    .frame(minWidth: 120)
                    .controlSize(.regular)
                    .buttonStyle(.bordered)
                    .disabled(isTesting)
                Button(buttonTitle, action: save)
                    .frame(minWidth: 88)
                    .controlSize(.regular)
                    .buttonStyle(.borderedProminent)
                    .tint(MoaTheme.tint)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isTesting)
            }
        }
        .moaModalFormBody()
        .onAppear { nameFocused = true }
    }

    private func save() {
        let name = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = self.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = self.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, !baseURL.isEmpty, !apiKey.isEmpty else {
            setStatus(MoaL10n.text("Name, base URL, and API key are required."), .error)
            return
        }
        do {
            _ = try MoaProviderBaseURLPolicy.validate(baseURL)
        } catch {
            setStatus(error.localizedDescription, .error)
            return
        }
        onSave(name, baseURL, apiKey)
    }

    private func testConnection() {
        let baseURL = self.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = self.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !baseURL.isEmpty, !apiKey.isEmpty else {
            setStatus(MoaL10n.text("Fill API Base URL and API Key before testing the connection."), .error)
            return
        }
        do {
            _ = try MoaProviderBaseURLPolicy.validate(baseURL)
        } catch {
            setStatus(error.localizedDescription, .error)
            return
        }

        let warning = MoaProviderBaseURLPolicy.warningMessage(for: baseURL)
        let testModel = ProviderConnectionTester.codexTestModel
        setStatus(
            String(
                format: MoaL10n.text("Testing connection with %@%@..."),
                testModel,
                warning == nil ? "" : MoaL10n.text(" (local HTTP)")
            ),
            .neutral
        )
        isTesting = true

        Task {
            do {
                let testResult = try await ProviderConnectionTester.testCodex(baseURL: baseURL, apiKey: apiKey)
                await MainActor.run {
                    if let warning {
                        setStatus(String(format: MoaL10n.text("Connection works: %@. %@"), testResult.model, warning), .warning)
                    } else {
                        setStatus(String(format: MoaL10n.text("Connection works: %@"), testResult.model), .success)
                    }
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    setStatus(error.localizedDescription, .error)
                    isTesting = false
                }
            }
        }
    }

    private func setStatus(_ text: String, _ tone: MoaFormStatusTone) {
        statusText = text
        statusTone = tone
    }
}

// MARK: - Claude Desktop provider form

private struct ClaudeProviderFormView: View {
    struct Initial {
        let name: String
        let baseURL: String
        let apiKey: String
        let modelsText: String

        static func directDefault() -> Initial {
            Initial(
                name: "",
                baseURL: "",
                apiKey: "",
                modelsText: ""
            )
        }
    }

    let title: String
    let message: String
    let buttonTitle: String
    let onSave: (String, String, String, [String], [String]) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var apiKey: String
    @State private var baseURL: String
    @State private var modelsText: String
    @State private var statusText: String = ""
    @State private var statusTone: MoaFormStatusTone = .neutral
    @State private var isTesting = false
    @FocusState private var nameFocused: Bool

    init(
        title: String,
        message: String,
        buttonTitle: String,
        initial: Initial?,
        onSave: @escaping (String, String, String, [String], [String]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.buttonTitle = buttonTitle
        self.onSave = onSave
        self.onCancel = onCancel
        let resolved = initial ?? .directDefault()
        _name = State(initialValue: resolved.name)
        _baseURL = State(initialValue: resolved.baseURL)
        _apiKey = State(initialValue: resolved.apiKey)
        _modelsText = State(initialValue: resolved.modelsText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MoaModalHeader(icon: "sparkles", title: title, message: message)

            VStack(alignment: .leading, spacing: 7) {
                MoaModalFieldLabel(text: MoaL10n.text("Provider Name"))
                TextField(MoaL10n.text("Example: Anthropic Compatible"), text: $name)
                    .moaModalFieldChrome()
                    .focused($nameFocused)
            }

            VStack(alignment: .leading, spacing: 7) {
                MoaModalFieldLabel(text: MoaL10n.text("API Key"))
                SecureField(MoaL10n.text("Paste your Anthropic-compatible bearer token"), text: $apiKey)
                    .moaModalFieldChrome()
            }

            VStack(alignment: .leading, spacing: 7) {
                MoaModalFieldLabel(text: MoaL10n.text("API Base URL"))
                TextField("https://your-api-endpoint.com", text: $baseURL)
                    .moaModalFieldChrome()
                Text(MoaProviderBaseURLPolicy.visibleGuidance)
                    .font(.system(size: 12))
                    .foregroundStyle(MoaTheme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 7) {
                MoaModalFieldLabel(text: MoaL10n.text("Models (optional)"))
                TextField("claude-opus-4.7[1M], claude-sonnet-4-5", text: $modelsText)
                    .moaModalFieldChrome()
                Text(MoaL10n.text("Append [1M] to a model to offer Claude Desktop's 1M-context variant, for example claude-opus-4.7[1M]."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(statusText.isEmpty ? " " : statusText)
                .font(.system(size: 12))
                .foregroundStyle(statusTone.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 16, alignment: .leading)

            HStack(spacing: 10) {
                Spacer()
                Button(MoaL10n.text("Cancel"), action: onCancel)
                    .frame(minWidth: 78)
                    .controlSize(.regular)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button(MoaL10n.text("Test Connection"), action: testConnection)
                    .frame(minWidth: 120)
                    .controlSize(.regular)
                    .buttonStyle(.bordered)
                    .disabled(isTesting)
                Button(buttonTitle, action: save)
                    .frame(minWidth: 88)
                    .controlSize(.regular)
                    .buttonStyle(.borderedProminent)
                    .tint(MoaTheme.tint)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isTesting)
            }
        }
        .moaModalFormBody()
        .onAppear { nameFocused = true }
    }

    private func save() {
        let name = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = self.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = self.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, !baseURL.isEmpty, !apiKey.isEmpty else {
            setStatus(MoaL10n.text("Name, base URL, and API key are required."), .error)
            return
        }
        do {
            _ = try MoaProviderBaseURLPolicy.validate(baseURL)
        } catch {
            setStatus(error.localizedDescription, .error)
            return
        }
        do {
            let parsed = try ClaudeDesktopProfileController.normalizedModels(from: modelsText)
            onSave(name, baseURL, apiKey, parsed.models, parsed.oneMModels)
        } catch {
            setStatus(error.localizedDescription, .error)
        }
    }

    private func testConnection() {
        let baseURL = self.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = self.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !baseURL.isEmpty, !apiKey.isEmpty else {
            setStatus(MoaL10n.text("Fill API Base URL and API Key before testing the connection."), .error)
            return
        }
        do {
            _ = try MoaProviderBaseURLPolicy.validate(baseURL)
        } catch {
            setStatus(error.localizedDescription, .error)
            return
        }

        let parsedModels: (models: [String], oneMModels: [String])
        do {
            parsedModels = try ClaudeDesktopProfileController.normalizedModels(from: modelsText)
        } catch {
            setStatus(error.localizedDescription, .error)
            return
        }

        let testModel = parsedModels.models.first ?? ProviderConnectionTester.claudeDefaultTestModel
        let warning = MoaProviderBaseURLPolicy.warningMessage(for: baseURL)
        setStatus(
            String(
                format: MoaL10n.text("Testing connection with %@%@..."),
                testModel,
                warning == nil ? "" : MoaL10n.text(" (local HTTP)")
            ),
            .neutral
        )
        isTesting = true

        Task {
            do {
                let testResult = try await ProviderConnectionTester.testClaude(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    models: parsedModels.models
                )
                await MainActor.run {
                    if let warning {
                        setStatus(String(format: MoaL10n.text("Connection works: %@. %@"), testResult.model, warning), .warning)
                    } else {
                        setStatus(String(format: MoaL10n.text("Connection works: %@"), testResult.model), .success)
                    }
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    setStatus(error.localizedDescription, .error)
                    isTesting = false
                }
            }
        }
    }

    private func setStatus(_ text: String, _ tone: MoaFormStatusTone) {
        statusText = text
        statusTone = tone
    }
}
