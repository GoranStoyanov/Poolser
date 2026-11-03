# Poolser brand reference

Status: redesign branch, 3 November 2026. Update this document whenever a visual or interaction decision changes. It describes the product implementation, not just concept images.

## Character

Poolser is a precise financial instrument with a curious, quietly playful personality. Liquidity is its visual material: a flowing pool, a settling wave, and two small eyes looking toward the data. Keep the character at the edge of the composition; numbers and risk always lead.

## Palette

| Role | Light | Dark |
| --- | --- | --- |
| Canvas | Porcelain `#F5F7F3` | Deep pool `#10262D` |
| Surface | White `#FFFFFF` | Petrol `#18343C` |
| Primary ink | Petrol `#153D47` | Ice `#EAF4F2` |
| Secondary ink | Slate `#536D76` | Mist `#A4BEC3` |
| Fees and active ranges | Jade `#187C67` | Jade `#68D4B5` |
| Brand wave | Jade `#278D78` → blue `#3979B7` | Jade `#42B69C` → blue `#629FE0` |
| Attention / out of range | Muted rose red `#A64F53` | Soft coral `#EDA6A6` |
| Near range edge / stale data | Dusty rose `#8D6062` | Pale rose `#DBB2B2` |

Green conveys earnings or an active range. Soft, muted red conveys attention, with a quieter dusty rose for near-edge states and stale data. Keep these colours desaturated to match the soft jade-to-blue palette; do not use orange, amber or purple for attention. Purple already identifies saved wallets in All Wallets. Retain a text status and marker so colour is never the only signal. Blue identifies today, the current-price marker and selected controls. Token and network logos retain their own colours. Avoid unrelated gradients, rainbow bars, glossy oversized characters, and decorative scenery.

## Typography and geometry

Use Avenir Next Demi Bold for the wordmark and prominent financial figures, with tabular digits. Use the native text face for labels and controls so accessibility sizes remain familiar. Keep addresses and technical identifiers monospaced. Reserve bold for the amount and section hierarchy.

Use an 8-point spacing rhythm, 16–20-point continuous card corners, hairline separators and capsule range tracks. The signature is Soft Crest: a broad, softly layered green-to-turquoise-to-blue wave at the upper left, with the original character peeking from behind its front edge. The crest uses the brighter icon colours; data, text and controls retain the semantic palette above. It is decorative, hidden from accessibility, and does not intercept interaction. Do not substitute decoration for the existing fee-pool level visualization.

## Information and interaction

Always show unclaimed fees, portfolio value, today's fees once in the blue chart badge labelled Today when available, daily bar chart, selected period, claimed fees, pool level and realized APR when known. Do not repeat position and chain counts beneath Total value; the position list provides that context. Keep syncing and unavailable states truthful. Retain wallet navigation, filters, sorting, collect actions, errors and refresh status.

Position cards use Range + Return (Диапазон + доходност): pair, chain/version/fee tier, value and unclaimed fees in the header; a labelled price range with a blue current-price badge and marker; Min/Max prices; a quiet footer with claimed fees, realized APR since opening and Daily fees with period and mini bars on the same row. Range status sits beside the range heading, and out-of-range distance stays visible with a directional arrow. Holdings, opening date, position ID, the position's pool level and pool statistics stay in Details: a keyboard-accessible popover on macOS and a native sheet on iOS. Opening Uniswap remains a separate explicit action. Do not hide error or collection status inside hover content.

Daily bars reveal their date and amount on hover or tap; keyboard and screen-reader users can activate each bar for the same information. Show average daily earnings in the chart context rather than repeating it across the summary. Explain pool return and APR alongside those metrics; do not imply projected yield is realized return.

## Motion

