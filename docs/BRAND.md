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

Always show unclaimed fees, portfolio value, today's fees when available, daily bar chart, selected period, claimed fees, pool level and realized APR when known. Keep syncing and unavailable states truthful. Retain wallet navigation, filters, sorting, collect actions, errors and refresh status.

Position cards always show pair, chain/version/fee tier, value, fees, range status, range track and current marker. Out-of-range distance remains visible. Exact prices, holdings, position ID, claimed return and pool statistics are secondary details: reveal on hover or keyboard-accessible Details on macOS, and via Details on iOS. Opening Uniswap remains a separate explicit action. Do not hide error or collection status inside hover content.

Daily bars reveal their date and amount on hover or tap; keyboard and screen-reader users can activate each bar for the same information. Show average daily earnings in the chart context rather than repeating it across the summary. Explain pool return and APR alongside those metrics; do not imply projected yield is realized return.

## Motion

Preserve the existing fee pool pouring and settling on opening. The Soft Crest wave enters briefly and its eyes fade in slightly later. Show data immediately. No perpetual decorative animation or repeated animation during ordinary refreshes. Respect Reduce Motion: no wave travel or slosh, only a short dissolve for the brand accent. Widgets are static.

## Platforms

- macOS: compact 420-point popover, bar chart above positions, hover detail with an explicit keyboard alternative.
- iOS: same hierarchy and shared cards, scrollable at accessibility sizes; tap for details instead of hover. Preserve wallet swiping and pull to refresh. Do not add empty Activity or Wallets tabs just to match a concept image.
- Small widget: unclaimed fees, today when known, range attention and last update. Keep critical text clear of the ribbon.
- Medium widget: fees and daily bars, portfolio value, attention and last update. If no history exists, show position context instead. Widgets read existing snapshots with up to 14 days of history; no network work or decorative animation.
- All Wallets: preserve wallet allocation and grouped positions; use the same palette, type and brand accent.

## Maintenance

Shared colours live in `Sources/PoolserKit/Presentation/GraphitePalette.swift`; reusable brand, summary and chart views live beside it. Widget layouts live in `Sources/PoolserKit/Widget/PortfolioWidgetViews.swift`. Preserve light and dark appearance and existing data semantics when changing this system. Update this reference in the same change as any new brand decision.

## Implementation details

The native macOS hover help exposes exact prices, holdings and identifiers without moving the position rows. The Details button opens the full position view on both platforms and supports keyboard access. Fee context expands below the summary; the chart heading opens period totals and daily average on tap or click. Preserve these explicit alternatives to hover.

The all-wallets summary uses a deeper jade-to-petrol gradient for white-text contrast and retains its allocation bar and grouped positions. The mobile app keeps its existing wallet navigation; the concept's extra bottom tabs are not part of this implementation.

Reference captures from the actual shared views (demo data): [macOS light](screenshots/redesign/macos-light.png), [macOS dark](screenshots/redesign/macos-dark.png), [small widget](screenshots/redesign/widget-small-light.png), [medium widget](screenshots/redesign/widget-medium-light.png).

### Soft Crest character

Use the original icon artwork for the character. `Sources/PoolserKit/Resources/PoolserCharacter.png` is an unmodified copy of the 1024-pixel app icon, shared by macOS, iOS and widgets through the package resource bundle. `PoolCharacterArtwork` loads the PNG explicitly from its bundle URL on each platform. `PoolEyes` samples the eye region and masks each eyeball at display time, preserving the original glossy pupils, pale rims and reflected highlights. Do not redraw the eyes with ellipses and dots or substitute emoji. Place the character at the upper left, preserving its original gaze down and to the right toward the financial data. Mirror the wave geometry, never the eye artwork. The front white crest overlaps roughly the lower quarter of the eyes so the character peeks from inside the blue-green pool and watches the figures; the eyes must never float on the white card. `PoolBrandMark` uses the same original icon.

Use a satin crest with a soft rim and restrained depth. Avoid multiple shiny glass folds: the selected direction is Soft Crest. Widgets use a shorter crest and smaller character to keep titles and data readable. Their title sits to the right of the character, with space reserved for the eyes rather than a duplicate eye mark. The existing fee-pool filling animation remains separate and unchanged.

For a focused reference export, set `POOLSER_SCREENSHOT_FILTER=redesign` with `POOLSER_SCREENSHOTS`. This captures the crest, original character, summary and widgets without waiting for external token icons. Use `popover` to capture only the Mac panels, or omit the filter for the complete screenshot set.
