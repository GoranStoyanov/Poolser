import Foundation
import Testing
@testable import Poolser

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_700_000_000)

    var now: Date { lock.withLock { current } }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { current += seconds }
    }
}

/// Records every network fetch and answers from a fixed price table.
private actor FakePriceSource {
    struct Call: Equatable {
        let platform: String
        let addresses: [String]
    }

    private(set) var calls: [Call] = []
    private var prices: [String: [String: Double]]
    private var isGated = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(prices: [String: [String: Double]]) {
        self.prices = prices
    }

    func setPrices(_ prices: [String: [String: Double]]) { self.prices = prices }

    /// Holds every fetch until `openGate()` is called.
    func closeGate() { isGated = true }

    func openGate() {
        isGated = false
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    func fetch(_ addresses: [String], platform: String) async -> [String: Double] {
        calls.append(Call(platform: platform, addresses: addresses))
        if isGated {
            await withCheckedContinuation { waiters.append($0) }
        }
        let table = prices[platform] ?? [:]
        return addresses.reduce(into: [:]) { acc, address in
            if let price = table[address] { acc[address] = price }
        }
    }

    func waitForCalls(_ count: Int) async {
        while calls.count < count {
            await Task.yield()
        }
    }
}

private func makeService(
    source: FakePriceSource,
    clock: TestClock,
    ttl: TimeInterval = 60
) -> PriceService {
    PriceService(ttl: ttl, now: { clock.now }) { addresses, platform, _ in
        await source.fetch(addresses, platform: platform)
    }
}

@Suite("PriceService cache")
struct PriceServiceTests {
    private let defaultPrices = ["ethereum": ["0xa": 1.0, "0xb": 2.0, "0xc": 3.0]]

    @Test func reusesPricesWithinTTL() async {
        let source = FakePriceSource(prices: defaultPrices)
        let clock = TestClock()
        let service = makeService(source: source, clock: clock)

        let first = await service.fetchPrices(for: ["0xA", "0xb"], coingeckoPlatformID: "ethereum", defiLlamaChainKey: "ethereum")
        clock.advance(59)
        let second = await service.fetchPrices(for: ["0xa", "0xB"], coingeckoPlatformID: "ethereum", defiLlamaChainKey: "ethereum")

        #expect(first == ["0xa": 1.0, "0xb": 2.0])
        #expect(second == first)
        #expect(await source.calls.count == 1)
    }

    @Test func refetchesOnceTTLExpires() async {
        let source = FakePriceSource(prices: defaultPrices)
        let clock = TestClock()
        let service = makeService(source: source, clock: clock)

        _ = await service.fetchPrices(for: ["0xa"], coingeckoPlatformID: "ethereum", defiLlamaChainKey: "ethereum")
        await source.setPrices(["ethereum": ["0xa": 1.5]])
        clock.advance(60)
        let refreshed = await service.fetchPrices(for: ["0xa"], coingeckoPlatformID: "ethereum", defiLlamaChainKey: "ethereum")

        #expect(refreshed == ["0xa": 1.5])
        #expect(await source.calls.count == 2)
    }

    @Test func fetchesOnlyTokensMissingFromCache() async {
        let source = FakePriceSource(prices: defaultPrices)
        let service = makeService(source: source, clock: TestClock())

        _ = await service.fetchPrices(for: ["0xa"], coingeckoPlatformID: "ethereum", defiLlamaChainKey: "ethereum")
        let result = await service.fetchPrices(for: ["0xa", "0xc"], coingeckoPlatformID: "ethereum", defiLlamaChainKey: "ethereum")

        #expect(result == ["0xa": 1.0, "0xc": 3.0])
        #expect(await source.calls.map(\.addresses) == [["0xa"], ["0xc"]])
    }

    @Test func keysCacheByPlatform() async {
        let source = FakePriceSource(prices: ["ethereum": ["0xa": 1.0], "base": ["0xa": 7.0]])
        let service = makeService(source: source, clock: TestClock())

        let mainnet = await service.fetchPrices(for: ["0xa"], coingeckoPlatformID: "ethereum", defiLlamaChainKey: "ethereum")
        let base = await service.fetchPrices(for: ["0xa"], coingeckoPlatformID: "base", defiLlamaChainKey: "base")

        #expect(mainnet == ["0xa": 1.0])
        #expect(base == ["0xa": 7.0])
        #expect(await source.calls.map(\.platform) == ["ethereum", "base"])
    }

    @Test func remembersUnpricedTokenWhenSourcesAnswered() async {
        let source = FakePriceSource(prices: defaultPrices)
        let service = makeService(source: source, clock: TestClock())

        let first = await service.fetchPrices(for: ["0xa", "0xjunk"], coingeckoPlatformID: "ethereum", defiLlamaChainKey: "ethereum")
        let second = await service.fetchPrices(for: ["0xjunk"], coingeckoPlatformID: "ethereum", defiLlamaChainKey: "ethereum")

        #expect(first == ["0xa": 1.0])
        #expect(second.isEmpty)
        #expect(await source.calls.count == 1)
    }

    @Test func retriesAfterEmptyAnswer() async {
        let source = FakePriceSource(prices: [:])
        let service = makeService(source: source, clock: TestClock())

        let failed = await service.fetchPrices(for: ["0xa"], coingeckoPlatformID: "ethereum", defiLlamaChainKey: "ethereum")
        await source.setPrices(defaultPrices)
        let retried = await service.fetchPrices(for: ["0xa"], coingeckoPlatformID: "ethereum", defiLlamaChainKey: "ethereum")

        #expect(failed.isEmpty)
        #expect(retried == ["0xa": 1.0])
        #expect(await source.calls.count == 2)
    }

    @Test func concurrentRequestsShareInFlightFetch() async {
        let source = FakePriceSource(prices: defaultPrices)
        let service = makeService(source: source, clock: TestClock())
        await source.closeGate()

        let first = Task {
            await service.fetchPrices(for: ["0xa", "0xb"], coingeckoPlatformID: "ethereum", defiLlamaChainKey: "ethereum")
        }
        await source.waitForCalls(1)
        // 0xa and 0xb are already on the wire, so only 0xc needs a request of its own. Seeing
        // that second call proves the overlapping request is now waiting on the first one.
        let second = Task {
            await service.fetchPrices(for: ["0xb", "0xa", "0xc"], coingeckoPlatformID: "ethereum", defiLlamaChainKey: "ethereum")
        }
        await source.waitForCalls(2)
        await source.openGate()

        #expect(await first.value == ["0xa": 1.0, "0xb": 2.0])
        #expect(await second.value == ["0xa": 1.0, "0xb": 2.0, "0xc": 3.0])
        #expect(await source.calls.map(\.addresses) == [["0xa", "0xb"], ["0xc"]])
    }
}
