# Poolser brand reference

Status: redesign branch, 2 November 2026. Update this document whenever a visual or interaction decision changes. It describes the product implementation, not just concept images.

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
| Attention | Amber `#A45417` | Apricot `#F2B174` |

Green conveys earnings or an active range. Amber conveys attention; retain a text status and marker so colour is never the only signal. Blue identifies today and selected controls. Token and network logos retain their own colours. Avoid unrelated gradients, rainbow bars, glossy oversized characters, and decorative scenery.

## Typography and geometry

Use Avenir Next Demi Bold for the wordmark and prominent financial figures, with tabular digits. Use the native text face for labels and controls so accessibility sizes remain familiar. Keep addresses and technical identifiers monospaced. Reserve bold for the amount and section hierarchy.

Use an 8-point spacing rhythm, 16–20-point continuous card corners, hairline separators and capsule range tracks. The signature is Soft Crest: a broad, softly layered green-to-turquoise-to-blue wave at the upper left, with the original character peeking from behind its front edge. The crest uses the brighter icon colours; data, text and controls retain the semantic palette above. It is decorative, hidden from accessibility, and does not intercept interaction. Do not substitute decoration for the existing fee-pool level visualization.

## Information and interaction

Always show unclaimed fees, portfolio value, today's fees once in the blue chart badge labelled Today when available, daily bar chart, selected period, claimed fees, pool level and realized APR when known. Do not repeat position and chain counts beneath Total value; the position list provides that context. Keep syncing and unavailable states truthful. Retain wallet navigation, filters, sorting, collect actions, errors and refresh status.

Position cards always show pair, chain/version/fee tier, value, fees, range status, range track and current marker. Out-of-range distance remains visible. Exact prices, holdings, position ID, claimed return and pool statistics are secondary details: reveal on hover or keyboard-accessible Details on macOS, and via Details on iOS. Opening Uniswap remains a separate explicit action. Do not hide error or collection status inside hover content.

Daily bars reveal their date and amount on hover or tap; keyboard and screen-reader users can activate each bar for the same information. Show average daily earnings in the chart context rather than repeating it across the summary. Explain pool return and APR alongside those metrics; do not imply projected yield is realized return.

## Motion

Preserve the existing fee pool pouring and settling on opening. The Soft Crest wave enters briefly and its eyes fade in slightly later. Show data immediately. The eyes blink briefly on hover and at random 12–24-second intervals while the app view is visible. Use sleeping, cancellable tasks rather than a continuously rendering timeline. Widgets never schedule blinks; inline eye marks remain still. Ordinary refreshes do not restart the entrance animation. Respect Reduce Motion: no wave travel or slosh, only a short dissolve for the brand accent and no blinking. Widgets are static.

## Platforms

- macOS: compact 420-point popover, bar chart above positions, hover detail with an explicit keyboard alternative.
- iOS: same hierarchy and shared cards, scrollable at accessibility sizes; tap for details instead of hover. Preserve wallet swiping and pull to refresh. Do not add empty Activity or Wallets tabs just to match a concept image.
- Small widget: unclaimed fees, today when known, range attention and last update. Keep critical text clear of the ribbon.
- Medium widget: fees and daily bars, portfolio value, attention and last update. If no history exists, show position context instead. Widgets read existing snapshots with up to 14 days of history; no network work or decorative animation.
- All Wallets: preserve wallet allocation and grouped positions; use the same palette, type and brand accent.

## Maintenance

Shared colours live in `Sources/PoolserKit/Presentation/GraphitePalette.swift`; reusable brand, summary and chart views live beside it. Widget layouts live in `Sources/PoolserKit/Widget/PortfolioWidgetViews.swift`. Preserve light and dark appearance and existing data semantics when changing this system. Update this reference in the same change as any new brand decision.

## Implementation details

