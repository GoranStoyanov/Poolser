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

        var metadata = TokenMetadataResolver(eth: eth)
        var poolCache: [String: (sqrtPrice: Double, tick: Int)] = [:]
        var tokenAddrs = Set<String>()
        var rawPositions: [Position] = []

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

        // 3 · per-position
        for tokenId in ownership.ownedTokenIds {
            do {
                // getPoolAndPositionInfo returns:
                //   word 0: currency0 (address)   word 1: currency1 (address)
                //   word 2: fee (uint24)           word 3: tickSpacing (int24)
                //   word 4: hooks (address)
                //   word 5: positionInfo (bytes32)
                //     bytes32 layout: [25 bytes poolId][3 bytes tickUpper][3 bytes tickLower][1 byte flags]
                //     i.e. tickUpper at word+25, tickLower at word+28
                let posData = try await eth.ethCall(
                    to: v4PM,
                    data: ABI.v4CallGetPoolAndPositionInfo(tokenId: tokenId)
                )
                guard posData.count >= 192 else { continue }

                let currency0   = posData.readAddress(wordAt: 0)
                let currency1   = posData.readAddress(wordAt: 32)
                let fee         = Int(posData.readUInt64(wordAt: 64))
                let tickSpacing = posData.readInt24(wordAt: 96)
                let hooks       = posData.readAddress(wordAt: 128)
                let tickLower   = posData.readInt24At(byteOffset: 160 + 28)
                let tickUpper   = posData.readInt24At(byteOffset: 160 + 25)

                // Liquidity
                let liqData = try await eth.ethCall(
                    to: v4PM,
                    data: ABI.v4CallGetPositionLiquidity(tokenId: tokenId)
                )
                let liquidity = liqData.readAmount(wordAt: 0, decimals: 0)
                guard liquidity > 0 else { continue }

                // Map native ETH → WETH for metadata/price lookups; keep original for PoolId
                let priceAddr0 = isNativeToken(currency0) ? chain.wrappedNativeToken : currency0
                let priceAddr1 = isNativeToken(currency1) ? chain.wrappedNativeToken : currency1

                let m0 = isNativeToken(currency0)
                    ? (symbol: chain.nativeCurrencySymbol, decimals: 18)
                    : await metadata.resolve(currency0)
                let m1 = isNativeToken(currency1)
                    ? (symbol: chain.nativeCurrencySymbol, decimals: 18)
                    : await metadata.resolve(currency1)

                tokenAddrs.insert(priceAddr0.lowercased())
                tokenAddrs.insert(priceAddr1.lowercased())

                let poolId = ABI.computeV4PoolId(
                    currency0: currency0, currency1: currency1,
                    fee: fee, tickSpacing: tickSpacing, hooks: hooks
                )

                rawPositions.append(Position(
                    chainID: chain.id,
                    chainName: chain.displayName,
                    chainNumericID: chain.chainId,
                    tokenId:   String(tokenId),
                    token0:    priceAddr0, token1:    priceAddr1,
                    sym0:      m0.symbol,  sym1:      m1.symbol,
                    feePct:    V4Fee.label(fee), feeRaw: fee,
                    fees0:     0,          fees1:     0,
                    tickLower: tickLower,  tickUpper: tickUpper,
                    liquidity: liquidity,
                    isV4:      true,
                    poolId:    poolId
                ))
            } catch EthereumClient.Err.noResult {
                continue // stale tokenId — contract returned null, position no longer exists
            } catch {
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

        // 4 · prices
        let priceMap = await prices.fetchPrices(
            for: Array(tokenAddrs),
            coingeckoPlatformID: chain.coingeckoPlatformID,
            defiLlamaChainKey: chain.defiLlamaChainKey
        )

        // 5 · in-range + amounts + fees
        var finalPositions: [Position] = []
        var totalFeesUSD = 0.0

        for var p in rawPositions {
            guard let pid = p.poolId else { finalPositions.append(p); continue }

            let cacheKey = pid.hexString
            let tick: Int; let sqrtPrice: Double
            if let c = poolCache[cacheKey] {
                tick = c.tick; sqrtPrice = c.sqrtPrice
            } else {
                guard let s0 = try? await eth.ethCall(to: v4SV, data: ABI.v4CallGetSlot0(poolId: pid)),
                      s0.count >= 64 else { finalPositions.append(p); continue }
                tick      = s0.readInt24(wordAt: 32)
                sqrtPrice = s0.readAmount(wordAt: 0, decimals: 0) / pow(2.0, 96)
                poolCache[cacheKey] = (sqrtPrice: sqrtPrice, tick: tick)
            }

            p.currentTick = tick
            p.inRange = Position.isInRange(tick: tick, lower: p.tickLower, upper: p.tickUpper)
            computeAmounts(position: &p, sqrtPrice: sqrtPrice, metaCache: metadata.cache, priceMap: priceMap)

            // Unclaimed fees via StateView feeGrowth math (4 concurrent RPC calls)
            if let tokenId = UInt64(p.tokenId) {
                do {
                    let fees = try await fetchUnclaimedFees(
                        poolId: pid, tokenId: tokenId,
                        tickLower: p.tickLower, tickUpper: p.tickUpper,
                        currentTick: tick, liquidityRaw: p.liquidity, v4SV: v4SV, v4PM: v4PM)
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

    /// Unclaimed fees for a single position from 4 concurrent StateView calls: getPosition,
    /// getTickInfo×2, getFeeGrowthGlobals. Returns raw fee amounts (before decimal conversion).
    /// Throws with a descriptive message if any call fails.
    private func fetchUnclaimedFees(
        poolId: Data, tokenId: UInt64,
        tickLower: Int, tickUpper: Int,
        currentTick: Int, liquidityRaw: Double,
        v4SV: String,
        v4PM: String
    ) async throws -> (fees0: Double, fees1: Double) {
        async let posTask  = eth.ethCall(to: v4SV, data: ABI.v4CallGetPosition(
            poolId: poolId, owner: v4PM,
            tickLower: tickLower, tickUpper: tickUpper, salt: tokenId))
        async let loTask   = eth.ethCall(to: v4SV, data: ABI.v4CallGetTickInfo(poolId: poolId, tick: tickLower))
        async let hiTask   = eth.ethCall(to: v4SV, data: ABI.v4CallGetTickInfo(poolId: poolId, tick: tickUpper))
        async let globTask = eth.ethCall(to: v4SV, data: ABI.v4CallGetFeeGrowthGlobals(poolId: poolId))

        let pos  = try? await posTask
        let lo   = try? await loTask
        let hi   = try? await hiTask
        let glob = try? await globTask

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

private func isNativeToken(_ addr: String) -> Bool {
    addr.lowercased() == nativeTokenAddress
}
