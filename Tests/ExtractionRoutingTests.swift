import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private struct StubProvider: AIExtractionProvider {
    let id: UUID
    let result: Result<AIExtractionResult, AIExtractionError>

    func extract(_ request: AIExtractionRequest) async throws -> AIExtractionResult {
        try result.get()
    }
}

@main
struct ExtractionRoutingTests {
    static func main() async {
        let primaryID = UUID()
        let fallbackID = UUID()
        let request = AIExtractionRequest(
            imageData: Data([0x01]),
            prompt: "Extract the image",
            mode: .automatic
        )

        let router = AIExtractionRouter(
            providers: [
                StubProvider(id: primaryID, result: .failure(.rateLimited)),
                StubProvider(
                    id: fallbackID,
                    result: .success(AIExtractionResult(text: "x^2", providerID: fallbackID))
                )
            ]
        )

        let result = try! await router.extract(request)
        expect(result.text == "x^2", "router should return the fallback provider result")
        expect(result.providerID == fallbackID, "router should fail over after a rate-limit error")

        let locationRestrictedRouter = AIExtractionRouter(
            providers: [
                StubProvider(
                    id: primaryID,
                    result: .failure(.providerUnavailable("User location is not supported for the API use."))
                ),
                StubProvider(
                    id: fallbackID,
                    result: .success(AIExtractionResult(text: "fallback", providerID: fallbackID))
                )
            ]
        )
        let locationFallback = try! await locationRestrictedRouter.extract(request)
        expect(
            locationFallback.providerID == fallbackID,
            "router should fail over when a provider is unavailable in the current region"
        )
    }
}
