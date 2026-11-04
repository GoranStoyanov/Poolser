# Privacy Policy

**Poolser** monitors Uniswap v3 and v4 liquidity positions on Mac, iPhone and iPad. Fee collection is available on Mac only.

_Last updated: November 3, 2026_

## Data Collection

Poolser's developer does not receive your wallet addresses, API key or portfolio data. There are no user accounts, analytics or tracking. To display positions, the app sends public wallet addresses and chain queries to Infura and requests price, icon and pool information from the services below.

## What Leaves Your Device

Poolser communicates only with the following external services to function:

- **Infura** (`infura.io`) — RPC requests to read on-chain data using your API key. Your wallet address is included in these requests as part of normal blockchain queries.
- **CoinGecko** (`api.coingecko.com`, `assets.coingecko.com`) — token USD prices and chain icon images.
- **DefiLlama** (`coins.llama.fi`, `token-icons.llamao.fi`) — token USD prices as a fallback, and token logo images (looked up by chain and token contract address).
- **GeckoTerminal** (`api.geckoterminal.com`) — pool volume, TVL, and yield data.

The iPhone and iPad app only reads portfolio data. No data is submitted to or stored by Poolser's developers.

## Collecting Fees

When you click **Collect** on a position in the Mac app, Poolser:

1. Runs the collect as a dry run (`eth_call`) through Infura, to check it would succeed.
2. Starts a temporary web server on `127.0.0.1`, reachable only from your Mac, and opens its page in your default browser.
3. The page passes the transaction to your browser wallet (for example MetaMask or Rabby), which asks you to confirm and signs it. The page reports the transaction hash back to Poolser so it can refresh.

**Collect all** works the same way for every position on one chain, with one transaction per Uniswap version. Poolser also estimates the network fee (`eth_estimateGas`, `eth_gasPrice`) through Infura, and may look up the chain's native token price from the price sources above. When you leave positions out on the page, it sends the chosen position IDs to Poolser on `127.0.0.1`, which builds and checks the transactions again. If your wallet supports batched calls (EIP-5792), both transactions can go to it as one batch.

Poolser never sees or stores your private keys and does not sign anything. The temporary server stops once the transactions are sent or after 15 minutes.

## Local Storage

Your saved wallet addresses and names, active address, app settings, daily fee history and cached chain data are stored locally in `UserDefaults` on the device. Your Infura API key is stored in that device's Keychain. Widgets read a summary of your positions and saved wallet names from a container shared with the app on the same device. Token logos and chain icons are cached locally. This data leaves your device only as needed for the RPC and pricing requests described above.

## Contact

For questions, open an issue at [github.com/GoranStoyanov/Poolser](https://github.com/GoranStoyanov/Poolser).
