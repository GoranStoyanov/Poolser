# Privacy Policy

**Poolser** is a macOS menu bar app for monitoring Uniswap v3 and v4 liquidity positions.

_Last updated: April 21, 2026_

## Data Collection

Poolser does not collect, store, or transmit any personal data. No analytics, no tracking, no user accounts.

## What Leaves Your Device

Poolser communicates only with the following external services to function:

- **Infura** (`infura.io`) — RPC requests to read on-chain data using your API key. Your wallet address is included in these requests as part of normal blockchain queries.
- **CoinGecko** (`api.coingecko.com`, `assets.coingecko.com`) — token USD prices and chain icon images.
- **DefiLlama** (`coins.llama.fi`) — token USD prices as a fallback.
- **GeckoTerminal** (`api.geckoterminal.com`) — pool volume, TVL, and yield data.

All requests are read-only. No data is submitted to or stored by Poolser's developers.

## Local Storage

Your wallet address, Infura API key, and app settings are stored locally in macOS `UserDefaults`. This data never leaves your device except as part of the RPC and pricing requests described above.

## Contact

For questions, open an issue at [github.com/GoranStoyanov/Poolser](https://github.com/GoranStoyanov/Poolser).
