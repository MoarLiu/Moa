import Foundation

struct ProviderConnectionTestResult {
    let model: String
    let endpoint: String
}

private enum ProviderConnectionTestError: LocalizedError {
    case missingBaseURL
    case invalidBaseURL(String)
    case missingAPIKey
    case requestFailed(Int, String)
    case noReachableEndpoint(String)

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return MoaL10n.text("Fill API Base URL first.")
        case .invalidBaseURL(let message):
            return message
        case .missingAPIKey:
            return MoaL10n.text("Fill API Key first.")
        case .requestFailed(let status, let message):
            if message.isEmpty {
                return MoaL10n.format("Connection test failed: HTTP %d.", status)
            }
            return MoaL10n.format("Connection test failed: HTTP %d, %@.", status, message)
        case .noReachableEndpoint(let message):
            return message.isEmpty ? MoaL10n.text("No test endpoint is reachable.") : message
        }
    }
}

enum ProviderConnectionTester {
    static let codexTestModel = "gpt-5.5"
    static let claudeDefaultTestModel = "claude-opus-4-8"

    #if MOA_TESTING || MOA_TEST_SUPPORT
    static var testingURLSession: URLSession?
    #endif

    private static var urlSession: URLSession {
        #if MOA_TESTING || MOA_TEST_SUPPORT
        if let testingURLSession { return testingURLSession }
        #endif
        return defaultURLSession
    }

    private static let defaultURLSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    static func testCodex(baseURL: String, apiKey: String, modelOverride: String? = nil) async throws -> ProviderConnectionTestResult {
        let baseURL = try validatedBaseURL(baseURL)
        let apiKey = try validatedAPIKey(apiKey)
        let model = modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? modelOverride!.trimmingCharacters(in: .whitespacesAndNewlines)
            : codexTestModel
        let responsesBody: [String: Any] = [
            "model": model,
            "input": "ping",
            "max_output_tokens": 16
        ]

        let endpoint = try await postJSON(
            body: responsesBody,
            baseURL: baseURL,
            endpoint: "responses",
            apiKey: apiKey,
            headers: [:])
        return ProviderConnectionTestResult(model: model, endpoint: endpoint)
    }

    static func testClaude(baseURL: String, apiKey: String, models: [String]) async throws -> ProviderConnectionTestResult {
        let baseURL = try validatedBaseURL(baseURL)
        let apiKey = try validatedAPIKey(apiKey)
        let model = models.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? models[0].trimmingCharacters(in: .whitespacesAndNewlines)
            : claudeDefaultTestModel
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1,
            "messages": [["role": "user", "content": "ping"]]
        ]
        let endpoint = try await postJSON(
            body: body,
            baseURL: baseURL,
            endpoint: "messages",
            apiKey: apiKey,
            headers: ["anthropic-version": "2023-06-01"])
        return ProviderConnectionTestResult(model: model, endpoint: endpoint)
    }

    private static func validatedBaseURL(_ raw: String) throws -> URL {
        do {
            return try MoaProviderBaseURLPolicy.validate(raw).url
        } catch MoaProviderBaseURLError.empty {
            throw ProviderConnectionTestError.missingBaseURL
        } catch {
            throw ProviderConnectionTestError.invalidBaseURL(error.localizedDescription)
        }
    }

    private static func validatedAPIKey(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProviderConnectionTestError.missingAPIKey
        }
        return trimmed
    }

    private static func postJSON(
        body: [String: Any],
        baseURL: URL,
        endpoint: String,
        apiKey: String,
        headers: [String: String]
    ) async throws -> String {
        var lastError: Error?
        for url in endpointURLs(baseURL: baseURL, endpoint: endpoint) {
            try Task.checkCancellation()
            do {
                try await postJSON(body, to: url, apiKey: apiKey, headers: headers)
                return url.absoluteString
            } catch let error as ProviderConnectionTestError {
                lastError = error
                if case .requestFailed(let status, _) = error,
                   !shouldTryNextEndpointCandidate(forHTTPStatus: status) {
                    throw error
                }
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }
        throw ProviderConnectionTestError.noReachableEndpoint("")
    }

    private static func postJSON(_ body: [String: Any], to url: URL, apiKey: String, headers: [String: String]) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderConnectionTestError.noReachableEndpoint(MoaL10n.text("The connection test did not receive a valid response."))
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ProviderConnectionTestError.requestFailed(httpResponse.statusCode, String(errorMessage(from: data).prefix(300)))
        }
    }

    private static func endpointURLs(baseURL: URL, endpoint: String) -> [URL] {
        let normalizedEndpoint = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let existingPath = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if existingPath.hasSuffix(normalizedEndpoint) {
            return [baseURL]
        }

        var candidates: [URL] = []
        if existingPath.isEmpty {
            candidates.append(baseURL.appendingPathComponent("v1").appendingPathComponent(normalizedEndpoint))
        } else if !existingPath.hasSuffix("v1") && !existingPath.contains("/v1/") {
            candidates.append(baseURL.appendingPathComponent("v1").appendingPathComponent(normalizedEndpoint))
        }

        candidates.append(baseURL.appendingPathComponent(normalizedEndpoint))
        return deduplicated(candidates)
    }

    private static func shouldTryNextEndpointCandidate(forHTTPStatus status: Int) -> Bool {
        status == 404 || status == 405
    }

    private static func deduplicated(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var output: [URL] = []
        for url in urls where !seen.contains(url.absoluteString) {
            seen.insert(url.absoluteString)
            output.append(url)
        }
        return output
    }

    private static func errorMessage(from data: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        if let error = object["error"] as? [String: Any] {
            return (error["message"] as? String) ?? String(describing: error)
        }

        if let message = object["message"] as? String {
            return message
        }

        return ""
    }
}
