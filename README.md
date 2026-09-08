# Moa

Moa is a focused macOS menu bar app for ChatGPT (formerly Codex Desktop), Claude Desktop, and local Provider Bridge workflows.

It intentionally excludes the original Moa Companion surface: no desktop pet, AI quick actions, reminders, journal, Pomodoro, MCP helper, workflow runner, asset upload, dashboard, skins, or sounds.

## Features

- ChatGPT / Codex controls: Fast Mode, a remote connection settings shortcut, official account switching, provider profile import/export, and client reopen helpers.
- Provider Bridge: local loopback Responses bridge for Chat Completions upstreams, with DeepSeek and common gateway presets.
- Claude Desktop profiles: write Claude Desktop 3P gateway profiles and copy Claude Code environment snippets.
- Usage insights: local Codex and Claude usage summaries with configurable daily alerts.
- Moa Data: export/import data packages, export redacted diagnostics, and optionally switch the active data root to iCloud Drive.
- Updates: check GitHub Releases from the main menu, then download, verify, and install the matching macOS DMG.

## ChatGPT Client Compatibility

Moa locates the client by its `com.openai.codex` bundle identifier, supporting both `ChatGPT.app` and legacy `Codex.app` installations. `CODEX_APP` can override the application location. Configuration and credentials remain under `~/.codex`, or the directory selected by `CODEX_HOME`.

For current clients, Fast Mode reads and writes `desktop.default-service-tier` in `config.toml`, recognizes both `priority` and `fast`, and synchronizes the root `service_tier`. Legacy Codex retains its JSON state path. Provider switching starts from the live client configuration, preserving other settings, unknown fields, and unrelated provider definitions.

The remote connection menu opens `codex://settings/connections`; ChatGPT manages the connections itself. The old `MoaApplyRemoteConnections` headless command returns migration guidance. Use `MoaOpenRemoteConnections=1` to open the settings page.

Usage scanning supports both `token_usage_record` and legacy `token_count` events without counting both, and retains cache reads, cache writes, and request boundaries. Long-context prices apply per request. Built-in GPT-6 Astra and GPT-5.6 prices use [official OpenAI pricing](https://developers.openai.com/api/docs/pricing) checked on 2026-09-07. These are standard API price estimates for local Codex tasks, not ChatGPT subscription invoices.

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

Moa checks `https://models.dev/api.json` every day at 00:20:01 local time. If the app was not running then, it catches up on the next launch after that time. Validated additions and field changes are merged into the local catalog; custom prices remain highest priority, and the built-in table remains available when the network or remote catalog is unavailable.

When iCloud storage is enabled, Moa reads and writes `iCloud Drive/Moa` directly instead of `~/.moa`.

## Build

```bash
swift build
./scripts/run-tests.sh
CODE_SIGN_IDENTITY=- ./scripts/build-menu-bar-app.sh
```

The app bundle is written to `Moa.app`.

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