Preserve the existing fee pool pouring and settling on opening. The Soft Crest wave enters briefly and its eyes fade in slightly later. Show data immediately. The eyes blink briefly on hover and at random 12–24-second intervals while the app view is visible. Use sleeping, cancellable tasks rather than a continuously rendering timeline. Widgets never schedule blinks; inline eye marks remain still. Ordinary refreshes do not restart the entrance animation. Respect Reduce Motion: no wave travel or slosh, only a short dissolve for the brand accent and no blinking. Widgets are static.

## Platforms

- macOS: compact 420-point popover, bar chart above positions, hover detail with an explicit keyboard alternative.
- iOS: same hierarchy and shared cards, scrollable at accessibility sizes. Tapping a card or its Details control opens a native bottom sheet with a system navigation title, Done button and drag indicator. Start at 70% height to fit the larger mobile content, allow expansion to large and swipe down to dismiss; use only large at accessibility text sizes. Details uses the available sheet width and height, without the Mac popover's 360-point width or 520-point height cap. Preserve wallet swiping and pull to refresh. Do not add empty Activity or Wallets tabs just to match a concept image.
- Small widget: unclaimed fees, today when known, range attention and last update. Keep critical text clear of the ribbon.
- Medium widget: fees and daily bars, portfolio value, attention and last update. If no history exists, show position context instead. Widgets read existing snapshots with up to 14 days of history; no network work or decorative animation.
- All Wallets: use a full jade-to-petrol summary surface and visible All wallets heading so the aggregate page is recognizable at a glance. Keep the shared typography, wallet colours and navigation effects; omit Pool level, fee-pool water and the single-wallet Soft Crest from this summary.

On macOS, the first wallet page is a compact All capsule with two overlapping oval pool outlines, rather than a stacked-layer symbol. Use the brand gradient for the unselected mark and a petrol/ice selected capsule with a matching high-contrast mark. Keep the short All label visible so its purpose is discoverable; the accessible name and hover help remain All Wallets. Individual wallets retain their page dots, with a 24-point-high click target. Preserve page order, wallet menu, swipes and keyboard navigation. iOS retains its native page indicator and wallet menu.

Wallet navigation references, showing both an individual wallet and All selected: [light](screenshots/redesign/wallet-navigation-light.png), [dark](screenshots/redesign/wallet-navigation-dark.png). Regenerate with `POOLSER_SCREENSHOT_FILTER=wallet-navigation`.

## Maintenance

Shared colours live in `Sources/PoolserKit/Presentation/GraphitePalette.swift`; reusable brand, summary and chart views live beside it. Widget layouts live in `Sources/PoolserKit/Widget/PortfolioWidgetViews.swift`. Preserve light and dark appearance and existing data semantics when changing this system. Update this reference in the same change as any new brand decision.

## Implementation details

### Local wallet handoff

The single-position and batch collect pages use one self-contained browser style under the existing nonce-based content security policy. A compact original app logo and Wallet handoff label lead into Review collection. The porcelain or deep-pool canvas holds white or petrol cards with 18-point corners; a narrow jade-to-blue crest line marks the fee summary. Avenir Next, when installed, leads the wordmark and tabular financial amounts, with system-font fallbacks. Technical identifiers use a selectable monospace face. Muted rose marks errors and unavailable positions; blue marks selected checkboxes and visible keyboard focus. Ordinary hover has a brief opacity transition only when Reduce Motion is off.

The page order is fee amount and position context, batch position selection when relevant, full transaction review, explicit collect action, live status and a quiet wallet-signing reminder. Transaction review keeps network, full wallet account, full destination and full fee recipient visible. Batch review also shows the estimated network fee when available and lists each destination with its version. At narrow widths, review rows stack labels above values and position fees move beneath their pair; neither addresses nor amounts are clipped. The shortened account chip is supplementary and exposes its full address on hover, while the review always shows the complete address without hover.

Batch selection explains empty and unavailable states in place. Wallet connection, account and network changes, pending confirmations, cancellation, retry, sent results and partial success use the existing bridge events and a live status region. Partial success keeps links for transaction hashes the wallet returned. A failed batch rebuild tells the user to check whether Poolser is still running. The browser pages do not infer on-chain confirmation from a submitted transaction or introduce a new bridge state.

