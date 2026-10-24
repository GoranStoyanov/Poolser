import Foundation

/// Native token in Uniswap v4 is represented as address(0).
private let nativeTokenAddress = "0x0000000000000000000000000000000000000000"

/// Reads a wallet's Uniswap v4 positions on one chain: ownership comes from
/// `V4OwnershipTracker`, position data from the PositionManager and pool state and fees
/// from StateView.
struct V4PositionLoader {
    let eth: EthereumClient
    let chain: SupportedChain
    let prices: PriceService
    let scanSettings: V4ScanSettings

    func load(wallet: String) async -> LoaderOutput {
        guard let v4PM = chain.v4PM, let v4SV = chain.v4SV else {
            return LoaderOutput()
        }
        guard let deployHex = chain.v4DeployBlockHex,
              let deployBlock = Int(deployHex.dropFirst(2), radix: 16) else {
            return LoaderOutput()
        }

        let reader = ContractReader(eth: eth, multicall3: chain.multicall3)
        let context = "v4 \(chain.displayName)"
        var metadata = TokenMetadataResolver()
        var tokenAddrs = Set<String>()

        // 1 · Quick balance check (cheap — avoids log queries when wallet has no v4 positions)
        let v4Balance: UInt64
        do {
            let numData = try await eth.ethCall(to: v4PM, data: ABI.callBalanceOf(owner: wallet))
            guard numData.count >= 32 else { return LoaderOutput(error: "v4: unexpected balanceOf response") }
            v4Balance = numData.readUInt64(wordAt: 0)
        } catch EthereumClient.Err.noResult {
            return LoaderOutput(error: "v4: balanceOf returned no result (RPC did not return a usable payload)")
        } catch {
            return LoaderOutput(error: "v4: balanceOf failed – \(error.localizedDescription)")
        }
        guard v4Balance > 0 else { return LoaderOutput() }

        // 2 · Owned tokenIds from Transfer logs + ownerOf
        let tracker = V4OwnershipTracker(
            eth: eth,
            chain: chain,
            positionManager: v4PM,
            deployBlock: deployBlock,
            settings: scanSettings
        )
        let ownership: V4Ownership
        do {
            ownership = try await tracker.scan(wallet: wallet, balance: v4Balance)
        } catch {
            return LoaderOutput(error: error.localizedDescription)
        }
        let nextFromBlock = ownership.nextFromBlock

        guard !ownership.ownedTokenIds.isEmpty else {
            // Still scanning: owned positions may be in a later block window.
            if let next = nextFromBlock {
                return LoaderOutput(bootstrapInProgress: true, bootstrapNextFromBlock: next)
            }
            if ownership.candidateCount == 0 {
                return LoaderOutput(error: "v4: no Transfer events found for this wallet (balance=\(v4Balance))")
            }
            return LoaderOutput(error: "v4: balance=\(v4Balance), found \(ownership.candidateCount) candidate tokenIds but none pass ownerOf check")
        }

        // 3 · pool key, PositionInfo and liquidity of every owned tokenId, in one batch
        let tokenIds = ownership.ownedTokenIds
        let positionReads = await reader.read(
            tokenIds.flatMap { tokenId in
                [ContractCall(target: v4PM, data: ABI.v4CallGetPoolAndPositionInfo(tokenId: tokenId)),
                 ContractCall(target: v4PM, data: ABI.v4CallGetPositionLiquidity(tokenId: tokenId))]
            },
            context: "\(context) positions"
        )
        var entries: [V4PositionEntry] = []
        for (i, tokenId) in tokenIds.enumerated() {
            do {
                // getPoolAndPositionInfo returns:
                //   word 0: currency0 (address)   word 1: currency1 (address)
                //   word 2: fee (uint24)           word 3: tickSpacing (int24)
                //   word 4: hooks (address)
                //   word 5: positionInfo (bytes32)
                //     bytes32 layout: [25 bytes poolId][3 bytes tickUpper][3 bytes tickLower][1 byte flags]
                //     i.e. tickUpper at word+25, tickLower at word+28
                let posData = try positionReads[2 * i].get()
                guard posData.count >= 192 else { continue }

                let currency0   = posData.readAddress(wordAt: 0)
                let currency1   = posData.readAddress(wordAt: 32)
                let fee         = Int(posData.readUInt64(wordAt: 64))
                let tickSpacing = posData.readInt24(wordAt: 96)
                let hooks       = posData.readAddress(wordAt: 128)
                let tickLower   = posData.readInt24At(byteOffset: 160 + 28)
                let tickUpper   = posData.readInt24At(byteOffset: 160 + 25)

                let liqData = try positionReads[2 * i + 1].get()
                let liquidity = liqData.readAmount(wordAt: 0, decimals: 0)
                guard liquidity > 0 else { continue }

                entries.append(.loaded(V4PositionFields(
                    tokenId: tokenId,
                    currency0: currency0, currency1: currency1,
                    fee: fee, tickLower: tickLower, tickUpper: tickUpper,
                    liquidity: liquidity,
                    poolId: ABI.computeV4PoolId(
                        currency0: currency0, currency1: currency1,
                        fee: fee, tickSpacing: tickSpacing, hooks: hooks
                    )
                )))
            } catch EthereumClient.Err.noResult {
                continue // stale tokenId — contract returned null, position no longer exists
            } catch {
                entries.append(.failed(tokenId: tokenId, error: error))
            }
        }
        let fields = entries.compactMap { entry -> V4PositionFields? in
            if case .loaded(let f) = entry { return f }
            return nil
        }

        // 4 · token metadata, pool slot0 and the fee-growth reads in one batch. The fee math
        // subtracts accumulators from several reads; within one aggregate3 they share a block.
        let metadataReads = metadata.pending(fields.flatMap { [$0.currency0, $0.currency1] }.filter { !isNativeToken($0) })
        let slot0Calls = fields.map { ContractCall(target: v4SV, data: ABI.v4CallGetSlot0(poolId: $0.poolId)) }
        let feeCalls = fields.flatMap { f in
            [ContractCall(target: v4SV, data: ABI.v4CallGetPosition(
                poolId: f.poolId, owner: v4PM,
                tickLower: f.tickLower, tickUpper: f.tickUpper, salt: f.tokenId)),
             ContractCall(target: v4SV, data: ABI.v4CallGetTickInfo(poolId: f.poolId, tick: f.tickLower)),
             ContractCall(target: v4SV, data: ABI.v4CallGetTickInfo(poolId: f.poolId, tick: f.tickUpper)),
             ContractCall(target: v4SV, data: ABI.v4CallGetFeeGrowthGlobals(poolId: f.poolId))]
        }
        let batch = await reader.read(metadataReads.calls + slot0Calls + feeCalls, context: "\(context) pools+fees")
        metadata.store(metadataReads, results: batch.prefix(metadataReads.calls.count))
        let slot0Results = Array(batch.dropFirst(metadataReads.calls.count).prefix(slot0Calls.count))
        let feeResults = Array(batch.suffix(feeCalls.count))
        var stateByTokenId: [UInt64: V4PoolReads] = [:]
        for (i, f) in fields.enumerated() {
            stateByTokenId[f.tokenId] = V4PoolReads(
                slot0: slot0Results[i],
                position: feeResults[4 * i], lowerTick: feeResults[4 * i + 1],
                upperTick: feeResults[4 * i + 2], feeGrowthGlobals: feeResults[4 * i + 3]
            )
        }

        var rawPositions: [Position] = []
        for entry in entries {
            switch entry {
            case .loaded(let f):
                // Map native ETH → WETH for metadata/price lookups; keep original for PoolId
                let priceAddr0 = isNativeToken(f.currency0) ? chain.wrappedNativeToken : f.currency0
                let priceAddr1 = isNativeToken(f.currency1) ? chain.wrappedNativeToken : f.currency1

                let m0 = isNativeToken(f.currency0)
                    ? (symbol: chain.nativeCurrencySymbol, decimals: 18)
                    : metadata.metadata(f.currency0)
                let m1 = isNativeToken(f.currency1)
                    ? (symbol: chain.nativeCurrencySymbol, decimals: 18)
                    : metadata.metadata(f.currency1)

                tokenAddrs.insert(priceAddr0.lowercased())
                tokenAddrs.insert(priceAddr1.lowercased())

                rawPositions.append(Position(
                    chainID: chain.id,
                    chainName: chain.displayName,
                    chainNumericID: chain.chainId,
                    tokenId:   String(f.tokenId),
                    token0:    priceAddr0,  token1:    priceAddr1,
                    sym0:      m0.symbol,   sym1:      m1.symbol,
                    feePct:    V4Fee.label(f.fee), feeRaw: f.fee,
                    fees0:     0,           fees1:     0,
                    tickLower: f.tickLower, tickUpper: f.tickUpper,
                    liquidity: f.liquidity,
                    isV4:      true,
                    poolId:    f.poolId
                ))
            case .failed(let tokenId, let error):
                rawPositions.append(Position(
                    chainID: chain.id,
                    chainName: chain.displayName,
                    chainNumericID: chain.chainId,
                    tokenId: String(tokenId), token0: "", token1: "",
                    sym0: "", sym1: "", feePct: "", feeRaw: 0,
                    fees0: 0, fees1: 0, tickLower: 0, tickUpper: 0,
                    liquidity: 0,
                    error: "v4 #\(tokenId): \(error.localizedDescription)",
                    isV4: true
                ))
            }
        }

        guard !rawPositions.isEmpty else {
            return LoaderOutput(bootstrapInProgress: nextFromBlock != nil, bootstrapNextFromBlock: nextFromBlock)
        }

        // 5 · prices
        let priceMap = await prices.fetchPrices(
            for: Array(tokenAddrs),
            coingeckoPlatformID: chain.coingeckoPlatformID,
            defiLlamaChainKey: chain.defiLlamaChainKey
        )

        // 6 · in-range + amounts + fees
        var finalPositions: [Position] = []
        var totalFeesUSD = 0.0

        for var p in rawPositions {
            guard let tokenId = UInt64(p.tokenId), let reads = stateByTokenId[tokenId],
                  case .success(let s0) = reads.slot0, s0.count >= 64 else {
                finalPositions.append(p); continue
            }
            let tick      = s0.readInt24(wordAt: 32)
            let sqrtPrice = s0.readAmount(wordAt: 0, decimals: 0) / pow(2.0, 96)

            p.currentTick = tick
            p.inRange = Position.isInRange(tick: tick, lower: p.tickLower, upper: p.tickUpper)
            computeAmounts(position: &p, sqrtPrice: sqrtPrice, metaCache: metadata.cache, priceMap: priceMap)

            // Unclaimed fees via StateView feeGrowth math
            do {
                let fees = try unclaimedFees(
                    reads, poolId: p.poolId ?? Data(), tokenId: tokenId,
                    tickLower: p.tickLower, tickUpper: p.tickUpper,
                    currentTick: tick, liquidityRaw: p.liquidity)
                let dec0 = metadata.cache[p.token0.lowercased()]?.decimals ?? 18
                let dec1 = metadata.cache[p.token1.lowercased()]?.decimals ?? 18
                p.fees0 = fees.fees0 / pow(10.0, Double(dec0))
                p.fees1 = fees.fees1 / pow(10.0, Double(dec1))
                var feeUSD = 0.0; var hasFeeUSD = false
                if let px = priceMap[p.token0.lowercased()], p.fees0 > 0 { feeUSD += p.fees0 * px; hasFeeUSD = true }
                if let px = priceMap[p.token1.lowercased()], p.fees1 > 0 { feeUSD += p.fees1 * px; hasFeeUSD = true }
                if hasFeeUSD { p.usd = feeUSD; totalFeesUSD += feeUSD }
            } catch {
                p.feesError = error.localizedDescription
            }

            finalPositions.append(p)
        }

        return LoaderOutput(
            positions: finalPositions,
            feesUSD: totalFeesUSD,
            bootstrapInProgress: nextFromBlock != nil,
            bootstrapNextFromBlock: nextFromBlock
        )
    }

