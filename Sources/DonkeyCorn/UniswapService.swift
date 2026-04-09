import Foundation
import Combine

// MARK: - Contract addresses

private let v3NFPM    = "0xC36442b4a4522E871399CD717aBDD847Ab11FE88"
private let v3Factory = "0x1F98431c8aD98523631AE4a59f267346ea31F984"
private let v4PM           = "0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9E"
private let v4SV           = "0x7fFE42C4a5DEeA5b0feC41C94C136Cf115597227"
/// First block to scan for v4 Transfer events (~Jan 2025, before v4 mainnet launch).
private let v4PMDeployBlock = "0x14A0000"

/// Native ETH in Uniswap v4 is represented as address(0).
/// We substitute WETH for price lookups since CoinGecko/DefiLlama index by token address.
private let nativeETHAddress = "0x0000000000000000000000000000000000000000"
private let wethAddress      = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"

// MARK: - Service

@MainActor
final class UniswapService: ObservableObject {
    @Published var titleText  = "🦄 …"
    @Published var positions: [Position] = []
    @Published var isLoading  = false
    @Published var lastError: String?

    private let priceService = PriceService()
    private var timer: Timer?

    init() {
        timer = .scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { await self?.load() }
        }
        Task { await load() }
    }

    func refresh() { Task { await load() } }

    // MARK: - Orchestrator

    private func load() async {
        let wallet = AppSettings.shared.walletAddress
        let rpcStr = AppSettings.shared.rpcURL
        guard !wallet.isEmpty, !rpcStr.isEmpty, let rpcURL = URL(string: rpcStr) else {
            titleText = "🦄 –"
            lastError = "Configure wallet address and RPC URL in Settings (⌘,)"
            return
        }

        isLoading = true
        lastError = nil

        let eth = EthereumClient(rpcURL: rpcURL)

        // Run v3 and v4 concurrently — they interleave at each network await.
        async let v3 = loadV3(wallet: wallet, eth: eth)
        async let v4 = loadV4(wallet: wallet, eth: eth)
        let (r3, r4) = await (v3, v4)

        let all = r3.positions + r4.positions
        positions = all

        let errors = [r3.error, r4.error].compactMap { $0 }
        lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")

        if all.isEmpty {
            titleText = "🦄 $0.00"
        } else {
            titleText = String(format: "🦄 $%.2f", r3.feesUSD + r4.feesUSD)
        }

        isLoading = false
    }

    // MARK: - v3

    private func loadV3(
        wallet: String, eth: EthereumClient
    ) async -> (positions: [Position], feesUSD: Double, error: String?) {

        var metaCache:      [String: (symbol: String, decimals: Int)] = [:]
        var poolTicks:      [String: Int]    = [:]
        var poolSqrtPrices: [String: Double] = [:]
        var tokenAddrs = Set<String>()
        var rawPositions: [Position] = []

        // 1 · balance
        let numPos: Int
        do {
            let d = try await eth.ethCall(to: v3NFPM, data: ABI.callBalanceOf(owner: wallet))
            numPos = Int(d.readUInt64(wordAt: 0))
        } catch {
            return ([], 0, error.localizedDescription)
        }
        guard numPos > 0 else { return ([], 0, nil) }

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

                let m0 = await resolve(addr: token0, eth: eth, cache: &metaCache)
                let m1 = await resolve(addr: token1, eth: eth, cache: &metaCache)

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
                    tokenId:   String(tokenId),
                    token0:    token0,    token1:    token1,
                    sym0:      m0.symbol, sym1:      m1.symbol,
                    feePct:    String(format: "%.2f", Double(feeRaw) / 10_000),
                    feeRaw:    feeRaw,
                    fees0:     fees0,     fees1:     fees1,
                    tickLower: tickLower, tickUpper: tickUpper,
                    liquidity: liquidity
                ))
            } catch {
                rawPositions.append(Position(
                    tokenId: "err-\(i)", token0: "", token1: "",
                    sym0: "", sym1: "", feePct: "", feeRaw: 0,
                    fees0: 0, fees1: 0, tickLower: 0, tickUpper: 0,
                    liquidity: 0,
                    error: error.localizedDescription
                ))
            }
        }

        guard !rawPositions.isEmpty else { return ([], 0, nil) }

        // 3 · prices
        let priceMap = await priceService.fetchPrices(for: Array(tokenAddrs))

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
                p.inRange = tick >= p.tickLower && tick <= p.tickUpper
                computeAmounts(position: &p, sqrtPrice: sqrtPrice, metaCache: metaCache, priceMap: priceMap)
            } catch { /* inRange stays nil */ }

            finalPositions.append(p)
        }

        return (finalPositions, totalFeesUSD, nil)
    }

    // MARK: - v4

    private func loadV4(
        wallet: String, eth: EthereumClient
    ) async -> (positions: [Position], feesUSD: Double, error: String?) {

        var metaCache: [String: (symbol: String, decimals: Int)] = [:]
        var poolCache: [String: (sqrtPrice: Double, tick: Int)] = [:]
        var tokenAddrs = Set<String>()
        var rawPositions: [Position] = []

        // 1 · Quick balance check (cheap — avoids log queries when wallet has no v4 positions)
        let v4Balance: UInt64
        do {
            let numData = try await eth.ethCall(to: v4PM, data: ABI.callBalanceOf(owner: wallet))
            guard numData.count >= 32 else { return ([], 0, "v4: unexpected balanceOf response") }
            v4Balance = numData.readUInt64(wordAt: 0)
        } catch {
            return ([], 0, "v4: balanceOf failed – \(error.localizedDescription)")
        }
        guard v4Balance > 0 else { return ([], 0, nil) }

        // 2 · Enumerate owned tokenIds via ERC-721 Transfer events.
        //     The v4 PositionManager does NOT implement ERC-721 Enumerable,
        //     so tokenOfOwnerByIndex() does not exist. We reconstruct ownership
        //     from Transfer(to=wallet) minus Transfer(from=wallet).
        //     Note: requires an RPC that supports large eth_getLogs block ranges
        //     (Alchemy/Infura paid tiers work; very restricted free-tier nodes may not).
        let walletPadded: String = {
            let hex = (wallet.hasPrefix("0x") ? String(wallet.dropFirst(2)) : wallet).lowercased()
            return "0x" + String(repeating: "0", count: 64 - min(hex.count, 64)) + hex
        }()

        // Get all tokenIds ever transferred TO this wallet (mints + incoming transfers).
        // transferSig is hardcoded (known keccak256) to avoid any keccak implementation variance.
        let transferSig = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

        let toLogs: [[String: Any]]
        do {
            toLogs = try await eth.ethGetLogs(address: v4PM,
                                              topics: [transferSig, nil, walletPadded],
                                              fromBlock: v4PMDeployBlock)
        } catch {
            return ([], 0, "v4: Transfer log query failed – \(error.localizedDescription)")
        }

        func extractTokenId(_ log: [String: Any]) -> UInt64? {
            guard let topics = log["topics"] as? [String], topics.count >= 4 else { return nil }
            let hex = topics[3].hasPrefix("0x") ? String(topics[3].dropFirst(2)) : topics[3]
            guard let val = UInt64(hex.suffix(16), radix: 16) else { return nil }
            return val
        }
        let candidateIds = Set(toLogs.compactMap(extractTokenId))
        guard !candidateIds.isEmpty else {
            // Diagnostic: query without wallet filter to see if the contract has ANY events.
            // If anyCount > 0, the wallet topic filter is wrong.
            // If anyCount == 0, the RPC can't serve logs for this block range.
            let anyCount = ((try? await eth.ethGetLogs(
                address: v4PM, topics: [transferSig], fromBlock: v4PMDeployBlock
            )) ?? []).count
            return ([], 0, """
                v4: 0 Transfer-to-wallet events (balance=\(v4Balance))
                unfiltered Transfer events for contract: \(anyCount)
                sig: \(transferSig)
                wallet topic: \(walletPadded)
                fromBlock: \(v4PMDeployBlock)
                """)
        }

        // Verify current ownership via ownerOf() — handles re-transfers, staking, etc.
        // Run all ownerOf calls concurrently.
        let ownedIds = await withTaskGroup(of: Optional<UInt64>.self) { group -> [UInt64] in
            for tokenId in candidateIds {
                group.addTask {
                    guard let data = try? await eth.ethCall(
                        to: v4PM, data: ABI.callOwnerOf(tokenId: tokenId)
                    ) else { return nil }
                    return data.readAddress(wordAt: 0).lowercased() == wallet.lowercased()
                        ? tokenId : nil
                }
            }
            var result: [UInt64] = []
            for await id in group { if let id { result.append(id) } }
            return result
        }
        guard !ownedIds.isEmpty else {
            return ([], 0, "v4: balance=\(v4Balance), found \(candidateIds.count) candidate tokenIds but none pass ownerOf check")
        }

        // 3 · per-position
        for tokenId in ownedIds {
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
                let priceAddr0 = isNativeETH(currency0) ? wethAddress : currency0
                let priceAddr1 = isNativeETH(currency1) ? wethAddress : currency1

                let m0 = isNativeETH(currency0)
                    ? (symbol: "ETH", decimals: 18)
                    : await resolve(addr: currency0, eth: eth, cache: &metaCache)
                let m1 = isNativeETH(currency1)
                    ? (symbol: "ETH", decimals: 18)
                    : await resolve(addr: currency1, eth: eth, cache: &metaCache)

                tokenAddrs.insert(priceAddr0.lowercased())
                tokenAddrs.insert(priceAddr1.lowercased())

                let poolId = ABI.computeV4PoolId(
                    currency0: currency0, currency1: currency1,
                    fee: fee, tickSpacing: tickSpacing, hooks: hooks
                )

                let feePct = fee == 0
                    ? "dyn"
                    : String(format: "%.4g", Double(fee) / 10_000)

                rawPositions.append(Position(
                    tokenId:   String(tokenId),
                    token0:    priceAddr0, token1:    priceAddr1,
                    sym0:      m0.symbol,  sym1:      m1.symbol,
                    feePct:    feePct,     feeRaw:    fee,
                    fees0:     0,          fees1:     0,
                    tickLower: tickLower,  tickUpper: tickUpper,
                    liquidity: liquidity,
                    isV4:      true,
                    poolId:    poolId
                ))
            } catch {
                rawPositions.append(Position(
                    tokenId: String(tokenId), token0: "", token1: "",
                    sym0: "", sym1: "", feePct: "", feeRaw: 0,
                    fees0: 0, fees1: 0, tickLower: 0, tickUpper: 0,
                    liquidity: 0,
                    error: "v4 #\(tokenId): \(error.localizedDescription)"
                ))
            }
        }

        guard !rawPositions.isEmpty else { return ([], 0, nil) }

        // 4 · prices
        let priceMap = await priceService.fetchPrices(for: Array(tokenAddrs))

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
            p.inRange = tick >= p.tickLower && tick <= p.tickUpper
            computeAmounts(position: &p, sqrtPrice: sqrtPrice, metaCache: metaCache, priceMap: priceMap)

            // Unclaimed fees via StateView feeGrowth math (4 concurrent RPC calls)
            if let tokenId = UInt64(p.tokenId) {
                do {
                    let fees = try await computeV4Fees(
                        poolId: pid, tokenId: tokenId,
                        tickLower: p.tickLower, tickUpper: p.tickUpper,
                        currentTick: tick, liquidityRaw: p.liquidity, eth: eth)
                    let dec0 = metaCache[p.token0.lowercased()]?.decimals ?? 18
                    let dec1 = metaCache[p.token1.lowercased()]?.decimals ?? 18
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

        return (finalPositions, totalFeesUSD, nil)
    }

    // MARK: - v4 fee computation

    /// Computes unclaimed v4 fees for a single position using the standard Uniswap feeGrowthInside formula.
    /// Makes 4 concurrent calls to StateView: getPosition, getTickInfo×2, getFeeGrowthGlobals.
    /// Returns raw fee amounts (before decimal conversion). Throws with a descriptive message if any call fails.
    ///
    /// All feeGrowth arithmetic is done in exact uint256 (wrapping) to avoid catastrophic cancellation
    /// when the accumulators are large (they can be ~2^150+ for active pools, which destroys double
    /// precision if you subtract two nearly-equal large doubles).
    private func computeV4Fees(
        poolId: Data, tokenId: UInt64,
        tickLower: Int, tickUpper: Int,
        currentTick: Int, liquidityRaw: Double,
        eth: EthereumClient
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
            throw V4FeesError("poolId=\(poolId.hexString.prefix(8))… tokenId=\(tokenId) ticks=[\(tickLower),\(tickUpper)]: \(failures.joined(separator: "; "))")
        }
        let posD = pos!, loD = lo!, hiD = hi!, globD = glob!

        // Read all feeGrowth values as exact 32-byte (uint256) words.
        // Do NOT use readAmount() here — those values are ~2^150+ for active pools,
        // causing catastrophic cancellation if converted to Double before subtraction.
        let fg0Last   = posD.readWord(at: 32)
        let fg1Last   = posD.readWord(at: 64)

        let fg0OutLo  = loD.readWord(at: 64)
        let fg1OutLo  = loD.readWord(at: 96)
        let fg0OutHi  = hiD.readWord(at: 64)
        let fg1OutHi  = hiD.readWord(at: 96)

        let fg0Global = globD.readWord(at: 0)
        let fg1Global = globD.readWord(at: 32)

        // Standard feeGrowthInside = global − feeGrowthBelow(lower) − feeGrowthAbove(upper)
        // All subtractions wrap mod 2^256, matching Solidity unchecked arithmetic.
        let fg0Below = currentTick >= tickLower ? fg0OutLo : u256Sub(fg0Global, fg0OutLo)
        let fg1Below = currentTick >= tickLower ? fg1OutLo : u256Sub(fg1Global, fg1OutLo)
        let fg0Above = currentTick <  tickUpper ? fg0OutHi : u256Sub(fg0Global, fg0OutHi)
        let fg1Above = currentTick <  tickUpper ? fg1OutHi : u256Sub(fg1Global, fg1OutHi)

        let fg0Inside = u256Sub(u256Sub(fg0Global, fg0Below), fg0Above)
        let fg1Inside = u256Sub(u256Sub(fg1Global, fg1Below), fg1Above)

        // Delta since last collection (wrapping — handles the fgInside < fgLast case gracefully)
        let delta0 = u256Sub(fg0Inside, fg0Last)
        let delta1 = u256Sub(fg1Inside, fg1Last)

        // Only now convert to Double — the delta is small (fees since last touch) so precision is fine.
        // unclaimed = (fgInsideDelta × liquidity) ÷ 2¹²⁸
        let fees0 = u256ToDouble(delta0) * liquidityRaw / pow(2.0, 128)
        let fees1 = u256ToDouble(delta1) * liquidityRaw / pow(2.0, 128)
        return (fees0: fees0, fees1: fees1)
    }

    // MARK: - Shared helpers

    /// Standard Uniswap v3/v4 amount calculation from sqrtPrice and liquidity.
    private func computeAmounts(
        position p: inout Position,
        sqrtPrice: Double,
        metaCache: [String: (symbol: String, decimals: Int)],
        priceMap: [String: Double]
    ) {
        guard p.liquidity > 0, sqrtPrice > 0 else { return }
        let dec0 = metaCache[p.token0.lowercased()]?.decimals ?? 18
        let dec1 = metaCache[p.token1.lowercased()]?.decimals ?? 18
        let half = log(1.0001) / 2.0
        let sqrtLower = exp(Double(p.tickLower) * half)
        let sqrtUpper = exp(Double(p.tickUpper) * half)
        let L = p.liquidity
        var raw0 = 0.0, raw1 = 0.0
        if sqrtPrice <= sqrtLower {
            raw0 = L * (1.0 / sqrtLower - 1.0 / sqrtUpper)
        } else if sqrtPrice >= sqrtUpper {
            raw1 = L * (sqrtUpper - sqrtLower)
        } else {
            raw0 = L * (1.0 / sqrtPrice - 1.0 / sqrtUpper)
            raw1 = L * (sqrtPrice - sqrtLower)
        }
        p.amount0 = raw0 / pow(10.0, Double(dec0))
        p.amount1 = raw1 / pow(10.0, Double(dec1))

        var posUSD = 0.0; var has = false
        if let px = priceMap[p.token0.lowercased()], p.amount0 > 0 { posUSD += p.amount0 * px; has = true }
        if let px = priceMap[p.token1.lowercased()], p.amount1 > 0 { posUSD += p.amount1 * px; has = true }
        if has { p.positionUSD = posUSD }
    }

    /// Fetches and caches ERC-20 symbol and decimals for a token address.
    private func resolve(
        addr: String,
        eth: EthereumClient,
        cache: inout [String: (symbol: String, decimals: Int)]
    ) async -> (symbol: String, decimals: Int) {
        let key = addr.lowercased()
        if let hit = cache[key] { return hit }
        var sym = shortenAddr(addr), dec = 18
        if let d = try? await eth.ethCall(to: addr, data: ABI.callSymbol()), !d.isEmpty {
            let s = d.readABIString(); if !s.isEmpty { sym = s }
        }
        if let d = try? await eth.ethCall(to: addr, data: ABI.callDecimals()), !d.isEmpty {
            dec = Int(d.readUInt64(wordAt: 0))
        }
        let meta = (symbol: sym, decimals: dec)
        cache[key] = meta
        return meta
    }
}

