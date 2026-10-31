# Changelog

## 1.6.6 - 2026-11-01

- Suppress legacy login-Keychain authorization windows during passive Antigravity menu refreshes. Serialize Keychain UI policy changes with account reads and writes, and restore the previous policy on errors.
- Use the existing local code signing identity consistently for builds, the Run button, smoke checks, and DMG packaging. Fail when the identity is missing or ambiguous instead of silently switching to ad-hoc signing.
- Verify certificate-signed updates against the installed app's designated requirement. Keep Gatekeeper checks for Developer ID and legacy ad-hoc transitions, and reject a certificate change or ad-hoc downgrade.
- Add explicit maintenance to replace stale Moa access entries in Antigravity Keychain items while retaining other access controls and leaving credential data untouched.
- Upgrade note: install this first certificate-signed release manually from its DMG when upgrading from an ad-hoc-signed version. Local signing is not Developer ID signing or notarization; macOS can require first-launch approval, and active Keychain operations can still require authorization after a rebuild.

## 1.6.5 - 2026-10-30

- Present Moa as a macOS manager for multiple AI agent clients. Reorganize English and Chinese guides around installation, per-client capabilities, account/provider management, and local usage.
- Clarify which credentials use Keychain, which files can sync through iCloud or appear in unencrypted data packages, and what checksum validation guarantees.
- Verify Google Developer ID signatures for Antigravity App and its language server before account changes, app launches, and creation of live Keychain access controls. Reject modified or lookalike installations with recovery guidance.
- Isolate Codex status-line menu and lifecycle state on the main actor while keeping log scanning on the background worker. Name scan limits and enforce the session-path cache bound.
- Add installation-trust regression coverage and retain the existing account-recovery, response-validation, and incremental-reader checks.
- Stage DMGs in a temporary directory and clean it on exit, keeping local macOS permission metadata out of installers.

## 1.6.4 - 2026-10-30

- Prevent stale Antigravity fallback logins from overwriting existing saved accounts during saving, switching, or enrollment.
- Preserve refreshed Antigravity credentials when restarting the same account fails, so retrying does not restore an older token.
- Validate Codex Responses and Claude Messages connection-test results. HTML login pages, mismatched protocols, and failed API responses no longer report success; invalid successful-HTTP responses do not trigger another potentially billable probe. Valid token-limited Responses results remain supported.
- Consolidate connection-test endpoint rules, add regression coverage, and update English and Chinese messages and account recovery guidance.

## 1.6.3 - 2026-10-29

- Keep the app launched on Apple silicon native. Cross-architecture packaging no longer replaces `Moa.app` with an Intel-only build, which macOS 27 warns will not open on macOS 28.
- Add Antigravity App 2.x account saving, enrollment, switching, rename/forget, and launch helpers to the menu and shared account window. Keep credential snapshots in the local Keychain, preserve outgoing refreshes, and recover failed launches without editing settings or conversation data.
- Detect other Antigravity login writers before credential changes. Refresh account indicators in the background without Keychain prompts; keep account metadata outside data packages, diagnostics, and iCloud data-root moves.

## 1.6.2 - 2026-10-29

- Place the inline Codex generation-rate indicator to the right of the permission selector in the composer toolbar.
- Recover failed Codex switches by reopening a previously running client only after the previous configuration is confirmed available. Keep the client closed and explain recovery when rollback fails or state is uncertain; preserve both write and launch errors.
- Support symbolic links to configuration directories while preserving existing Codex, Claude Desktop, and export directory permissions. Keep sensitive files private from creation, reject destination-file links, and include paths in file errors.
- Save current official logins without rewriting or rolling back the client's auth file, preserving credentials refreshed while an account snapshot is saved.
- Apply private atomic writes to provider profile JSON exports and continue recovery-package maintenance after individual file failures.
- Preserve exact-limit CRLF log records, stop endpoint fallback after probe cancellation, and record enhancement launch errors.
- Complete English and Chinese error translations, check localization key coverage, repair build-recovery fixtures, and document recovery files, old Downloads backups, usage limits, and legacy headless behavior.

## 1.6.1 - 2026-10-28