### Native app details

The native macOS hover help adds context without moving the position rows. The Details button opens the full position view on both platforms and supports keyboard access. Explanatory info controls open one popover on click, tap or keyboard activation; do not attach a native hover tooltip containing the same explanation. This applies to position metrics, Details statistics, summary metrics and the daily chart's context heading. Retain accessible labels and action hints. Ordinary hover help remains for controls without an explanatory popover. There is no expanding Fee context row. The Claimed explanation describes collected v3 fees at current prices without repeating the displayed amount. Pool level explains all-time fees divided by current eligible position value. Summary APR explains Σ all-time fees / Σ (current value × years open), annualized, excluding positions younger than one day or missing data; the chart heading opens period totals and daily average on tap or click.

### Position cards: Range + Return

Use the existing opaque card surface, a neutral hairline border, 18-point corners and 16-point padding. Keep the Avenir Next amounts and wordmark; use native caption labels and tabular digits for prices and financial figures. Reserve jade, dusty rose and muted red for the range band, its labelled status and the out-of-range distance; do not outline the whole healthy or out-of-range card in a status colour. Error cards retain their warning border.

Use the same attention tokens for Needs attention chips, out-of-range pills, range ticks, distance arrows, All Wallets and widget status. Light appearance uses pale blush surfaces (`#FAEEEE` pills, `#F2DDDD` bands); dark appearance uses deep rose surfaces (`#3E2B2E` pills, `#4D3438` bands). Keep attention text at least 4.5:1 against its surfaces and range ticks at least 3:1 against the band and track. The current-price badge and marker stay blue.

The blue price badge follows the current marker, measuring its actual text width and clamping the label at the card edges. The marker retains its original position, including a clamped marker for a price beyond the displayed scale. Keep both range-bound ticks visible. Min/Max are explicitly labelled values below the track, not extra axis ticks; full range remains 0 to ∞. Retain the existing quote-token orientation, logarithmic tick geometry, exclusive upper bound and numeric formatting. Never shorten a tiny price or change the scale just to fit its label.

Claimed and APR since open are always labelled on the main card. Show a known USD amount, including a known zero; completed v3 history without any Collect events is also a known zero. Retain token amounts if USD pricing is unavailable. Unknown data and untracked v4 claims are a dash. Label partial claimed history as syncing and suppress APR until syncing is complete; APR still requires the existing minimum age and priced data. The realized position APR remains distinct from the pool's estimated 24-hour Yield. Keep claimed/APR explanations accessible and do not repeat these metrics as another row inside Details.

In the position header, replace a known zero unclaimed balance with No unclaimed fees in secondary ink. A positive USD amount below one cent reads <$0.01 fees in jade, never a rounded zero or an empty-balance message. Keep token amounts when USD pricing is unavailable and keep read failures unavailable rather than treating them as zero.

Show Daily fees as the third footer metric beside Claimed and APR since open when recorded daily history is nonempty. Place the mini bars next to its day count, aligned with the other metric values; do not reserve a separate fee-history row above the divider. Retain the actual number of days and the blue rightmost bar for today. The info control opens the existing Today/best-day explanation on click, tap or keyboard activation; there is no duplicate hover tooltip. Hide the metric for missing history rather than inventing zero-fee days. Do not repeat it inside Details.

Details is a compact info-circle button at the trailing edge of the footer, beside the three metrics. Retain its accessible Details label, explanatory hover help and a 24-point click target. Fit all footer controls on one row when possible; if Collect needs another row, keep Details beside the metrics and move only the labelled Collect action below. At narrow widths or large text sizes, stack the header, Min/Max labels, footer metrics and actions as needed rather than compressing the financial data. Preserve Collect, errors, context menus and all existing actions. All Wallets rows and widgets keep their existing compact gauges.

