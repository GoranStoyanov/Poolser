import Foundation
import Testing
@testable import Poolser
@testable import PoolserKit

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

@Suite struct SavedWalletTests {
    private let second = "0x1111111111111111111111111111111111111111"

    @Test func savedWalletsAreNormalizedAndDeduplicated() {
        let wallets = SavedWallet.unique([
            SavedWallet(address: " \(address) ", name: "Main"),
            SavedWallet(address: address.lowercased(), name: "Copy"),
            SavedWallet(address: "invalid"),
            SavedWallet(address: second),
        ])
        #expect(wallets == [SavedWallet(address: address, name: "Main"), SavedWallet(address: second)])
    }

    @Test func blankNameMeansNoName() {
        let wallet = SavedWallet(address: address, name: "  ")
        #expect(wallet.name == nil)
        #expect(wallet.displayName == "0x7A40…354f")
        #expect(SavedWallet(address: address, name: " Cold ").displayName == "Cold")
    }

    @Test func addressListFromTheFirstMultiWalletBuildIsMigrated() throws {
        let defaults = try #require(UserDefaults(suiteName: "SavedWalletTests-\(UUID().uuidString)"))
        defaults.set([address, second], forKey: SavedWallet.legacyDefaultsKey)
        #expect(SavedWallet.load(from: defaults) == [SavedWallet(address: address), SavedWallet(address: second)])

        SavedWallet.save([SavedWallet(address: second, name: "Hot")], to: defaults)
        #expect(SavedWallet.load(from: defaults) == [SavedWallet(address: second, name: "Hot")])
    }

    @Test func removingAWalletClearsOnlyItsCaches() throws {
        let defaults = try #require(UserDefaults(suiteName: "SavedWalletTests-\(UUID().uuidString)"))
        let keys = { (wallet: String) in [
            HiddenPositionStore.key(for: wallet),
            FeeHistoryService.cacheKey(chainID: "ethereum", wallet: wallet),
            "v4OwnershipCache.base.\(wallet.lowercased())",
        ] }
        for key in keys(address) + keys(second) { defaults.set(Data([1]), forKey: key) }

        WalletCaches.remove(wallet: address, from: defaults)

        #expect(keys(address).allSatisfy { defaults.object(forKey: $0) == nil })
        #expect(keys(second).allSatisfy { defaults.object(forKey: $0) != nil })
    }
}

@Suite struct WalletListDraftTests {
    private let second = "0x1111111111111111111111111111111111111111"

    @Test func addedWalletKeepsItsNameAndClearsTheFields() {
        var draft = WalletListDraft(wallets: [SavedWallet(address: address)], active: address)
        draft.newAddress = " \(second)\n"
        draft.newName = "Ledger"
        draft.add()
        #expect(draft.wallets.last == SavedWallet(address: second, name: "Ledger"))
        #expect(draft.newAddress.isEmpty && draft.newName.isEmpty)
        #expect(draft.active == address)
    }

    @Test func firstWalletBecomesActive() {
        var draft = WalletListDraft(wallets: [], active: "")
        draft.newAddress = second
        draft.addPending()
        #expect(draft.active == second)
    }

    @Test func savedAddressCannotBeAddedAgain() {
        var draft = WalletListDraft(wallets: [SavedWallet(address: address)], active: address)
        draft.newAddress = address.lowercased()
        #expect(draft.newAddressError != nil)
        #expect(!draft.canAdd)
        draft.addPending()
        #expect(draft.wallets.count == 1)
    }

    @Test func removingTheActiveWalletActivatesTheFirst() {
        var draft = WalletListDraft(wallets: [SavedWallet(address: address), SavedWallet(address: second)], active: second)
        draft.remove(SavedWallet(address: second))
        #expect(draft.active == address)
    }

    @Test func walletsMove() {
        let third = "0x2222222222222222222222222222222222222222"
        let wallets = [address, second, third].map { SavedWallet(address: $0) }
        var draft = WalletListDraft(wallets: wallets, active: address)
        draft.move(wallets[2], to: wallets[0])
        #expect(draft.wallets.map(\.address) == [third, address, second])
        draft.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(draft.wallets.map(\.address) == [address, second, third])
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

@Suite struct MenuBarSourceTests {
    @Test(arguments: [MenuBarSource.allWallets, .shownPage, .wallet("0xabc")])
    func storedValueRoundTrips(_ source: MenuBarSource) {
        #expect(MenuBarSource(rawValue: source.rawValue) == source)
    }

    @Test func missingValueMeansAllWallets() {
        #expect(MenuBarSource(rawValue: nil) == .allWallets)
        #expect(MenuBarSource(rawValue: "0xABC") == .wallet("0xabc"))
    }
}
