import Foundation

struct GeminiProvider: AIExtractionProvider {
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
            "contents": [["parts": [["inline_data": [
                "mime_type": "image/png",
                "data": extractionRequest.imageData.base64EncodedString()
            ]]]]],
            "systemInstruction": ["parts": [["text": extractionRequest.prompt]]],
            "generationConfig": ["temperature": 0, "candidateCount": 1, "maxOutputTokens": 2048]
        ]
        var components = URLComponents(url: configuration.endpoint.appendingPathComponent("models/\(configuration.model):generateContent"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components?.url else { throw AIExtractionError.requestFailed("Invalid Gemini endpoint") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    static func parseResponse(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String
        else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func error(for statusCode: Int) -> AIExtractionError {
        switch statusCode {
        case 401, 403: return .authenticationFailed
        case 402: return .quotaExceeded
        case 429: return .rateLimited
        case 500...599: return .serviceUnavailable
        default: return .requestFailed("HTTP \(statusCode)")
        }
    }
}
