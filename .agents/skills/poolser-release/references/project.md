# Poolser release reference

## Sources of truth

| Concern | Location |
| --- | --- |
| Native app project | `Poolser/Poolser.xcodeproj` |
| Shared domain, views and widget layouts | `Sources/PoolserKit/` |
| macOS application and collection bridge | `Sources/Poolser/` |
| iOS application | `Poolser/PoolserIOS/` |
| Widget targets | `Poolser/PoolserWidget/`, `Poolser/PoolserIOSWidget/` |
| Version/build and target configuration | `Poolser/Poolser.xcodeproj/project.pbxproj` |
| Local signing settings | `Poolser/CodeSigning.xcconfig` (ignored; `.sample` documents setup) |
| Brand and platform interactions | `docs/BRAND.md` |
| Store listing and existing screenshot order | `docs/app-store.md` |
| Product/setup documentation | `README.md` |
| Published privacy statement | `PRIVACY.md` |
| Native screenshot renderer and demo positions | `Sources/Poolser/Graphite/StoreScreenshots.swift`, `GraphitePreviews.swift` |

Discover the current remote with `git remote get-url origin`; the current project is `GoranStoyanov/Poolser`. The Mac listing currently linked by the README has app ID `6762252798`. Verify listing/platform records at release time. There is no guaranteed GitHub release/tag baseline. An existing store-copy document headed 1.3 is not evidence that 1.3 shipped.

The schemes are `Poolser` (macOS) and `PoolserIOS` (iOS). Embedded extension targets are `PoolserWidget` and `PoolserIOSWidget`. Confirm with `xcodebuild -list -project Poolser/Poolser.xcodeproj`; generated user schemes are ignored, so discover rather than assume their existence on another machine. Both apps share project-level `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`; check effective values in every archive. iOS currently enables iPhone **and iPad** (`TARGETED_DEVICE_FAMILY = "1,2"`). Do not silently drop iPad to avoid its release requirements.

macOS notifications and Launch at Login require the signed Xcode app for meaningful runtime checks. A missing installed simulator runtime is not a Swift compile failure. The project now includes iOS even if older run instructions still describe it as Mac-only. `PoolserKit` changes must remain portable; new Mac source files also need Xcode project membership.

## Local build commands

Run from the repository root. Choose a version-specific artifact directory outside the repository. The following examples use `/tmp/poolser-release`; use distinct version paths in real releases and do not overwrite a previous archive.

```sh
swift test
swift build -c release
xcodebuild -list -project Poolser/Poolser.xcodeproj
xcodebuild -project Poolser/Poolser.xcodeproj -scheme Poolser -configuration Release -destination 'generic/platform=macOS' -archivePath /tmp/poolser-release/Poolser.xcarchive archive
xcodebuild -project Poolser/Poolser.xcodeproj -scheme PoolserIOS -configuration Release -destination 'generic/platform=iOS' -archivePath /tmp/poolser-release/PoolserIOS.xcarchive archive
```

Sandboxed environments may require authorized access to tool caches, signing and archive destinations. Use the environment's approval mechanism rather than changing project configuration. Do not automatically add `-allowProvisioningUpdates` or `CODE_SIGNING_ALLOWED=NO` to a shipping archive. Read current Xcode export help (`xcodebuild -help`) before constructing a private `ExportOptions.plist`. Exporting an archive locally and uploading to App Store Connect are separate actions. Keep distribution credentials out of shell output and logs.

## Native screenshot exports

```sh
POOLSER_SCREENSHOTS=/tmp/poolser-release/screenshots swift run
```

This is a **Debug-only** demo renderer: it exports screenshots and quits. It does not need a user's wallet or Infura key; icon prefetching may use public endpoints. It currently produces the Mac App Store JPEG set in `appstore/`, popover PNGs and focused brand references in `redesign/`. Inspect all captures before copying the release's public files into `docs/screenshots/`. Do not accidentally run a real user session with private settings for public captures.

`POOLSER_SCREENSHOT_FILTER` selects shot names by substring: `appstore`, `popover`, `all-wallets`, `position-cards`, `pool-levels`, `wallet-navigation` or `redesign`. Use a complete export when preparing a release; focused exports only cover their names. Settings and logs images in the README are not produced by this renderer; verify them separately with sanitized data and refresh when changed.

The existing Mac canvases are 1440×900 points, exported as 2880×1800 JPEGs. Verify actual pixel output and current store specifications. Widgets rendered as isolated images document widget UI; use real device captures where required for store assets. No dedicated iOS App Store screenshot exporter exists yet: prepare native iPhone/iPad captures for the target device families and flag any unavailable capture environment honestly.

## App Store checks

Use the current official requirements, not a frozen list of device sizes or SDK deadlines:

- [Submission requirements and supported tooling](https://developer.apple.com/app-store/submitting/)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [Uploading previews and screenshots](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/)
- [Required, localizable and editable properties](https://developer.apple.com/help/app-store-connect/reference/app-information/required-localizable-and-editable-properties)
- [App privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files)
- [App Review preparation](https://developer.apple.com/app-store/review/)
- [Submitting an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app)

Verify platform-specific support/privacy URLs resolve and review notes match the app being shipped. Poolser needs an Infura key and a representative public wallet to show live positions; a reviewer must not need private keys or funds to inspect the monitoring UI. Collection opens a temporary loopback browser page on macOS; do not promise that browser-extension flow on iOS without checking implementation. Privacy, encryption and financial-app declarations must match actual behavior and current store questions.

Keep the existing no-attribution, configured-author and secret-scan rules from the repository instructions. Store test results and packaging logs outside the repository; polished release notes and store metadata are product deliverables, not build logs.
