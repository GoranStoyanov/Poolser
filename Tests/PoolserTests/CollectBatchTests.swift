import Foundation
import Testing
@testable import Poolser
@testable import PoolserKit

private let owner = "0x8f3c4b1e9d2a7c6f5e0b3a8d1c4e7f2a9b6da21c"
private let native = "0x0000000000000000000000000000000000000000"
private let usdc = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
private let usdt = "0xdac17f958d2ee523a2206206994597c13d831ec7"
private let weth = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"
private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func position(
    _ tokenId: Int, v4: Bool = false, chain: String = "ethereum", currencies: (String, String) = (native, usdc),
    usd: Double? = 10, fees: Double = 0.01
) -> Position {
    let names = ["ethereum": ("Ethereum", 1), "base": ("Base", 8453)]
    var pos = Position(
        chainID: chain, chainName: names[chain]!.0, chainNumericID: names[chain]!.1,
        tokenId: String(tokenId), token0: weth, token1: currencies.1,
        sym0: "ETH", sym1: currencies.1 == usdt ? "USDT" : "USDC", feePct: "0.05", feeRaw: 500,
        fees0: fees, fees1: 0, tickLower: 0, tickUpper: 100, liquidity: 1
    )
    pos.usd = usd
    if v4 {
        pos.isV4 = true
        pos.currency0 = currencies.0
        pos.currency1 = currencies.1
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

private func fullWord(_ data: Data, _ i: Int, skip: Int = 4) -> String {
    let start = data.startIndex + skip + i * 32
    return data[start..<(start + 32)].hexString
}

private let maxUInt128 = String(repeating: "0", count: 32) + String(repeating: "f", count: 32)

@Suite("Collect batch transactions")
struct CollectBatchTests {
    @Test func multicallSelector() {
        #expect(keccak256(Data("multicall(bytes[])".utf8)).prefix(4).hexString == "ac9650d8")
    }

    @Test func v3PositionsShareOneMulticallOfCollects() throws {
        let batch = try #require(CollectBatch(chainID: "ethereum", positions: [position(11), position(22)], owner: owner))
        let transactions = batch.transactions(for: Set(batch.items.map(\.id)), now: now)
        #expect(transactions.count == 1)
        let tx = try #require(transactions.first)
        #expect(tx.to == "0xC36442b4a4522E871399CD717aBDD847Ab11FE88")
        #expect(tx.versionLabel == "v3")
        #expect(tx.itemIDs == ["ethereum-v3-11", "ethereum-v3-22"])

        // multicall(bytes[] data)
        let data = tx.data
        #expect(data.prefix(4).hexString == "ac9650d8")
        #expect(data.count == 4 + 4 * 32 + 2 * (32 + 160))
        #expect(word(data, 0) == 0x20)
        #expect(word(data, 1) == 2)
        #expect(word(data, 2) == 2 * 32)
        #expect(word(data, 3) == 2 * 32 + 32 + 160)
        // Each item: length 4 + 4 * 32, then collect((tokenId, owner, max, max)) padded to 160
        for (index, tokenId) in [11, 22].enumerated() {
            let item = 4 + 4 * 32 + index * (32 + 160)
            #expect(word(data, 0, skip: item) == 4 + 4 * 32)
            let call = item + 32
            #expect(data[(data.startIndex + call)..<(data.startIndex + call + 4)].hexString == "fc6f7865")
            #expect(word(data, 0, skip: call + 4) == tokenId)
            #expect(addressWord(data, 1, skip: call + 4) == owner)
            #expect(fullWord(data, 2, skip: call + 4) == maxUInt128)
            #expect(fullWord(data, 3, skip: call + 4) == maxUInt128)
            #expect(data[(data.startIndex + call + 132)..<(data.startIndex + call + 160)].allSatisfy { $0 == 0 })
        }
    }

    @Test func oneV3PositionIsAPlainCollect() throws {
        let batch = try #require(CollectBatch(chainID: "ethereum", positions: [position(11), position(22)], owner: owner))
        let tx = try #require(batch.transactions(for: ["ethereum-v3-22"], now: now).first)
        #expect(tx.data == ABI.callCollectStatic(tokenId: 22, recipient: owner))
    }

    @Test func v4PositionsDecreaseEachThenTakeEachCurrencyOnce() throws {
        let positions = [
            position(7, v4: true, currencies: (native, usdc)),
            position(9, v4: true, currencies: (native, usdt)),
        ]
        let batch = try #require(CollectBatch(chainID: "ethereum", positions: positions, owner: owner))
        let tx = try #require(batch.transactions(for: Set(batch.items.map(\.id)), now: now).first)
        #expect(tx.to == "0xbd216513d74c8cf14cf4747e6aaa6420ff64ee9e")
        #expect(tx.versionLabel == "v4")
        let data = tx.data

        // modifyLiquidities(bytes unlockData, uint256 deadline)
        #expect(data.prefix(4).hexString == "dd46508f")
        #expect(data.count == 4 + 3 * 32 + 36 * 32)
        #expect(word(data, 0) == 0x40)
        #expect(word(data, 1) == 1_800_000_000 + 20 * 60)
        #expect(word(data, 2) == 36 * 32)

        // unlockData = abi.encode(bytes actions, bytes[] params)
        let u = 4 + 3 * 32
        #expect(word(data, 0, skip: u) == 0x40)
        #expect(word(data, 1, skip: u) == 0x80)
        #expect(word(data, 2, skip: u) == 5)
        let actions = data[(data.startIndex + u + 3 * 32)..<(data.startIndex + u + 4 * 32)]
        #expect(Array(actions.prefix(5)) == [0x01, 0x01, 0x0e, 0x0e, 0x0e]) // DECREASE ×2, TAKE ×3
        #expect(actions.dropFirst(5).allSatisfy { $0 == 0 })
        #expect(word(data, 4, skip: u) == 5)
        let offsets = (5...9).map { word(data, $0, skip: u) }
        #expect(offsets == [160, 160 + 224, 160 + 2 * 224, 160 + 2 * 224 + 128, 160 + 2 * 224 + 2 * 128])

        // DECREASE_LIQUIDITY: tokenId, liquidity 0, mins 0, offset to empty hookData
        for (index, tokenId) in [7, 9].enumerated() {
            let first = 10 + index * 7
            #expect(word(data, first, skip: u) == 6 * 32)
            #expect(word(data, first + 1, skip: u) == tokenId)
            #expect((first + 2...first + 4).allSatisfy { word(data, $0, skip: u) == 0 })
            #expect(word(data, first + 5, skip: u) == 5 * 32)
            #expect(word(data, first + 6, skip: u) == 0)
        }

        // TAKE (currency, recipient, amount 0 = full credit): ETH once, though both pools hold it
        for (index, currency) in [native, usdc, usdt].enumerated() {
            let first = 24 + index * 4
            #expect(word(data, first, skip: u) == 3 * 32)
            #expect(addressWord(data, first + 1, skip: u) == currency)
            #expect(addressWord(data, first + 2, skip: u) == owner)
            #expect(word(data, first + 3, skip: u) == 0)
        }
    }

    @Test func singlePositionV4EncodingIsUnchanged() {
        // The single-position collect keeps TAKE_PAIR and its exact encoding.
        let data = ABI.v4CallCollectFees(tokenId: 1, currency0: native, currency1: usdc, recipient: owner, deadline: 5)
        #expect(data.count == 4 + 3 * 32 + 18 * 32)
        #expect(data[data.startIndex + 4 + 6 * 32 + 1] == 0x11)
    }

    @Test func v3AndV4OnOneChainAreTwoTransactions() throws {
        let positions = [position(11), position(7, v4: true), position(22), position(5, chain: "base")]
        let batch = try #require(CollectBatch(chainID: "ethereum", positions: positions, owner: owner))
        #expect(batch.items.map(\.id) == ["ethereum-v3-11", "ethereum-v4-7", "ethereum-v3-22"])
        #expect(batch.subject == "3 positions on Ethereum")
        let all = batch.transactions(for: Set(batch.items.map(\.id)), now: now)
        #expect(all.map(\.versionLabel) == ["v3", "v4"])
        #expect(all.map(\.itemIDs) == [["ethereum-v3-11", "ethereum-v3-22"], ["ethereum-v4-7"]])
        #expect(batch.transactions(for: ["ethereum-v4-7"], now: now).map(\.versionLabel) == ["v4"])
        #expect(batch.transactions(for: [], now: now).isEmpty)
        #expect(batch.transactions(for: ["base-v3-5"], now: now).isEmpty)
    }

    @Test func onlyCollectablePositions() {
        #expect(CollectBatch(chainID: "ethereum", positions: [position(1, fees: 0)], owner: owner) == nil)
        #expect(CollectBatch(chainID: "ethereum", positions: [position(1)], owner: "0x12") == nil)
        #expect(CollectBatch(chainID: "ethereum", positions: [position(1, chain: "base")], owner: owner) == nil)
    }

    @Test func chainSummariesMostValuableFirst() {
        let summaries = CollectBatch.chains(in: [
            position(1, usd: 300), position(2, v4: true, usd: 112), position(3, fees: 0),
            position(4, chain: "base", usd: 96), position(5, chain: "base", usd: nil),
        ])
        #expect(summaries.map(\.label) == ["Ethereum · 2 positions · $412.00", "Base · 2 positions · $96.00"])
        #expect(CollectBatch.chains(in: [position(4, chain: "base", usd: nil)]).map(\.label) == ["Base · 1 position"])
    }
}

@Suite("Collect batch check")
struct CollectBatchCheckerTests {
    private struct Revert: Error {}

    @Test func namesAndDropsTheFailingPosition() async throws {
        let batch = try #require(CollectBatch(
            chainID: "ethereum", positions: [position(1), position(2), position(3)], owner: owner
        ))
        let all = try #require(batch.transactions(for: Set(batch.items.map(\.id)), now: now).first).data
        let rest = try #require(batch.transactions(for: ["ethereum-v3-1", "ethereum-v3-3"], now: now).first).data
        let bad = try #require(batch.transactions(for: ["ethereum-v3-2"], now: now).first).data
        let checker = CollectBatchChecker(
            estimateGas: { _, data, from in
                #expect(from == owner)
                if data == all { throw EthereumClient.Err.reverted("execution reverted: Not approved") }
                #expect(data == rest)
                return 150_000
            },
            dryRun: { _, data, _ in
                if data == bad { throw EthereumClient.Err.reverted("execution reverted: Not approved") }
            },
            gasPrice: { 2_000_000_000 }
        )
        let check = await checker.check(batch, ids: Set(batch.items.map(\.id)), now: now)
        #expect(check.error == nil)
        #expect(check.failing == ["ethereum-v3-2": "RPC: execution reverted: Not approved"])
        #expect(check.transactions.map(\.data) == [rest])
        #expect(check.gas == 150_000)
        #expect(check.feeLabel(nativeUSD: 3000) == "≈ $0.90")
        #expect(check.feeLabel(nativeUSD: nil) == "≈ 150,000 gas")
    }

    @Test func revertWithNoSingleCulpritIsAnError() async throws {
        let batch = try #require(CollectBatch(chainID: "ethereum", positions: [position(1), position(2)], owner: owner))
        let checker = CollectBatchChecker(
            estimateGas: { _, _, _ in throw EthereumClient.Err.reverted("execution reverted") },
            dryRun: { _, _, _ in },
            gasPrice: { 1 }
        )
        let check = await checker.check(batch, ids: Set(batch.items.map(\.id)), now: now)
        #expect(check.transactions.isEmpty)
        #expect(check.error == "The v3 collect would fail: RPC: execution reverted")
        #expect(check.feeLabel(nativeUSD: 1) == nil)
    }

    @Test func rpcFailureIsAnErrorNotAFailingPosition() async throws {
        let batch = try #require(CollectBatch(chainID: "ethereum", positions: [position(1)], owner: owner))
        let checker = CollectBatchChecker(
            estimateGas: { _, _, _ in throw EthereumClient.Err.rpc("HTTP 429") },
            dryRun: { _, _, _ in Issue.record("no per-position retry for a transport error") },
            gasPrice: { 1 }
        )
        let check = await checker.check(batch, ids: ["ethereum-v3-1"], now: now)
        #expect(check.failing.isEmpty)
        #expect(check.error?.hasPrefix("Could not check the transaction") == true)
    }

    @Test func everyPositionFailing() async throws {
        let batch = try #require(CollectBatch(chainID: "ethereum", positions: [position(1), position(2)], owner: owner))
        let checker = CollectBatchChecker(
            estimateGas: { _, _, _ in throw EthereumClient.Err.reverted("execution reverted") },
            dryRun: { _, _, _ in throw EthereumClient.Err.reverted("execution reverted") },
            gasPrice: { 1 }
        )
        let check = await checker.check(batch, ids: Set(batch.items.map(\.id)), now: now)
        #expect(check.transactions.isEmpty)
        #expect(check.error == nil)
        #expect(Set(check.failing.keys) == ["ethereum-v3-1", "ethereum-v3-2"])
    }
}

