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
- Uniswap v4 position loading + fee calculation on:
  - Ethereum
  - Base
  - Arbitrum
  - Optimism
  - Polygon
  - Blast
  - Unichain
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
  - bootstrap follow-ups run per chain (accelerated while in progress)
  - in-app bootstrap status shows live countdown to next auto-refresh
  - ownership cache avoids rescanning full history every refresh
- Chain icons in UI (downloaded once from CoinGecko and cached locally)
- Reads data directly from chain RPC (Infura endpoints derived from your API key), with no third-party indexer
- Click any position to open it on app.uniswap.org
- Launch at Login support (toggle in Settings)
- Native macOS app — no Electron, no web view

## Product Screenshots

Main menu bar popup:

![Poolser main popup](docs/screenshots/positions.png)

Menu bar overview:

![Poolser menu bar overview](docs/screenshots/menubar-overview.png)

Settings:

![Poolser settings](docs/screenshots/settings.png)

Logs:

![Poolser logs](docs/screenshots/logs.png)

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

## Pre-Commit Secret Scan (gitleaks)

This repo includes a pre-commit hook that scans staged changes for secrets.

1. Install gitleaks:

```bash
brew install gitleaks
```

2. Enable repo-managed hooks once:

```bash
git config core.hooksPath .githooks
chmod +x .githooks/pre-commit
```

After setup, each commit runs gitleaks on staged changes and blocks the commit if a secret is detected.

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
- Some Infura networks are gated per project; enable the network in your Infura dashboard first if needed

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
- next bootstrap cursor block (`nextBootstrapFromBlock`) for resume
- First-time bootstrap progresses in chunks and resumes from cache until caught up
- While bootstrap is active, Poolser schedules accelerated per-chain follow-up refreshes (without changing the normal global refresh interval)

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

- `v4: bootstrap scan in progress (auto-refresh in ~Xs from 0x...)`
  - Expected on first sync for wallets with long history. `0x...` is the next resume block and `~Xs` is a live countdown.

- `v4: bootstrap refresh in progress (from 0x...)`
  - Countdown reached zero and the accelerated follow-up refresh is currently running for that chain.

- `v4: no Transfer events found for this wallet (balance=N)`
  - Usually indicates incomplete log coverage from the RPC provider, or bootstrap not completed yet.

- Intermittent `no result` / bad JSON in logs
  - Usually provider instability. The app retries automatically, but a more reliable endpoint helps.

- A network you enabled disappears from selection after refresh
  - Your Infura project likely has no access to that network yet. Enable it in the Infura dashboard for your API key, then re-enable it in Settings.
  - Poolser auto-disables networks that return Infura access-denied responses.

## Privacy

Poolser communicates only with:

- Infura RPC endpoints derived from your API key (on-chain reads)
- [CoinGecko](https://coingecko.com) and [DefiLlama](https://defillama.com) public APIs (token USD pricing)
- CoinGecko asset-platform metadata/icons (for chain icon rendering + local cache)

No analytics, no tracking, no data leaves your machine beyond those requests.

## License

MIT — see [LICENSE](LICENSE).