The native macOS hover help exposes exact prices, holdings and identifiers without moving the position rows. The Details button opens the full position view on both platforms and supports keyboard access. Claimed, Pool level and APR each expose their own contextual tooltip on Mac and an accessible click/tap popover; there is no expanding Fee context row. The Claimed explanation describes collected v3 fees at current prices without repeating the displayed amount. Pool level explains all-time fees divided by current eligible position value. APR explains Σ all-time fees / Σ (current value × years open), annualized, excluding positions younger than one day or missing data; the chart heading opens period totals and daily average on tap or click. Preserve these explicit alternatives to hover.

The all-wallets summary uses a deeper jade-to-petrol gradient for white-text contrast and retains its allocation bar and grouped positions. The mobile app keeps its existing wallet navigation; the concept's extra bottom tabs are not part of this implementation.

Reference captures from the actual shared views (demo data): [macOS light](screenshots/redesign/macos-light.png), [macOS dark](screenshots/redesign/macos-dark.png), [small widget](screenshots/redesign/widget-small-light.png), [medium widget](screenshots/redesign/widget-medium-light.png).

### Soft Crest character

Use the original icon artwork for the character. `Sources/PoolserKit/Resources/PoolserCharacter.png` is an unmodified copy of the 1024-pixel app icon, shared by macOS, iOS and widgets through the package resource bundle. `PoolCharacterArtwork` loads the PNG explicitly from its bundle URL on each platform. `PoolEyes` samples the eye region and masks each eyeball at display time, preserving the original glossy pupils, pale rims and reflected highlights. Do not redraw the eyes with ellipses and dots or substitute emoji. Place the character at the upper left, preserving its original gaze down and to the right toward the financial data. Mirror the wave geometry, never the eye artwork. Use the original eyes without mirroring them. Keep nearly the whole eyeball visible; only the lowest edge may sit behind the white card. The coloured wave must continue directly behind the eyes, meeting a single white foreground edge. Background and foreground share the same curve, with no white gap, doubled ridge or inset pocket around the eyes. `PoolBrandMark` uses the same original icon.

Use a satin crest with a soft rim and restrained depth. Leave a small blue-green cushion below the eyes by lowering the shared curve locally under the character; keep the eye position fixed. The crest is 62 points tall in the app and 40 in widgets, with the eyes held near the top so added depth goes below them. Avoid multiple shiny glass folds: the selected direction is Soft Crest. Widgets use a shorter crest and smaller character to keep titles and data readable. Their title sits to the right of the character, below the coloured edge, with space reserved for the eyes rather than a duplicate eye mark. The existing fee-pool filling animation remains separate and unchanged.

For a focused reference export, set `POOLSER_SCREENSHOT_FILTER=redesign` with `POOLSER_SCREENSHOTS`. This captures the crest, original character, summary and widgets without waiting for external token icons. Use `popover` to capture only the Mac panels, or omit the filter for the complete screenshot set.

The fee-pool water uses a separate vivid turquoise gradient (`#18D6B0` → `#23C5CF`) behind the complete card content. Composite the foreground separately so the water never paints over bars, text or controls. Daily history bars use opaque semantic jade, with an ink outline and a blue today bar, to remain distinct from the water in both appearances. Keep the background tint restrained (front/back opacity 14%/8% in light, 14%/5% in dark), maintaining at least 4.5:1 contrast for secondary text even at full water.

Map the pool level linearly to the full card height, from the bottom edge (0%, completely empty) to the top edge (100%, completely full). There is no minimum decorative fill. At 25% the surface is one quarter of the card height above its bottom; at 50% it is halfway. Waves oscillate around that surface and taper near the limits; neither layer leaves a gap at 100% or paints water at 0%. Returns above 100% keep a full card while the metric and accessible label retain the actual percentage. The decorative Soft Crest remains in the foreground and does not represent the fee return. Mask its artwork to the crest edge; leave the area below transparent so high water continues behind it without an opaque white or petrol strip. Preserve pouring, settling, unavailable/syncing states and the financial calculation. The compact position gauge retains its separate 10% minimum for visibility.

Boundary references from the actual shared summary, with fixture levels of 0%, 25%, 50%, 100% and 150%: [light](screenshots/redesign/pool-levels-light.png), [dark](screenshots/redesign/pool-levels-dark.png). Render them with `POOLSER_SCREENSHOT_FILTER=pool-levels`.
