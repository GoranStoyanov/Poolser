import Foundation
import Testing
@testable import Poolser

private let owner = "0x8f3c4b1e9d2a7c6f5e0b3a8d1c4e7f2a9b6da21c"
private let native = "0x0000000000000000000000000000000000000000"
private let usdc = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"

private func position(v4: Bool, fees0: Double = 0.01, fees1: Double = 0) -> Position {
    var pos = Position(
        chainID: v4 ? "base" : "ethereum", chainName: v4 ? "Base" : "Ethereum", chainNumericID: v4 ? 8453 : 1,
        tokenId: "198220", token0: "0x4200000000000000000000000000000000000006", token1: usdc,
        sym0: "ETH", sym1: "USDC", feePct: "0.05", feeRaw: 500, fees0: fees0, fees1: fees1,
        tickLower: 0, tickUpper: 100, liquidity: 1
    )
    if v4 {
        pos.isV4 = true
        pos.currency0 = native
        pos.currency1 = usdc
    }
    return pos
}

/// Word `i` of `data` (after `skip` bytes) as an integer; enough for offsets, lengths and IDs.
private func word(_ data: Data, _ i: Int, skip: Int = 4) -> Int {
    let start = data.startIndex + skip + i * 32
    return data[(start + 24)..<(start + 32)].reduce(0) { $0 << 8 | Int($1) }
}

private func addressWord(_ data: Data, _ i: Int, skip: Int = 4) -> String {
    let start = data.startIndex + skip + i * 32
    return "0x" + data[(start + 12)..<(start + 32)].hexString
}

@Suite("Collect transaction")
struct CollectRequestTests {
    @Test func v3CallsCollectWithMaxAmountsToTheOwner() throws {
        let request = try #require(CollectRequest(position: position(v4: false), owner: owner))
        #expect(request.to == "0xC36442b4a4522E871399CD717aBDD847Ab11FE88")
        #expect(request.data.prefix(4).hexString == "fc6f7865")
        #expect(word(request.data, 0) == 198220)
        #expect(addressWord(request.data, 1) == owner)
        #expect(request.chainId == 1)
    }

    @Test func v4SelectorIsModifyLiquidities() {
        #expect(keccak256(Data("modifyLiquidities(bytes,uint256)".utf8)).prefix(4).hexString == "dd46508f")
    }

    @Test func v4DecreasesByZeroThenTakesBothCurrencies() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let request = try #require(CollectRequest(position: position(v4: true), owner: owner, now: now))
        let data = request.data
        #expect(data.prefix(4).hexString == "dd46508f")
        #expect(data.count == 4 + 3 * 32 + 18 * 32)
        // modifyLiquidities(bytes unlockData, uint256 deadline)
        #expect(word(data, 0) == 0x40)
        #expect(word(data, 1) == 1_800_000_000 + 20 * 60)
        #expect(word(data, 2) == 18 * 32)
        // unlockData = abi.encode(bytes actions, bytes[] params), starting at word 3
        let u = 4 + 3 * 32
        #expect(word(data, 0, skip: u) == 0x40)
        #expect(word(data, 1, skip: u) == 0x80)
        #expect(word(data, 2, skip: u) == 2)
        #expect(data[data.startIndex + u + 3 * 32] == 0x01)       // DECREASE_LIQUIDITY
        #expect(data[data.startIndex + u + 3 * 32 + 1] == 0x11)   // TAKE_PAIR
        #expect(word(data, 4, skip: u) == 2)                      // two params
        #expect(word(data, 5, skip: u) == 0x40)
        #expect(word(data, 6, skip: u) == 0x40 + 32 + 6 * 32)
        // DECREASE_LIQUIDITY: tokenId, liquidity 0, mins 0, empty hookData
        #expect(word(data, 7, skip: u) == 6 * 32)
        #expect(word(data, 8, skip: u) == 198220)
        #expect((9...11).allSatisfy { word(data, $0, skip: u) == 0 })
        #expect(word(data, 12, skip: u) == 5 * 32)
        #expect(word(data, 13, skip: u) == 0)
        // TAKE_PAIR: native ETH as address(0), not the wrapped token used for prices
        #expect(word(data, 14, skip: u) == 3 * 32)
        #expect(addressWord(data, 15, skip: u) == native)
        #expect(addressWord(data, 16, skip: u) == usdc)
        #expect(addressWord(data, 17, skip: u) == owner)
    }

    @Test func nothingToCollectOrUnknownFees() {
        #expect(!CollectRequest.canCollect(position(v4: false, fees0: 0, fees1: 0)))
        var failed = position(v4: false)
        failed.feesError = "timeout"
        #expect(!CollectRequest.canCollect(failed))
        var noCurrencies = position(v4: true)
        noCurrencies.currency0 = nil
        #expect(!CollectRequest.canCollect(noCurrencies))
        #expect(CollectRequest.canCollect(position(v4: true)))
    }

    @Test func ownerMustBeAnAddress() {
        #expect(CollectRequest(position: position(v4: false), owner: "vitalik.eth") == nil)
        #expect(CollectRequest(position: position(v4: false), owner: "0x123") == nil)
    }
}