Reference captures from the implemented shared cards: [light](screenshots/redesign/position-cards-light.png), [dark](screenshots/redesign/position-cards-dark.png), [accessibility layout](screenshots/redesign/position-cards-accessibility.png). Use `POOLSER_SCREENSHOT_FILTER=position-cards` to regenerate this set.

Details is a compact supplementary panel: holdings, position ID, opening date, position pool level and pool statistics. Do not repeat the pair heading, chain/version/fee tier, range status, prices, position value, unclaimed fees, claimed amount, realized APR or daily fee history from the main card. Use a generic Position details heading; token symbols remain as units beside holdings. Show detailed read errors when present.

On macOS, use the same balance tiles, evenly distributed pool statistics and full-width Open in Uniswap action as iOS, at compact desktop proportions: 16-point outer padding, 12-point section spacing, 12-point tile padding and corners, scaled 18-point balance amounts and 16-point statistics. Keep the popover's title and Done control, 320-point ideal width and 360-point maximum width. Let its height fit the content instead of reserving a fixed 400-point height. On iOS, align the content to the top of the native sheet below its navigation bar. Ordinary text and data fit without a scroll container. Keep explanations for pool yield and pool level behind accessible info controls rather than permanent paragraphs. Retain a scrolling fallback when large accessibility text, long error messages or a short screen cannot fit the content in the available space (up to 520 points on Mac); never crop data or actions to remove scrolling. Keep Open in Uniswap as a separate action.

Compact macOS Details references: [light](screenshots/redesign/position-details-light.png), [dark](screenshots/redesign/position-details-dark.png).

Give iOS Details its own proportions: 24-point outer padding and section spacing, clear headline section labels, two equal token-balance tiles with 16-point insets and scaled 24-point Avenir Next amounts. Position ID and opening date use body-size label/value rows. Pool statistics fill three equal columns with subheadline labels and scaled 22-point amounts; explanation buttons have at least 44 points of height. Stack tiles and statistics at accessibility text sizes or when their values cannot fit side by side; do not split a balance or its compact USD suffix just to retain columns. Keep truthful unavailable states and readable errors. Pin Open in Uniswap in a full-width, at-least-44-point button in the bottom safe area, outside any scrolling content. Do not repeat card metrics to fill space; retain the same supplemental data and explanations as Mac.

### All Wallets overview

The aggregate summary is a continuous deep jade-to-petrol gradient with white text, 18-point corners and 18-point insets. Its full coloured silhouette distinguishes it from a single wallet's pale Soft Crest card, including in peripheral vision. Lead with All wallets, wallet count and total value, followed by the allocation bar and a visible wallet-name/percentage legend. Do not show Pool level or water in this summary. Single-wallet pool levels, filling and settling effects remain unchanged.

Show Unclaimed fees, Claimed and realized aggregate APR beneath a quiet divider; use the existing capital-and-time-weighted APR rather than averaging wallet percentages. Suppress APR while claimed history syncs and retain unavailable values. Each metric opens its explanation by click, tap or keyboard, without a second hover tooltip. Allocation colours follow saved-wallet order even when values reorder the cards. Hovering a segment or wallet highlights its matching card; the labelled allocation controls also support keyboard and touch. Highlight with the wallet border and a quiet shadow, preserving text contrast on the other cards.

Wallet cards use the shared surface, 18-point corners, 16-point insets and Avenir Next amounts. Keep wallet name, total value, position/chain counts, unclaimed fees and soft-red attention count visible. Read errors and loading/empty states stay visible without opening positions. The header opens that wallet; the separate View N positions disclosure expands compact position rows in place. Start with positions collapsed, preserve expansion while that card refreshes, and respect Reduce Motion when toggling. Keep existing row actions and range gauges. Stack headings and metrics at narrow widths or accessibility sizes instead of squeezing figures. Named-wallet addresses remain in header hover help; wallet names and figures stay visible.

