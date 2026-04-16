# Poolser — TODO

## Features Pending

- [ ] Sorting / filtering positions (by value, in-range only, v3/v4, chain)
- [ ] Notifications when a position goes out of range
- [ ] Show pool fee APR or 24h volume (requires subgraph/API)

## App Store Submission Prerequisites

- [x] Create Xcode project targeting this SPM package
- [x] Set `CFBundleIdentifier` in the Xcode target (`dev.goodmorning.Poolser`)
- [x] Set up Apple Developer account and code signing
- [x] Configure provisioning profiles in Xcode
- [x] Create app icons (all required sizes for macOS)
- [x] Test `SMAppService` (Launch at Login) with a properly bundled `.app` — it requires a bundle ID to work
- [ ] Write App Store listing (description, screenshots, keywords)
- [x] Test on a clean Mac (no dev tools) before submitting

## Features Completed

- [x] Uniswap v3 position support (Ethereum mainnet)
- [x] Uniswap v4 position support (Ethereum mainnet)
- [x] Multi-chain support (Ethereum, Base, Arbitrum, Optimism, Polygon) — per-chain RPC URLs in Settings
- [x] v4 unclaimed fees via StateView feeGrowth math (4 concurrent RPC calls per position)
- [x] Full range position handling — blue FULL RANGE badge, tick bar hidden
- [x] Position value in USD (total liquidity value)
- [x] Current token distribution label (e.g. "0.05 WBTC + 1,200 USDC")
- [x] Tick range bar — visual indicator of current price vs position range
- [x] Liquid glass design (`.glassEffect()` on macOS 26+, `.ultraThinMaterial` fallback)
- [x] Settings as in-place swap — main window never closes
- [x] Wallet address shown in header
- [x] Loading state with explanatory text (RPC rate limiting context)
- [x] Logs view — RPC and service-level event tracking, copy-all, clear, color-coded legend
- [x] Rate limiting + retry logic in EthereumClient (credit-based limiter, exponential backoff)
- [x] Launch at Login toggle (uses `SMAppService`, App Store safe)
- [x] Click on position opens Uniswap app URL (v3 and v4)
