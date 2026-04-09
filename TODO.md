# DonkeyCorn — TODO

## Quick Fixes / Polish

- [x] Add `.gitignore` (Xcode, SPM, macOS defaults: `.DS_Store`, `.build/`, `*.xcuserstate`, `xcuserdata/`, `DerivedData/`)
- [x] Update header text from "Uniswap v3 Positions" → "Uniswap Positions" (v4 is now supported)
- [x] Title bar shows only v3 fees — update to include v4 fees once v4 fee tracking is implemented
- [x] LICENSE: replace "Goran" placeholder with full legal name
- [x] README: replace `yourusername` in git clone URL with actual GitHub username

## Known Bugs

### v4 positions not showing (broken)
The v4 PositionManager (`0xbD216513...`) does **not** implement ERC-721 Enumerable,
so `tokenOfOwnerByIndex` doesn't exist on it — calls fail silently and return no positions.

**Fix attempted (round 2):**
- Fixed a serialization bug in `ethGetLogs`: topics were wrapped as `Optional<Any>` instead of
  plain `String`, causing JSON to potentially encode them wrong. Fixed with explicit `guard let`.
- Added proper error surfacing throughout `loadV4` — errors now propagate to the UI so we can
  see exactly which step fails (balanceOf / eth_getLogs / getPoolAndPositionInfo).
- Per-position `getPoolAndPositionInfo` errors now show as error cards in the position list.
- `load()` now combines and surfaces both v3 and v4 errors.

**If still broken after round 2, next steps:**
1. Run the app and check what error message appears in the UI — it will now show exactly where it fails
2. If "Transfer log query failed – block range too large": your RPC doesn't support large ranges.
   Switch to Alchemy/Infura paid tier, or implement batched getLogs (5K blocks at a time).
3. If "balance=N but 0 owned tokenIds": logs are found but tokenId parsing fails. Check if the
   v4 PM Transfer event has tokenId as topic[3] (indexed). Some ERC-721 implementations emit
   tokenId as data (not indexed) — in that case, parse from `data` field instead of `topics[3]`.
4. If position error cards appear: `getPoolAndPositionInfo` return layout may differ from expected.
   Verify the exact ABI on Etherscan for `0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9E`.

**Files changed:** `UniswapService.swift` (loadV4, load), `EthereumClient.swift` (ethGetLogs fix)

## Features Pending

### ~~v4 Unclaimed Fees~~ ✓ Implemented
Uses 4 concurrent StateView calls per position:
1. Call `StateView.getPositionInfo(poolId, positionManagerAddress, tickLower, tickUpper, bytes32(tokenId))`
   → returns `feeGrowthInside0LastX128`, `feeGrowthInside1LastX128`, `liquidity`
2. Call `StateView.getTickInfo(poolId, tickLower)` and `getTickInfo(poolId, tickUpper)`
   → each returns `feeGrowthOutside0X128`, `feeGrowthOutside1X128`
3. Call `StateView.getFeeGrowthGlobals(poolId)`
   → returns `feeGrowthGlobal0X128`, `feeGrowthGlobal1X128`
4. Compute `feeGrowthInside` from globals and tick feeGrowthOutside values (standard Uniswap formula)
5. `unclaimed = (feeGrowthInside - feeGrowthInsideLast) * liquidity >> 128`

### Multi-chain Support
- [ ] Add chain selector in Settings (Ethereum, Base, Arbitrum, Optimism, Polygon)
- [ ] Support v3 on non-mainnet chains (different NFPM/Factory addresses per chain)
- [ ] Support v4 on chains where it's deployed

### Other Features
- [ ] Sorting / filtering positions (by value, in-range only, v3/v4)
- [x] Click on position opens correct URL for v4 (`/positions/v4/1/[tokenId]`)
- [ ] Show pool fee APR or 24h volume (would require subgraph/API call)
- [ ] Notifications when a position goes out of range

## App Store Submission Prerequisites

- [ ] Create Xcode project targeting this SPM package
- [ ] Set `CFBundleIdentifier` in the Xcode target (e.g. `com.yourname.DonkeyCorn`)
- [ ] Set up Apple Developer account and code signing
- [ ] Configure provisioning profiles in Xcode
- [ ] Test `SMAppService` (Launch at Login) with a properly bundled `.app` — it requires a bundle ID to work
- [ ] Create app icons (all required sizes for macOS)
- [ ] Write App Store listing (description, screenshots, keywords)
- [ ] Test on a clean Mac (no dev tools) before submitting

## Known Bugs Fixed

- [x] Settings window didn't come to front in accessory-mode app — replaced `SettingsLink` with `openSettings` + `NSApp.activate`

## Features Completed

- [x] Launch at Login toggle in Settings (uses `SMAppService`, App Store safe)
- [x] Uniswap v4 position support (Ethereum mainnet) — positions fetched concurrently with v3
- [x] Position value in USD (total liquidity value)
- [x] Current token distribution label (e.g. "0.05 WBTC + 1,200 USDC")
- [x] Tick range bar — visual indicator of current price vs position range
- [x] Liquid glass design (`.glassEffect()` on macOS 26+, `.ultraThinMaterial` fallback)
- [x] v4 badge (pink capsule) vs v3 badge (gray capsule) on each position card
