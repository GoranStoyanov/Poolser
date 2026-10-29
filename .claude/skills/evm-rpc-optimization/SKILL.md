---
name: evm-rpc-optimization
description: Reduce, batch and harden EVM JSON-RPC reads in Poolser (EthereumClient, UniswapService, FeeHistoryService). Use when adding or changing any eth_call / eth_getLogs / eth_blockNumber usage, when the user mentions RPC calls, Infura credits, HTTP 429, rate limits, slow refresh, Multicall, batching, caching chain data, log scanning, reorgs, or "too many requests", and when reviewing code that reads from the blockchain.
---

# EVM RPC optimization (Poolser)

Poolser reads chain state directly from Infura over hand-rolled JSON-RPC — no web3 library,
no indexer. Every request costs Infura credits and wall-clock time, and the free tier is
throttled. The goal of any change touching chain reads: **fewer round trips, fewer credits,
coherent snapshots, and no regressions in error surfacing.**

## Where things live

| Concern | File |
|---|---|
| JSON-RPC transport, retries, backoff, credit limiter (`RPCCreditLimiter` actor) | `Sources/PoolserKit/EthereumClient.swift` |
| Calldata builders, selectors, word decoders (`readWord`, `readInt24`, `readAddress`…) | `Sources/PoolserKit/ABI.swift` |
| Runtime selector hashing (used for v4 selectors) | `Sources/PoolserKit/Keccak256.swift` |
| v3/v4 position loading, v4 Transfer-log ownership scan + cache | `Sources/PoolserKit/UniswapService.swift` |
| `Collect` event scan (claimed fee history) | `Sources/PoolserKit/FeeHistoryService.swift` |
| Per-chain addresses, deploy blocks, Infura hosts | `Sources/PoolserKit/ChainConfig.swift` |
| User-tunable budget (`rpcCreditsPerSecondBudget`, v4 log chunk size/concurrency) | `Sources/PoolserKit/AppSettings.swift` |

Credit costs used by the limiter (Infura): `eth_call` 80, `eth_getLogs` 255,
`eth_blockNumber` 80, `eth_chainId` 80. Default budget 400 credits/s (Infura free ≈ 500).

## Current hot spots (verify before relying on this list — code may have moved on)

1. **v3 load is fully sequential per position** (`loadV3`): for each index it does
   `tokenOfOwnerByIndex` → `positions` → `symbol`+`decimals` per new token → `collect` (static)
   → later `getPool` → `slot0`. That is ~5–7 serial `eth_call`s per position, ×80 credits each.
2. **No Multicall.** Every read is its own HTTP request.
3. **Reads use `"latest"`**, so a position's `getPositionInfo`, `getTickInfo(lower/upper)` and
   `getFeeGrowthGlobals` can come from different blocks (v4 `computeV4Fees` fires them with
   `async let`). On fast chains this yields occasional nonsense fee deltas.
4. **Immutable data is re-fetched every refresh**: token `symbol`/`decimals`, v3 `getPool`
   results, and a v3 tokenId's `token0/token1/fee/tickLower/tickUpper` never change.
5. The four request functions in `EthereumClient` duplicate the same envelope/retry code.

## Techniques, in order of payoff

### 1. Multicall3 `aggregate3` — collapse N calls into 1

Multicall3 is deployed at `0xcA11bde05977b3631167028862bE2a173976CA11` on Ethereum, Base,
Arbitrum, Optimism, Polygon and most other EVM chains. **Confirm with `eth_getCode` once per
chain** before enabling it for a chain (cache the result), and keep the per-call path as fallback.

```
aggregate3((address target, bool allowFailure, bytes callData)[] calls)
    returns ((bool success, bytes returnData)[] returnData)
```

- Compute the selector with the project's `Keccak256` from the canonical signature
  `aggregate3((address,bool,bytes)[])`, the same way the v4 selectors in `ABI.swift` are built —
  do not paste a selector from memory without checking it.
- Encoding is dynamic ABI: head = offset to array; array = length + per-element offsets;
  each tuple = `address`, `bool`, offset to `bytes`, then `bytes` length + right-padded data.
  Decoding mirrors it. Add the encoder/decoder to `ABI.swift` next to the existing helpers and
  write a round-trip unit test with a hand-checked vector.
- Always `allowFailure: true` for reads where one bad token (non-standard `symbol()`) must not
  sink the whole batch; check `success` per item and fall back to the existing defaults.
- One `aggregate3` = one `eth_call` = 80 credits regardless of how many inner calls.
  Keep batches to ~50–100 inner calls: providers cap `eth_call` gas and response size.
  On a gas/size error, split the batch in half and retry (recursive bisection).
- Pipeline shape for v3: `balanceOf` → one multicall of all `tokenOfOwnerByIndex(i)` →
  one multicall of all `positions(id)` + `collect` → one multicall of unique tokens'
  `symbol`/`decimals` (only cache misses) + unique `getPool` → one multicall of unique `slot0`.
  That is ~5 requests for any number of positions instead of ~6N.