@Suite("Batch collect page")
struct BatchCollectPageTests {
    private func batch() throws -> CollectBatch {
        var odd = position(2, v4: true)
        odd = Position(
            chainID: odd.chainID, chainName: odd.chainName, chainNumericID: odd.chainNumericID, tokenId: "2",
            token0: weth, token1: usdc, sym0: "<img src=x>", sym1: "USDC", feePct: "0.05", feeRaw: 500,
            fees0: 1, fees1: 0, tickLower: 0, tickUpper: 1, liquidity: 1
        )
        odd.isV4 = true
        odd.currency0 = native
        odd.currency1 = usdc
        return try #require(CollectBatch(chainID: "ethereum", positions: [position(1), odd], owner: owner))
    }

    @Test func listsEveryPositionEscapedWithFailingOnesDisabled() throws {
        let batch = try batch()
        var check = CollectBatchCheck()
        check.failing = ["ethereum-v4-2": "<b>reverted</b>"]
        let html = BatchCollectPage.html(for: batch, check: check, feeLabel: nil, nonce: "abc")
        #expect(html.contains("<input type=\"checkbox\" value=\"ethereum-v3-1\" checked>"))
        #expect(html.contains("<input type=\"checkbox\" value=\"ethereum-v4-2\" disabled>"))
        #expect(!html.contains("<img src=x>"))
        #expect(!html.contains("<b>reverted</b>"))
        #expect(html.contains("Would fail: &lt;b&gt;reverted&lt;/b&gt;"))
        #expect(html.contains("<script nonce=\"abc\">"))
        #expect(html.contains("<style nonce=\"abc\">"))
    }