The shared overview is used on macOS and iOS. The mobile app keeps its existing wallet navigation; no extra bottom tabs are introduced. Native reference captures from demo data: [light](screenshots/redesign/all-wallets-light.png), [dark](screenshots/redesign/all-wallets-dark.png), [narrow accessibility layout](screenshots/redesign/all-wallets-accessibility.png). Regenerate with `POOLSER_SCREENSHOT_FILTER=all-wallets`.

Reference captures from the actual shared views (demo data): [macOS light](screenshots/redesign/macos-light.png), [macOS dark](screenshots/redesign/macos-dark.png), [small widget](screenshots/redesign/widget-small-light.png), [medium widget](screenshots/redesign/widget-medium-light.png).

### Soft Crest character

Use the original icon artwork for the character. `Sources/PoolserKit/Resources/PoolserCharacter.png` is an unmodified copy of the 1024-pixel app icon, shared by macOS, iOS and widgets through the package resource bundle. `PoolCharacterArtwork` loads the PNG explicitly from its bundle URL on each platform. `PoolEyes` samples the eye region and masks each eyeball at display time, preserving the original glossy pupils, pale rims and reflected highlights. Do not redraw the eyes with ellipses and dots or substitute emoji. Place the character at the upper left, preserving its original gaze down and to the right toward the financial data. Mirror the wave geometry, never the eye artwork. Use the original eyes without mirroring them. Keep nearly the whole eyeball visible; only the lowest edge may sit behind the white card. The coloured wave must continue directly behind the eyes, meeting a single white foreground edge. Background and foreground share the same curve, with no white gap, doubled ridge or inset pocket around the eyes. `PoolBrandMark` uses the same original icon.

Use a satin crest with a soft rim and restrained depth. Leave a small blue-green cushion below the eyes by lowering the shared curve locally under the character; keep the eye position fixed. The crest is 62 points tall in the app and 40 in widgets, with the eyes held near the top so added depth goes below them. Avoid multiple shiny glass folds: the selected direction is Soft Crest. Widgets use a shorter crest and smaller character to keep titles and data readable. Their title sits to the right of the character, below the coloured edge, with space reserved for the eyes rather than a duplicate eye mark. The existing fee-pool filling animation remains separate and unchanged.

For a focused reference export, set `POOLSER_SCREENSHOT_FILTER=redesign` with `POOLSER_SCREENSHOTS`. This captures the crest, original character, summary and widgets without waiting for external token icons. Use `popover` to capture only the Mac panels, or omit the filter for the complete screenshot set.

The fee-pool water uses a separate vivid turquoise gradient (`#18D6B0` → `#23C5CF`) behind the complete card content. Composite the foreground separately so the water never paints over bars, text or controls. Daily history bars use opaque semantic jade, with an ink outline and a blue today bar, to remain distinct from the water in both appearances. Keep the background tint restrained (front/back opacity 14%/8% in light, 14%/5% in dark), maintaining at least 4.5:1 contrast for secondary text even at full water.

Map the pool level linearly to the full card height, from the bottom edge (0%, completely empty) to the top edge (100%, completely full). There is no minimum decorative fill. At 25% the surface is one quarter of the card height above its bottom; at 50% it is halfway. Waves oscillate around that surface and taper near the limits; neither layer leaves a gap at 100% or paints water at 0%. Returns above 100% keep a full card while the metric and accessible label retain the actual percentage. The decorative Soft Crest remains in the foreground and does not represent the fee return. Mask its artwork to the crest edge; leave the area below transparent so high water continues behind it without an opaque white or petrol strip. Preserve pouring, settling, unavailable/syncing states and the financial calculation. The compact position gauge retains its separate 10% minimum for visibility.

Boundary references from the actual shared summary, with fixture levels of 0%, 25%, 50%, 100% and 150%: [light](screenshots/redesign/pool-levels-light.png), [dark](screenshots/redesign/pool-levels-dark.png). Render them with `POOLSER_SCREENSHOT_FILTER=pool-levels`.
