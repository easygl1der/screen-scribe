import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct ProviderConfigurationTests {
    static func main() {
        let first = AIProviderConfiguration(
            id: UUID(),
            name: "Primary",
            kind: .openAICompatible,
            endpoint: URL(string: "https://api.example.com/v1")!,
            model: "vision-primary",
            priority: 10,
            isEnabled: true
        )
        let disabled = AIProviderConfiguration(
            id: UUID(),
            name: "Disabled",
            kind: .gemini,
            endpoint: URL(string: "https://generativelanguage.googleapis.com")!,
            model: "gemini-test",
            priority: 0,
            isEnabled: false
        )
        let fallback = AIProviderConfiguration(
            id: UUID(),
            name: "Fallback",
            kind: .openAICompatible,
            endpoint: URL(string: "https://fallback.example.com/v1")!,
            model: "vision-fallback",
            priority: 20,
            isEnabled: true
        )

        let active = AIProviderConfiguration.active(from: [fallback, disabled, first])
        expect(active.map(\.id) == [first.id, fallback.id], "active providers should exclude disabled entries and honor priority")
    }
}
