# Moa

**One macOS menu bar for your AI agents: accounts, providers, and local usage.**

[简体中文](README_ZH.md) · [Download](https://github.com/MoarLiu/Moa/releases/latest) · [Changelog](CHANGELOG.md)

Moa is a local management app for people who use multiple AI agent clients. It brings ChatGPT / Codex, Claude Desktop, Antigravity App, DeepSeek Harness, WorkBuddy, WorkBuddy AI International, and ZCode into a shared menu bar, account window, and usage overview. Each client keeps running its own conversations and tasks; Moa manages the supported account, configuration, and maintenance actions around it.

## Get Started

1. Download the latest DMG from [GitHub Releases](https://github.com/MoarLiu/Moa/releases/latest): choose `arm64` for Apple silicon or `x86_64` for an Intel Mac. macOS 12 or later is required. Matching `.sha256` files are provided.
2. Drag **Moa.app** into **Applications**, then open it. Current releases are ad-hoc signed and not notarized; macOS may require approval in **System Settings → Privacy & Security** on first launch.
3. Install and sign in to the clients you use. Open Moa's menu and choose **Accounts…** to save supported logins or configure providers. Finish active client tasks before switching accounts.
4. Open **Usage Overview…** for the supported local usage sources. Use each client's submenu for switching, launch helpers, and client-specific options.

## Supported Clients

Capabilities differ by client. Account switching preserves supported local login snapshots; provider configuration selects API endpoints. Neither implies a shared login or shared history between clients.

| Client | Accounts and providers | Local usage | Additional controls |
| --- | --- | --- | --- |
| ChatGPT / Codex | Official logins; direct Responses-compatible provider profiles; profile import/export | Tokens, cache, models, estimated API costs | Open/reopen; optional generation-rate status line |
| Claude Desktop / Claude Code | Desktop 3P gateway profiles; copy Claude Code environment snippets | Claude Code log usage and estimated API costs | Open/reopen Desktop; profile import/export |
| Antigravity App 2.x | Google login saving, enrollment, switching, rename/forget | Not available | Open/reopen; local Keychain snapshots |
| DeepSeek Harness | Login saving, enrollment, switching, rename/forget | Not available | Open/reopen; local account snapshots |
| WorkBuddy (China) | Login saving, enrollment, switching, rename/forget | Separate token, model, and estimated-cost reports | Open/reopen; independent account store |
| WorkBuddy AI International | Login saving, enrollment, switching, rename/forget | Separate token, model, and estimated-cost reports | Open/reopen; independent account store |
| ZCode | Account/provider management not available | Local database usage and estimated API costs | Open/reopen and folder helpers |

## Core Features

- **Accounts and providers:** a shared window grouped by client, one-click menu switching, provider editing and import/export where supported, progress feedback, and recovery guidance.
- **Usage and costs:** aggregate supported local sources, inspect model and cache details, export CSV / Markdown, set custom prices and daily usage alerts. These are estimates from local records and API reference prices, not subscription bills, credits, or account balances.
- **Model prices:** **Moa → Update Prices** fetches the public catalog used as Sub2API's reference. Supported USD token rates update immediately and persist. Custom prices take precedence; failed downloads preserve the previous table. Daily automatic checks are enabled.
- **Data and maintenance:** import/export Moa data packages, export redacted diagnostics, optionally use iCloud for the shared data root, and check GitHub Releases for application updates. Storage and synchronization differ by credential type; see [Security and Credential Storage](#security-and-credential-storage).

Moa's current scope is client management and local usage insight. Agent execution, conversations, and service authentication remain with the respective clients. The optional Codex status line is one client-specific feature within this broader tool.

## Everyday Workflow

- The version/build row is first in the main menu. Top-level **Accounts…** and **Usage Overview…** entries provide shared windows. Client menus retain usage summaries, refresh, and one-click switching; launch and folder helpers appear directly at the bottom of each client submenu.
- Account windows and menus share per-client progress. Switch remains the primary row action; rename, edit, and delete are available in the actions menu.
- Success and informational feedback do not steal focus. Long forms scroll while Save and Cancel remain visible, and usage insights adapt to narrower windows.
- Shortcuts: **Command-U** opens usage overview, **Command-Shift-A** opens accounts, and **Command-R** refreshes the current usage window or all menu usage sources.
- Maintenance actions, including price updates, update checks, and data management, are grouped under **Moa** in the main menu.

## ChatGPT Client Compatibility

Moa locates the client by its `com.openai.codex` bundle identifier, supporting both `ChatGPT.app` and legacy `Codex.app` installations. `CODEX_APP` can override the application location. Configuration and credentials remain under `~/.codex`, or the directory selected by `CODEX_HOME`.

Moa 1.5.0 removes Fast Mode and remote connection settings controls, including their legacy headless commands. Manage these preferences in ChatGPT itself. Existing preferences remain untouched. Provider switching starts from the live client configuration, preserving other settings, unknown fields, and unrelated provider definitions.

Usage scanning supports both `token_usage_record` and legacy `token_count` events without counting both, and retains cache reads, cache writes, and request boundaries. Long-context prices apply per request. The bundled API price table covers OpenAI, Claude, GLM, and WorkBuddy models, including cache and Fast parameters; use **Update Prices** for the latest supported catalog. See the [complete model price and source table](MODEL_PRICING.md). These are standard API price estimates for local Codex tasks, not ChatGPT subscription invoices.

### Generation-rate Status Line (Experimental)

Experimental Codex generation-rate status line: enable **Codex → Show Generation Rate (Estimated)**, finish active tasks, then choose **Status Line Settings → Reopen ChatGPT to Apply**. It is off by default. Optional controls show request tokens/context estimates, input cache hits, or use a layout below the composer. A refused quit stops the enhancement restart rather than force-terminating the client.

If the status says the client could not close, wait for this response and other active tasks to finish, quit ChatGPT with Command-Q, then use **Moa → Codex → Open Codex**. Opening from the Dock does not add Moa's enhancement arguments. Hidden quick-chat prewarm and pet windows are excluded when finding the main chat page.

The indicator estimates throughput from adjacent local usage records in the same turn, using a time-weighted average of the last three valid intervals. It includes waits and tool time and updates after usage is recorded; it is not a per-token measurement of a single streaming response. The first sample shows `--`. Context usage is the latest request's token count divided by the window recorded in the log.

Moa launches the official client with a loopback debug connection and adds an isolated display script; it does not patch the app, change provider routing, or run a proxy/HTTP service. Only the process launched by this Moa instance and a single unambiguous main page are supported. After restarting Moa, reopen the client through Moa again. `CODEX_HOME` must point to that client's actual local logs. Turning the feature off removes the display; reopen normally to remove the process-level debug listener. Isolated log, WebSocket and HTML tests cover the implementation, and a preview was manually verified with one installed client version; compatibility can vary by client version and layout.

## Antigravity App

Moa verifies the app and language-server signatures against Google's Developer ID before saving or switching logins, launching the app, and creating access controls for a missing live Keychain item. Modified, ad-hoc signed, or lookalike installations are rejected. Existing Keychain access controls are preserved; `/usr/bin/security` remains trusted when creating the live item for compatibility with the client's keyring access. This does not isolate credentials from all software running as the same macOS user.

The **Antigravity** menu targets Antigravity App 2.x (`com.google.antigravity`), with compatibility research against macOS App `2.28.0`. It manages the OAuth login in the login Keychain (`service=gemini`, `account=antigravity`). Antigravity IDE's `state.vscdb` is a separate format and is not edited. Enterprise/ADC and API-key account management are outside this adapter's scope.

1. Sign in to Antigravity with Google account A. Finish active tasks, close `agy` and Antigravity IDE extensions, then choose **Antigravity → Manage Accounts… → Save Current Login** in Moa. Give the account a recognizable name and allow Keychain access if macOS asks.
2. Choose **Add Another Account**. Moa exits Antigravity normally, saves the latest login, removes the active Keychain item and its standalone fallback token file, and reopens the Google sign-in screen. Sign in as B, then save B in Moa. This does not call Google's token-revocation endpoint or Antigravity's logout/cache-clearing flow.
3. Select A or B in the Antigravity menu. Moa exits the app, saves the outgoing login, replaces the active Keychain credential and fallback token file together, and reopens the app. Verify the displayed Google account and send a request. Rename or forget saved logins in the account window; forgetting leaves the active login unchanged.

Snapshots preserve the complete credential envelope and unknown fields under Moa's own Keychain service, `com.moa.antigravity.accounts`, without requesting iCloud Keychain synchronization. Local metadata (names, email labels when available, hashed identities, timestamps) lives in `~/Library/Application Support/Moa/antigravity-accounts/accounts.json` with directory/file modes `700`/`600`. This directory is outside data packages, diagnostics, and Moa's iCloud data-root moves. Opening menus refreshes in the background without requesting Keychain authorization. Switching or saving can request authorization; signing changes between Moa builds can require granting access again.

Google ID-token subjects identify accounts when available; otherwise a refresh-grant fingerprint identifies the saved login. If that grant changes without an ID token, Moa saves a separate entry rather than guessing which account to overwrite. Only supported OAuth envelopes are accepted, and the exact original bytes are restored. Settings and conversations remain shared and untouched; this feature does not isolate history or add usage reporting.

The standalone fallback `~/.gemini/jetski-standalone-oauth-token` is also a login source. Moa saves a distinct fallback account only if it has not already been saved; a stale fallback never overwrites an existing snapshot. Switching writes a matching complete JSON envelope, and enrollment removes both sources. If updating Keychain fails, the fallback file is restored before reopening. A failed switch to another account restores the previous pair; a failed restart of the same account retains its refreshed login in both sources so a retry cannot restore an older token. Existing `.gemini` directory permissions are retained; token files are written privately. Gemini CLI `oauth_creds.json` and CLI-specific token files are not edited. Environment-injected credentials and custom credential roots are outside the supported configuration.

Other App/CLI/extension instances can share the active login. Moa checks running executable paths before credential changes and rechecks the live value before replacement; its operation lock coordinates Moa instances only. Refused quits and detected shared writers prevent changes. Launch failures preserve credentials refreshed during startup before restoring the previous account; if recovery cannot be verified, the client stays closed with recovery guidance. Isolated tests cover these paths, metadata failures, and storage exclusion. Account enrollment and switching have been manually verified on a real Mac. Keychain authorization/ACL behavior across signing changes, actual requests from each target account, and session validity after server-side expiration or revocation remain manual acceptance checks. The adapter does not refresh tokens itself or promise an uninterrupted in-progress task.

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

## Switching, Recovery, and Usage Limits

Codex switches and active-profile edits request a graceful client quit before saving and reopening. A refused or timed-out quit stops the operation without force-terminating tasks. If a change fails and the previous configuration is confirmed available, Moa reopens a previously running client and reports the failed change. If rollback fails or the configuration cannot be verified, the client stays closed with recovery guidance. If saving succeeds but launching fails, Moa reports that the client must be opened manually. Finish active tasks and close other desktop or CLI instances sharing the same configuration directory first.

Saving the current official login stores an account snapshot without rewriting the client's credentials. Configuration and export writes support linked parent directories, preserve existing third-party directory permissions, and reject symbolic links at the destination file.

Automatic recovery packages for imports and iCloud changes stay in `~/Library/Application Support/Moa/Recovery`, with directory/file modes `700`/`600` and the latest 12 packages retained on this Mac. Cleanup continues past individual file failures and logs any failures. Manual exports keep their chosen destination. Backups previously written to Downloads are not automatically deleted: review old `Moa-Data-Rollback-*.zip` and `Moa-Data-Before-iCloud-*.zip` archives and remove them when no longer needed, because they contain unencrypted credentials.

Usage scanning bounds memory by skipping oversized records. Claude records above 8 MiB and Codex usage records above 512 KiB are omitted, so local totals can undercount these records. Larger Codex model-context records are inspected separately. History migration uses a separate reader.

The legacy `MoaApplyProfileID` environment command requests a graceful ChatGPT quit, applies the profile, and exits without reopening the client. It reports failures on standard error with a nonzero exit code. Use the menu switch when you want the client reopened automatically.

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
- `~/Library/Application Support/Moa/Recovery/*.zip` — device-local credential recovery packages, outside iCloud sync and exported data packages; directory/file modes `700`/`600`, retention target 12 packages

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

A native build updates `Moa.app`. Setting `APP_ARCH` to another architecture writes `build/macos-<arch>/Moa.app` and does not replace the native app; packaging deletes that cross-built bundle after the DMG is created. macOS 27 warns when an Intel-only app is opened on Apple silicon and says it will not open on macOS 28, so launch the native `arm64` bundle on this Mac.


## Local Run Button

Codex app run-button support is wired through:

- `script/build_and_run.sh`
- `.codex/environments/environment.toml`

The script builds `Moa.app`, stops any currently running Moa process, and launches the fresh bundle.

## Security and Credential Storage

Credential storage is client-specific; not every credential is stored in Keychain.

| Data | Storage | iCloud / data packages |
| --- | --- | --- |
| Provider API keys and saved Codex logins | Files in Moa's active data root | Synced when iCloud storage is enabled; included unencrypted in full exports and recovery packages |
| Antigravity saved logins | Local login Keychain; labels and identity metadata in Application Support | Moa does not request Keychain synchronization; excluded from Moa data exports and data-root moves |
| WorkBuddy, WorkBuddy AI International, DeepSeek snapshots | Separate local Application Support stores | Excluded from Moa data exports and data-root moves |
| Automatic recovery packages | Local Application Support/Moa/Recovery, target retention of 12 | Excluded from Moa iCloud storage and full exports; may contain unencrypted credentials |

- Moa does not upload credentials to its own server. Keep full exports and recovery packages private; only import packages from a trusted source. Schema 2 SHA-256 checks detect content mismatches, but do not authenticate the package's author or encrypt its contents.
- Sensitive configuration saves and provider profile JSON exports use atomic replacement with temporary files created as `600`; permission-setting failures stop the save. Existing client and export directory permissions are preserved; Moa-owned private directories use `700`.
- Automatic updates currently trust GitHub Releases and a SHA-256 checksum from the same source. They do not independently authenticate the publisher. Independent update signatures have not yet been deployed.
- Diagnostic packages redact auth, key, and token fields.
- Packaging scripts refuse to include `.moa`, `.codex`, `.dsh`, client login/account stores, auth/config/profile files, environment files, and signing keys.
- Moa does not bundle `MoaMCP` and does not expose local workflow tools.

For release candidates, `scripts/version.env` keeps `APP_VERSION` numeric for macOS bundle metadata and uses `APP_RELEASE_VERSION` for the displayed version, GitHub tag, and DMG filename. Both architecture builds must use the same `APP_BUILD`; set `MOA_AUTO_BUMP_BUILD=0` after choosing that build number.


## Legacy Upgrade Notes

### Provider Bridge

1.3.2 removes Provider Bridge, its local HTTP server, protocol conversion, and configuration controls. Codex providers now connect directly to OpenAI Responses-compatible endpoints. Connection tests check Responses without falling back to Chat Completions.

If you used Provider Bridge, select an existing Responses profile in the Codex menu, add the provider's Responses Base URL, or select Official Mode. Old bridge profiles are not automatically converted to direct profiles. Existing files remain on disk; 1.3.2 no longer reads the separate bridge database. Bridge entries in mixed profile databases remain stored but are hidden and excluded from profile exports; importing them asks you to add a Responses endpoint instead. Upgrading does not rewrite the live Codex configuration. Selecting a replacement updates the client configuration and reopens the client.
