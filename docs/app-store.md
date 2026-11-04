# App Store listing for Poolser 1.4

English copy for the Mac update and first iPhone/iPad release. Add iOS to the existing Mac app record for a single Poolser listing and universal purchase. The app name and subtitle are shared across platforms in that record; platform version descriptions, promotional text and keywords differ. Both app targets use the same bundle ID; the widgets keep platform-specific IDs and App Groups. Do not create a separate iOS app record.

## Shared name (30)

```
Poolser
```

## Shared subtitle (30)

```
Uniswap positions & fees
```

## Mac promotional text (170)

```
Now with multiple wallets, an All Wallets overview, a portfolio widget and a refreshed menu. Your positions stay visible through connection outages.
```

## Mac keywords (100)

```
liquidity,lp,defi,v3,v4,ethereum,base,arbitrum,optimism,crypto,yield,apr,pool,range,collect,web3
```

## Mac description (4000)

```
Poolser keeps your Uniswap v3 and v4 positions in the Mac menu bar. See value and unclaimed fees at a glance, spot ranges that need attention, and collect fees with your browser wallet.

ADD YOUR WALLETS
Save multiple wallet addresses and give each a name. Swipe between wallets or use All Wallets to see combined value, fees and positions. Choose whether the menu bar shows all wallets or one. Hide positions you do not want included in totals.

FOLLOW EVERY POSITION
See a daily fee chart, your total value and unclaimed fees. Position cards show the current price in its range, daily fees, claimed fees and realized APR when known. Open Details for holdings, opening date, position ID and pool statistics. Filter and sort positions to focus on what matters.

STAY IN THE LOOP
The small and medium widgets show fees and range attention for all wallets or a wallet you choose. Poolser keeps the last successful portfolio visible during a connection outage and refreshes when the connection returns. Optional range change notifications are off by default.

COLLECT ON MAC
Collect from one position or select positions on a chain. Poolser checks the transaction, then opens a local page in your browser so your own wallet extension can review and sign it. Poolser does not hold your private keys or sign transactions.

PRIVATE BY DESIGN
No account, analytics or tracking. Your Infura API key stays in the Keychain. Poolser reads chain data through your Infura project and uses public price and pool data services.

Requires macOS 14 or later, an Infura API key and a wallet address with Uniswap v3 or v4 positions. Some networks require access enabled in your Infura project.

Poolser is independent and is not affiliated with Uniswap Labs.
```

## What's New in Mac 1.4 (4000)

```
- Add and name multiple wallets, then swipe between them or see combined totals and positions in All Wallets.
- Choose which wallet the menu bar shows and set each new portfolio widget to one wallet or all wallets.
- A refreshed menu brings price ranges, daily fees and realized returns onto the position cards, with more detail one click away.
- The last successful portfolio stays visible when your connection drops, including after an offline restart, and refreshes on reconnect.
- The collect page is easier to read on narrow browser windows and keeps transaction details visible before wallet approval.
```

## iPhone and iPad promotional text (170)

```
See your Uniswap positions, daily fees and range attention across wallets, with small and medium widgets for your Home Screen.
```

## iPhone and iPad keywords (100)

```
liquidity,lp,defi,v3,v4,ethereum,base,arbitrum,crypto,fees,yield,apr,pool,range,widget
```

## iPhone and iPad description (4000)

```
Poolser lets you monitor Uniswap v3 and v4 liquidity positions on iPhone and iPad. See portfolio value, unclaimed fees and daily fees, and find positions whose prices are near or outside their ranges.

YOUR PORTFOLIO
Save and name multiple public wallet addresses. Swipe between wallets or see combined totals in All Wallets. Each position card shows its price range, fees and realized return when known. Tap a card for holdings, position ID, opening date and pool statistics. Pull down to refresh.

WIDGETS
Small and medium Home Screen widgets show fees, range attention and the latest update. Set a widget to one wallet or all wallets. They display the app's last saved snapshot, so open Poolser to refresh live data.

PRIVATE BY DESIGN
No account, analytics or tracking. Your Infura API key stays in this device's Keychain. Poolser reads chain data through your Infura project and uses public price and pool data services. Wallet addresses are public blockchain data.

The iPhone and iPad app monitors positions; fee collection with a browser wallet is available in Poolser for Mac.

Requires iOS or iPadOS 17 or later, an Infura API key and a wallet address with Uniswap v3 or v4 positions. Some networks require access enabled in your Infura project.

Poolser is independent and is not affiliated with Uniswap Labs.
```

