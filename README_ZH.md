# Moa

Moa 是一个专注于 ChatGPT（原 Codex Desktop）、Claude Desktop 和本地 Provider Bridge 工作流的 macOS 菜单栏应用。

它不包含原 Moa 的 Companion 相关功能：没有桌面宠物、AI 快捷动作、提醒事项、日记、番茄钟、MCP helper、Workflow Runner、资产上传、Dashboard、皮肤和声音资源包。

## 功能范围

- ChatGPT / Codex 控制：Fast Mode、远程连接设置入口、官方账号切换、provider profile 导入导出、重新打开客户端。
- Provider Bridge：本地 loopback Responses bridge，用于把 Codex 请求转发到 Chat Completions 上游，内置 DeepSeek 和常见网关 preset。
- Claude Desktop profile：写入 Claude Desktop 3P gateway profile，并复制 Claude Code 环境变量片段。
- 用量统计：基于本地 Codex / Claude session 日志估算用量，并支持每日提醒阈值。
- Moa 数据：导出/导入完整数据包、导出脱敏诊断包，并可把数据根切换到 iCloud Drive。
- 更新检查：可从主菜单检查 GitHub Releases，下载、校验并安装匹配当前 Mac 的 DMG。

## ChatGPT 客户端兼容

客户端通过 `com.openai.codex` Bundle ID 定位，兼容 `ChatGPT.app` 和旧版 `Codex.app`，也支持 `CODEX_APP` 指定安装位置。内部配置和登录数据仍位于 `~/.codex`，或 `CODEX_HOME` 指定的目录。

新版 Fast Mode 读写 `config.toml` 的 `desktop.default-service-tier`，识别 `priority` 和 `fast`，并同步根级 `service_tier`。旧版 Codex 仍保留 JSON 状态兼容路径。切换服务商以客户端当前配置为基础，保留其他设置、未知字段和其他服务商配置。

远程连接由 ChatGPT 自己管理；菜单打开 `codex://settings/connections`，不再通过旧 feature flags 开关。旧无界面命令 `MoaApplyRemoteConnections` 会返回迁移提示；使用 `MoaOpenRemoteConnections=1` 可打开设置页。

用量读取兼容 `token_usage_record` 和旧 `token_count`，避免双重计数，分别保留缓存读取、缓存写入和每次请求的用量。费用按单次请求判断长上下文档位；GPT-6 Astra 与 GPT-5.6 内置价格参考 2026-09-07 的 [OpenAI 官方价格](https://developers.openai.com/api/docs/pricing)。这些是本地 Codex 任务的 API 标准价格估算，不是 ChatGPT 订阅账单。

## App 身份

Moa 在 bundle、数据根、provider ID 和发布产物里统一使用主 Moa 身份：

- App bundle：`Moa.app`
- Bundle ID：`com.moarliu.moa`
- SwiftPM executable product：`Moa`
- 本地数据根：`~/.moa`
- Application Support：`~/Library/Application Support/Moa`
- iCloud 数据根：`iCloud Drive/Moa`
- 数据包根目录：`MoaDataPackage/.moa`
- Provider Bridge 默认端口：`19360`
- Codex 托管 provider ID：`moa-*`
- Claude Desktop 3P config-library profile：`Moa`

Moa 在你执行切换动作时仍会写入真实的 Codex 和 Claude Desktop 配置文件；它自己的 profile 数据库、bridge token、数据包 manifest、iCloud 状态和诊断包都存放在 Moa 数据根下。

## 数据文件

Moa 的本地数据存放在：

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

Moa 每天按本地时间在 `00:20:01` 检查 `https://models.dev/api.json`；如果当时没有运行，会在该时间之后的下一次启动时补查。通过校验的新增模型和价格字段变化会合并进本地目录；自定义价格始终优先，网络或远程目录不可用时继续使用内置价格表。

开启 iCloud 存储后，Moa 会直接读写 `iCloud Drive/Moa`，不再读写 `~/.moa`。

## 构建

```bash
swift build
./scripts/run-tests.sh
CODE_SIGN_IDENTITY=- ./scripts/build-menu-bar-app.sh
```

构建结果会输出到 `Moa.app`。

生成 DMG：

```bash
CODE_SIGN_IDENTITY=- ./scripts/package-dmg.sh
```

DMG 会输出到 `dist/Moa-<release-version>-macos-<arch>.dmg`，并生成匹配的 SHA-256 文件。

## Codex 本地运行按钮

Codex app 的 Run 按钮通过以下文件接入：

- `script/build_and_run.sh`
- `.codex/environments/environment.toml`

脚本会构建 `Moa.app`，停止正在运行的 Moa 进程，然后启动新 bundle。

## 安全说明

- Provider API key 和 bridge token 只保存在本地。
- Provider Bridge 只监听 `127.0.0.1`。
- 诊断包会脱敏 auth、key、token 字段。
- 打包脚本会拒绝把 `.moa`、`.codex`、auth/config/profile 文件、环境变量文件和签名密钥打进发布包。
- Moa 不打包 `MoaMCP`，也不暴露本地 workflow tools。

候选版在 `scripts/version.env` 中使用数字 `APP_VERSION` 作为 macOS 包版本，使用 `APP_RELEASE_VERSION` 作为显示版本、GitHub 标签和 DMG 文件名。两个架构应使用相同的 `APP_BUILD`；确定构建号后，通过 `MOA_AUTO_BUMP_BUILD=0` 避免分别封包时重复递增。
