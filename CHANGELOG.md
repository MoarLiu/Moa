# Changelog

## Unreleased

- Added one account-management window grouped by client, with save/enroll, rename, edit, delete, and switch actions for the appropriate account types.
- Unified account-window and menu switching for WorkBuddy and DeepSeek; account-list reads wait until switching finishes, and menu switches refresh an open account window.
- Added **Update Prices** to fetch and persist the complete Sub2API-reference catalog, apply new USD token prices without an app release, and refresh usage immediately. Failed downloads retain the previous catalog and custom prices remain independent.
- Added Grok 4.7 Build log-name matching and separate Fast/context/cache pricing; newer remote entries override offline seeds and independent scanner caches invalidate immediately after a price update.
- Added a DeepSeek menu for local DeepSeek Harness account enrollment, switching, rename/forget, and client launch helpers. Account-only credential edits preserve API keys and device/session data, coordinate writers, and roll back failed launches. Snapshots remain outside data exports and iCloud moves; real multi-account session validity requires manual verification.
- Removed the remaining Responses provider preset menu and templates. Direct provider configurations can still be added manually.

## 1.3.2 - 2026-10-26

- Removed Provider Bridge, including the local HTTP server, Responses-to-Chat Completions conversion, bridge presets, runtime controls, tokens, ports, and diagnostics.
- Removed bridge mode from the Codex menu and simplified provider configuration and profile exports to direct Responses connections.
- Codex connection tests now require a working Responses endpoint and no longer fall back to Chat Completions.
- Kept existing data files on disk, excluded retired bridge profiles from active configuration lists and profile exports, and rejected their import with migration guidance. Existing bridge users must select a Responses-compatible provider or Codex Official Mode; upgrading does not rewrite the live client configuration.

## 1.3.1 - 2026-10-25

- Prevented child-process output deadlocks, bounded discarded-output commands, and released data operations after command failures or timeouts.
- Limited Provider Bridge connections, cancelled active upstream work on stop, isolated restarts, and rejected unsupported request transfer encodings.
- Required valid SHA-256 entries in schema 2 data packages and streamed file hashing to bound memory during data operations and updates.
- Cached unchanged ZCode database queries with database/WAL change detection while recalculating current prices; avoided rewriting unchanged official account credentials on menu reads.
- Preserved provider comments and accepted usage-only upstream chunks without a choices array.
- Consolidated usage refresh scheduling, reduced idle scans, split usage modules by responsibility, and added individually discoverable SwiftPM/XCTest checks.
- Matched saved ChatGPT accounts using workspace and JWT user identities, preventing different users in a shared workspace from overwriting each other's credentials while retaining normal token refreshes.
- Removed configuration values from TOML diagnostics and omitted unparseable credential files so inline headers and multiline secrets cannot leak into diagnostic packages.
- Rejected external, escaping, cyclic, and undeclared legacy symbolic links during data import while preserving safe relative links inside the package.
- Preserved complete provider multiline strings, arrays, and neighboring tables, including array headers with inline comments, when switching configurations.
- Removed complete quoted and multiline third-party URLs and bearer tokens when restoring official mode, while retaining unrelated configuration and provider identity.
- Returned valid HTTP errors for Provider Bridge connection failures, rejected prematurely ended streams, and preserved incomplete output and tool-call status.
- Deduplicated WorkBuddy request replays by their stable identity and added fractional ISO timestamp support for both clients.
- Kept custom-price editing available for all model rows and refreshed cached prices after data imports or storage-root changes.
- Kept menu storage-state reads responsive during background exports and removed the WorkBuddy menu scope note.
- Coordinated data imports and storage moves with configuration, pricing, and cache writes; concurrent changes now return a retry message, and cached stores reload after replacement.
- Normalized quoted and dotted provider names and complete multiline scalar assignments, preserving case-sensitive selection and avoiding duplicate settings.
- Added regression checks for the reviewed account, data, streaming, usage, and price-setting boundaries.

## 1.3.0 - 2026-10-24

- Added independent WorkBuddy and WorkBuddy AI account menus and usage tabs, including account enrollment, switching, rename/forget actions, and client launch helpers.
- Isolated credential files, encryption-key bindings, operation locks, usage caches, custom prices, exports, and daily alerts between the two clients; retained compatibility with older international account snapshots.
- Preserved refreshed credentials before account changes and during failed-launch recovery, with atomic writes and protection against competing Moa instances.
- Kept device-bound account snapshots outside iCloud data moves, data exports, diagnostic packages, and release artifacts.
- Refreshed 208 API price records on 2026-10-24, added Sub2API-compatible pricing updates and WorkBuddy model aliases, and documented prices and sources in MODEL_PRICING.md.
- Added GPT-6.1 Sol / GPT-6 Luna and current Claude pricing, retained Fast/cache/context parameters, and priced ZCode context tiers per request.
- Kept independent usage requests distinct during deduplication and isolated source-read failures so other clients' reports remain available.
- Expanded regression coverage to 68 checks for account recovery, cross-client isolation, pricing, exports, and alerts.

