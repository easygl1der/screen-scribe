import Foundation
import Carbon
import SwiftUI

@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var textShortcut: ShortcutMonitor.KeyboardShortcut? {
        willSet {
            objectWillChange.send()
        }
        didSet {
            UserDefaults.standard.setCodable(textShortcut, forKey: "textShortcut")
            ShortcutMonitor.shared.setShortcut(textShortcut, for: .visionOCR)
        }
    }

    @Published var defaultPromptShortcut: ShortcutMonitor.KeyboardShortcut? {
        willSet {
            objectWillChange.send()
        }
        didSet {
            UserDefaults.standard.setCodable(defaultPromptShortcut, forKey: "defaultPromptShortcut")
            ShortcutMonitor.shared.setShortcut(defaultPromptShortcut, for: .defaultPrompt)
        }
    }

    @Published var selectedModel: String {
        willSet {
            objectWillChange.send()
        }
        didSet {
            UserDefaults.standard.set(selectedModel, forKey: "geminiModel")
        }
    }

    @Published var providers: [AIProviderConfiguration] {
        didSet { UserDefaults.standard.setCodable(providers, forKey: "aiProviders") }
    }
    @Published private var credentialProviderIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(credentialProviderIDs), forKey: "providerCredentialIDs") }
    }
    @Published var extractionMode: ExtractionMode { didSet { UserDefaults.standard.set(extractionMode.rawValue, forKey: "extractionMode") } }
    @Published var mathDelimiter: MathDelimiterStyle { didSet { UserDefaults.standard.set(mathDelimiter.rawValue, forKey: "mathDelimiter") } }
    @Published var outputLanguage: OutputLanguage { didSet { UserDefaults.standard.set(outputLanguage.rawValue, forKey: "outputLanguage") } }
    @Published var customOutputLanguage: String { didSet { UserDefaults.standard.set(customOutputLanguage, forKey: "customOutputLanguage") } }
    @Published var showPreview: Bool { didSet { UserDefaults.standard.set(showPreview, forKey: "showPreview") } }

    func saveProvider(_ provider: AIProviderConfiguration, token: String?) {
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = provider
        } else {
            providers.append(provider)
        }
        if let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if ProviderCredentialStore.save(token.trimmingCharacters(in: .whitespacesAndNewlines), for: provider.id) {
                credentialProviderIDs.insert(provider.id.uuidString.lowercased())
            }
        }
    }

    func deleteProvider(_ provider: AIProviderConfiguration) {
        providers.removeAll { $0.id == provider.id }
        _ = ProviderCredentialStore.delete(for: provider.id)
        credentialProviderIDs.remove(provider.id.uuidString.lowercased())
    }

    func hasStoredCredential(for providerID: UUID) -> Bool {
        credentialProviderIDs.contains(providerID.uuidString.lowercased())
    }

    func moveProvider(id: UUID, by offset: Int) {
        guard let index = providers.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard providers.indices.contains(destination) else { return }
        providers.swapAt(index, destination)
        for index in providers.indices { providers[index].priority = index }
    }

    private init() {
        providers = UserDefaults.standard.codable(forKey: "aiProviders") ?? []
        credentialProviderIDs = Set(UserDefaults.standard.stringArray(forKey: "providerCredentialIDs") ?? [])
        extractionMode = ExtractionMode(rawValue: UserDefaults.standard.string(forKey: "extractionMode") ?? "") ?? .automatic
        mathDelimiter = MathDelimiterStyle(rawValue: UserDefaults.standard.string(forKey: "mathDelimiter") ?? "") ?? .automatic
        outputLanguage = OutputLanguage(rawValue: UserDefaults.standard.string(forKey: "outputLanguage") ?? "") ?? .original
        customOutputLanguage = UserDefaults.standard.string(forKey: "customOutputLanguage") ?? ""
        showPreview = UserDefaults.standard.bool(forKey: "showPreview")
        textShortcut = UserDefaults.standard.codable(forKey: "textShortcut")

        // Try to load new key first, fall back to old key for migration
        if let shortcut: ShortcutMonitor.KeyboardShortcut = UserDefaults.standard.codable(forKey: "defaultPromptShortcut") {
            defaultPromptShortcut = shortcut
        } else if let oldShortcut: ShortcutMonitor.KeyboardShortcut = UserDefaults.standard.codable(forKey: "latexShortcut") {
            // Migrate old latexShortcut to defaultPromptShortcut
            defaultPromptShortcut = oldShortcut
            UserDefaults.standard.removeObject(forKey: "latexShortcut")
        }

        let storedModel = UserDefaults.standard.string(forKey: "geminiModel")
        let resolvedModel = Config.resolvedGeminiModelID(from: storedModel)
        selectedModel = resolvedModel
        if let migratedModel = Config.persistedGeminiModelMigration(from: storedModel) {
            UserDefaults.standard.set(migratedModel, forKey: "geminiModel")
        }

        if providers.isEmpty || Self.isLegacyDefaultProviderSet(providers) {
            let legacyCredentialIDs = credentialProviderIDs

            providers = Self.defaultProviders()
            credentialProviderIDs = legacyCredentialIDs
        }

        if textShortcut == nil {
            textShortcut = ShortcutMonitor.KeyboardShortcut(
                keyCode: kVK_ANSI_T,
                modifiers: [.command]
            )
        }

        if defaultPromptShortcut == nil {
            defaultPromptShortcut = ShortcutMonitor.KeyboardShortcut(
                keyCode: kVK_ANSI_L,
                modifiers: [.command]
            )
        }

        ShortcutMonitor.shared.setShortcut(textShortcut, for: .visionOCR)
        ShortcutMonitor.shared.setShortcut(defaultPromptShortcut, for: .defaultPrompt)
    }

    private static let geminiFlashLiteProviderID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
    private static let legacyQwenFlashProviderID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
    private static let qwenPlusProviderID = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
    private static let qwenMaxProviderID = UUID(uuidString: "00000000-0000-0000-0000-000000000013")!
    private static let geminiFlashProviderID = UUID(uuidString: "00000000-0000-0000-0000-000000000014")!

    private static func isLegacyDefaultProviderSet(_ providers: [AIProviderConfiguration]) -> Bool {
        let legacyIDs: Set<UUID> = [geminiFlashLiteProviderID, legacyQwenFlashProviderID]
        return !providers.isEmpty && Set(providers.map(\.id)).isSubset(of: legacyIDs)
    }

    private static func defaultProviders() -> [AIProviderConfiguration] {
        let geminiEndpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta")!
        let dashScopeEndpoint = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1")!
        return [
            AIProviderConfiguration(id: geminiFlashLiteProviderID, name: "Gemini 3.1 Flash-Lite", kind: .gemini, endpoint: geminiEndpoint, model: "gemini-3.1-flash-lite", priority: 0, isEnabled: true),
            AIProviderConfiguration(id: geminiFlashProviderID, name: "Gemini 3.5 Flash", kind: .gemini, endpoint: geminiEndpoint, model: "gemini-3.5-flash", priority: 1, isEnabled: true),
            AIProviderConfiguration(id: qwenPlusProviderID, name: "Qwen 3.7 Plus", kind: .openAICompatible, endpoint: dashScopeEndpoint, model: "qwen3.7-plus", priority: 2, isEnabled: true),
            AIProviderConfiguration(id: qwenMaxProviderID, name: "Qwen 3.7 Max", kind: .openAICompatible, endpoint: dashScopeEndpoint, model: "qwen3.7-max", priority: 3, isEnabled: true)
        ]
    }
}
