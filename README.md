# Moa

Experimental Codex generation-rate status line: enable **Codex → Show Generation Rate (Estimated)**, finish active tasks, then choose **Status Line Settings → Reopen ChatGPT to Apply**. It is off by default. Optional controls show request tokens/context estimates, input cache hits, or use a layout below the composer. A refused quit stops the enhancement restart rather than force-terminating the client.

If the status says the client could not close, wait for this response and other active tasks to finish, quit ChatGPT with Command-Q, then use **Moa → Codex → Open Codex**. Opening from the Dock does not add Moa's enhancement arguments. Hidden quick-chat prewarm and pet windows are excluded when finding the main chat page.

The indicator estimates throughput from adjacent local usage records in the same turn, using a time-weighted average of the last three valid intervals. It includes waits and tool time and updates after usage is recorded; it is not a per-token measurement of a single streaming response. The first sample shows `--`. Context usage is the latest request's token count divided by the window recorded in the log.

Moa launches the official client with a loopback debug connection and adds an isolated display script; it does not patch the app, change provider routing, or run a proxy/HTTP service. Only the process launched by this Moa instance and a single unambiguous main page are supported. After restarting Moa, reopen the client through Moa again. `CODEX_HOME` must point to that client's actual local logs. Turning the feature off removes the display; reopen normally to remove the process-level debug listener. Isolated log, WebSocket and HTML tests cover the implementation, and a preview was manually verified with one installed client version; compatibility can vary by client version and layout.

Moa is a macOS menu bar app for ChatGPT (formerly Codex Desktop), Claude Desktop, ZCode, WorkBuddy, WorkBuddy AI International, and DeepSeek Harness workflows.

It intentionally excludes the original Moa Companion surface: no desktop pet, AI quick actions, reminders, journal, Pomodoro, MCP helper, workflow runner, asset upload, dashboard, skins, or sounds.

## Features

- ChatGPT / Codex controls: official account switching, provider profile import/export, and client reopen helpers.
- Claude Desktop profiles: write Claude Desktop 3P gateway profiles and copy Claude Code environment snippets.
- Account management: **Manage Accounts…** opens one window grouped by client. Rename, edit, or delete saved entries there; selecting an account in the menu still switches immediately.
- WorkBuddy / WorkBuddy AI International: separate account menus and usage tabs, local logins, account enrollment and switching, rename/forget actions, and client launch helpers.
- DeepSeek: save, enroll, switch, rename, and forget local DeepSeek Harness account logins, with open/reopen helpers.
- Usage insights: local Codex, Claude, ZCode, and WorkBuddy AI summaries, model details, CSV / Markdown exports, custom prices, and configurable daily alerts.
- Moa Data: export/import data packages, export redacted diagnostics, and optionally switch the active data root to iCloud Drive.
- Updates: check GitHub Releases from the main menu, then download, verify, and install the matching macOS DMG.
- Model prices: choose **Update Prices** in the main menu to download the complete public price table used as Sub2API's reference. Supported USD token rates take effect immediately, refresh open usage reports, and persist across restarts. Failed downloads keep the previous table; custom prices take precedence. Daily automatic checks remain enabled.

## 1.5.0 Interface and Interaction

- The version/build row is first in the main menu. Top-level **Accounts…** and **Usage Overview…** entries provide shared windows. Client menus retain usage summaries, refresh, and one-click switching; launch and folder helpers appear directly at the bottom of each client submenu.
- Account windows and menus share per-client progress. Switch remains the primary row action; rename, edit, and delete are available in the actions menu.
- Success and informational feedback do not steal focus. Long forms scroll while Save and Cancel remain visible, and usage insights adapt to narrower windows.
- Shortcuts: **Command-U** opens usage overview, **Command-Shift-A** opens accounts, and **Command-R** refreshes the current usage window or all menu usage sources.
- Maintenance actions, including price updates, update checks, and data management, are grouped under **Moa** in the main menu.

## Upgrading to 1.4.0

Existing account stores and custom prices are retained. Use **Manage Accounts…** in a client menu for enrollment and saved-entry management, and **Update Prices** in the main menu to refresh pricing without replacing the app. The new **DeepSeek** menu controls DeepSeek Harness; see its account-enrollment instructions below.

