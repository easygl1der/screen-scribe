import SwiftUI
import Carbon

private class EventMonitor {
    var monitor: Any?

    init(eventMask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) {
        self.monitor = NSEvent.addLocalMonitorForEvents(matching: eventMask, handler: handler)
    }

    deinit {
        if let monitor = self.monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

struct ShortcutRecorderButton: View {
    let label: String
    @Binding var shortcut: ShortcutMonitor.KeyboardShortcut?
    @State private var isRecording = false
    @State private var eventMonitor: EventMonitor?

    var body: some View {
        Button {
            if isRecording {
                eventMonitor = nil
                isRecording = false
            } else {
                isRecording = true
                startRecording()
            }
        } label: {
            HStack {
                Text(isRecording ? "Recording..." : (shortcut?.description ?? "Click to Record"))
                    .foregroundStyle(isRecording ? .secondary : .primary)
                if !isRecording {
                    Image(systemName: "keyboard")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func startRecording() {
        DispatchQueue.main.async {
            self.eventMonitor = nil
            self.eventMonitor = EventMonitor(eventMask: [.keyDown, .flagsChanged]) { event in
                if event.type == .keyDown &&
                   event.keyCode != kVK_Shift &&
                   event.keyCode != kVK_Control &&
                   event.keyCode != kVK_Option &&
                   event.keyCode != kVK_Command &&
                   event.keyCode != kVK_Function {
                    let newShortcut = ShortcutMonitor.KeyboardShortcut(
                        keyCode: Int(event.keyCode),
                        modifiers: event.modifierFlags
                    )
                    shortcut = newShortcut
                    isRecording = false
                    self.eventMonitor = nil
                    return nil
                } else if event.type == .flagsChanged {
                    return event
                }
                return event
            }
        }
    }
}

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var editingProvider: AIProviderConfiguration?
    @State private var isCreatingProvider = false

    var body: some View {
        Form {
            Section("AI Providers") {
                ForEach(settings.providers) { provider in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(provider.name)
                            Text("\(provider.kind.rawValue) · \(provider.model) · priority \(provider.priority)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: settings.hasStoredCredential(for: provider.id) ? "key.fill" : "key.slash")
                            .foregroundStyle(provider.isEnabled ? .green : .secondary)

                        Button {
                            editingProvider = provider
                            isCreatingProvider = true
                        } label: { Image(systemName: "pencil") }
                            .help("Edit provider")
                        Button { settings.moveProvider(id: provider.id, by: -1) } label: { Image(systemName: "arrow.up") }
                            .help("Increase priority")
                        Button { settings.moveProvider(id: provider.id, by: 1) } label: { Image(systemName: "arrow.down") }
                            .help("Decrease priority")
                        Button(role: .destructive) {
                            settings.deleteProvider(provider)
                            if editingProvider?.id == provider.id { editingProvider = nil }
                        } label: { Image(systemName: "trash") }
                            .help("Delete provider")
                    }
                }
                HStack {
                    Button("Add Provider") { isCreatingProvider = true }
                }
                Text("Provider tokens are stored in macOS Keychain and screenshots are never persisted by ScreenScribe.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Extraction Output") {
                Picker("Mode", selection: $settings.extractionMode) {
                    ForEach(ExtractionMode.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                Picker("Math delimiters", selection: $settings.mathDelimiter) {
                    ForEach(MathDelimiterStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Output language", selection: $settings.outputLanguage) {
                    ForEach(OutputLanguage.allCases) { language in
                        Text(language.label).tag(language)
                    }
                }
                if settings.outputLanguage == .custom {
                    TextField("Target language", text: $settings.customOutputLanguage)
                }
                Toggle("Preview before copying", isOn: $settings.showPreview)
            }

            Section {
                LabeledContent("Text Shortcut:") {
                    ShortcutRecorderButton(
                        label: "Text Shortcut",
                        shortcut: Binding(
                            get: { settings.textShortcut },
                            set: { settings.textShortcut = $0 }
                        )
                    )
                    .frame(width: 200)
                }

                LabeledContent("Default Prompt:") {
                    ShortcutRecorderButton(
                        label: "Default Prompt Shortcut",
                        shortcut: Binding(
                            get: { settings.defaultPromptShortcut },
                            set: { settings.defaultPromptShortcut = $0 }
                        )
                    )
                    .frame(width: 200)
                }
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text("Text uses offline Vision OCR. Default Prompt uses your selected AI prompt.")
                    .foregroundStyle(.secondary)
            }

            Section {
                PromptListView()
                    .frame(height: 280)
            } header: {
                Text("Prompts")
            } footer: {
                Text("Manage AI prompts for extraction. Set a default prompt for the keyboard shortcut.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 700)
        .sheet(isPresented: $isCreatingProvider) {
            ProviderEditorView(provider: editingProvider) { provider, token in
                settings.saveProvider(provider, token: token)
                editingProvider = provider
            }
        }
    }
}

private struct ProviderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let original: AIProviderConfiguration?
    let onSave: (AIProviderConfiguration, String?) -> Void
    @State private var name: String
    @State private var kind: AIProviderKind
    @State private var endpoint: String
    @State private var model: String
    @State private var priority: Int
    @State private var enabled: Bool
    @State private var token: String = ""

    private let dashScopeEndpoint = "https://dashscope.aliyuncs.com/compatible-mode/v1"

    init(provider: AIProviderConfiguration?, onSave: @escaping (AIProviderConfiguration, String?) -> Void) {
        original = provider; self.onSave = onSave
        _name = State(initialValue: provider?.name ?? "")
        _kind = State(initialValue: provider?.kind ?? .openAICompatible)
        _endpoint = State(initialValue: provider?.endpoint.absoluteString ?? "https://")
        _model = State(initialValue: provider?.model ?? "")
        _priority = State(initialValue: provider?.priority ?? SettingsManager.shared.providers.count)
        _enabled = State(initialValue: provider?.isEnabled ?? true)
    }

    var body: some View {
        Form {
            TextField("Name", text: $name)
            Picker("Provider", selection: $kind) { ForEach(AIProviderKind.allCases) { Text($0.rawValue).tag($0) } }
            TextField("Base URL", text: $endpoint)
            TextField("Model", text: $model)
            if kind == .openAICompatible {
                Button("Use Qwen 3.6 Flash defaults") {
                    name = "Qwen 3.6 Flash"
                    endpoint = dashScopeEndpoint
                    model = "qwen3.6-flash"
                }
                Button("Use Qwen 3.7 Max defaults") {
                    name = "Qwen 3.7 Max"
                    endpoint = dashScopeEndpoint
                    model = "qwen3.7-max"
                }
                Button("Use Qwen OCR defaults") {
                    name = "Qwen OCR"
                    endpoint = dashScopeEndpoint
                    model = "qwen3.5-ocr"
                }
                Text("For a regional DashScope workspace, replace the base URL with its OpenAI-compatible endpoint. Do not paste the /chat/completions suffix twice.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Stepper("Priority: \(priority)", value: $priority, in: 0...99)
            Toggle("Enabled", isOn: $enabled)
            LabeledContent("API token") {
                VStack(alignment: .leading, spacing: 4) {
                    SecureField("", text: $token)
                    if original != nil {
                        Text("Leave blank to keep the stored token.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") { save() }.disabled(name.isEmpty || model.isEmpty || validatedEndpoint == nil) }
        }.padding().frame(width: 460)
    }

    private func save() {
        guard let url = validatedEndpoint else { return }
        let provider = AIProviderConfiguration(id: original?.id ?? UUID(), name: name, kind: kind, endpoint: url, model: model, priority: priority, isEnabled: enabled)
        onSave(provider, token.isEmpty ? nil : token); dismiss()
    }

    private var validatedEndpoint: URL? {
        guard let url = URL(string: endpoint),
              let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              url.host != nil
        else {
            return nil
        }
        return url
    }
}

#Preview {
    SettingsView()
}
