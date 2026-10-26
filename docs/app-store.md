# App Store listing

The Mac App Store text for Poolser, kept here so each release can update it with the code.
Paste each block as plain text, with no trailing spaces.

Current version: **1.3** (previous: 1.2, released April 29, 2026)

## Name (30)

```
Poolser
```

## Subtitle (30)

```
Uniswap fees in your menu bar
```

## Promotional text (170)

```
New in 1.3: a redesigned menu with a daily fee chart and APR since open. You can now collect fees right from the menu bar with your browser wallet.
```

## Keywords (100)

```
liquidity,lp,defi,v3,v4,ethereum,base,arbitrum,optimism,crypto,yield,apr,pool,range,collect,web3
```

## Description (4000)

```
Poolser keeps your Uniswap v3 and v4 positions in the Mac menu bar. See your total value and unclaimed fees at a glance, spot the ranges that need attention, and collect fees without opening a dashboard.

Everything is read straight from the chain through your own Infura key. No account, no sign-in, no tracking.

AT A GLANCE
- Total value and unclaimed fees in the menu bar, refreshed every 10 minutes by default
- Unclaimed fees in USD across all your positions and chains
- A daily fee chart for the last 7, 14 or 30 days, recorded on your Mac while Poolser runs
- All-time fees, claimed fees and APR since you opened each position

EVERY POSITION ON ONE CARD
- A range gauge with the current price, and Min and Max shown as prices
- In range, near the edge or out of range, with how far the price has moved
- Current token amounts, pool volume, TVL and 24h yield
- Token logos and a badge for each chain
- Filter by chain, by Uniswap version or by positions that need attention, and sort by value, fees, yield or pair

COLLECT FEES
- Collect one position, or every position on a chain at once
- Poolser checks the transaction first, then hands it to the browser wallet you already use, such as MetaMask or Rabby
- Poolser never sees your keys and never signs anything

MULTI-CHAIN
Uniswap v3 and v4 on Ethereum, Base, Arbitrum, Optimism, Polygon, Blast and Unichain, plus Uniswap v3 on Avalanche, BNB Chain, Celo, zkSync, Monad and MegaETH. One Infura API key covers all of them.

OPTIONAL
- A notification when a position moves in or out of range
- Claimed fee history from on-chain Collect events
- Launch at login
- A log of every RPC request the app makes

PRIVATE BY DESIGN
Your wallet address and settings stay on your Mac, and your API key is kept in the macOS Keychain. Poolser talks only to Infura for chain data and to public price and pool APIs (CoinGecko, DefiLlama, GeckoTerminal). No analytics.

Requires macOS 14 or later, an Infura API key (the free plan works) and a wallet address with Uniswap v3 or v4 positions.

Poolser is an independent app and is not affiliated with Uniswap Labs.
```

## What's New in 1.3 (4000)

```
A new look, and much more to see.

- Redesigned menu: a summary card with unclaimed fees, total value and a daily fee chart (7D, 14D or 30D), and cleaner position cards with a price range gauge
- Collect fees from the menu bar with your browser wallet, one position at a time or every position on a chain at once
- All-time fees, claimed fees and APR since you opened each position
- The menu bar shows your total value next to unclaimed fees
- Token logos and chain badges on every position
- Filter positions by chain, version or those that need attention, and sort the list
- Right-click a position to open it on Uniswap or copy its position ID or pool
- Positions within 3% of a range bound are flagged before they go out of range
- Optional notifications when a position moves in or out of range
- Fewer RPC requests: contract reads are batched and prices are cached, and Poolser slows down by itself when Infura rate-limits
- Your Infura API key is now stored in the Keychain
- Runs on macOS 14 Sonoma and later
- Fixes for v4 positions, range checks at the upper bound, claimed fee scans and the menu window size
```

## Screenshots

2880×1800 JPEGs in `docs/screenshots/appstore/`, uploaded in this order. Regenerate them with
`POOLSER_SCREENSHOTS=docs/screenshots swift run` (debug build, demo wallet, no network keys).

| # | File | Headline | Subline |
|---|---|---|---|
| 1 | `1-menu-bar.jpg` | Uniswap fees, always in view | Every position on every chain, one click away in the menu bar. |
| 2 | `2-daily-fees.jpg` | See what you earn each day | Daily fees, all-time return and APR since you opened each position. |
| 3 | `3-ranges.jpg` | Know when a range needs you | Each card shows where the price sits, so drifting positions stand out. |
| 4 | `4-collect.jpg` | Collect fees in a click | Claim from the menu bar with the browser wallet you already use. |
| 5 | `5-fees-went-up.jpg` | Fees went up? You'll know | Total value and unclaimed fees sit in the menu bar and blink when fees grow. |
| 6 | `6-private.jpg` | Private by design | No account and no tracking. Poolser reads straight from the chain. |

## Before submitting

- Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Xcode project.
- Minimum macOS in the Xcode project must match the description (14.0).
- App Privacy answers stay "Data Not Collected"; PRIVACY.md describes the collect flow.
- Review notes: the reviewer needs an Infura API key and a wallet with positions. Give a
  public wallet address with open positions and a test Infura key in App Review Information.
