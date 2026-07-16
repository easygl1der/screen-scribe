import Foundation

struct OpenAICompatibleProvider: AIExtractionProvider {
    let id: UUID
    private let configuration: AIProviderConfiguration
    private let apiKey: String
    private let session: URLSession

    init(configuration: AIProviderConfiguration, apiKey: String, session: URLSession = .shared) {
        self.id = configuration.id
        self.configuration = configuration
        self.apiKey = apiKey
        self.session = session
    }

    func extract(_ request: AIExtractionRequest) async throws -> AIExtractionResult {
        let urlRequest = try Self.makeURLRequest(
            configuration: configuration,
            apiKey: apiKey,
            extractionRequest: request
        )
        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIExtractionError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw error(for: httpResponse.statusCode)
        }

        guard let text = Self.parseResponse(data) else {
            throw AIExtractionError.invalidResponse
        }
        return AIExtractionResult(text: text, providerID: id)
    }

    static func makeURLRequest(
        configuration: AIProviderConfiguration,
        apiKey: String,
        extractionRequest: AIExtractionRequest
    ) throws -> URLRequest {
        let payload: [String: Any] = [
            "model": configuration.model,
            "temperature": 0,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": extractionRequest.prompt],
                    [
                        "type": "image_url",
                        "image_url": [
                            "url": "data:image/png;base64,\(extractionRequest.imageData.base64EncodedString())"
                        ]
                    ]
                ]
            ]]
        ]

        var request = URLRequest(url: configuration.endpoint.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    static func parseResponse(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            return nil
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func error(for statusCode: Int) -> AIExtractionError {
        switch statusCode {
        case 401, 403:
            return .authenticationFailed
        case 402:
            return .quotaExceeded
        case 429:
            return .rateLimited
        case 500...599:
            return .serviceUnavailable
        default:
            return .requestFailed("HTTP \(statusCode)")
        }
    }
}
