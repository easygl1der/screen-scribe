import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct OutputContractTests {
    static func main() {
        let automaticContract = ExtractionOutputContract(
            mode: .automatic,
            mathDelimiter: .automatic
        )
        expect(
            automaticContract.instructions.contains("Choose the most appropriate output format"),
            "automatic mode should ask the model to classify the captured content"
        )

        let bracketContract = ExtractionOutputContract(
            mode: .latex,
            mathDelimiter: .latexBrackets
        )
        expect(
            bracketContract.instructions.contains("\\[...\\]"),
            "LaTeX bracket mode should require bracket delimiters"
        )
        expect(
            bracketContract.instructions.contains("Output only the extracted content"),
            "every output contract should prohibit explanatory wrapper text"
        )
    }
}
