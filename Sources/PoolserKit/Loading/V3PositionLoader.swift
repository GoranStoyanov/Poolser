import Foundation

/// Reads a wallet's Uniswap v3 positions on one chain through the NonfungiblePositionManager,
/// which is ERC-721 Enumerable, so positions are listed with tokenOfOwnerByIndex.
struct V3PositionLoader {
    let eth: EthereumClient
    let chain: SupportedChain
    let prices: PriceService
    /// Marks loaded positions as waiting for the background claimed-fee scan.
    let trackClaimedFees: Bool

    /// `balance` is the wallet's position count when it was already read with other wallets'.
    func load(wallet: String, balance: UInt64? = nil) async -> LoaderOutput {
        guard let v3Factory = chain.v3Factory, let v3NFPM = chain.v3NFPM else {
            return LoaderOutput()
        }

        let reader = ContractReader(eth: eth, multicall3: chain.multicall3)
        let context = "v3 \(chain.displayName)"
        var metadata = TokenMetadataResolver()
        var tokenAddrs = Set<String>()
        var rawPositions: [Position] = []

        // 1 · balance
        let numPos: Int
        do {
            if let balance {
                numPos = Int(balance)
            } else {
                let d = try await eth.ethCall(to: v3NFPM, data: ABI.callBalanceOf(owner: wallet))
                numPos = Int(d.readUInt64(wordAt: 0))
            }
        } catch EthereumClient.Err.noResult {
            return LoaderOutput(error: "v3: balanceOf returned no result (RPC did not return a usable payload)")
        } catch {
            return LoaderOutput(error: error.localizedDescription)
        }
        guard numPos > 0 else { return LoaderOutput() }

        // 2 · tokenIds, then positions() for each id that was read
        let idResults = await reader.read(
            (0..<numPos).map {
                ContractCall(target: v3NFPM, data: ABI.callTokenOfOwnerByIndex(owner: wallet, index: UInt64($0)))
            },
            context: "\(context) tokenOfOwnerByIndex"
        )
        let tokenIds = idResults.map { $0.map { $0.readUInt64(wordAt: 0) } }
        let readIds = tokenIds.compactMap { try? $0.get() }
        var positionResults = await reader.read(
            readIds.map { ContractCall(target: v3NFPM, data: ABI.callPositions(tokenId: $0)) },
            context: "\(context) positions"
        ).makeIterator()
        var entries: [Result<V3PositionFields, Error>] = []
        for idResult in tokenIds {
            entries.append(idResult.flatMap { tokenId in
                positionResults.next()!.map { V3PositionFields(tokenId: tokenId, positions: $0) }
            })
        }
        let fields = entries.compactMap { try? $0.get() }

        // 3 · token metadata and pool addresses in one batch, while the collect() simulations run
        async let owedByTokenId = simulateCollect(fields.map(\.tokenId), nfpm: v3NFPM, wallet: wallet)
        let metadataReads = metadata.pending(fields.flatMap { [$0.token0, $0.token1] })
        let poolCalls = fields.map {
            ContractCall(target: v3Factory, data: ABI.callGetPool(token0: $0.token0, token1: $0.token1, fee: $0.feeRaw))
        }
        let batch = await reader.readRetryingFailures(metadataReads.calls + poolCalls, context: "\(context) tokens+pools")
        metadata.store(metadataReads, results: batch.prefix(metadataReads.calls.count))
        let poolResultByTokenId = Dictionary(
            zip(fields.map(\.tokenId), batch.suffix(poolCalls.count)),
            uniquingKeysWith: { first, _ in first }
        )
        let owed = await owedByTokenId

        for (i, entry) in entries.enumerated() {
            switch entry {
            case .success(let f):
                let m0 = metadata.metadata(f.token0)
                let m1 = metadata.metadata(f.token1)

                var fees0 = 0.0, fees1 = 0.0
                let owedData = owed[f.tokenId].flatMap { $0.count >= 64 ? $0 : nil }
                if let c = owedData {
                    fees0 = c.readAmount(wordAt: 0,  decimals: m0.decimals)
                    fees1 = c.readAmount(wordAt: 32, decimals: m1.decimals)
                }

                if f.liqZero && fees0 == 0 && fees1 == 0 { continue }

                tokenAddrs.insert(f.token0.lowercased())
                tokenAddrs.insert(f.token1.lowercased())

                var position = Position(
                    chainID: chain.id,
                    chainName: chain.displayName,
                    chainNumericID: chain.chainId,
                    tokenId:   String(f.tokenId),
                    token0:    f.token0,    token1:    f.token1,
                    sym0:      m0.symbol,   sym1:      m1.symbol,
                    feePct:    String(format: "%.2f", Double(f.feeRaw) / 10_000),
                    feeRaw:    f.feeRaw,
                    fees0:     fees0,       fees1:     fees1,
                    tickLower: f.tickLower, tickUpper: f.tickUpper,
                    liquidity: f.liquidity,
                    dec0:      m0.decimals,
                    dec1:      m1.decimals
                )
                // Zero from a failed read is not zero owed: shown as $0 it reads as a collect,
                // and the daily ledger then counts the whole balance as earned once it reappears.
                if owedData == nil { position.feesError = "Unclaimed fees could not be read (collect simulation failed)" }
                rawPositions.append(position)
            case .failure(let error):
                rawPositions.append(Position(
                    chainID: chain.id,
                    chainName: chain.displayName,
                    chainNumericID: chain.chainId,
                    tokenId: "err-\(i)", token0: "", token1: "",
                    sym0: "", sym1: "", feePct: "", feeRaw: 0,
                    fees0: 0, fees1: 0, tickLower: 0, tickUpper: 0,
                    liquidity: 0,
                    error: error.localizedDescription
                ))
            }
        }

        guard !rawPositions.isEmpty else { return LoaderOutput() }

        // 4 · prices
        let priceMap = await prices.fetchPrices(
            for: Array(tokenAddrs),
            coingeckoPlatformID: chain.coingeckoPlatformID,
            defiLlamaChainKey: chain.defiLlamaChainKey
        )

        // 5 · pool state in one batch: slot0 of every pool that still has a position, plus the
        // fee growth reads that let the daily fee history measure today without its own request.
        // Without Multicall3 each of those would be a request of its own, so only slot0 is read.
        var poolByTokenId: [String: String] = [:]
        for p in rawPositions where p.error == nil {
            guard let tokenId = UInt64(p.tokenId),
                  case .success(let pd)? = poolResultByTokenId[tokenId] else { continue }
            let pool = pd.readAddress(wordAt: 0)
            guard pool.dropFirst(2).lowercased() != String(repeating: "0", count: 40) else { continue }
            poolByTokenId[p.tokenId] = pool.lowercased()
        }
        let stateCalls = rawPositions.flatMap { p -> [ContractCall] in
            guard let pool = poolByTokenId[p.tokenId] else { return [] }
            guard reader.multicall3 != nil else { return [V3FeeGrowthReads.slot0(pool)] }
            return V3FeeGrowthReads.calls(pool: pool, tickLower: p.tickLower, tickUpper: p.tickUpper)
        }
        let stateResults = await reader.readRetryingFailures(stateCalls, context: "\(context) pool state")
        let stateByCall = Dictionary(zip(stateCalls, stateResults), uniquingKeysWith: { first, _ in first })
        let positionsByTokenId = Dictionary(fields.map { (String($0.tokenId), $0.raw) }, uniquingKeysWith: { first, _ in first })

        // 6 · USD + in-range + amounts
        var totalFeesUSD = 0.0
        var finalPositions: [Position] = []

        for var p in rawPositions {
            guard p.error == nil else { finalPositions.append(p); continue }

            p.price0USD = priceMap[p.token0.lowercased()]
            p.price1USD = priceMap[p.token1.lowercased()]
            var usd = 0.0; var hasUsd = false
            if let px = priceMap[p.token0.lowercased()], p.fees0 > 0 { usd += p.fees0 * px; hasUsd = true }
            if let px = priceMap[p.token1.lowercased()], p.fees1 > 0 { usd += p.fees1 * px; hasUsd = true }
            if hasUsd { p.usd = usd; totalFeesUSD += usd }

            // A failed getPool or slot0 read leaves inRange nil.
            if let pool = poolByTokenId[p.tokenId], case .success(let s0)? = stateByCall[V3FeeGrowthReads.slot0(pool)] {
                let tick      = s0.readInt24(wordAt: 32)
                let sqrtPrice = s0.readAmount(wordAt: 0, decimals: 0) / pow(2.0, 96)
                p.currentTick = tick
                p.inRange = Position.isInRange(tick: tick, lower: p.tickLower, upper: p.tickUpper)
                p.poolAddress = pool
                computeAmounts(position: &p, sqrtPrice: sqrtPrice, metaCache: metadata.cache, priceMap: priceMap)
                if let positionsData = positionsByTokenId[p.tokenId] {
                    p.feeGrowth = V3FeeGrowthReads.snapshot(
                        positions: positionsData, pool: pool, tickLower: p.tickLower, tickUpper: p.tickUpper,
                        results: stateByCall
                    )
                }
            } else {
                p.poolStateError = Self.poolStateError(
                    pool: UInt64(p.tokenId).flatMap { poolResultByTokenId[$0] },
                    slot0: poolByTokenId[p.tokenId].flatMap { stateByCall[V3FeeGrowthReads.slot0($0)] }
                )
            }

            finalPositions.append(p)
        }
        for p in finalPositions {
            guard let reason = p.poolStateError else { continue }
            await LogStore.shared.log("\(context) #\(p.tokenId): pool state unavailable — \(reason)", level: .error)
        }

        // Mark v3 positions as pending fee history scan (background task will fill in claimed amounts).
        if chain.v3DeployBlock != nil && trackClaimedFees {
            for i in finalPositions.indices where finalPositions[i].error == nil {
                finalPositions[i].feeHistoryBootstrapping = true
            }
        }

        return LoaderOutput(positions: finalPositions, feesUSD: totalFeesUSD)
    }

