# DonkeyHorn

<p align="center">
  <img src="Sources/DonkeyHorn/Resources/donkeyhorn-logo.png" alt="DonkeyHorn logo" width="220" />
</p>

**DonkeyHorn** — for Uniswap positions.

A macOS menu bar app for monitoring your [Uniswap v3](https://uniswap.org) and [Uniswap v4](https://uniswap.org) liquidity positions. See unclaimed fees in USD at a glance, check whether positions are in range, and open any position directly in the Uniswap app — all without leaving your desktop.

> **Disclaimer:** This is an independent hobby project with no affiliation, association, or connection to Uniswap Labs or the Uniswap Protocol. "Uniswap" is a trademark of Uniswap Labs.

---

## Features

- Live unclaimed fee totals in the menu bar (auto-refresh every 10 minutes + manual refresh)
- Supports both **Uniswap v3** and **Uniswap v4** positions on Ethereum mainnet
- Per-position breakdown: token pair, fee tier, in/out-of-range status, position value, unclaimed fees
- Tick range visualization with:
  - in/out-of-range styling
  - current tick needle and boundary markers
  - compact out-of-range distance labels
- Robust RPC handling:
  - retries with backoff + jitter
  - request pacing with a shared credit-based limiter
  - clearer RPC error surfacing in-app logs/UI
- Incremental v4 ownership discovery:
  - bootstrap scan is chunked and resumable
  - ownership cache avoids rescanning full history every refresh
- Reads data directly from Ethereum via your own RPC — no third-party indexer or API key required
- Click any position to open it on app.uniswap.org
- Launch at Login support (toggle in Settings)
- Native macOS app — no Electron, no web view

## Requirements

- macOS 14 (Sonoma) or later
- An Ethereum RPC URL (e.g. [Infura](https://infura.io), [Alchemy](https://alchemy.com), or your own node)
- A wallet address that holds Uniswap v3 or v4 positions

## Building

The project uses Swift Package Manager with no external dependencies.

```bash
git clone https://github.com/GoranStoyanov/DonkeyHorn.git
cd DonkeyHorn
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

On first launch, open **Settings** (gear icon in the popup, or `⌘,`) and enter:

| Field | Description |
|---|---|
| Wallet Address | Your Ethereum address (`0x…`) |
| RPC URL | Any Ethereum JSON-RPC endpoint |

Settings are saved to `UserDefaults` and persist across launches.

## How Position Discovery Works

### v3
- Uses `balanceOf(owner)` on the v3 `NonfungiblePositionManager`
- Enumerates token IDs via `tokenOfOwnerByIndex`
- Loads per-position details via `positions(tokenId)`

### v4
- Uses `balanceOf(owner)` on the v4 `PositionManager`
- Reconstructs ownership from `Transfer` logs (v4 PM is not ERC-721 Enumerable)
- Persists a local ownership cache in `UserDefaults`:
  - last scanned block
  - candidate token IDs
  - currently owned token IDs
- First-time bootstrap is bounded per refresh and resumes next refresh until caught up

## RPC Rate Limiting Notes

DonkeyHorn includes built-in pacing to reduce `HTTP 429` rate-limit errors:

- Credit-aware request limiter (safe margin for constrained plans)
- Reduced `eth_getLogs` concurrency/chunk pressure
- Retry logic for transient/null/malformed responses

If your provider still rate-limits frequently:

1. Increase the refresh interval and avoid rapid manual refresh spam.
2. Use a higher-throughput RPC plan.
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

## Privacy

DonkeyHorn communicates only with:

- The RPC URL you provide (to read on-chain data)
- [CoinGecko](https://coingecko.com) and [DefiLlama](https://defillama.com) public APIs (to fetch token prices in USD)

No analytics, no tracking, no data leaves your machine beyond those requests.

## License

MIT — see [LICENSE](LICENSE).
