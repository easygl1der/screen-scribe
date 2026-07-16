import Foundation

enum ExtractionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case latex
    case markdown
    case table
    case code
    case text

    var id: String { rawValue }
}

enum MathDelimiterStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case none
    case inlineDollar
    case displayDollar
    case latexParentheses
    case latexBrackets

    var id: String { rawValue }
}

enum OutputLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case original
    case english
    case simplifiedChinese
    case traditionalChinese
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: return "Original"
        case .english: return "English"
        case .simplifiedChinese: return "Simplified Chinese"
        case .traditionalChinese: return "Traditional Chinese"
        case .custom: return "Custom"
        }
    }
}

struct ExtractionOutputContract: Codable, Equatable, Sendable {
    var mode: ExtractionMode
    var mathDelimiter: MathDelimiterStyle
    var outputLanguage: OutputLanguage = .original
    var customOutputLanguage: String = ""

    var instructions: String {
        let modeInstruction: String
        switch mode {
        case .automatic:
            modeInstruction = "First identify the captured content, then choose its output format: LaTeX for mathematics, Markdown for prose and tables, fenced Markdown code blocks for source code, and a concise Markdown description for diagrams or figures. These output instructions take precedence over any conflicting format instruction in the selected prompt."
        case .latex:
            modeInstruction = "Convert mathematical notation into syntactically correct LaTeX and preserve non-mathematical text."
        case .markdown:
            modeInstruction = "Extract the content as clean Markdown with headings, lists, tables, and code structure preserved."
        case .table:
            modeInstruction = "Extract tabular content as a valid Markdown table."
        case .code:
            modeInstruction = "Extract source code in a fenced Markdown code block and preserve indentation exactly."
        case .text:
            modeInstruction = "Extract readable text without adding Markdown structure."
        }

        return [
            modeInstruction,
            mathDelimiterInstruction,
            languageInstruction,
            "Output only the extracted content. Do not add explanations, labels, or Markdown fences around the entire response."
        ].joined(separator: "\n\n")
    }

    private var languageInstruction: String {
        let target: String
        switch outputLanguage {
        case .original:
            return "Preserve the source language. Do not translate the extracted content."
        case .english:
            target = "English"
        case .simplifiedChinese:
            target = "Simplified Chinese"
        case .traditionalChinese:
            target = "Traditional Chinese"
        case .custom:
            let trimmedLanguage = customOutputLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedLanguage.isEmpty
                ? "Preserve the source language. Do not translate the extracted content."
                : translationInstruction(target: trimmedLanguage)
        }
        return translationInstruction(target: target)
    }

    private func translationInstruction(target: String) -> String {
        "Translate all natural-language prose, headings, captions, and table cell text into \(target). Preserve source code, URLs, identifiers, file paths, mathematical symbols, and LaTeX commands exactly."
    }

    private var mathDelimiterInstruction: String {
        switch mathDelimiter {
        case .automatic:
            return "Choose inline or display mathematics delimiters that fit the extracted structure."
        case .none:
            return "Return mathematical expressions without outer math delimiters."
        case .inlineDollar:
            return "Wrap every mathematical expression with $...$."
        case .displayDollar:
            return "Wrap every standalone mathematical expression with $$...$$."
        case .latexParentheses:
            return "Wrap every mathematical expression with \\(...\\)."
        case .latexBrackets:
            return "Wrap every standalone mathematical expression with \\[...\\]."
        }
    }
}

enum AIProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case gemini
    case openAICompatible

    var id: String { rawValue }
}

struct AIProviderConfiguration: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var kind: AIProviderKind
    var endpoint: URL
    var model: String
    var priority: Int
    var isEnabled: Bool

    static func active(from configurations: [AIProviderConfiguration]) -> [AIProviderConfiguration] {
        configurations
            .filter(\.isEnabled)
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.priority < rhs.priority
            }
    }
}

struct AIExtractionRequest: Sendable {
    let imageData: Data
    let prompt: String
    let mode: ExtractionMode
}

struct AIExtractionResult: Sendable, Equatable {
    let text: String
    let providerID: UUID
}

enum AIExtractionError: Error, Equatable, Sendable {
    case rateLimited
    case quotaExceeded
    case serviceUnavailable
    case networkUnavailable
    case authenticationFailed
    case invalidResponse
    case requestFailed(String)

    var isFallbackEligible: Bool {
        switch self {
        case .rateLimited, .quotaExceeded, .serviceUnavailable, .networkUnavailable:
            return true
        case .authenticationFailed, .invalidResponse, .requestFailed:
            return false
        }
    }
}

protocol AIExtractionProvider: Sendable {
    var id: UUID { get }

    func extract(_ request: AIExtractionRequest) async throws -> AIExtractionResult
}

struct AIExtractionRouter: Sendable {
    let providers: [any AIExtractionProvider]

    func extract(_ request: AIExtractionRequest) async throws -> AIExtractionResult {
        var lastError: Error?

        for provider in providers {
            do {
                return try await provider.extract(request)
            } catch let error as AIExtractionError {
                lastError = error
                guard error.isFallbackEligible else {
                    throw error
                }
            } catch {
                lastError = error
            }
        }

        throw lastError ?? AIExtractionError.serviceUnavailable
    }
}