    /// Why a position has no pool state: the failed slot0 or getPool read, or a pool the
    /// factory does not know.
    static func poolStateError(pool: Result<Data, Error>?, slot0: Result<Data, Error>?) -> String {
        if case .failure(let error)? = slot0 { return "slot0: \(error.localizedDescription)" }
        if case .failure(let error)? = pool { return "getPool: \(error.localizedDescription)" }
        return "pool not found"
    }

    /// Unclaimed fees per tokenId from collect() simulated with eth_call; a failed simulation
    /// is left out. These cannot go through Multicall3: collect() requires msg.sender to be
    /// authorized for the token. A plain eth_call runs as address(0), which passes because
    /// getApproved() of a token with no approval is also address(0); from Multicall3,
    /// msg.sender is the Multicall3 contract and collect() reverts with "Not approved".
    private func simulateCollect(_ tokenIds: [UInt64], nfpm: String, wallet: String) async -> [UInt64: Data] {
        await withTaskGroup(of: (UInt64, Data?).self) { group in
            for tokenId in tokenIds {
                group.addTask {
                    let data = try? await eth.ethCall(
                        to: nfpm,
                        data: ABI.callCollectStatic(tokenId: tokenId, recipient: wallet)
                    )
                    return (tokenId, data)
                }
            }
            var owed: [UInt64: Data] = [:]
            for await (tokenId, data) in group {
                if let data { owed[tokenId] = data }
            }
            return owed
        }
    }
}

