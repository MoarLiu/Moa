import Foundation

enum MoaProviderPresetFamily: String, CaseIterable {
    case responsesNative
    case responsesGateway
}

struct MoaProviderPreset: Equatable {
    let id: String
    let family: MoaProviderPresetFamily
    let name: String
    let baseURL: String
    let model: String
    let testModel: String
    let models: [String]
}

enum MoaProviderPresets {
    static let responsesNative: [MoaProviderPreset] = [
        MoaProviderPreset(
            id: "openai-responses-native",
            family: .responsesNative,
            name: "OpenAI Responses Native",
            baseURL: "https://api.openai.com/v1",
            model: "gpt-5.2-codex",
            testModel: "gpt-5.2-codex",
            models: [
                "gpt-5.2-codex",
                "gpt-5.1-codex-max",
                "gpt-5-codex"
            ]
        )
    ]

    static let responsesGateways: [MoaProviderPreset] = [
        MoaProviderPreset(
            id: "openrouter-responses-gateway",
            family: .responsesGateway,
            name: "OpenRouter Responses Gateway",
            baseURL: "https://openrouter.ai/api/v1",
            model: "openai/gpt-4o",
            testModel: "openai/gpt-4o-mini",
            models: [
                "openai/gpt-4o",
                "openai/gpt-4o-mini"
            ]
        ),
        MoaProviderPreset(
            id: "litellm-responses-gateway",
            family: .responsesGateway,
            name: "LiteLLM Responses Gateway",
            baseURL: "http://127.0.0.1:4000/v1",
            model: "moa-codex",
            testModel: "moa-codex",
            models: [
                "moa-codex"
            ]
        ),
        MoaProviderPreset(
            id: "portkey-responses-gateway",
            family: .responsesGateway,
            name: "Portkey Responses Gateway",
            baseURL: "https://api.portkey.ai/v1",
            model: "gpt-4o-mini",
            testModel: "gpt-4o-mini",
            models: [
                "gpt-4o-mini"
            ]
        ),
        MoaProviderPreset(
            id: "helicone-responses-gateway",
            family: .responsesGateway,
            name: "Helicone Responses Gateway",
            baseURL: "https://ai-gateway.helicone.ai/v1",
            model: "gpt-4o-mini",
            testModel: "gpt-4o-mini",
            models: [
                "gpt-4o-mini"
            ]
        )
    ]

    static let all: [MoaProviderPreset] = responsesNative + responsesGateways

    static func preset(id: String) -> MoaProviderPreset? {
        all.first { $0.id == id }
    }
}
