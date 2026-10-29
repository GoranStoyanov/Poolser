import Foundation
import Testing
@testable import PoolserKit

private let wallet = "0x7A406E87B49e8a62C7F579E51AE94ed6Ee2d354f"

private func ownerWord(_ address: String) -> Data {
    ABI.encodeAddress(address)
}

@Suite struct V4OwnerCheckTests {
    @Test func ownedWhenOwnerMatchesWalletIgnoringCase() {
        let result: Result<Data, Error> = .success(ownerWord(wallet.lowercased()))
        #expect(v4OwnerCheck(result, wallet: wallet) == true)
    }

    @Test func notOwnedWhenOwnerIsAnotherAddress() {
        let result: Result<Data, Error> = .success(ownerWord("0x000000000000000000000000000000000000dEaD"))
        #expect(v4OwnerCheck(result, wallet: wallet) == false)
    }

    /// Burned tokens make ownerOf revert ("NOT_MINTED"); they must be dropped, not retried forever.
    @Test func revertMeansNotOwned() {
        let result: Result<Data, Error> = .failure(EthereumClient.Err.reverted("execution reverted: NOT_MINTED"))
        #expect(v4OwnerCheck(result, wallet: wallet) == false)
    }

    @Test(arguments: [
        EthereumClient.Err.rpc("HTTP 429"),
        EthereumClient.Err.rpc("Internal error"),
        EthereumClient.Err.noResult,
        EthereumClient.Err.badJSON,
    ])
    func transientFailureIsUnknown(error: EthereumClient.Err) {
        #expect(v4OwnerCheck(.failure(error), wallet: wallet) == nil)
    }

    @Test func networkErrorIsUnknown() {
        #expect(v4OwnerCheck(.failure(URLError(.timedOut)), wallet: wallet) == nil)
    }
}

@Suite struct RevertDetectionTests {
    /// Shape returned by geth-based nodes (verified against a public mainnet RPC).
    @Test func gethCode3IsRevert() {
        #expect(EthereumClient.Err.isRevert(code: 3, message: "execution reverted: NOT_MINTED"))
    }

    @Test func revertMessageWithoutCodeIsRevert() {
        #expect(EthereumClient.Err.isRevert(code: -32000, message: "Execution reverted"))
    }

    @Test(arguments: [
        (-32005, "too many requests"),
        (-32603, "Internal error"),
        (-32000, "header not found"),
    ])
    func otherErrorsAreNotRevert(code: Int, message: String) {
        #expect(!EthereumClient.Err.isRevert(code: code, message: message))
    }
}