### 2. Pin a block for coherent snapshots

Fetch `eth_blockNumber` once per chain per refresh and pass that block (hex) as the block tag
to every `eth_call` in the refresh, instead of `"latest"`. Fee math subtracts accumulators read
from several calls; they must come from the same state. Inside a single `aggregate3` the calls
are already same-block, which is another reason to batch. Infura full nodes serve recent blocks
(the last ~128) without archive access, so pinning to head is safe.

### 3. Cache what cannot change

| Data | Lifetime | Where to cache |
|---|---|---|
| ERC-20 `symbol`, `decimals` | forever per (chain, address) | in-memory + `UserDefaults`/file, like `V4OwnershipCache` |
| v3 `getPool(token0, token1, fee)` | forever | same; or compute locally via CREATE2 (factory, `keccak(abi.encode(token0,token1,fee))`, POOL_INIT_CODE_HASH) once the init-code hash is verified for that chain |
| v4 `poolId` | forever | compute locally: `keccak256(abi.encode(PoolKey))` — no RPC needed |
| v3 position static fields (`token0`, `token1`, `fee`, ticks) | forever per tokenId | per-wallet cache; only `liquidity`, fee growth and `tokensOwed` change |
| Multicall3 presence per chain | forever | per chain |
| Prices (CoinGecko/DefiLlama), pool stats (GeckoTerminal) | minutes | already TTL-cached in `PoolStatsService`; keep TTLs |

Never cache `slot0`, liquidity, fee-growth values or `tokensOwed` across refreshes.

### 4. JSON-RPC batch arrays (when Multicall doesn't fit)

For non-`eth_call` methods (e.g. several `eth_getLogs` ranges, `eth_getCode` probes) a
JSON-RPC batch (`[ {id:1,...}, {id:2,...} ]`) saves HTTP round trips but **not credits** —
Infura bills each item. Responses may come back in any order: match by `id`. Each item can
fail independently (`error` per element); retry only the failed ids. Debit the limiter for the
sum of item costs before sending.

### 5. `eth_getLogs` discipline

- Always filter by `address` and as many topics as possible (wallet-padded topic for Transfer
  `to`/`from`; tokenId topics in `FeeHistoryService` are batched 50 per OR-list — keep that).
- Infura caps a query at 10,000 results (and a time budget). On a "more than 10000 results" /
  "query timeout" / "block range too large" error, **bisect the range** and retry the halves
  rather than failing the scan. Parse the suggested range from the error message when present.
- Incremental scans: persist `lastScannedBlock`, re-scan a short reorg lookback window
  (`v4ReorgLookbackBlocks`) and de-duplicate by `(transactionHash, logIndex)`.
- Bound concurrency (`v4LogMaxConcurrentRequests`); the limiter already paces credits, extra
  parallelism only increases 429s.

### 6. Transport hygiene in `EthereumClient`

- Fold `ethBlockNumber`, `ethChainId`, `ethGetLogs`, `ethGetLogsOR`, `ethCall` onto one private
  `send(method:params:cost:maxRetries:timeout:context:)` that returns the decoded `result`.
  Keep current retry semantics (`shouldRetry`, 429 cooldown, jitter) and the `LogStore` lines.
- Map JSON-RPC `error.code` too, not only `message` text: `-32005` (limit exceeded),
  `429`/`-32029` (rate limit) are retryable; `3` / `-32000` "execution reverted" is **not**.
- `RPCCreditLimiter.acquire` swallows cancellation (`try? await Task.sleep`). Respect
  `Task.isCancelled` so stale refresh generations stop consuming budget.
- Coalesce identical in-flight requests (same method+params+block) behind one `Task` when
  several positions need the same pool/token data concurrently.

## Review checklist for any change that reads the chain

- [ ] How many RPC requests does a refresh make for a wallet with N positions on one chain?
      Write the number in the PR description (before → after).
- [ ] Are related reads (fee accumulators, slot0, ticks) taken at the same block?
- [ ] Is anything immutable fetched more than once per app lifetime?
- [ ] Does one failing token/pool/position degrade only itself (per-item `allowFailure`)?
- [ ] Are errors still visible in Logs (`LogStore`) with a short, specific message?
- [ ] Is the limiter debited with the real credit cost of what is sent?
- [ ] Reverts are not retried; transient errors are.
- [ ] For log scans: bounded range, bisect-on-limit, reorg lookback, dedup.

## Verifying

- `swift build` must pass (see the `run-poolser` skill to launch and watch Logs).
- Compare the Logs view request count for one refresh before and after the change on the same
  wallet; numbers in the UI (fees, amounts, in-range) must be unchanged except for intended fixes.
- Add unit tests for any new ABI encoder/decoder (see `swift-testing-pro`).
