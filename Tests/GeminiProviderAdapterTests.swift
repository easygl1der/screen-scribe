import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct GeminiProviderAdapterTests {
    static func main() throws {
        let configuration = AIProviderConfiguration(
            id: UUID(), name: "Gemini", kind: .gemini,
            endpoint: URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
            model: "gemini-3.5-flash", priority: 0, isEnabled: true
        )
        let request = AIExtractionRequest(imageData: Data([0x01]), prompt: "Extract.", mode: .latex)
        let urlRequest = try GeminiProvider.makeURLRequest(configuration: configuration, apiKey: "key", extractionRequest: request)
        expect(urlRequest.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent?key=key", "Gemini provider should use its native endpoint")

        let response = try JSONSerialization.data(
            withJSONObject: ["candidates": [["content": ["parts": [["text": "x"]]]]]]
        )
        expect(GeminiProvider.parseResponse(response) == "x", "Gemini provider should parse generated text")

        let unsupportedLocationResponse = try JSONSerialization.data(
            withJSONObject: ["error": ["message": "User location is not supported for the API use."]]
        )
        let unsupportedLocationError = GeminiProvider.error(
            for: 400,
            responseData: unsupportedLocationResponse
        )
        expect(
            unsupportedLocationError == .providerUnavailable("User location is not supported for the API use."),
            "Gemini location restrictions should allow routing to the next provider"
        )
        expect(
            unsupportedLocationError.localizedDescription.contains("User location is not supported"),
            "provider errors should preserve a useful explanation"
        )
    }
}