The iPhone/iPad listing is for a first release. Do not invent What's New history for it.

## Screenshots

Mac: 2880×1800 JPEGs in `docs/screenshots/appstore/`, generated with the native demo renderer. Captions are in `Sources/Poolser/Graphite/StoreScreenshots.swift`. Check the actual exported images before upload.

| # | File | Headline | Subline |
|---|---|---|
| 1 | `1-menu-bar.jpg` | Uniswap fees, always in view | Every position on every chain, one click away in the menu bar. |
| 2 | `2-daily-fees.jpg` | See what you earn each day | Daily fees, all-time return and APR since you opened each position. |
| 3 | `3-ranges.jpg` | Know when a range needs you | Each card shows where the price sits, so drifting positions stand out. |
| 4 | `4-collect.jpg` | Collect fees in a click | Claim from the menu bar with the browser wallet you already use. |
| 5 | `5-fees-went-up.jpg` | Fees went up? You'll know | Total value and unclaimed fees sit in the menu bar and blink when fees grow. |
| 6 | `6-private.jpg` | Private by design | No account and no tracking. Poolser reads straight from the chain. |
| 7 | `7-all-wallets.jpg` | Every wallet, one view | See combined value and fees, then open any wallet's positions. |

iOS: upload the three native iPhone 18 Pro captures (1206×2622) in `docs/screenshots/ios/iphone/` to **iPhone with Dynamic Island (medium display)**, and the three iPad Air 13-inch (M4) captures (2048×2732) in `docs/screenshots/ios/ipad/` to **iPad 13" display**. These are the required device-size sections in App Store Connect. The earlier iPhone 18 Pro Max captures (1320×2868) are retained in `docs/screenshots/ios/iphone-large/` and belong only in the optional **iPhone with Dynamic Island (large display)** section; uploading them to the medium section produces a dimensions error. All captures are opaque PNGs, ordered `1-all-wallets.png`, `2-position-cards.png`, `3-range-attention-dark.png`. They show the actual SwiftUI app with fictional wallet data; the Debug screenshot mode is excluded from Release builds. The small and medium Home Screen widgets were installed and inspected on the iPhone simulator, but the local simulator build showed its unavailable state instead of the demo snapshot. Capture widget screenshots only after a signed build loads a real shared snapshot. Do not submit the placeholder or unavailable widget captures as feature screenshots.

To recreate the required iPhone captures, use the iPhone 18 Pro simulator. Launch the Debug iOS app with `POOLSER_SCREENSHOT_DEMO=1` (or `SIMCTL_CHILD_POOLSER_SCREENSHOT_DEMO=1 xcrun simctl launch booted dev.goodmorning.Poolser`). Use `POOLSER_SCREENSHOT_PAGE=0`, `1` or `2` for All Wallets, Mine or Team. Capture with `xcrun simctl io booted screenshot`, then remove the alpha channel before App Store upload. Capture the iPad set on a 13-inch iPad simulator. Do not substitute Mac renderer images for iOS captures.

## Store setup and review

- Retain the existing Mac category, price, availability, age rating, copyright, content rights and support/marketing/privacy URLs pending confirmation in App Store Connect. Add the iOS platform to the existing Poolser record after checking the bundle ID, then confirm iOS-specific listing fields there.
- Check App Privacy answers for both platforms against `PRIVACY.md`, particularly transmission of public wallet addresses to Infura and local widget snapshots. Confirm required-reason API declarations and export compliance for each archive. The apps declare non-exempt encryption as `NO`; confirm the answer in App Store Connect.
- Mac review: provide an approved test Infura key and a public address with representative positions in the private App Review field. In Settings save the key and address, then open the menu. Show All Wallets by adding a second address. Widgets read the app's latest snapshot. Collection opens a browser wallet handoff; a configured browser wallet is needed only to test signing. No real transaction is required to inspect monitoring.
- iOS review: provide the same approved read-only setup in the private field. Launch, add an address and Infura key, save, then swipe between wallets and pull to refresh. Add a widget after the app has loaded a snapshot. Collection is unavailable on iOS. Never place credentials in this file or public screenshots.