## 1.2.0 - 2026-09-08

- Added compatibility with the renamed ChatGPT desktop app while retaining Codex data paths and legacy app discovery.
- Updated Fast Mode to use current desktop settings, recognize priority/fast tiers, and preserve recovery backups.
- Preserved live desktop preferences, unknown TOML content, and unrelated providers when switching configurations.
- Replaced obsolete remote connection toggles with a shortcut to ChatGPT connection settings.
- Added deduplicated usage-record support, cache-write accounting, and per-request long-context pricing.
- Refreshed GPT-6 Astra and GPT-5.6 prices and tracked catalog freshness per model.
- Fixed release-candidate version comparisons and kept automatic update fallback on the stable release channel.
- Added compatibility and prerelease regression coverage.

## 1.1.8 - 2026-07-12

- Fixed Codex usage statistics so inherited subagent history is not counted again.
- Stopped labeling model-less Codex usage events as GPT-5, and automatically rebuilt the local usage cache with the corrected model attribution.

## 1.1.7 - 2026-07-12

- Made Codex and Claude Desktop profile changes transactional so live configuration, account files, and selected state roll back together after a failed write.
- Preserved TOML multiline strings during structural edits, hardened recursive legacy-data migration and data-package integrity checks, and rejected invalid Provider Bridge ports and Codex account paths.
- Improved updater handoff cleanup, Provider Bridge streaming completion order, menu load-error visibility, and large ZCode usage-query output handling.
- Expanded regression coverage and made local build and test scripts reliably select a full Xcode toolchain when SwiftUI macros require it.

## 1.1.6 - 2026-07-10

- Refreshed GPT-5.6 pricing, adding Sol, Terra, and Luna with current standard, long-context, cached-input, and Priority rates.
- Added a daily 00:20:01 local-time pricing refresh from `models.dev`, with startup catch-up, validated incremental snapshots, and built-in pricing fallback.

## 1.1.5 - 2026-07-03

- Added a main-menu Check Update action backed by GitHub Releases.
- The updater selects the matching `arm64` or `x86_64` macOS DMG, verifies the `.sha256` checksum, backs up the current app, and installs the update.

## 1.1.4 - 2026-07-03

- Added a Codex history migration action that updates saved session `model_provider` values to the current `~/.codex/config.toml` provider.
- The migration checks for a current root `model_provider`, asks for confirmation, quits Codex before editing history state, and asks the user to restart Codex after completion.
- Added backups and automatic rollback for Codex session JSONL and SQLite history indexes if migration fails.
- Added regression coverage for missing provider config, JSONL/SQLite migration, non-standard JSONL skipping, and rollback on SQLite failure.

## 1.1.3 - 2026-06-26

- Renamed the app, bundle, package, data roots, Provider Bridge identifiers, release artifacts, and documentation from Moa-Lite to Moa.
- Updated the default Provider Bridge port to `19360` for the primary Moa identity.
- Renamed the GitHub repository to `MoarLiu/Moa`.

## 1.1.2 - 2026-06-26

- Show saved Codex official accounts with their email address, including renamed accounts such as `Plus(email@example.com)`.
- Added a default checked ZCode official mode item to the ZCode menu.
- Added a Codex official no-account option that writes `auth.json` in API key mode, keeps or selects a direct Codex API config, and saves the current login as an account when one is available.
- Disabled the Codex official restore button while the no-account option is selected.

## 1.1.1 - 2026-06-21

- Fixed Codex Official Mode restore so it preserves the selected `model_provider` value for session continuity.
- Removed third-party `base_url` and `experimental_bearer_token` values from the selected provider when restoring Codex Official Mode.
- Added regression coverage for restoring from direct third-party provider profiles such as `model_provider = "one"`.

## 1.1.0 - 2026-06-21

- Added a ZCode menu with usage statistics, launch/relaunch actions, and quick access to `~/.zcode`.
- Added ZCode usage scanning from the local CLI SQLite database with GLM-5.2, GLM-5.1, and GLM-5-Turbo pricing.
- Added cache hit ratio to Codex, Claude Desktop, and ZCode usage summaries and insights.
- Localized new ZCode and cache-hit UI strings in English and Simplified Chinese.

## 1.0.0

- Created Moa as an independent macOS menu bar app.
- Kept Codex, Claude Desktop, Provider Bridge, local usage insights, data package import/export, diagnostics, and iCloud data-root switching.
- Removed Companion, desktop pet, AI quick actions, reminders, journal, Pomodoro, MCP helper, workflow runner, asset upload, updater, dashboard, skins, and sounds.
- Restored trimmed English and Simplified Chinese localization bundles for the Moa menu and dialogs.
- Standardized the app identity and data paths as Moa: `Moa.app`, `com.moarliu.moa`, `~/.moa`, `iCloud Drive/Moa`, `moa-*` Codex provider IDs, and Provider Bridge port `19360`.
- Replaced legacy Moa integration tests with Moa focused core tests.