## Upgrading from Provider Bridge

1.3.2 removes Provider Bridge, its local HTTP server, protocol conversion, and configuration controls. Codex providers now connect directly to OpenAI Responses-compatible endpoints. Connection tests check Responses without falling back to Chat Completions.

If you used Provider Bridge, select an existing Responses profile in the Codex menu, add the provider's Responses Base URL, or select Official Mode. Old bridge profiles are not automatically converted to direct profiles. Existing files remain on disk; 1.3.2 no longer reads the separate bridge database. Bridge entries in mixed profile databases remain stored but are hidden and excluded from profile exports; importing them asks you to add a Responses endpoint instead. Upgrading does not rewrite the live Codex configuration. Selecting a replacement updates the client configuration and reopens the client.

## ChatGPT Client Compatibility

Moa locates the client by its `com.openai.codex` bundle identifier, supporting both `ChatGPT.app` and legacy `Codex.app` installations. `CODEX_APP` can override the application location. Configuration and credentials remain under `~/.codex`, or the directory selected by `CODEX_HOME`.

Moa 1.5.0 removes Fast Mode and remote connection settings controls, including their legacy headless commands. Manage these preferences in ChatGPT itself. Existing preferences remain untouched. Provider switching starts from the live client configuration, preserving other settings, unknown fields, and unrelated provider definitions.

Usage scanning supports both `token_usage_record` and legacy `token_count` events without counting both, and retains cache reads, cache writes, and request boundaries. Long-context prices apply per request. Version 1.3.0 includes API prices checked on 2026-10-24 for OpenAI, Claude, GLM, and WorkBuddy models, including cache and Fast parameters. See the [complete model price and source table](MODEL_PRICING.md). These are standard API price estimates for local Codex tasks, not ChatGPT subscription invoices.

## DeepSeek

The **DeepSeek** menu controls DeepSeek Harness (`com.deepseek.dsh`). Its account adapter targets the version-1 block YAML used by Harness `0.2.1-rc.3`. The default credential file is `~/.dsh/.credentials.yaml`; an absolute `DSH_HOME` inherited by Moa selects another Harness home. Saved accounts are bound to that credential path.

1. Sign in as account A in Harness, finish active tasks, and choose **DeepSeek → Manage Accounts…** in Moa. In the DeepSeek group, choose **Save Current Login** and give the account a recognizable name.
2. In the same group, choose **Add Another Account**. Moa exits Harness normally, saves A, removes only the account login record, and reopens Harness. Choose **Sign In** and authorize account B in the browser, then use **Save Current Login** again. Existing API keys can keep Harness in its workspace rather than its welcome screen.
3. Select A or B in the DeepSeek menu to switch. Confirm the account shown in Harness and send a request using its account provider. Rename or delete saved copies in the account window, including accounts that are no longer signed in.

Switching edits only `records.deepseek-account-platform/default`. Provider API keys, device identity, the browser-connection secret, settings, and local sessions are retained. Close other DSH instances before switching: the desktop and CLI can share a credential store. Moa uses Harness's credential writer lock and a separate account-operation lock. Refused quits prevent writes; launch failures restore the original account record while retaining unrelated changes made during startup. Unsupported or ambiguous credential formats are rejected before editing.

Account snapshots stay in `~/Library/Application Support/Moa/deepseek-accounts/accounts.json` with directory/file modes `700`/`600`. They do not enter data packages, diagnostics, or iCloud data-root moves. Forgetting a saved entry leaves Harness signed in. Do not use Harness **Log Out** to enroll another account, because it revokes the server session. Expired or revoked sessions require signing in and saving again. Local fixture tests cover switching and rollback; real A → B → A login and inference remain a manual acceptance check, including whether the server retains both sessions on one device. This module does not add DeepSeek usage reporting.

## WorkBuddy

The **WorkBuddy** menu and usage tab address `com.tencent.workbuddy.mac`, using `~/Library/Application Support/CodeBuddyExtension/Data/Public/auth/workbuddy-desktop.info` and the data/keyblob under `~/.workbuddy`. Account enrollment follows the international steps below, with WorkBuddy client labels. Saving, switching, fresh sign-in, and recovery only control the domestic client.

