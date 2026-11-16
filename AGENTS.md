# Product design

Before changing the interface, read [docs/BRAND.md](docs/BRAND.md). Keep that reference up to date in the same change whenever the palette, typography, motion, information hierarchy or platform interactions change. Preserve the existing financial data semantics, unavailable states and accessibility behavior.

Shared identity and original artwork are maintained in [poolser-app/brand](https://github.com/poolser-app/brand). Read the [pinned shared guide](docs/brand/BRAND.md) alongside the native reference. Make shared brand changes there first, then adopt a reviewed commit using [docs/brand/README.md](docs/brand/README.md). Keep Mac/iOS/widget implementation guidance in this repository and keep builds independent of the brand repository.

<!-- shared-poolser-rules:start -->
## Shared Poolser rules

### Authorship and public text

- Do not add AI co-authors or attribution trailers (`Co-Authored-By`, `Generated-by`, `Assisted-by`, `Signed-off-by` or equivalents naming an assistant, model, bot or vendor).
- Do not mention or imply AI/tool authorship in commits, branch names, PR titles/bodies, issues, review comments, release notes, tags, changelogs, store copy, product UI, source comments, logs or public documentation. No generated-with footers, badges or robot signatures. Describe the change and its reason in the repository owner's voice.
- Tool configuration files (`AGENTS.md`, `CLAUDE.md`, `.agents/`, `.claude/` and `.githooks/`) may state these instructions and tool configuration; this exception does not allow authorship narratives or attribution.
- Use only the configured Git identity. Never override `--author`, change `user.name`/`user.email`, or set `GIT_AUTHOR_*`/`GIT_COMMITTER_*`.
- Use Conventional Commits with an imperative, lower-case summary (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`, `revert:`). Use purpose-based branch names such as `feat/native-network-support` or `chore/repository-guidance`, without tool/model/vendor prefixes.
- Before every commit, push or PR, review the message, public text and staged diff for these rules; tooling-policy files above are exempt from the text scan. Enable repository hooks with `git config core.hooksPath .githooks`. Install `gitleaks` before committing; do not bypass hooks. The commit-message hook checks attribution; the pre-commit hook checks staged secrets.

### Scope, security and verification

- Read the local README, relevant instructions and existing implementation before editing. Make the smallest complete change that solves the task, using existing helpers and dependencies. Preserve unrelated work and keep each task reviewable.
- Never commit credentials, project API keys, signing material, private wallet configuration or real/private portfolio captures. Use fictional fixtures or sanitized public-chain evidence. Do not log credential-bearing URLs or raw provider errors.
- Keep scratch plans, transcripts, temporary scripts and conversational summaries outside the repository. Commit only maintained product/engineering documentation. Source comments explain why; no chat-style or generated-code annotations, empty scaffolding or unfinished TODO stubs.
- Preserve exact financial integer math, token decimals, quote/range orientation and the difference between known zero, unavailable, partial, syncing and stale. Realized APR must remain distinct from estimated pool yield. Do not fabricate history, returns, availability or progress.
- Run checks appropriate to the change. New nontrivial financial/security/storage logic needs meaningful fixtures or tests; documentation-only changes need link/diff checks, not unrelated full application builds. Report what actually passed and any material verification gap.
- Do not silently merge unrelated/open predecessor PRs, deploy, publish or alter accounts as an implementation shortcut. Follow the task's authorized scope and explicit dependencies.

### Shared design and repository boundaries

- Before interface changes, read the local `docs/BRAND.md` and pinned shared guide when present; `poolser-app/brand` is the shared identity source. Update the owning guide alongside changes to palette, typography, motion, hierarchy or platform interaction.
- Preserve original artwork, semantic colours, numeric formatting, accessibility, light/dark appearance and reduced motion. Keep adopted brand assets/tokens local at a reviewed commit; builds and runtime must not fetch mutable brand files or require another repository checkout.
- Reuse established Poolser product labels and approved copy. Avoid invented slogans and repeated headings/field labels. The web application follows native financial meaning and hierarchy, adapting platform interactions rather than inventing a separate product design.
- Keep application-specific implementation in its owner: native for Mac/iOS/widgets, web for browser monitoring/collection, website for presentation/downloads/support/privacy, brand for shared identity/assets/tokens, `.github` for organization presentation and coordination.
<!-- shared-poolser-rules:end -->

## Native repository

- The native domain guides live in `.claude/skills/` (RPC optimization, position math, running the app, Swift and SwiftUI). Follow the relevant guide for the work being done.
- Keep SwiftPM and Xcode builds working. Chain loading, math, models, settings and shared views live in `Sources/PoolserKit`; it also builds for iOS. Guard platform-only frameworks with the existing platform checks.
- macOS application/Collect code lives in `Sources/Poolser`; add new files to the Xcode project where required. iOS apps and widget targets are Xcode-only; shared rendering and snapshot semantics stay in PoolserKit.
- Preserve App Group snapshots, Keychain/access-group boundaries and matching application/extension versions. Do not treat browser lifecycle, notifications or credential storage as equivalent to native capabilities.
- Use `swift build`, relevant tests and Xcode/platform checks when the change reaches those paths. Interface changes need actual native, sanitized reference captures, including accessibility and unavailable states.

The shared section above is canonical for the Poolser repositories. Consumers keep an identical self-contained copy and record the reviewed native revision. Review updates here first, then synchronize consumers; instructions must remain usable without a sibling checkout or runtime fetch.