- Quit Codex gracefully before applying account or provider changes from menus and account management. Refused quits stop writes, and launch failures report whether configuration was already saved.
- Corrected the Responses connection probe token budget and retained the original HTTP 400 error instead of trying a different endpoint; limited displayed error text.
- Bounded Codex and Claude usage-scanner JSONL line buffers and removed repeated scans of long lines while preserving Codex model context and following usage records.
- Moved automatic data-recovery packages to a private, device-local directory with a 12-package retention limit. Manual data-package exports retain their selected location and use private file permissions.
- Created sensitive configuration files with private permissions before writing and propagated permission failures. Clarified credentials in iCloud storage and unencrypted data packages, as well as the current update trust boundary.

## 1.6.0 - 2026-10-27

- Added an opt-in Codex generation-rate status line with incremental local usage reading, mirrored-event deduplication, optional request/context and cache metrics, and a below-composer compatibility layout.
- Added a loopback-only enhancement launch mode and isolated display script, with graceful restart, verified launch ownership, timeout recovery and stale-display cleanup. Provider routing and historical billing calculations remain independent.
- Added log replay, local WebSocket and isolated HTML tests. The status line was also manually verified in one installed client version; compatibility varies by client version and layout.
- Clarified recovery after a refused client quit, allowed more time for graceful shutdown, excluded auxiliary prewarm/overlay pages, and supported composer placement markers on inner forms.
- Displayed the input cache hit rate to two decimal places.

## 1.5.1 - 2026-10-27

- Hardened Codex history migration with client-process checks, consistent SQLite backups, transactional index updates, and conflict-aware rollback. Keep all Codex instances closed until migration finishes.
- Preserved unrelated provider definitions, rejected unsupported inline provider tables before writing, and rolled back failed edits and account deletions.
- Prevented legacy iCloud migration from repeatedly restoring deleted data or re-enabling storage. Ambiguous nested legacy data is retained for manual review.
- Redacted credentials embedded in diagnostic URLs, validated exported links, and kept existing archives intact when export fails.
- Waited for the old app before installing updates and restored or retained the previous app with a failure log when installation fails.
- Validated custom prices without losing precision, invalidated stale connection results, and repaired usage and pricing cache recovery and model redirects.
- Added regression coverage and included SwiftPM interaction tests in the release smoke checks.

## 1.5.0 - 2026-10-26

- Kept the version/build row first in the main menu and added top-level account management and usage overview entries. Client menus retain usage summaries and one-click account switching, with launch, folder, and migration helpers listed directly at the bottom. Maintenance actions are grouped under Moa.
- Removed Fast Mode and remote connection settings controls, their preference-editing implementations, and legacy headless commands. Client launch/quit helpers remain independent; existing client preferences and usage-price calculations are preserved.
- Shared per-client operation state between account windows and menu actions, with visible progress, duplicate-operation protection, and recovery after completion or failure. Reopening account management from a client always locates that client's group.
- Kept Switch as the primary account-row action and grouped rename, edit, and delete under an accessible actions menu. Added guidance for empty account lists and unavailable login-saving actions.
- Replaced custom usage-refresh rows with native menu items supporting highlighting, keyboard navigation, and a clear refreshing state. Added Command-U for usage overview, Command-Shift-A for accounts, and Command-R for usage refresh.
- Replaced informational and success dialogs with inline feedback or a nonactivating menu-bar banner. Confirmations and important failures retain explicit dialogs.
- Made glass forms readable in dark appearance, shared semantic button colors and disabled styling, and kept form headers and action buttons visible while long content scrolls. Validation messages scroll into view.
- Adapted the usage window to smaller screens with a compact source picker, two-row toolbar, wrapping summary cards, and a horizontally scrollable detail table.
- Separated current storage/mode status from the actions that change it. Kept menu account switching immediate.
- Built app bundles in isolated staging directories, retained the previous app until promotion succeeds, and restored it after a failed replacement. Failed restores preserve a recoverable backup.

## 1.4.1 - 2026-10-26

- Fixed glass-form buttons. Save, Cancel, and the other modal actions now run immediately. Borderless glass forms no longer drag from the background, because that drag handling swallowed button clicks.

## 1.4.0 - 2026-10-26

- Matched Codex account deletion against the actual client login, preserving unsaved and signed-out sessions when deleting stale selections. Profile edits recheck and apply the current selection under the store lock, with live-edit confirmation based on the current state.
- Enabled Escape to close focused glass forms and background dragging for borderless form panels.
- Excluded DeepSeek credential files and saved account stores from source tracking and release packaging.
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
