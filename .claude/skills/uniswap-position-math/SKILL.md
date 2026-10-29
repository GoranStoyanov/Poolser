---
name: uniswap-position-math
description: Uniswap v3/v4 concentrated-liquidity math and DeFi data patterns as implemented in Poolser — sqrtPriceX96, ticks, token amounts from liquidity, in-range checks, unclaimed fees via feeGrowthInside (uint256 wrapping), v4 StateView/PositionManager reads, PositionInfo packing, USD valuation and pricing sources. Use when touching computeAmounts, computeV4Fees, position decoding, price or APR display, when adding a new protocol/version/chain, when numbers in the UI look wrong, or when the user asks about fees, ticks, ranges, prices or LP math.
---

# Uniswap position math (Poolser)

All math lives in `Sources/PoolserKit/UniswapService.swift` (`loadV3`, `loadV4`, `computeV4Fees`,
`computeAmounts`) on top of decoders in `Sources/PoolserKit/ABI.swift`. Read those before changing
anything; this skill is the reference for **what the numbers must be**.

## Core definitions

- `price(tick) = 1.0001^tick` — raw token1 per raw token0 (no decimals).
- `sqrtPriceX96 = sqrt(price) · 2^96` (uint160). At tick 0: `2^96 = 79228162514264337593543950336`.
- Human price (token1 per token0): `(sqrtPriceX96 / 2^96)^2 · 10^(dec0 − dec1)`.
  Invert for token0 per token1. Token order is by address (`token0 < token1`), not by "base/quote".
- Tick spacing (v3 fee tiers): 100→1, 500→10, 3000→60, 10000→200. v4 pools carry their own
  `tickSpacing` and `fee` in the `PoolKey` (fee may be dynamic: `0x800000` flag).

## In range

A position earns fees iff `tickLower <= currentTick < tickUpper` (upper bound **exclusive**,
matching v3/v4 core). `loadV3` currently uses `tick <= p.tickUpper`; when touching that code,
align it with the core definition and keep v3 and v4 consistent. Edge case to test: `currentTick == tickUpper`
→ out of range, the position is entirely token1.

## Token amounts from liquidity (`computeAmounts`)

With `sa = sqrt(1.0001^tickLower)`, `sb = sqrt(1.0001^tickUpper)`, `sp = sqrtPriceX96 / 2^96`, `L = liquidity`:

| Case | amount0 (raw) | amount1 (raw) |
|---|---|---|
| `sp <= sa` (below range) | `L·(1/sa − 1/sb)` | 0 |
| `sp >= sb` (above range) | 0 | `L·(sb − sa)` |
| inside | `L·(1/sp − 1/sb)` | `L·(sp − sa)` |

Divide by `10^decimals`. `Double` is fine here (display precision); the existing code is correct.

## Unclaimed fees

### Fee growth inside (v3 `Tick.getFeeGrowthInside`, identical in v4)

```
below  = currentTick >= tickLower ? outside(lower) : global − outside(lower)
above  = currentTick <  tickUpper ? outside(upper) : global − outside(upper)
inside = global − below − above
unclaimed = tokensOwed + L · (inside − insideLast) / 2^128
```

- **All subtractions wrap mod 2^256** (Solidity `unchecked`). Accumulators are ~2^128+ and
  routinely "underflow" by design. Keep them as raw 32-byte words (`readWord`) and use the
  project's `u256Sub`; convert to `Double` **only the final delta**. Never `readAmount` a
  fee-growth word — catastrophic cancellation.
- `tokensOwed` exists only in v3 (`positions()` words 10–11). v4 has none: fees are settled on
  every liquidity modification, so v4 unclaimed is just the growth delta term.
- All inputs (`global`, both tick `outside`s, `insideLast`, `currentTick`) must come from the
  **same block** — batch them in one Multicall or pin the block (see `evm-rpc-optimization`).

### v3: `collect` static call