// MARK: - Exact uint256 arithmetic (for feeGrowth accumulators)

/// Wrapping 256-bit subtraction (mod 2^256), matching Solidity `unchecked { a - b }`.
private func u256Sub(_ a: Data, _ b: Data) -> Data {
    var r = [UInt8](repeating: 0, count: 32)
    var borrow: Int = 0
    for i in stride(from: 31, through: 0, by: -1) {
        let diff = Int(a[i]) - Int(b[i]) - borrow
        r[i] = UInt8((diff + 256) & 0xFF)
        borrow = diff < 0 ? 1 : 0
    }
    return Data(r)
}

/// Convert a 32-byte big-endian uint256 to Double.
/// Only call this on values known to be small (e.g. feeGrowth deltas), where precision loss is acceptable.
private func u256ToDouble(_ d: Data) -> Double {
    var v = 0.0
    for byte in d { v = v * 256.0 + Double(byte) }
    return v
}

// MARK: - Error types

private struct V4FeesError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

// MARK: - Utilities

private func isNativeETH(_ addr: String) -> Bool {
    addr.lowercased() == nativeETHAddress
}

private func shortenAddr(_ addr: String) -> String {
    let a = addr.hasPrefix("0x") ? addr : "0x\(addr)"
    guard a.count >= 10 else { return a }
    return "\(a.prefix(6))…\(a.suffix(4))"
}
