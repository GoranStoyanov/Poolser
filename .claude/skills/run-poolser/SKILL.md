---
name: run-poolser
description: Build, launch and verify the Poolser macOS menu bar app (SwiftPM or Xcode). Use when asked to run, build, start, test or screenshot the app, or to confirm a code change works in the real app rather than only compiling.
---

# Run Poolser

Poolser is a **macOS 14+ menu bar app** (SwiftUI, `MenuBarExtra`), not an iOS app — there is no
simulator target. It has two build paths that must both keep working:

| Path | Use for | Notes |
|---|---|---|
| SwiftPM — `Package.swift` | fast compile checks, CI-style builds | defines `SPM_BUILD`; resources via `.process("Resources")` |
| Xcode — `Poolser/Poolser.xcodeproj` | signed app bundle, notifications, Launch at Login | needs `Poolser/CodeSigning.xcconfig` (copy from `.sample`, gitignored) |

## Build

```bash
swift build
```

Release build: `swift build -c release`. A compile check after every Swift change is the minimum
bar. If you add a new source file, make sure it is also in the Xcode project target
(`project.pbxproj`), otherwise the Xcode build breaks while SwiftPM passes.

## Launch

```bash
swift run
```

- The app has no Dock icon and no window: it appears as an item in the menu bar. Nothing
  "opens" — say so instead of waiting for a window.
- In a sandboxed shell, GUI launch may be blocked; give the user the command to run.
- Features that need a real app bundle — `UNUserNotificationCenter` (range-change
  notifications in `NotificationService`) and `SMAppService` (Launch at Login in `AppSettings`) —
  are only reliable from the Xcode-built `.app`, not from `swift run`. Test them there.
- `#if SPM_BUILD` currently only switches resource lookup (`Bundle.module` vs the app bundle,
  e.g. `AppLogo` in `MenuBarContentView`). New resources need to load on both paths.

## Verify a change

1. `swift build` passes with no new warnings.
2. Launch, open the popover, press refresh.
3. Open **Logs** (in the popover): check request count, retries and errors for one refresh —
   this is the ground truth for RPC changes (see `evm-rpc-optimization`).
4. Numbers to eyeball against app.uniswap.org for the same wallet: unclaimed fees, in-range
   badge, position value. Small differences are price-source differences; large ones are bugs
   (see `uniswap-position-math`).

Configuration (wallet address, Infura key, networks) lives in the app's Settings and
`UserDefaults`; never write a real API key into source, tests or commits — the gitleaks
pre-commit hook (`.githooks/pre-commit`) blocks it.

## Tests

There is no test target yet. When adding one, use Swift Testing (`swift-testing-pro` skill)
and a separate `testTarget` in `Package.swift`; run with `swift test`. Pure functions first:
ABI encode/decode, tick/price math, fee-growth wrapping.
