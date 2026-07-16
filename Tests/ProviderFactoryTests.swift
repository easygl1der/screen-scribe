import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main
struct ProviderFactoryTests {
    static func main() {
        let valid = AIProviderConfiguration(id: UUID(), name: "Qwen", kind: .openAICompatible, endpoint: URL(string: "https://example.com/v1")!, model: "qwen", priority: 0, isEnabled: true)
        let disabled = AIProviderConfiguration(id: UUID(), name: "Off", kind: .gemini, endpoint: URL(string: "https://example.com")!, model: "gemini", priority: 1, isEnabled: false)
        let ready = AIProviderFactory.readyConfigurations(from: [disabled, valid]) { id in id == valid.id ? "token" : nil }
        expect(ready.map(\.id) == [valid.id], "factory should only select enabled providers with credentials")
    }
}
