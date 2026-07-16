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

struct ExtractionOutputContract: Codable, Equatable, Sendable {
    var mode: ExtractionMode
    var mathDelimiter: MathDelimiterStyle

    var instructions: String {
        let modeInstruction: String
        switch mode {
        case .automatic:
            modeInstruction = "Choose the most appropriate output format for the captured content: LaTeX for mathematics, Markdown for prose and tables, and fenced Markdown code blocks for source code."
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
            "Output only the extracted content. Do not add explanations, labels, or Markdown fences around the entire response."
        ].joined(separator: "\n\n")
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
