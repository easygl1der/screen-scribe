import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main
struct ProviderCredentialKeyTests {
    static func main() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        expect(
            ProviderCredentialKey.account(for: id) == "provider-api-key-00000000-0000-0000-0000-000000000001",
            "credentials should use a stable, provider-scoped Keychain account"
        )
    }
}
