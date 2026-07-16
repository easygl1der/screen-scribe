import Foundation

enum AIProviderFactory {
    static func readyConfigurations(
        from configurations: [AIProviderConfiguration],
        secretForProvider: (UUID) -> String?
    ) -> [AIProviderConfiguration] {
        AIProviderConfiguration.active(from: configurations).filter {
            guard let secret = secretForProvider($0.id) else { return false }
            return !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    static func makeProviders(from configurations: [AIProviderConfiguration]) -> [any AIExtractionProvider] {
        makeProviders(from: configurations, secretForProvider: ProviderCredentialStore.secret(for:))
    }

    static func makeProviders(
        from configurations: [AIProviderConfiguration],
        secretForProvider: (UUID) -> String?
    ) -> [any AIExtractionProvider] {
        readyConfigurations(from: configurations, secretForProvider: secretForProvider).compactMap { configuration -> (any AIExtractionProvider)? in
            guard let secret = secretForProvider(configuration.id) else { return nil }
            switch configuration.kind {
            case .gemini:
                return LegacyGeminiProvider(id: configuration.id, apiKey: secret)
            case .openAICompatible:
                return OpenAICompatibleProvider(configuration: configuration, apiKey: secret)
            }
        }
    }
}

private struct LegacyGeminiProvider: AIExtractionProvider {
    let id: UUID
    let apiKey: String

    func extract(_ request: AIExtractionRequest) async throws -> AIExtractionResult {
        let service = await MainActor.run { GeminiService() }
        do {
            let text = try await service.extractContent(
                from: request.imageData.base64EncodedString(),
                apiKey: apiKey,
                promptContent: request.prompt
            )
            return AIExtractionResult(text: text, providerID: id)
        } catch {
            throw AIExtractionError.requestFailed(error.localizedDescription)
        }
    }
}
