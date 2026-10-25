# Privacy Policy

**Poolser** is a macOS menu bar app for monitoring Uniswap v3 and v4 liquidity positions.

_Last updated: October 25, 2026_

## Data Collection

Poolser does not collect, store, or transmit any personal data. No analytics, no tracking, no user accounts.

## What Leaves Your Device

Poolser communicates only with the following external services to function:

- **Infura** (`infura.io`) — RPC requests to read on-chain data using your API key. Your wallet address is included in these requests as part of normal blockchain queries.
- **CoinGecko** (`api.coingecko.com`, `assets.coingecko.com`) — token USD prices and chain icon images.
- **DefiLlama** (`coins.llama.fi`) — token USD prices as a fallback.
- **GeckoTerminal** (`api.geckoterminal.com`) — pool volume, TVL, and yield data.

All requests are read-only. No data is submitted to or stored by Poolser's developers.

## Collecting Fees

When you click **Collect** on a position, Poolser:

1. Runs the collect as a dry run (`eth_call`) through Infura, to check it would succeed.
2. Starts a temporary web server on `127.0.0.1`, reachable only from your Mac, and opens its page in your default browser.
3. The page passes the transaction to your browser wallet (for example MetaMask or Rabby), which asks you to confirm and signs it. The page reports the transaction hash back to Poolser so it can refresh.

**Collect all** works the same way for every position on one chain, with one transaction per Uniswap version. Poolser also estimates the network fee (`eth_estimateGas`, `eth_gasPrice`) through Infura, and may look up the chain's native token price from the price sources above. When you leave positions out on the page, it sends the chosen position IDs to Poolser on `127.0.0.1`, which builds and checks the transactions again. If your wallet supports batched calls (EIP-5792), both transactions can go to it as one batch.

Poolser never sees or stores your private keys and does not sign anything. The temporary server stops once the transactions are sent or after 15 minutes.

## Local Storage

Your wallet address, Infura API key, and app settings are stored locally in macOS `UserDefaults`. This data never leaves your device except as part of the RPC and pricing requests described above.

## Contact

For questions, open an issue at [github.com/GoranStoyanov/Poolser](https://github.com/GoranStoyanov/Poolser).