/// The fields of a NonfungiblePositionManager.positions() result the loader uses.
private struct V3PositionFields {
    let tokenId: UInt64
    let token0: String
    let token1: String
    let feeRaw: Int
    let tickLower: Int
    let tickUpper: Int
    let liqZero: Bool
    let liquidity: Double
    let raw: Data

    // positions() returns 12 × 32-byte words:
    //  0:nonce 1:operator 2:token0 3:token1 4:fee
    //  5:tickLower 6:tickUpper 7:liquidity 8-9:feeGrowth 10-11:tokensOwed
    init(tokenId: UInt64, positions pos: Data) {
        self.tokenId = tokenId
        raw       = pos
        token0    = pos.readAddress(wordAt: 64)
        token1    = pos.readAddress(wordAt: 96)
        feeRaw    = Int(pos.readUInt64(wordAt: 128))
        tickLower = pos.readInt24(wordAt: 160)
        tickUpper = pos.readInt24(wordAt: 192)
        liqZero   = pos.isZeroWord(at: 224)
        liquidity = liqZero ? 0.0 : pos.readAmount(wordAt: 224, decimals: 0)
    }
}

/// The pool reads behind a `FeeGrowthSnapshot`, shared by the loader (latest state) and the
/// daily fee history (state at the start of each day).
enum V3FeeGrowthReads {
    static func slot0(_ pool: String) -> ContractCall {
        ContractCall(target: pool, data: ABI.callSlot0())
    }

    /// slot0, both fee growth globals and the ticks at both ends of the range. Positions in the
    /// same pool share the pool reads; ContractReader sends each identical call once.
    static func calls(pool: String, tickLower: Int, tickUpper: Int) -> [ContractCall] {
        [
            slot0(pool),
            ContractCall(target: pool, data: ABI.callFeeGrowthGlobal0()),
            ContractCall(target: pool, data: ABI.callFeeGrowthGlobal1()),
            ContractCall(target: pool, data: ABI.callTicks(tickLower)),
            ContractCall(target: pool, data: ABI.callTicks(tickUpper)),
        ]
    }

    /// nil unless every read behind it succeeded.
    static func snapshot(
        positions: Data, pool: String, tickLower: Int, tickUpper: Int,
        results: [ContractCall: Result<Data, Error>]
    ) -> FeeGrowthSnapshot? {
        let reads = calls(pool: pool, tickLower: tickLower, tickUpper: tickUpper).map { try? results[$0]?.get() }
        guard let slot0 = reads[0], let global0 = reads[1], let global1 = reads[2],
              let lower = reads[3], let upper = reads[4] else { return nil }
        return FeeGrowthSnapshot(
            positions: positions, slot0: slot0, global0: global0, global1: global1, lowerTick: lower, upperTick: upper
        )
    }
}