    /// Unclaimed fees for a single position from its StateView reads: getPosition,
    /// getTickInfo×2, getFeeGrowthGlobals. Returns raw fee amounts (before decimal conversion).
    /// Throws with a descriptive message if any read failed.
    private func unclaimedFees(
        _ reads: V4PoolReads,
        poolId: Data, tokenId: UInt64,
        tickLower: Int, tickUpper: Int,
        currentTick: Int, liquidityRaw: Double
    ) throws -> (fees0: Double, fees1: Double) {
        let pos  = try? reads.position.get()
        let lo   = try? reads.lowerTick.get()
        let hi   = try? reads.upperTick.get()
        let glob = try? reads.feeGrowthGlobals.get()

        // Collect specific failures for diagnosis
        var failures: [String] = []
        if pos  == nil { failures.append("getPosition: no response") }
        else if pos!.count < 96  { failures.append("getPosition: \(pos!.count)B < 96B") }
        if lo   == nil { failures.append("getTickInfo(lo \(tickLower)): no response") }
        else if lo!.count < 128  { failures.append("getTickInfo(lo): \(lo!.count)B < 128B") }
        if hi   == nil { failures.append("getTickInfo(hi \(tickUpper)): no response") }
        else if hi!.count < 128  { failures.append("getTickInfo(hi): \(hi!.count)B < 128B") }
        if glob == nil { failures.append("getFeeGrowthGlobals: no response") }
        else if glob!.count < 64 { failures.append("getFeeGrowthGlobals: \(glob!.count)B < 64B") }

        if !failures.isEmpty {
            throw LoaderError("poolId=\(poolId.hexString.prefix(8))… tokenId=\(tokenId) ticks=[\(tickLower),\(tickUpper)]: \(failures.joined(separator: "; "))")
        }

        return v4UnclaimedFees(
            position: pos!, lowerTickInfo: lo!, upperTickInfo: hi!, feeGrowthGlobals: glob!,
            tickLower: tickLower, tickUpper: tickUpper,
            currentTick: currentTick, liquidityRaw: liquidityRaw
        )
    }
}

/// The fields of a PositionManager position the loader uses, for one tokenId with liquidity.
private struct V4PositionFields {
    let tokenId: UInt64
    let currency0: String
    let currency1: String
    let fee: Int
    let tickLower: Int
    let tickUpper: Int
    let liquidity: Double
    let poolId: Data
}

private enum V4PositionEntry {
    case loaded(V4PositionFields)
    /// Shown as an error row for that tokenId.
    case failed(tokenId: UInt64, error: Error)
}

/// StateView reads behind one position's price, range and unclaimed fees.
private struct V4PoolReads {
    let slot0: Result<Data, Error>
    let position: Result<Data, Error>
    let lowerTick: Result<Data, Error>
    let upperTick: Result<Data, Error>
    let feeGrowthGlobals: Result<Data, Error>
}

private func isNativeToken(_ addr: String) -> Bool {
    addr.lowercased() == nativeTokenAddress
}