    @Test func stateCarriesThePlanAndCannotCloseItsBlock() throws {
        let batch = try batch()
        var check = CollectBatchCheck()
        check.transactions = batch.transactions(for: ["ethereum-v3-1"], now: now)
        check.error = "</script><b>"
        let json = BatchCollectPage.stateJSON(batch, check: check, feeLabel: "≈ $0.90")
        #expect(!json.contains("<"))
        let state = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(state["chainId"] as? Int == 1)
        #expect(state["owner"] as? String == owner)
        #expect(state["explorer"] as? String == "https://etherscan.io/tx/")
        let items = try #require(state["items"] as? [[String: Any]])
        #expect(items.map { $0["id"] as? String } == ["ethereum-v3-1", "ethereum-v4-2"])
        #expect(items[0]["usd"] as? Double == 10)
        let plan = try #require(state["plan"] as? [String: Any])
        #expect(plan["gas"] as? String == "≈ $0.90")
        #expect(plan["error"] as? String == "</script><b>")
        let transactions = try #require(plan["transactions"] as? [[String: Any]])
        #expect(transactions.first?["version"] as? String == "v3")
        #expect(transactions.first?["data"] as? String == "0x" + ABI.callCollectStatic(tokenId: 1, recipient: owner).hexString)
    }

    @Test func buildBodies() {
        #expect(BatchCollectPage.selection(fromBuildBody: Data("{\"ids\":[\"a\",\"b\"]}".utf8)) == ["a", "b"])
        #expect(BatchCollectPage.selection(fromBuildBody: Data("{\"ids\":[]}".utf8)) == [])
        #expect(BatchCollectPage.selection(fromBuildBody: Data("{\"ids\":[1]}".utf8)) == nil)
        #expect(BatchCollectPage.selection(fromBuildBody: Data("nope".utf8)) == nil)
    }
}