Domestic snapshots live in `~/Library/Application Support/Moa/workbuddy-cn-accounts/accounts.json`, separate from the existing international `workbuddy-accounts` directory. Process targets, account lists, operation locks, key fingerprints, request deduplication, usage caches, custom prices, and daily alerts are edition-specific. Saved snapshots carry an edition marker; cross-edition databases and known opposite-edition auth domains are rejected. Untagged older international databases remain compatible.

Each scanner reads only its own `.workbuddy` or `.workbuddy-ai` projects/sessions logs. Edition tabs and exports contain only that edition's rows; **All Sources** retains separate source identities. Both use the public USD API reference price catalog, without sharing custom overrides or applying WorkBuddy credit/plan discounts. This is not a CNY billing estimate.

Domestic credentials use directory/file modes `700`/`600`, remain outside iCloud data moves and package/diagnostic exports, and never cause WorkBuddy AI to quit or have its auth overwritten.

## WorkBuddy AI International

The `WorkBuddy AI` menu addresses `com.workbuddy.workbuddy-ai` and only changes `~/Library/Application Support/CodeBuddyExtension/Data/Public/auth/workbuddy-desktop-ai.info`. Actions in this international menu leave the domestic edition's `workbuddy-desktop.info` untouched.

To enroll two accounts:

1. Sign into account A in WorkBuddy AI, finish active tasks, then choose **WorkBuddy AI → Manage Accounts…** in Moa. In the WorkBuddy AI group, choose **Save Current Login** and give it a name.
2. Choose **Add Another Account** in that group. Moa quits the client normally, saves the current login, removes the live auth file, and opens a fresh sign-in screen without calling logout or revoking credentials.
3. Sign into account B and use **Save Current Login** again. Select either saved account in the menu to switch; rename or delete saved copies in the account window.

Moa captures credentials after the client exits, preserving rotated refresh tokens, encrypted envelopes, and unknown fields. A file lock serializes account operations across Moa instances. Switching also saves an unrecognized outgoing account automatically. A refused or timed-out quit stops the operation; failed launches retain any newly refreshed target credentials before restoring the previous login file. Forgetting a saved account only removes Moa's copy and leaves the live login intact. Avoid **Log Out** in WorkBuddy AI because it may invalidate saved credentials.

Snapshots stay in `~/Library/Application Support/Moa/workbuddy-accounts/accounts.json` with directory mode `700` and file mode `600`. This device-local directory is excluded from Moa's iCloud data-root moves, data packages, and diagnostics. Moa neither copies nor decrypts `~/.workbuddy-ai/keyblob`; its fingerprint binds encrypted snapshots to the local key. After replacing keyblob, sign in and save accounts again. Do not manually sync these snapshots to cloud storage.

Usage scans `~/.workbuddy-ai/projects/**/*.jsonl` and `sessions/**/*.jsonl` read-only, combining recorded requests from all local accounts, excluding duplicate copies and replayed context under `subagents`. It does not edit conversation databases or share conversations across accounts. Today's and lifetime tokens, cache hit percentage, and model details use the Codex reporting interface. Costs use known model API reference prices or custom overrides, **not WorkBuddy credits, plan balances, or official invoices**. Unpriced models retain their token counts and are flagged in details; their costs are excluded, so estimated totals and monetary alerts may understate complete usage. Calls absent from local logs cannot be counted.

If a client's logs cannot be read, the usage window reports that source's error and continues displaying the other clients' data. WorkBuddy deduplication preserves upstream request or event IDs so independent calls with identical timestamps and token counts remain distinct. Only records without IDs fall back to a timestamp, model, and token-count fingerprint.

## App Identity

Moa uses the primary Moa app identity throughout the bundle, data roots, provider IDs, and release artifacts:

- App bundle: `Moa.app`
- Bundle identifier: `com.moarliu.moa`
- SwiftPM executable product: `Moa`
- Local data root: `~/.moa`
- Application Support root: `~/Library/Application Support/Moa`
- iCloud data root: `iCloud Drive/Moa`
- Data package root: `MoaDataPackage/.moa`
- Codex managed provider IDs: `moa-*`
- Claude Desktop 3P config-library profile: `Moa`

