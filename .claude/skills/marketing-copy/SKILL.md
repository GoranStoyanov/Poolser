---
name: marketing-copy
description: Write or edit Poolser's public-facing copy (App Store name, subtitle, promotional text, description, keywords, What's New, screenshot captions, README intro and feature list, release notes, social posts) in a plain, specific, human voice with no em dashes and none of the stock phrasing that makes text read as machine-written. Use whenever drafting or reviewing marketing text, store listings, release notes or README prose, or when the user asks for a description, tagline, changelog or "what's new".
---

# Marketing copy for Poolser

Poolser's copy should read like one developer who uses the app describing it to another
liquidity provider: concrete, calm, a little dry. Every sentence names something the app
actually does. If a line would fit any other app, cut it.

## Hard rules

These are checked mechanically (see **Check** below). A draft that breaks one is not done.

1. **No em dashes (—) and no en dashes (–) as punctuation.** Use a full stop, a comma, a colon
   or parentheses instead. Ranges are written with "to" ("7 to 30 days"). Hyphens in compound
   words ("out-of-range", "read-only") are fine.
2. **No stock phrases.** Never use: seamless(ly), effortless(ly), elevate, unlock, unleash,
   empower, supercharge, revolutionize, game-changer, cutting-edge, next-level, robust,
   leverage, harness, streamline, delve, dive in, tapestry, testament, boasts, ensures,
   "whether you're … or …", "in today's fast-paced …", "look no further", "take … to the next
   level", "say goodbye to", "peace of mind", "at your fingertips", "all-in-one", "designed
   with you in mind".
3. **No "not just X, it's Y"** constructions and no rhetorical question followed by its own
   answer in the body text. One question as a screenshot caption is fine ("Fees went up?").
4. **No emoji** in store text or README prose, and no emoji used as bullets. The 👀 in the
   product name and menu bar title is part of the UI, so it may appear when showing the UI.
5. **No exclamation marks.**
6. **Sentence case** for headings and captions ("See what you earn each day"), not Title Case.
7. **No claims the code does not back.** Check the feature in source before writing it. No
   "best", "fastest", "#1", "most secure", no prices, no promises about returns or yield.
8. **Never mention AI, assistants, models or prompts**, and never imply the text or the app was
   written by one (see `CLAUDE.md`).

## Soft rules

- Lead with the outcome for the user, then the mechanism: "See unclaimed fees in the menu bar.
  Poolser reads them straight from the chain."
- Short sentences. One idea each. Prefer verbs to nouns ("collect fees", not "fee collection
  functionality").
- Specific beats general: name chains, versions, numbers ("7D, 14D or 30D", "Uniswap v3 and
  v4", "every 10 minutes").
- Avoid lists of exactly three adjectives, and avoid triplets in general unless there really
  are three things.
- Use plain bullets ("- ") in store text; App Store descriptions render plain text only. No
  Markdown bold, headings or links there.
- US spelling in public copy ("color", "favorite"); code comments keep their own style.
- "Uniswap" is a trademark of Uniswap Labs. Say Poolser works *with* Uniswap positions; never
  imply affiliation. Keep the disclaimer in the README.
- Requirements belong at the end: macOS version, an Infura API key, a wallet with positions.

## App Store limits

| Field | Limit | Notes |
|---|---|---|
| Name | 30 | "Poolser" |
| Subtitle | 30 | Shown under the name everywhere |
| Promotional text | 170 | Can change without a new build |
| Keywords | 100 bytes | Comma separated, no spaces after commas, no words already in name or subtitle, no competitor names |
| Description | 4000 | Plain text. First 2 to 3 lines show before "more", so they must sell the app on their own |
| What's New | 4000 | Lead with the 2 or 3 changes users will notice; group fixes in one line |
| Screenshot captions | ~6 words headline, ~12 words subline | Must match what the screenshot shows |

Paste store text as plain text: no trailing spaces, no tabs, no leading indentation. (The 1.2
description went out with long runs of trailing spaces from a terminal copy.)

## Check

Run on any draft before handing it over:

```bash
grep -nE '—|–' FILE
grep -niwE 'seamless(ly)?|effortless(ly)?|elevate|unlock|unleash|empower|supercharge|revolutioni[sz]e|game-?changer|cutting-edge|next-level|robust|leverage|harness|streamline|delve|tapestry|testament|boasts|ensures|fingertips|all-in-one' FILE
grep -nE '!|[[:space:]]+$' FILE
```

All three must print nothing (the last one may match a `!` inside code or URLs; check by eye).

## Where copy lives

- `docs/app-store.md`: the current listing (name, subtitle, promo text, description, keywords,
  What's New, screenshot order and captions). Update it with every release.
- `README.md`: features and screenshots for GitHub.
- Screenshot captions are in `Sources/Poolser/Graphite/StoreScreenshots.swift`; regenerate the
  images with `POOLSER_SCREENSHOTS=docs/screenshots swift run` after changing them.
