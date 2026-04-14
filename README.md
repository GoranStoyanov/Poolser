# 👀 Poolser

**👀 Poolser** — for Uniswap positions.

A macOS menu bar app for monitoring your [Uniswap v3](https://uniswap.org) and [Uniswap v4](https://uniswap.org) liquidity positions. See unclaimed fees in USD at a glance, check whether positions are in range, and open positions directly in the Uniswap app.

> **Disclaimer:** This is an independent hobby project with no affiliation, association, or connection to Uniswap Labs or the Uniswap Protocol. "Uniswap" is a trademark of Uniswap Labs.

---

## Features

- Live unclaimed fee totals in the menu bar (auto-refresh every 10 minutes + manual refresh)
- Multi-chain Uniswap v3 support on Infura-backed EVM networks:
  - Ethereum
  - Base
  - Arbitrum
  - Optimism
  - Polygon
- Uniswap v4 position loading + fee calculation on Ethereum mainnet
- Per-position breakdown: token pair, fee tier, in/out-of-range status, position value, unclaimed fees
- Tick range visualization with:
  - in/out-of-range styling
  - current tick needle and boundary markers
  - compact out-of-range distance labels
- Robust RPC handling:
  - retries with backoff + jitter
  - request pacing with a shared credit-based limiter
  - clearer RPC error surfacing in-app logs/UI
  - stale refresh protection (older in-flight loads cannot override newer refreshes)
- Incremental v4 ownership discovery:
  - bootstrap scan is chunked and resumable
  - ownership cache avoids rescanning full history every refresh
- Chain icons in UI (downloaded once from CoinGecko and cached locally)
- Reads data directly from chain RPC (Infura endpoints derived from your API key), with no third-party indexer
- Click any position to open it on app.uniswap.org
- Launch at Login support (toggle in Settings)
- Native macOS app — no Electron, no web view

## Requirements

- macOS 14 (Sonoma) or later
- An [Infura](https://infura.io) API key
- A wallet address that holds Uniswap v3 or v4 positions

## Building

The project uses Swift Package Manager with no external dependencies.

```bash
git clone https://github.com/GoranStoyanov/Poolser.git
cd Poolser
swift build -c release
```

To run directly:

```bash
swift run
```

To open in Xcode:

```bash
open Package.swift
```

## Configuration

Open **Settings** (gear icon in the popup, or `⌘,`) and configure:

| Field | Description |
|---|---|
| Wallet Address | Your Ethereum address (`0x…`) |
| Infura API Key | The API key only (no full URL needed) |
| Enabled Networks | Toggle supported Infura networks on/off |
| Refresh Interval | Auto-refresh period |
| RPC Credit Budget | Local pacing budget for RPC calls |
| v4 Log Settings | Chunk size/concurrency/bootstrap controls for v4 log scans |

Important behavior:
- Setting edits are draft-only until you press **Save & Refresh**
- Closing settings with `X`/`Esc` discards unsaved changes
- Saved settings are persisted in `UserDefaults`

## How Position Discovery Works

### v3
- Uses `balanceOf(owner)` on the v3 `NonfungiblePositionManager`
- Enumerates token IDs via `tokenOfOwnerByIndex`
- Loads per-position details via `positions(tokenId)`

### v4
- Currently active on Ethereum mainnet in this codebase (other chains are configured but gated by deployment-block support)
- Uses `balanceOf(owner)` on the v4 `PositionManager`
- Reconstructs ownership from `Transfer` logs (v4 PM is not ERC-721 Enumerable)
- Persists a local ownership cache in `UserDefaults`:
  - last scanned block
  - candidate token IDs
  - currently owned token IDs
- First-time bootstrap is bounded per refresh and resumes next refresh until caught up

## RPC Rate Limiting Notes

Poolser includes built-in pacing to reduce `HTTP 429` rate-limit errors:

- Credit-aware request limiter (safe margin for constrained plans)
- Reduced `eth_getLogs` concurrency/chunk pressure
- Retry logic for transient/null/malformed responses

If your provider still rate-limits frequently:

1. Increase the refresh interval and avoid rapid manual refresh spam.
2. Use a higher-throughput Infura plan.
3. Prefer reliable archival/log-capable endpoints for heavy `eth_getLogs` workloads.

## Troubleshooting

- `RPC: HTTP 429`
  - Your RPC provider is throttling requests. See the rate-limiting section above.

- `v4: bootstrap scan in progress (next from 0x...)`
  - Expected on first sync for wallets with long history. The app resumes from that block next refresh.

- `v4: no Transfer events found for this wallet (balance=N)`
  - Usually indicates incomplete log coverage from the RPC provider, or bootstrap not completed yet.

- Intermittent `no result` / bad JSON in logs
  - Usually provider instability. The app retries automatically, but a more reliable endpoint helps.

- A network you enabled disappears from selection after refresh
  - Your Infura project likely has no access to that network; Poolser auto-disables networks that return access-denied responses.

## Privacy

Poolser communicates only with:

- Infura RPC endpoints derived from your API key (on-chain reads)
- [CoinGecko](https://coingecko.com) and [DefiLlama](https://defillama.com) public APIs (token USD pricing)
- CoinGecko asset-platform metadata/icons (for chain icon rendering + local cache)

No analytics, no tracking, no data leaves your machine beyond those requests.

## License

MIT — see [LICENSE](LICENSE).