Moa still edits the real Codex and Claude Desktop configuration files when you ask it to switch profiles. Its own profile databases, package manifests, iCloud state, and diagnostics are stored under the Moa data root.

## 1.6.1 Maintenance Update

Codex switches and active-profile edits request a graceful client quit before saving and reopening. A refused or timed-out quit stops the operation without force-terminating tasks. If saving succeeds but launching fails, Moa reports that the client must be opened manually. Finish active tasks and close other desktop or CLI instances sharing the same configuration directory first.

Automatic recovery packages for imports and iCloud changes stay in `~/Library/Application Support/Moa/Recovery`, with directory/file modes `700`/`600` and the latest 12 packages retained on this Mac. Manual exports keep their chosen destination. Backups previously written to Downloads are not automatically deleted.

## Data Files

Moa stores its local profile and recovery data under:

- `~/.moa/config.toml`
- `~/.moa/auth.json`
- `~/.moa/codex_official_accounts.json`
- `~/.moa/codex-auth/accounts/*.json`
- `~/.moa/profiles.json`
- `~/.moa/claude_desktop_profiles.json`
- `~/.moa/usage-pricing-overrides.json`
- `~/.moa/usage-pricing-catalog-v1.json`
- `~/.moa/backups`
- `~/Library/Application Support/Moa/usage-pricing-update-state.json`

Moa checks the [model-price-repo catalog](https://github.com/Wei-Shaw/model-price-repo), also used by Sub2API, every day at 00:20:01 local time. It catches up after a missed check and checks immediately after a source migration. Validated additions and field changes are merged into the local catalog. Custom prices remain highest priority; separately verified official corrections and the bundled snapshot remain available despite stale caches or network failures.

When iCloud storage is enabled, Moa reads and writes `iCloud Drive/Moa` directly instead of `~/.moa`.

If both the outer and nested legacy iCloud directories contain data, Moa preserves both without automatically merging them, so deleted entries are not restored. Review the nested directory before changing the data. Before migrating Codex history, close all ChatGPT and Codex desktop and CLI instances and keep them closed until migration finishes. Moa cannot prevent another process from starting during migration.

## Build

```bash
swift build
swift test
./scripts/run-tests.sh
CODE_SIGN_IDENTITY=- ./scripts/build-menu-bar-app.sh
```

The app bundle is written to `Moa.app`.

`swift test` runs the checks as individual XCTest cases in the default debug configuration; they are also discoverable in Xcode. The script retains the standalone runner and checks that every app source is compiled. Use full Xcode (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`) if the selected command-line tools cannot expand SwiftUI macros. Run the suite serially because pricing and fault-injection checks use shared test state.

To create a DMG:

```bash
CODE_SIGN_IDENTITY=- ./scripts/package-dmg.sh
```

The DMG is written to `dist/Moa-<release-version>-macos-<arch>.dmg` with a matching SHA-256 file.

## Local Run Button

Codex app run-button support is wired through:

- `script/build_and_run.sh`
- `.codex/environments/environment.toml`

The script builds `Moa.app`, stops any currently running Moa process, and launches the fresh bundle.

## Security Notes

- Provider API keys and Codex login sessions are stored in Moa data files; Moa does not upload them to its own server. Enabling iCloud storage syncs these files through iCloud Drive. Data exports and automatic recovery packages contain these credentials without encryption and must be kept private. Separate WorkBuddy and DeepSeek account stores remain excluded from sync and exports.
- Sensitive configuration saves use atomic replacement with temporary files created as `600`; permission-setting failures stop the save.
- Automatic updates currently trust GitHub Releases and a SHA-256 checksum from the same source. They do not independently authenticate the publisher. Independent update signatures have not yet been deployed.
- Diagnostic packages redact auth, key, and token fields.
- Packaging scripts refuse to include `.moa`, `.codex`, `.dsh`, client login/account stores, auth/config/profile files, environment files, and signing keys.
- Moa does not bundle `MoaMCP` and does not expose local workflow tools.

For release candidates, `scripts/version.env` keeps `APP_VERSION` numeric for macOS bundle metadata and uses `APP_RELEASE_VERSION` for the displayed version, GitHub tag, and DMG filename. Both architecture builds must use the same `APP_BUILD`; set `MOA_AUTO_BUMP_BUILD=0` after choosing that build number.
