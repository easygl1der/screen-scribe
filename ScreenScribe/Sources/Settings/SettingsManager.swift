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
            _ = ProviderCredentialStore.save(token.trimmingCharacters(in: .whitespacesAndNewlines), for: provider.id)
        }
    }

    func deleteProvider(_ provider: AIProviderConfiguration) {
        providers.removeAll { $0.id == provider.id }
        _ = ProviderCredentialStore.delete(for: provider.id)
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

        if providers.isEmpty {
            let legacyID = Self.geminiProviderID
            providers = [
                Self.defaultQwenProvider(),
                Self.defaultGeminiProvider(model: selectedModel, priority: 1)
            ]
            if let oldKey = UserDefaults.standard.string(forKey: "geminiAPIKey"), !oldKey.isEmpty {
                _ = ProviderCredentialStore.save(oldKey, for: legacyID)
                UserDefaults.standard.removeObject(forKey: "geminiAPIKey")
            }
        } else if providers.count == 1,
                  providers[0].id == Self.geminiProviderID,
                  providers[0].kind == .gemini {
            providers[0].priority = 1
            providers.insert(Self.defaultQwenProvider(), at: 0)
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

    private static let geminiProviderID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
    private static let qwenProviderID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!

    private static func defaultQwenProvider() -> AIProviderConfiguration {
        AIProviderConfiguration(
            id: qwenProviderID,
            name: "Qwen 3.6 Flash",
            kind: .openAICompatible,
            endpoint: URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1")!,
            model: "qwen3.6-flash",
            priority: 0,
            isEnabled: true
        )
    }

    private static func defaultGeminiProvider(model: String, priority: Int) -> AIProviderConfiguration {
        AIProviderConfiguration(
            id: geminiProviderID,
            name: "Gemini",
            kind: .gemini,
            endpoint: URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
            model: model,
            priority: priority,
            isEnabled: true
        )
    }
}
