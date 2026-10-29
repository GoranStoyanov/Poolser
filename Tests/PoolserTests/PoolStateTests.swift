import Foundation
import Testing
@testable import PoolserKit

@Suite("Missing pool state")
struct PoolStateErrorTests {
    @Test func reasonNamesTheFailedRead() {
        let failure: Result<Data, Error> = .failure(EthereumClient.Err.rpc("too many requests"))
        let ok: Result<Data, Error> = .success(Data())
        #expect(V3PositionLoader.poolStateError(pool: ok, slot0: failure) == "slot0: RPC: too many requests")
        #expect(V3PositionLoader.poolStateError(pool: failure, slot0: nil) == "getPool: RPC: too many requests")
        #expect(V3PositionLoader.poolStateError(pool: ok, slot0: nil) == "pool not found")
    }

    @Test func unknownAmountsAreNotShownAsZero() {
        var p = Position(
            chainID: "ethereum", chainName: "Ethereum", chainNumericID: 1,
            tokenId: "1", token0: "", token1: "",
            sym0: "A", sym1: "B", feePct: "1.00", feeRaw: 10_000,
            fees0: 0, fees1: 0, tickLower: -100, tickUpper: 100,
            liquidity: 1
        )
        #expect(p.amount0Label == "0")
        p.poolStateError = "slot0: RPC: too many requests"
        #expect(p.amount0Label == "–")
        #expect(p.amount1Label == "–")
    }
}