`loadV3` simulates `NonfungiblePositionManager.collect(tokenId, recipient, maxUint128, maxUint128)`
via `eth_call`; the NFPM pokes the pool (`burn(0)`) so the result already includes accrued fees.
`collect` is guarded by `isAuthorizedForToken`, so the simulation must run with `from` = the
position owner (or an approved operator). If fees ever read as zero for every v3 position,
check the `from` field of the `eth_call` first. Falling back to the manual formula above
(pool `ticks(lower/upper)`, `feeGrowthGlobal0/1X128`, `positions()` lasts + `tokensOwed`)
is valid and avoids the authorization question entirely.

### v4 reads

- `PositionManager.getPoolAndPositionInfo(tokenId)` → `PoolKey(currency0, currency1, fee,
  tickSpacing, hooks)` + packed `PositionInfo` (bytes32).
- `PositionInfo` packing (v4-periphery `PositionInfoLibrary`), from the low bits:
  `hasSubscriber` (8 bits) · `tickLower` (int24) · `tickUpper` (int24) · truncated `poolId` (200 bits).
  Ticks are byte-packed, not word-aligned — decode with `readInt24At(byteOffset:)`, never `readInt24(wordAt:)`.
- `poolId = keccak256(abi.encode(PoolKey))` — compute locally, no RPC.
- PoolManager position key: `owner = PositionManager address`, `salt = bytes32(tokenId)`.
  Read via StateView: `getPositionInfo(poolId, owner, tickLower, tickUpper, salt)`,
  `getTickInfo(poolId, tick)` (fee growth outside at words 2–3), `getFeeGrowthGlobals(poolId)`,
  `getSlot0(poolId)`.
- v4 PositionManager is **not** ERC-721 Enumerable → ownership is reconstructed from
  `Transfer` logs (`to = wallet` minus `from = wallet`) with the incremental cache in
  `UserDefaults`. Burned positions (liquidity 0, no fees) should be skipped, not shown.
- `currency == 0x0000…0000` is **native ETH** in v4: symbol "ETH", 18 decimals, price via the
  chain's wrapped-native address. Do not call `symbol()`/`decimals()` on address zero.
- Hooks can charge extra fees or alter accounting; Poolser shows pool-level fee growth only.
  Mention this if a user compares with the Uniswap UI for a hooked pool.

## USD valuation and prices

- Prices: CoinGecko token-price endpoint first, DefiLlama backfill (`PriceService`). Keys are
  lowercased addresses — keep lowercasing at every boundary.
- A missing price means "unknown", not zero: leave `usd`/`positionUSD` `nil` and let the UI show
  a dash. Never sum partial USD silently into a total without marking it partial.
- Pool stats/APR come from GeckoTerminal (`PoolStatsService`, 5-min TTL). APR shown is
  pool-level `24h fees × 365 / TVL`, not the position's own APR — label accordingly.
- An on-chain cross-check is cheap: the pool's `sqrtPriceX96` gives the ratio between the two
  tokens; if one side's USD price is known, the other can be derived. Useful for long-tail tokens
  the APIs don't price, but flag derived prices in the UI.

## Decimals and decoding pitfalls

- `decimals()` may revert or be absent (default 18 today); `symbol()` may be `bytes32`
  (handled by `readABIString` fallback). Cache both forever per (chain, address).
- `readUInt64(wordAt:)` reads only the low 8 bytes — fine for counts, tokenIds and fee tiers,
  wrong for liquidity, amounts or prices.
- int24 ticks are sign-extended from 3 bytes; negative ticks are common — test them.
- Fee tier units: v3 `fee` is in hundredths of a bip (3000 = 0.30%). v4 static fee same units;
  dynamic-fee flag `0x800000` means the fee lives in the hook — don't print it as a percentage.

## Test vectors to keep (Swift Testing)

- tick 0 ↔ `sqrtPriceX96 = 2^96`, price 1; tick round-trip for ±1, ±887272 (MIN/MAX_TICK).
- `computeAmounts` at `sp == sa`, `sp == sb`, mid-range; amounts continuous across boundaries.
- Fee growth where `global < outside` (wrap) yields a small positive delta, not ~2^256.
- `PositionInfo` decode for a known bytes32 with negative `tickLower` and positive `tickUpper`.
- In-range at `currentTick == tickLower` (true) and `== tickUpper` (false).
