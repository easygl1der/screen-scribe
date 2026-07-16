import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct OpenAICompatibleProviderTests {
    static func main() throws {
        let configuration = AIProviderConfiguration(
            id: UUID(),
            name: "Qwen",
            kind: .openAICompatible,
            endpoint: URL(string: "https://vision.example.com/v1")!,
            model: "qwen-vl",
            priority: 0,
            isEnabled: true
        )
        let request = AIExtractionRequest(
            imageData: Data([0x01, 0x02]),
            prompt: "Extract this image.",
            mode: .automatic
        )

        let urlRequest = try OpenAICompatibleProvider.makeURLRequest(
            configuration: configuration,
            apiKey: "test-token",
            extractionRequest: request
        )
        expect(urlRequest.url?.absoluteString == "https://vision.example.com/v1/chat/completions", "provider should target chat completions")
        expect(urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer test-token", "provider should use bearer authentication")

        let payload = try JSONSerialization.jsonObject(with: urlRequest.httpBody!) as! [String: Any]
        expect(payload["model"] as? String == "qwen-vl", "provider should use the configured model")
        let choices = [["message": ["content": "x^2"]]]
        let response = try JSONSerialization.data(withJSONObject: ["choices": choices])
        expect(OpenAICompatibleProvider.parseResponse(response) == "x^2", "provider should parse chat completions content")

        let completeEndpoint = URL(string: "https://vision.example.com/v1/chat/completions")!
        expect(
            OpenAICompatibleProvider.chatCompletionsURL(from: completeEndpoint) == completeEndpoint,
            "provider should not duplicate an explicit chat completions path"
        )

        let quotaBody = Data("{\"code\":\"AllocationQuota.FreeTierOnly\"}".utf8)
        expect(
            OpenAICompatibleProvider.error(for: 403, responseData: quotaBody) == .quotaExceeded,
            "DashScope free-tier exhaustion should allow provider fallback"
        )
    }
}
