import Testing
@testable import Poolser

private let address = "0x7A406E87B49e8a62C7F579E51AE94ed6Ee2d354f"
private let bareHex = String(address.dropFirst(2))

@Suite struct WalletAddressTests {
    @Test(arguments: [
        address,
        address.lowercased(),
        "0x" + bareHex.uppercased(),
    ])
    func validAddressIsKeptAsIs(_ input: String) {
        #expect(WalletAddress.normalize(input) == input)
    }

    @Test(arguments: [
        " \(address)",
        "\(address) ",
        "\(address)\n",
        "\t\(address)\r\n",
    ])
    func surroundingWhitespaceIsStripped(_ input: String) {
        #expect(WalletAddress.normalize(input) == address)
    }

    @Test(arguments: [bareHex, "0X" + bareHex])
    func missingOrUppercasePrefixIsNormalized(_ input: String) {
        #expect(WalletAddress.normalize(input) == address)
    }

    @Test(arguments: [
        "",
        "   ",
        "0x",
        String(address.dropLast()),                     // 39 hex digits
        address + "0",                                  // 41 hex digits
        "0x" + String(repeating: "Z", count: 40),
        "0x7A406E87B49e8a62C7F579E51AE94ed6Ee2d354g",
        "0x7A406E87B49e8a62C7F5 9E51AE94ed6Ee2d354f",   // inner whitespace
        "0x" + String(repeating: "\u{FF11}", count: 40), // fullwidth digit one
        "vitalik.eth",
    ])
    func invalidInputIsRejected(_ input: String) {
        #expect(WalletAddress.normalize(input) == nil)
    }

    @Test(arguments: ["", "  \n"])
    func emptyFieldHasNoValidationError(_ input: String) {
        #expect(WalletAddress.validationError(for: input) == nil)
    }

    @Test func validFieldHasNoValidationError() {
        #expect(WalletAddress.validationError(for: "\(address)\n") == nil)
    }

    @Test(arguments: [String(address.dropLast()), "0xZZ"])
    func invalidFieldHasValidationError(_ input: String) {
        #expect(WalletAddress.validationError(for: input) != nil)
    }
}

@Suite struct PerformanceDefaultsTests {
    /// The Settings reset button reads these, so they must be values the steppers can show.
    @Test func defaultsMatchFreshInstallAndFitSettingRanges() {
        #expect(AppSettings.Defaults.refreshIntervalMinutes == 10)
        #expect(AppSettings.Defaults.rpcCreditsPerSecondBudget == 400)
        #expect(AppSettings.Defaults.v4LogChunkSize == 10_000)
        #expect(AppSettings.Defaults.v4LogMaxConcurrentRequests == 3)
        #expect(AppSettings.Defaults.v4BootstrapMaxChunksPerRefresh == 120)

        #expect((1...120).contains(AppSettings.Defaults.refreshIntervalMinutes))
        #expect((50...5_000).contains(AppSettings.Defaults.rpcCreditsPerSecondBudget))
        #expect(AppSettings.Defaults.v4LogChunkSizeRange.contains(AppSettings.Defaults.v4LogChunkSize))
        #expect((1...8).contains(AppSettings.Defaults.v4LogMaxConcurrentRequests))
        #expect((5...200).contains(AppSettings.Defaults.v4BootstrapMaxChunksPerRefresh))
    }

    /// Infura rejects eth_getLogs over more than 10,000 blocks; stored values from older
    /// versions (12,000 / 20,000) must be pulled down or every log scan fails forever.
    @Test(arguments: [(12_000, 10_000), (20_000, 10_000), (50_000, 10_000), (10_000, 10_000), (5_000, 5_000), (500, 1_000)])
    func logChunkSizeIsClampedToInfuraLimit(stored: Int, expected: Int) {
        #expect(AppSettings.clampLogChunkSize(stored) == expected)
    }
}

@Suite("App version label")
struct AppVersionLabelTests {
    @Test func bundledAppShowsVersionAndBuild() {
        #expect(AppVersion.label(info: ["CFBundleShortVersionString": "1.4", "CFBundleVersion": "27"]) == "v1.4 (27)")
        #expect(AppVersion.label(info: ["CFBundleShortVersionString": "1.4"]) == "v1.4")
    }

    @Test func swiftPMBuildIsNamedInsteadOfQuestionMarks() {
        #expect(AppVersion.label(info: nil) == "development build")
        #expect(AppVersion.label(info: ["CFBundleExecutable": "Poolser"]) == "development build")
    }
}
