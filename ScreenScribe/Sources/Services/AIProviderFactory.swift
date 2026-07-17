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
        AIProviderConfiguration.active(from: configurations).map(KeychainBackedProvider.init)
    }

    static func makeProviders(
        from configurations: [AIProviderConfiguration],
        secretForProvider: (UUID) -> String?
    ) -> [any AIExtractionProvider] {
        readyConfigurations(from: configurations, secretForProvider: secretForProvider).compactMap { configuration -> (any AIExtractionProvider)? in
            guard let secret = secretForProvider(configuration.id) else { return nil }
            switch configuration.kind {
            case .gemini:
                return GeminiProvider(configuration: configuration, apiKey: secret)
            case .openAICompatible:
                return OpenAICompatibleProvider(configuration: configuration, apiKey: secret)
            }
        }
    }
}

private struct KeychainBackedProvider: AIExtractionProvider {
    let configuration: AIProviderConfiguration

    var id: UUID { configuration.id }

    func extract(_ request: AIExtractionRequest) async throws -> AIExtractionResult {
        guard let secret = credential(),
              !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw AIExtractionError.authenticationFailed
        }

        switch configuration.kind {
        case .gemini:
            return try await GeminiProvider(configuration: configuration, apiKey: secret).extract(request)
        case .openAICompatible:
            return try await OpenAICompatibleProvider(configuration: configuration, apiKey: secret).extract(request)
        }
    }

    private func credential() -> String? {
        if let secret = ProviderCredentialStore.secret(for: configuration.id) {
            return secret
        }

        // Gemini providers share one API credential. Do not read it until this
        // fallback provider is actually selected by the router.
        if configuration.kind == .gemini,
           configuration.id == UUID(uuidString: "00000000-0000-0000-0000-000000000014")! {
            return ProviderCredentialStore.secret(
                for: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
            )
        }
        return nil
    }
}
