---
name: poolser-release
description: Prepare a Poolser release for macOS and iOS, including versions, signed archives, README updates since the last published release, release notes, native screenshots and App Store submission materials. Use for release preparation or shipping Poolser, not ordinary development builds.
---

# Poolser release

Produce a reviewable release package from the actual source and the last published release. Preparation includes changing versions, updating public documentation, building, checking and assembling store materials. Creating this skill is not a request to release the app.

Read the repository instructions, `docs/BRAND.md`, `README.md`, `docs/app-store.md` and [the project reference](references/project.md). Resolve paths from the active Poolser checkout, not a fixed machine path. Keep the reference aligned with changes to targets or release tooling.

## Establish the release

- Inspect the branch, working tree, configured remote, tags, published GitHub releases and relevant history. Preserve unrelated work. Do not merge a redesign branch or discard edits to make a release possible.
- Identify the latest **published** version and source baseline for each requested platform from App Store Connect, the public listing, release tags or published GitHub releases. Draft releases and the Xcode marketing version are not proof of publication. With no source tag, inspect history and the prior release notes; state any uncertain baseline instead of inventing a tag or calling all history new.
- Infer the requested platforms from the request. For an unqualified Poolser release, prepare both shipping app targets and embedded widgets; identify separately whether iOS is a first store release. Ask only when platform scope or an unknown baseline changes a consequential decision. Continue independent preparation while a required answer is pending.
- Use an explicitly requested version. Otherwise choose and report the smallest appropriate version increase from the verified published version and changes. Choose an unused build number above the project and uploaded builds, including rejected/TestFlight builds. Verify it in App Store Connect when available; otherwise mark the number provisional. Keep app and embedded extension versions consistent. Version values currently live at project level for both Debug and Release; do not introduce conflicting target overrides.

## Prepare documentation and store copy

- Compare the release source to the published baseline using commits **and** the resulting code. Update `README.md` for the release's actual behavior, platform availability, requirements, screenshots and setup. Distinguish unreleased iOS support from an available App Store download. Remove stale claims and links; preserve installation, privacy and collection limitations.
- Update `docs/app-store.md` with platform-specific listing copy and What's New for an update. A first release needs complete listing copy rather than invented update history. Follow the existing English copy unless another locale is requested. Count field lengths against current Apple limits.
- Prepare concise user-facing release notes in `docs/releases/<version>.md`, separated by platform where behavior differs, and a GitHub release body in the external artifact directory. Describe visible outcomes and material fixes since the baseline; omit internal churn and unsupported feature claims. Do not duplicate the entire README. Preserve existing notes for prior versions.
- Check name, subtitle, description, keywords, promotional text, category, age rating, support/marketing/privacy URLs, copyright, content rights, availability, pricing, review notes and export-compliance answers for the selected platforms. Reassess privacy answers against actual data flows and required-reason API/privacy-manifest requirements; do not blindly reuse an old declaration. Do not change legal, pricing or availability choices by inference.
- Prepare actionable App Review instructions: setup, access to representative positions, platform differences, optional permissions and collection handoff. Put a real reviewer key or contact details only in an approved private artifact or App Store Connect field, never source, screenshots, release notes or public issues. Never fabricate credentials. Flag missing reviewer access without blocking unrelated work.

## Build and verify

- Run the package tests and Release build, then archive the requested Xcode app schemes for their native generic destinations. Archive the app, including its widget; a SwiftPM executable or simulator build is not an App Store binary. Use existing local signing configuration and installed tooling. Do not replace signing identities, entitlements or bundle identifiers to make a build pass.
- Verify the **archived** app and embedded extensions: marketing/build versions, bundle IDs, minimum OS, icons, signatures, entitlements, App Groups and required capabilities. Retain dSYMs and archive provenance. Use the appropriate App Store distribution/export and validation workflow for each platform; derive export options from current Xcode and local signing, not an old hard-coded plist. Record validation failures faithfully.
- Smoke-test the current app and widgets in light/dark appearance, a single wallet and multiple wallets, empty/loading/unavailable states, position disclosures and Details. Include large text and narrow layouts on iOS. Report physical-device checks separately from compilation or simulator checks. Never sign or send a real collect transaction as a release test; use controlled fixtures for transaction UI states.

## Screenshots and handoff

- Regenerate README and Mac App Store images with the repository's native fixture renderer. Refresh captions to match the release and inspect every output for clipping, stale copy, missing icons, contrast and truthful numbers. Extend fixtures only when coverage needed by this release is missing.
- For iOS, capture the actual native app with demo data and the enabled widget families at the required device sizes. The existing Mac renderer is not an iOS screenshot pipeline. If a required runtime/device is unavailable, finish all other materials and identify the exact missing captures. Never stretch Mac artwork into iPhone/iPad screenshots or label concept images as app captures.
- Recheck Apple's live requirements through the official links in the reference at release time, including supported SDKs and device sizes. Validate image dimensions, format and alpha behavior for each selected platform. Required device families follow the actual target configuration. Optional previews or extra localizations are included only when part of the release scope.
- Keep archives, exports, validation logs and the release manifest outside the repository, e.g. `/tmp/poolser-release-<version>/`. The manifest records source commit, baseline, platform versions/builds, archive/export/dSYM paths, metadata and image paths, checks completed and concrete unresolved blockers. Keep secrets out of it. Public release notes, listing copy and selected screenshots belong in the repository.
- Review the final diff and the repository's required pre-commit checks. Commit release preparation only when requested or already authorized. Record the final source commit in the artifact manifest. A preparation request does not authorize push, tag creation, a published GitHub release, App Store upload, TestFlight distribution or submission. Carry out those steps only when explicitly requested; complete and verify preparation first, then ask once for any missing authorization using concrete artifacts. Do not recreate releases or repeatedly upload after an ambiguous failure: inspect the remote state before retrying.

Finish with the version/build per platform, changes prepared, artifact paths, validation results and remaining manual items. Distinguish prepared, archived, validated, uploaded, submitted and published; never report one as another.
