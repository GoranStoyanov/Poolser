# Shared brand snapshot

Poolser's shared identity and original artwork are maintained in [poolser-app/brand](https://github.com/poolser-app/brand). This directory keeps an offline copy of its [guide](BRAND.md) and [colour tokens](colors.json). The [native reference](../BRAND.md) retains platform-specific layouts, interactions and screenshot instructions.

`manifest.json` pins a full brand commit and maps every imported file to its source path and SHA-256 hash. The original character, logo and Apple asset exports remain in their existing `Sources/` resource locations. They are vendored copies of the pinned brand version, not independent artwork sources. SwiftPM and Xcode continue to bundle these files locally; no build step downloads content or requires another checkout.

## Verify the current snapshot

From the native repository root, using Python 3.9 or later:

```bash
python3 scripts/sync-brand.py
```

This only checks local hashes. It does not access the network or update files.

## Adopt a shared brand change

Make and review shared identity changes in brand first. Check out the reviewed brand commit locally, then run from the native repository root:

```bash
git clone https://github.com/poolser-app/brand.git ../brand
git -C ../brand checkout <reviewed-full-commit-sha>
python3 scripts/sync-brand.py ../brand
python3 scripts/sync-brand.py
swift test --filter BrandArtworkTests
```

Reuse an existing brand checkout instead of cloning it again when available. The importer reads committed files from that checkout's HEAD, ignoring uncommitted source edits. It validates current local copies first and loads every source before changing any file, so a missing export does not leave a partial import. Local copy edits must be reconciled with brand before another import.

Review and commit the updated snapshot, resource copies and manifest together in a native PR. Add or remove manifest mappings explicitly when the asset inventory changes. The script copies files; it does not translate JSON tokens into SwiftUI colours or alter financial logic. A palette update also requires matching changes to `GraphitePalette.swift`, the local Collect page styling and any affected native guidance/tests in the same adoption PR.

Native screenshots and their demo generators stay here and are regenerated when the app UI changes. Brand changes must preserve light/dark appearance, accessibility, reduced motion and existing financial data semantics.
