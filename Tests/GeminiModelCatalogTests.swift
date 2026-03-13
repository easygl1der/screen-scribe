import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct GeminiModelCatalogTests {
    static func main() {
        let modelIDs = Config.availableGeminiModels.map(\.id)

        expect(modelIDs.contains("gemini-3-flash-preview"), "Gemini 3 Flash should remain available")
        expect(modelIDs.contains("gemini-3.1-pro-preview"), "Gemini 3.1 Pro Preview should be available")
        expect(modelIDs.contains("gemini-3.1-flash-lite-preview"), "Gemini 3.1 Flash-Lite Preview should be available")
        expect(!modelIDs.contains("gemini-3-pro-preview"), "Gemini 3 Pro Preview should be removed from the catalog")
        expect(!modelIDs.contains("gemini-2.5-flash-lite"), "Gemini 2.5 Flash-Lite should be removed from the catalog")

        expect(
            Config.defaultGeminiModelID == "gemini-3-flash-preview",
            "The default Gemini model should remain Gemini 3 Flash"
        )
        expect(
            Config.migratedGeminiModelID("gemini-3-pro-preview") == "gemini-3.1-pro-preview",
            "Stored Gemini 3 Pro Preview selections should migrate to Gemini 3.1 Pro Preview"
        )
        expect(
            Config.migratedGeminiModelID("gemini-2.5-flash-lite") == "gemini-3.1-flash-lite-preview",
            "Stored Gemini 2.5 Flash-Lite selections should migrate to Gemini 3.1 Flash-Lite Preview"
        )
        expect(
            Config.migratedGeminiModelID("gemini-3-flash-preview") == "gemini-3-flash-preview",
            "Current supported selections should remain unchanged"
        )

        print("GeminiModelCatalogTests passed")
    }
}
