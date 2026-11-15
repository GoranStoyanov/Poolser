# Poolser brand reference

Shared identity for Poolser's native apps, web app and public website. Extracted from the implemented native brand on 15 November 2026; this first import preserves its artwork and palette.

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

## Original artwork and Soft Crest

Use the original character in `assets/PoolserCharacter.png`, an unmodified 1024-pixel copy of the default app icon. `assets/AppLogo.png` is the existing compact app logo. The Apple icon and logo exports in `assets/apple/` preserve their original filenames, sizes, appearances and asset-catalog metadata.

Preserve the original glossy pupils, pale rims, reflected highlights and gaze down and to the right toward the data. Never mirror the eye artwork, redraw it with ellipses and dots, or substitute emoji or another mascot. The wave geometry may be mirrored independently. Keep nearly the whole eyeball visible, with only its lowest edge behind the foreground crest edge.

Use a satin crest with a soft rim, restrained depth and a small blue-green cushion below the eyes. The coloured wave continues directly behind the eyes and meets one foreground edge, without a white gap, doubled ridge or inset pocket. The decorative crest never represents a financial value. The fee-pool water is a separate visualization.

## Financial meaning and accessibility

Lead with financial figures and risk, keeping decoration secondary. Preserve the difference between a known zero, missing data, partial history, syncing and stale data. Realized return remains distinct from estimated pool yield. Keep the existing numeric precision, token orientation and range semantics when adapting an interface to another platform.

Status always has a text or marker alternative to colour. Charts expose the same information to keyboard, touch and screen-reader users as they do on hover. Explanations and actions remain explicitly accessible. Keep errors and transaction status visible. Aim for at least 4.5:1 text contrast and 3:1 for essential graphical indicators; test the actual composited surfaces in light and dark appearance.

Marketing content describes the published product and platform availability. Use sanitized captures from the actual apps, with demo data. Keep Mac and mobile presentations distinct and retain the independent-project and Uniswap non-affiliation statements.

## Motion

Financial data and the crest appear immediately. Where a character entrance is used, keep its playful peek, retreat and settling pop within the crest silhouette; do not move financial content or restart the entrance on a data refresh. The current native entrance lasts about 1.5 seconds. Eye blinks are brief and sparse, and run only while the app view is visible. Widgets and inline eye marks remain still.

Respect the platform's reduced-motion setting. Skip the entrance performance, blinking and fee-pool slosh; the native reference uses only a 0.15-second eye dissolve. Keep motion cancellable and avoid continuously running decorative animations. Platform-specific timing, layout dimensions and implementation details live with the consuming application.

## Shared tokens and platform implementations

`tokens/colors.json` records the current native palette, including range statuses, saved-wallet colours and water opacity. The property names match `GraphitePalette` to make comparison straightforward. Treat the values as sRGB colours; keep monetary and range semantics in the applications.

The typography reference uses installed Avenir Next plus platform system fonts; this repository does not distribute fonts. On the web use an installed-font stack such as `"Avenir Next", Avenir, system-ui, sans-serif`, tabular figures for amounts, and a system monospace stack for technical identifiers.

Update shared identity, artwork and tokens here first. Consumers adopt a reviewed commit explicitly, keeping the required files locally so builds do not fetch brand content. Native SwiftUI components, platform interactions, product screenshots and screenshot generation remain in `poolser-app/native`. The website and browser application keep their own platform-specific implementation guidance.
