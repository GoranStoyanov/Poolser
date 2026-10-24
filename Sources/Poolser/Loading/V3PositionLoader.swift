import Foundation

/// Reads a wallet's Uniswap v3 positions on one chain through the NonfungiblePositionManager,
/// which is ERC-721 Enumerable, so positions are listed with tokenOfOwnerByIndex.
struct V3PositionLoader {
    let eth: EthereumClient
    let chain: SupportedChain
    let prices: PriceService
    /// Marks loaded positions as waiting for the background claimed-fee scan.
    let trackClaimedFees: Bool

    func load(wallet: String) async -> LoaderOutput {
        guard let v3Factory = chain.v3Factory, let v3NFPM = chain.v3NFPM else {
            return LoaderOutput()
        }

        var metadata = TokenMetadataResolver(eth: eth)
        var poolTicks:      [String: Int]    = [:]
        var poolSqrtPrices: [String: Double] = [:]
        var tokenAddrs = Set<String>()
        var rawPositions: [Position] = []

        // 1 · balance
        let numPos: Int
        do {
            let d = try await eth.ethCall(to: v3NFPM, data: ABI.callBalanceOf(owner: wallet))
            numPos = Int(d.readUInt64(wordAt: 0))
        } catch EthereumClient.Err.noResult {
            return LoaderOutput(error: "v3: balanceOf returned no result (RPC did not return a usable payload)")
        } catch {
            return LoaderOutput(error: error.localizedDescription)
        }
        guard numPos > 0 else { return LoaderOutput() }

        // 2 · per-position
        for i in 0..<numPos {
            do {
                let idData = try await eth.ethCall(
                    to: v3NFPM,
                    data: ABI.callTokenOfOwnerByIndex(owner: wallet, index: UInt64(i))
                )
                let tokenId = idData.readUInt64(wordAt: 0)

                // positions() returns 12 × 32-byte words:
                //  0:nonce 1:operator 2:token0 3:token1 4:fee
                //  5:tickLower 6:tickUpper 7:liquidity 8-9:feeGrowth 10-11:tokensOwed
                let pos = try await eth.ethCall(to: v3NFPM, data: ABI.callPositions(tokenId: tokenId))
                let token0    = pos.readAddress(wordAt: 64)
                let token1    = pos.readAddress(wordAt: 96)
                let feeRaw    = Int(pos.readUInt64(wordAt: 128))
                let tickLower = pos.readInt24(wordAt: 160)
                let tickUpper = pos.readInt24(wordAt: 192)
                let liqZero   = pos.isZeroWord(at: 224)
                let liquidity = liqZero ? 0.0 : pos.readAmount(wordAt: 224, decimals: 0)

                let m0 = await metadata.resolve(token0)
                let m1 = await metadata.resolve(token1)

                var fees0 = 0.0, fees1 = 0.0
                if let c = try? await eth.ethCall(
                    to: v3NFPM,
                    data: ABI.callCollectStatic(tokenId: tokenId, recipient: wallet)
                ), c.count >= 64 {
                    fees0 = c.readAmount(wordAt: 0,  decimals: m0.decimals)
                    fees1 = c.readAmount(wordAt: 32, decimals: m1.decimals)
                }

                if liqZero && fees0 == 0 && fees1 == 0 { continue }

                tokenAddrs.insert(token0.lowercased())
                tokenAddrs.insert(token1.lowercased())

                rawPositions.append(Position(
                    chainID: chain.id,
                    chainName: chain.displayName,
                    chainNumericID: chain.chainId,
                    tokenId:   String(tokenId),
                    token0:    token0,    token1:    token1,
                    sym0:      m0.symbol, sym1:      m1.symbol,
                    feePct:    String(format: "%.2f", Double(feeRaw) / 10_000),
                    feeRaw:    feeRaw,
                    fees0:     fees0,     fees1:     fees1,
                    tickLower: tickLower, tickUpper: tickUpper,
                    liquidity: liquidity,
                    dec0:      m0.decimals,
                    dec1:      m1.decimals
                ))
            } catch {
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

        // 3 · prices
        let priceMap = await prices.fetchPrices(
            for: Array(tokenAddrs),
            coingeckoPlatformID: chain.coingeckoPlatformID,
            defiLlamaChainKey: chain.defiLlamaChainKey
        )

        // 4 · USD + in-range + amounts
        var totalFeesUSD = 0.0
        var finalPositions: [Position] = []

        for var p in rawPositions {
            guard p.error == nil else { finalPositions.append(p); continue }

            var usd = 0.0; var hasUsd = false
            if let px = priceMap[p.token0.lowercased()], p.fees0 > 0 { usd += p.fees0 * px; hasUsd = true }
            if let px = priceMap[p.token1.lowercased()], p.fees1 > 0 { usd += p.fees1 * px; hasUsd = true }
            if hasUsd { p.usd = usd; totalFeesUSD += usd }

            do {
                let pd   = try await eth.ethCall(to: v3Factory, data: ABI.callGetPool(token0: p.token0, token1: p.token1, fee: p.feeRaw))
                let pool = pd.readAddress(wordAt: 0)
                guard pool.dropFirst(2).lowercased() != String(repeating: "0", count: 40) else {
                    finalPositions.append(p); continue
                }
                let key = pool.lowercased()
                let tick: Int; let sqrtPrice: Double
                if let ct = poolTicks[key], let sp = poolSqrtPrices[key] {
                    tick = ct; sqrtPrice = sp
                } else {
                    let s0 = try await eth.ethCall(to: pool, data: ABI.callSlot0())
                    tick      = s0.readInt24(wordAt: 32)
                    sqrtPrice = s0.readAmount(wordAt: 0, decimals: 0) / pow(2.0, 96)
                    poolTicks[key] = tick; poolSqrtPrices[key] = sqrtPrice
                }
                p.currentTick = tick
                p.inRange = Position.isInRange(tick: tick, lower: p.tickLower, upper: p.tickUpper)
                p.poolAddress = pool.lowercased()
                computeAmounts(position: &p, sqrtPrice: sqrtPrice, metaCache: metadata.cache, priceMap: priceMap)
            } catch { /* inRange stays nil */ }

            finalPositions.append(p)
        }

        // Mark v3 positions as pending fee history scan (background task will fill in claimed amounts).
        if chain.v3DeployBlock != nil && trackClaimedFees {
            for i in finalPositions.indices where finalPositions[i].error == nil {
                finalPositions[i].feeHistoryBootstrapping = true
            }
        }

        return LoaderOutput(positions: finalPositions, feesUSD: totalFeesUSD)
    }
}
