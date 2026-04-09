# DonkeyCorn

A macOS menu bar app for monitoring your [Uniswap v3](https://uniswap.org) and [Uniswap v4](https://uniswap.org) liquidity positions. See unclaimed fees in USD at a glance, check whether positions are in range, and open any position directly in the Uniswap app — all without leaving your desktop.

> **Disclaimer:** This is an independent hobby project with no affiliation, association, or connection to Uniswap Labs or the Uniswap Protocol. "Uniswap" is a trademark of Uniswap Labs.

---

## Features

- Live unclaimed fee totals in the menu bar (refreshes every 10 minutes)
- Supports both **Uniswap v3** and **Uniswap v4** positions on Ethereum mainnet
- Per-position breakdown: token pair, fee tier, in/out of range status, fee amounts in USD
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
git clone https://github.com/GoranStoyanov/DonkeyCorn.git
cd DonkeyCorn
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

## Privacy

DonkeyCorn communicates only with:

- The RPC URL you provide (to read on-chain data)
- [CoinGecko](https://coingecko.com) and [DefiLlama](https://defillama.com) public APIs (to fetch token prices in USD)

No analytics, no tracking, no data leaves your machine beyond those requests.

## License

MIT — see [LICENSE](LICENSE).
