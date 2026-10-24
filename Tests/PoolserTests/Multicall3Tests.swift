import Foundation
import Testing
@testable import Poolser

private let multicall3 = SupportedChain.canonicalMulticall3
private let baseNFPM = "0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1"

private func hex(_ string: String) -> Data { Data(hexString: string)! }

private let malformedResults: [Data] = {
    var cases: [Data] = []
    cases.append(Data())
    cases.append(word(32))                                   // array length missing
    cases.append(word(32) + word(5))                         // 5 entries, no heads
    cases.append(word(32) + word(1) + word(4096))            // tuple offset out of bounds
    var pastEnd = word(32) + word(1) + word(32)              // returnData past the end
    pastEnd += word(1) + word(64) + word(1000)
    cases.append(pastEnd)
    cases.append(Data(repeating: 0xff, count: 32) + word(1)) // offset not a small integer
    return cases
}()

@Suite("Multicall3 ABI")
struct Multicall3ABITests {
    @Test func selectorMatchesAggregate3() {
        #expect(ABI.encodeAggregate3([]).prefix(4).hexString == "82ad56cb")
    }

    /// Calldata sent to Multicall3 on Base: getChainId() with allowFailure false, then
    /// positions(0) on the v3 NFPM with allowFailure true.
    @Test func encodesTwoCallsLikeOnChainVector() {
        let calldata = ABI.encodeAggregate3([
            Call3(target: multicall3, allowFailure: false, data: hex("3408e470")),
            Call3(target: baseNFPM, allowFailure: true, data: ABI.callPositions(tokenId: 0)),
        ])
        #expect(calldata.hexString == """
            82ad56cb\
            0000000000000000000000000000000000000000000000000000000000000020\
            0000000000000000000000000000000000000000000000000000000000000002\
            0000000000000000000000000000000000000000000000000000000000000040\
            00000000000000000000000000000000000000000000000000000000000000e0\
            000000000000000000000000ca11bde05977b3631167028862be2a173976ca11\
            0000000000000000000000000000000000000000000000000000000000000000\
            0000000000000000000000000000000000000000000000000000000000000060\
            0000000000000000000000000000000000000000000000000000000000000004\
            3408e47000000000000000000000000000000000000000000000000000000000\
            00000000000000000000000003a520b32c04bf3beef7beb72e919cf822ed34f1\
            0000000000000000000000000000000000000000000000000000000000000001\
            0000000000000000000000000000000000000000000000000000000000000060\
            0000000000000000000000000000000000000000000000000000000000000024\
            99fbab8800000000000000000000000000000000000000000000000000000000\
            0000000000000000000000000000000000000000000000000000000000000000
            """)
    }

    @Test func encodedCallsRoundTripThroughIndependentDecoder() {
        let calls = [
            Call3(target: baseNFPM, allowFailure: true, data: Data()),
            Call3(target: multicall3, allowFailure: false, data: Data(repeating: 0xab, count: 32)),
            Call3(target: baseNFPM, allowFailure: true, data: Data(repeating: 0xcd, count: 33)),
        ]
        let decoded = decodeAggregate3Calls(ABI.encodeAggregate3(calls))
        #expect(decoded.map(\.target) == calls.map { $0.target.lowercased() })
        #expect(decoded.map(\.allowFailure) == [true, false, true])
        #expect(decoded.map(\.data) == calls.map(\.data))
    }

    /// Result of the call above: chain id 8453, then positions(0) reverting with
    /// "Invalid token ID" (success false, revert data kept).
    @Test func decodesOnChainResultWithFailedCall() throws {
        let raw = hex("""
            0000000000000000000000000000000000000000000000000000000000000020\
            0000000000000000000000000000000000000000000000000000000000000002\
            0000000000000000000000000000000000000000000000000000000000000040\
            00000000000000000000000000000000000000000000000000000000000000c0\
            0000000000000000000000000000000000000000000000000000000000000001\
            0000000000000000000000000000000000000000000000000000000000000040\
            0000000000000000000000000000000000000000000000000000000000000020\
            0000000000000000000000000000000000000000000000000000000000002105\
            0000000000000000000000000000000000000000000000000000000000000000\
            0000000000000000000000000000000000000000000000000000000000000040\
            0000000000000000000000000000000000000000000000000000000000000064\
            08c379a000000000000000000000000000000000000000000000000000000000\
            0000002000000000000000000000000000000000000000000000000000000000\
            00000010496e76616c696420746f6b656e204944000000000000000000000000\
            0000000000000000000000000000000000000000000000000000000000000000
            """)
        let results = try ABI.decodeAggregate3Result(raw)

        #expect(results.count == 2)
        #expect(results[0].success)
        #expect(results[0].returnData.readUInt64(wordAt: 0) == 8453)
        #expect(!results[1].success)
        #expect(results[1].returnData == errorString("Invalid token ID"))
        #expect(ABI.revertMessage(results[1].returnData) == "execution reverted: Invalid token ID")
    }

    @Test func decodesEmptyAndUnalignedReturnData() throws {
        let raw = encodeAggregate3Results([
            (success: true, data: Data()),
            (success: false, data: Data()),
            (success: true, data: Data(repeating: 0x11, count: 33)),
        ])
        let results = try ABI.decodeAggregate3Result(raw)
        #expect(results == [
            Call3Result(success: true, returnData: Data()),
            Call3Result(success: false, returnData: Data()),
            Call3Result(success: true, returnData: Data(repeating: 0x11, count: 33)),
        ])
    }

    @Test func decodesSlice() throws {
        let raw = Data([0xff, 0xff]) + encodeAggregate3Results([(success: true, data: word(7))])
        let results = try ABI.decodeAggregate3Result(raw.dropFirst(2))
        #expect(results == [Call3Result(success: true, returnData: word(7))])
    }

    @Test("Malformed aggregate3 results throw instead of trapping", arguments: malformedResults)
    func malformedResultThrows(raw: Data) {
        #expect(throws: ABI.DecodeError.self) { try ABI.decodeAggregate3Result(raw) }
    }

    @Test("Revert data is described like a node's error message", arguments: [
        (errorString("Not approved"), "execution reverted: Not approved"),
        (errorString(""), "execution reverted"),
        (Data([0x4e, 0x48, 0x7b, 0x71]) + word(0x11), "execution reverted: panic 0x11"),
        (Data(), "execution reverted"),
        (Data([0xde, 0xad, 0xbe, 0xef]), "execution reverted: 0xdeadbeef"),
    ])
    func revertMessage(data: Data, expected: String) {
        #expect(ABI.revertMessage(data) == expected)
    }
}

@Suite("EthereumClient.aggregate3")
struct Aggregate3ClientTests {
    @Test func sendsOneEthCallAndReturnsResultsInOrder() async throws {
        let chain = FakeChain()
        await chain.set("0x00000000000000000000000000000000000000aa", hex("01"), .value(word(1)))
        await chain.set("0x00000000000000000000000000000000000000bb", hex("02"), .revert("nope"))

        let results = try await chain.client().aggregate3([
            Call3(target: "0x00000000000000000000000000000000000000aa", allowFailure: true, data: hex("01")),
            Call3(target: "0x00000000000000000000000000000000000000bb", allowFailure: true, data: hex("02")),
        ], multicall3: multicall3, context: "test")

        #expect(results == [
            Call3Result(success: true, returnData: word(1)),
            Call3Result(success: false, returnData: errorString("nope")),
        ])
        let requests = await chain.requests
        #expect(requests.count == 1)
        #expect(requests[0].to == multicall3)
        #expect(requests[0].subcalls == 2)
    }

    @Test func costsOneEthCallOfCredits() async throws {
        let limiter = RPCCreditLimiter(creditsPerSecond: 0.001, maxBurstCredits: 1000)
        let chain = FakeChain()
        let calls = (0..<50).map { Call3(target: multicall3, allowFailure: true, data: word($0)) }

        _ = try await chain.client(limiter: limiter).aggregate3(calls, multicall3: multicall3, context: "test")

        let remaining = await limiter.availableCredits
        #expect(remaining > 919 && remaining < 921)
    }
}

@Suite("ContractReader")
struct ContractReaderTests {
    private let a = "0x00000000000000000000000000000000000000aa"
    private let b = "0x00000000000000000000000000000000000000bb"

    private func calls(_ count: Int, target: String) -> [ContractCall] {
        (0..<count).map { ContractCall(target: target, data: word($0)) }
    }

    private func answerAll(_ chain: FakeChain, _ calls: [ContractCall]) async {
        for call in calls { await chain.set(call.target, call.data, .value(word(100) + call.data)) }
    }

    @Test func batchesCallsIntoOneAggregate3() async {
        let chain = FakeChain()
        let reads = calls(5, target: a)
        await answerAll(chain, reads)

        let results = await ContractReader(eth: chain.client(), multicall3: multicall3).read(reads, context: "test")

        #expect(results.map { try? $0.get() } == reads.map { word(100) + $0.data })
        #expect(await chain.requests.count == 1)
        #expect(await chain.aggregateCount == 1)
    }

    @Test func revertedSubcallFailsOnlyItsOwnRead() async throws {
        let chain = FakeChain()
        await chain.set(a, hex("01"), .value(word(1)))
        await chain.set(b, hex("02"), .revert("Invalid token ID"))

        let results = await ContractReader(eth: chain.client(), multicall3: multicall3).read(
            [ContractCall(target: a, data: hex("01")), ContractCall(target: b, data: hex("02"))],
            context: "test"
        )

        #expect(try results[0].get() == word(1))
        #expect(throws: EthereumClient.Err.self) { try results[1].get() }
        guard case .failure(EthereumClient.Err.reverted(let message)) = results[1] else {
            Issue.record("expected a revert, got \(results[1])"); return
        }
        #expect(message == "execution reverted: Invalid token ID")
        // ownerOf of a burned token reverts: still read as "not owned", not as a failed check.
        #expect(v4OwnerCheck(results[1], wallet: a) == false)
    }

    @Test func failedRequestFailsEveryReadInIt() async {
        let chain = FakeChain()
        let reads = calls(3, target: a)
        await answerAll(chain, reads)
        await chain.failNextRequest(with: "invalid params")

        let results = await ContractReader(eth: chain.client(), multicall3: multicall3).read(reads, context: "test")

        for result in results {
            guard case .failure(EthereumClient.Err.rpc(let message)) = result else {
                Issue.record("expected the request error, got \(result)"); continue
            }
            #expect(message == "invalid params")
            // A failed request is not a burned token: ownership stays unknown and is retried.
            #expect(v4OwnerCheck(result, wallet: a) == nil)
        }
    }

    @Test func identicalCallsAreSentOnce() async {
        let chain = FakeChain()
        let reads = calls(2, target: a)
        await answerAll(chain, reads)

        let results = await ContractReader(eth: chain.client(), multicall3: multicall3)
            .read(reads + reads + [ContractCall(target: a.uppercased().replacingOccurrences(of: "0X", with: "0x"), data: word(0))], context: "test")

        #expect(results.count == 5)
        #expect(results.map { try? $0.get() } == [0, 1, 0, 1, 0].map { word(100) + word($0) })
        #expect(await chain.requests.map(\.subcalls) == [2])
    }

    @Test func largeBatchesAreChunked() async {
        let chain = FakeChain()
        let reads = calls(5, target: a)
        await answerAll(chain, reads)
        var reader = ContractReader(eth: chain.client(), multicall3: multicall3)
        reader.maxCallsPerBatch = 2

        let results = await reader.read(reads, context: "test")

        #expect(results.map { try? $0.get() } == reads.map { word(100) + $0.data })
        // The last chunk holds a single call, which goes out as a plain eth_call.
        #expect(await chain.requests.map(\.subcalls) == [2, 2, nil])
    }

    @Test func singleCallSkipsMulticall() async {
        let chain = FakeChain()
        await chain.set(a, hex("01"), .value(word(1)))

        let results = await ContractReader(eth: chain.client(), multicall3: multicall3)
            .read([ContractCall(target: a, data: hex("01"))], context: "test")

        #expect(results.map { try? $0.get() } == [word(1)])
        #expect(await chain.requests.map(\.to) == [a])
    }

    @Test func batchThatRunsOutOfGasIsSplit() async {
        let chain = FakeChain()
        let reads = calls(6, target: a)
        await answerAll(chain, reads)
        await chain.setMaxSubcallsPerAggregate(3)

        let results = await ContractReader(eth: chain.client(), multicall3: multicall3).read(reads, context: "test")

        #expect(results.map { try? $0.get() } == reads.map { word(100) + $0.data })
        #expect(await chain.requests.map(\.subcalls) == [6, 3, 3])
    }

    @Test func withoutMulticall3EachReadIsItsOwnEthCall() async {
        let chain = FakeChain()
        let reads = calls(4, target: a) + [ContractCall(target: b, data: hex("02"))]
        await answerAll(chain, Array(reads.prefix(4)))
        await chain.set(b, hex("02"), .revert("Invalid token ID"))

        let results = await ContractReader(eth: chain.client(), multicall3: nil).read(reads, context: "test")

        #expect(results.prefix(4).map { try? $0.get() } == reads.prefix(4).map { word(100) + $0.data })
        #expect(throws: EthereumClient.Err.self) { try results[4].get() }
        let requests = await chain.requests
        #expect(requests.count == 5)
        #expect(requests.allSatisfy { $0.subcalls == nil })
        #expect(Set(requests.map(\.data)) == Set(reads.map(\.data)))
    }

    @Test func bothPathsReturnTheSameResults() async {
        let chain = FakeChain()
        let reads = calls(3, target: a) + [ContractCall(target: b, data: hex("02")), ContractCall(target: b, data: hex("03"))]
        await answerAll(chain, Array(reads.prefix(3)))
        await chain.set(b, hex("02"), .revert("Invalid token ID"))
        await chain.set(b, hex("03"), .value(Data()))

        let batched = await ContractReader(eth: chain.client(), multicall3: multicall3).read(reads, context: "test")
        let single = await ContractReader(eth: chain.client(), multicall3: nil).read(reads, context: "test")

        #expect(batched.map(describe) == single.map(describe))
    }

    @Test func emptyReadSendsNothing() async {
        let chain = FakeChain()
        let results = await ContractReader(eth: chain.client(), multicall3: multicall3).read([], context: "test")
        #expect(results.isEmpty)
        #expect(await chain.requests.isEmpty)
    }
}

func describe(_ result: Result<Data, Error>) -> String {
    switch result {
    case .success(let data): return "ok \(data.hexString)"
    case .failure(let error): return "error \(error.localizedDescription)"
    }
}
