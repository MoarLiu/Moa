# Moa

Moa is a macOS menu bar app for ChatGPT (formerly Codex Desktop), Claude Desktop, ZCode, WorkBuddy, WorkBuddy AI International, and local Provider Bridge workflows.

It intentionally excludes the original Moa Companion surface: no desktop pet, AI quick actions, reminders, journal, Pomodoro, MCP helper, workflow runner, asset upload, dashboard, skins, or sounds.

## Features

- ChatGPT / Codex controls: Fast Mode, a remote connection settings shortcut, official account switching, provider profile import/export, and client reopen helpers.
- Provider Bridge: local loopback Responses bridge for Chat Completions upstreams, with DeepSeek and common gateway presets.
- Claude Desktop profiles: write Claude Desktop 3P gateway profiles and copy Claude Code environment snippets.
- WorkBuddy / WorkBuddy AI International: separate account menus and usage tabs, local logins, account enrollment and switching, rename/forget actions, and client launch helpers.
- Usage insights: local Codex, Claude, ZCode, and WorkBuddy AI summaries, model details, CSV / Markdown exports, custom prices, and configurable daily alerts.
- Moa Data: export/import data packages, export redacted diagnostics, and optionally switch the active data root to iCloud Drive.
- Updates: check GitHub Releases from the main menu, then download, verify, and install the matching macOS DMG.

## ChatGPT Client Compatibility

Moa locates the client by its `com.openai.codex` bundle identifier, supporting both `ChatGPT.app` and legacy `Codex.app` installations. `CODEX_APP` can override the application location. Configuration and credentials remain under `~/.codex`, or the directory selected by `CODEX_HOME`.

For current clients, Fast Mode reads and writes `desktop.default-service-tier` in `config.toml`, recognizes both `priority` and `fast`, and synchronizes the root `service_tier`. Legacy Codex retains its JSON state path. Provider switching starts from the live client configuration, preserving other settings, unknown fields, and unrelated provider definitions.

The remote connection menu opens `codex://settings/connections`; ChatGPT manages the connections itself. The old `MoaApplyRemoteConnections` headless command returns migration guidance. Use `MoaOpenRemoteConnections=1` to open the settings page.

Usage scanning supports both `token_usage_record` and legacy `token_count` events without counting both, and retains cache reads, cache writes, and request boundaries. Long-context prices apply per request. Version 1.3.0 includes API prices checked on 2026-10-24 for OpenAI, Claude, GLM, and WorkBuddy models, including cache and Fast parameters. See the [complete model price and source table](MODEL_PRICING.md). These are standard API price estimates for local Codex tasks, not ChatGPT subscription invoices.

## WorkBuddy

The **WorkBuddy** menu and usage tab address `com.tencent.workbuddy.mac`, using `~/Library/Application Support/CodeBuddyExtension/Data/Public/auth/workbuddy-desktop.info` and the data/keyblob under `~/.workbuddy`. Account enrollment follows the international steps below, with WorkBuddy client labels. Saving, switching, fresh sign-in, and recovery only control the domestic client.

Domestic snapshots live in `~/Library/Application Support/Moa/workbuddy-cn-accounts/accounts.json`, separate from the existing international `workbuddy-accounts` directory. Process targets, account lists, operation locks, key fingerprints, request deduplication, usage caches, custom prices, and daily alerts are edition-specific. Saved snapshots carry an edition marker; cross-edition databases and known opposite-edition auth domains are rejected. Untagged older international databases remain compatible.

Each scanner reads only its own `.workbuddy` or `.workbuddy-ai` projects/sessions logs. Edition tabs and exports contain only that edition's rows; **All Sources** retains separate source identities. Both use the public USD API reference price catalog, without sharing custom overrides or applying WorkBuddy credit/plan discounts. This is not a CNY billing estimate.

Domestic credentials use directory/file modes `700`/`600`, remain outside iCloud data moves and package/diagnostic exports, and never cause WorkBuddy AI to quit or have its auth overwritten.

## WorkBuddy AI International

The `WorkBuddy AI` menu addresses `com.workbuddy.workbuddy-ai` and only changes `~/Library/Application Support/CodeBuddyExtension/Data/Public/auth/workbuddy-desktop-ai.info`. Actions in this international menu leave the domestic edition's `workbuddy-desktop.info` untouched.

To enroll two accounts:

1. Sign into account A in WorkBuddy AI, finish active tasks, then choose **Save Current WorkBuddy AI Account** in Moa and give it a name.
2. Choose **Add Another WorkBuddy AI Account**. Moa quits the client normally, saves the current login, removes the live auth file, and opens a fresh sign-in screen without calling logout or revoking credentials.
3. Sign into account B and save it in Moa. Select either saved account in the menu to switch.

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
- Provider Bridge default port: `19360`
- Codex managed provider IDs: `moa-*`
- Claude Desktop 3P config-library profile: `Moa`

Moa still edits the real Codex and Claude Desktop configuration files when you ask it to switch profiles. Its own profile databases, bridge tokens, package manifests, iCloud state, and diagnostics are stored under the Moa data root.

## Data Files

Moa stores its local profile and recovery data under:

- `~/.moa/config.toml`
- `~/.moa/auth.json`
- `~/.moa/codex_official_accounts.json`
- `~/.moa/codex-auth/accounts/*.json`
- `~/.moa/profiles.json`
- `~/.moa/provider_bridge_profiles.json`
- `~/.moa/claude_desktop_profiles.json`
- `~/.moa/usage-pricing-overrides.json`
- `~/.moa/usage-pricing-catalog-v1.json`
- `~/.moa/backups`
- `~/Library/Application Support/Moa/usage-pricing-update-state.json`

Moa checks the [model-price-repo catalog](https://github.com/Wei-Shaw/model-price-repo), also used by Sub2API, every day at 00:20:01 local time. It catches up after a missed check and checks immediately after a source migration. Validated additions and field changes are merged into the local catalog. Custom prices remain highest priority; separately verified official corrections and the bundled snapshot remain available despite stale caches or network failures.

When iCloud storage is enabled, Moa reads and writes `iCloud Drive/Moa` directly instead of `~/.moa`.

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

- Provider API keys and bridge tokens stay local.
- The Provider Bridge listens on `127.0.0.1` only.
- Diagnostic packages redact auth, key, and token fields.
- Packaging scripts refuse to include `.moa`, `.codex`, auth/config/profile files, environment files, and signing keys.
- Moa does not bundle `MoaMCP` and does not expose local workflow tools.

For release candidates, `scripts/version.env` keeps `APP_VERSION` numeric for macOS bundle metadata and uses `APP_RELEASE_VERSION` for the displayed version, GitHub tag, and DMG filename. Both architecture builds must use the same `APP_BUILD`; set `MOA_AUTO_BUMP_BUILD=0` after choosing that build number.
