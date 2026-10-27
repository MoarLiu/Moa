# Moa

Moa 是一个支持 ChatGPT（原 Codex Desktop）、Claude Desktop、ZCode、WorkBuddy、WorkBuddy AI 国际版及 DeepSeek Harness 工作流的 macOS 菜单栏应用。

它不包含原 Moa 的 Companion 相关功能：没有桌面宠物、AI 快捷动作、提醒事项、日记、番茄钟、MCP helper、Workflow Runner、资产上传、Dashboard、皮肤和声音资源包。

## 功能范围

- ChatGPT / Codex 控制：官方账号切换、provider profile 导入导出、重新打开客户端。
- Claude Desktop profile：写入 Claude Desktop 3P gateway profile，并复制 Claude Code 环境变量片段。
- 账号管理：各客户端菜单的「管理账号…」打开同一个按客户端分组的窗口，在其中重命名、编辑或删除已保存条目；菜单里点击账号仍会立即切换。
- WorkBuddy / WorkBuddy AI 国际版：各有独立菜单和用量 Tab，分别保存本机登录态、添加和切换账号、重命名或删除已保存账号，并正常退出和重启对应客户端。
- DeepSeek：保存、添加、切换、重命名和忘记本机 DeepSeek Harness 账号，并提供打开和重启入口。
- 用量统计：基于本地 Codex / Claude / ZCode / WorkBuddy AI 日志估算用量，提供模型明细、CSV / Markdown 导出、自定义价格和每日提醒阈值。
- Moa 数据：导出/导入完整数据包、导出脱敏诊断包，并可把数据根切换到 iCloud Drive。
- 更新检查：可从主菜单检查 GitHub Releases，下载、校验并安装匹配当前 Mac 的 DMG。
- 价格热更新：主菜单点击「更新价格」，即可获取 Sub2API 参考的完整公开价格目录。支持的美元 Token 价格立即生效，自动刷新已打开的用量明细，并在重启后保留。下载失败继续使用原价格，自定义价格始终优先；每天自动检查仍保留。

## 1.5.0 界面与交互改进

- 主菜单顶部显示版本和构建号，并提供“账号管理…”和“用量总览…”，各客户端仍保留用量摘要、刷新和一键切换；打开客户端、文件夹等辅助动作直接列在各客户端二级菜单底部，不再折叠。
- 账号操作在菜单与窗口共享进行中状态；账号行保留“切换”，重命名、编辑、删除归入操作菜单。
- 成功与普通信息使用不抢焦点的提示，长表单正文可滚动且保存、取消始终可见；用量窗口支持较窄窗口。
- 快捷键：`⌘U` 用量总览、`⌘⇧A` 账号管理、`⌘R` 刷新当前用量窗口（其他场景刷新各来源用量）。
- 维护入口位于主菜单的“Moa”子菜单，包括价格更新、更新检查与数据管理。

## 1.4.0 升级说明

原有账号库和自定义价格继续保留。请在客户端菜单中通过「管理账号…」保存或管理账号，在主菜单点击「更新价格」即可刷新价格，无需替换应用。新增「DeepSeek」菜单用于 DeepSeek Harness，账号录入步骤见下文。

## 从 Provider Bridge 升级

1.3.2 移除了 Provider Bridge、本地 HTTP 服务、协议转换和相关配置入口。Codex 服务商现在直接使用支持 OpenAI Responses 的端点；连接测试只验证 Responses，不再回退到 Chat Completions。

如果此前使用 Provider Bridge，请在 Codex 菜单中选择已有的 Responses 配置，或添加服务商提供的 Responses Base URL；也可以选择官方模式。旧桥接配置不会自动转换为直连配置。旧配置文件保留在磁盘，1.3.2 不再读取独立桥接配置库；混合配置库中的桥接项仍保留在本地，但不再显示或导出，导入此类配置会提示重新添加 Responses 端点。升级本身不会改写当前 Codex 配置，完成上述选择后才会更新客户端配置并重新打开客户端。

## ChatGPT 客户端兼容

客户端通过 `com.openai.codex` Bundle ID 定位，兼容 `ChatGPT.app` 和旧版 `Codex.app`，也支持 `CODEX_APP` 指定安装位置。内部配置和登录数据仍位于 `~/.codex`，或 `CODEX_HOME` 指定的目录。

Moa 1.5.0 移除了快速模式和远程连接设置入口、对应实现及旧无界面命令。这些偏好由 ChatGPT 自己管理；已有设置保留。切换服务商以客户端当前配置为基础，保留其他设置、未知字段和其他服务商配置。

用量读取兼容 `token_usage_record` 和旧 `token_count`，避免双重计数，分别保留缓存读取、缓存写入和每次请求的用量。费用按单次请求判断长上下文档位；1.3.0 使用 2026-10-24 核对的 API 价格快照，覆盖 OpenAI、Claude、GLM 及 WorkBuddy 模型，并保留缓存与 Fast 参数；详见[完整模型价格与来源](MODEL_PRICING.md)。这些是本地 Codex 任务的 API 标准价格估算，不是 ChatGPT 订阅账单。

### 生成速率状态栏（实验功能）

在 Moa 的 **Codex → 显示生成速率（估算）** 开启，再在 **状态栏设置 → 重新打开 ChatGPT 以应用** 正常重开客户端。请先结束活动任务；客户端拒绝退出时会停止操作，不会为开启此功能强制终止。也可开启请求 Token、上下文估计和输入缓存命中率；footer 不兼容时可选择“在输入框下方显示（兼容布局）”。此功能默认关闭。

如果状态提示无法关闭或请手动退出，先等待当前回复和其他活动任务结束，在 ChatGPT 按 `⌘Q` 完成退出，再选择 **Moa → Codex → 打开 Codex**，确保本次启动带入增强参数。隐藏的快捷聊天预热窗口和宠物窗口不计作额外主聊天页面。

状态栏读取当前聊天的本地日志，以同一轮相邻记录的输出 Token 增量除以时间间隔，再对最近三个有效区间按时间加权，显示 `~80 t/s`。它包含等待与工具执行时间，用量写入后才更新，不是单次回答逐 Token 的精确解码速度。第一条记录显示 `--`；切换会话、模型或轮次会重新采样。上下文百分比是最近请求用量除以日志中的窗口大小，不是下一次请求的精确上下文。

增强模式会让 Moa 以本机回环调试参数启动官方客户端，并通过隔离的页面脚本添加状态栏；不修改安装文件、账号或供应商请求路径，不启动代理或 HTTP 服务。只连接 Moa 本次启动的进程，目前只接受唯一的主聊天页面；多窗口、远程聊天或无法识别的页面会显示不可用状态。Moa 重新启动后需再次通过 Moa 重开客户端。`CODEX_HOME` 必须对应实际客户端的日志目录，否则显示未找到记录。

关闭后会移除显示并停止采集；再次正常重开客户端才能撤掉进程级调试监听。Moa 意外退出后，页面脚本租约到期会自行移除。日志、WebSocket 协议与隔离 HTML 页面已有自动测试，预览版也已在一个客户端版本上实测显示；其他客户端版本和布局的兼容性可能不同。

## DeepSeek

「DeepSeek」菜单控制 DeepSeek Harness（`com.deepseek.dsh`）。账号适配针对 Harness `0.2.1-rc.3` 使用的 version 1 块式 YAML。默认凭据文件为 `~/.dsh/.credentials.yaml`；Moa 继承的绝对路径 `DSH_HOME` 可指定其他 Harness 目录，已保存账号与该凭据路径绑定。

1. 在 Harness 登录账号 A，结束正在运行的任务，然后在 Moa 选择「DeepSeek → 管理账号…」。在 DeepSeek 分组点击「保存当前登录」，填写便于识别的名称。
2. 在同一分组点击「再添加一个账号」。Moa 正常退出 Harness，保存 A，仅移除账号登录记录后重新打开客户端。请选择登录，在浏览器中授权账号 B，再回到 Moa 点击「保存当前登录」。保留的 API Key 可能使客户端直接进入工作区，此时从客户端的登录入口继续。
3. 在 DeepSeek 菜单点击 A 或 B 切换，确认 Harness 显示的账号，并使用账号供应商实际发送一次请求。账号管理窗口可重命名或删除所有副本，包括当前未登录的账号。

切换仅修改 `records.deepseek-account-platform/default`，保留 API Key、设备标识、浏览器连接凭据、设置和本地会话。切换前请关闭其他 DSH 实例，桌面端和 CLI 可能共享凭据文件。Moa 使用 Harness 的凭据写入锁及独立账号操作锁；客户端拒绝退出时停止写入，启动失败时只恢复原账号记录，并保留启动期间其他字段的更新。无法确认的凭据格式会在编辑前被拒绝。

账号副本保存在 `~/Library/Application Support/Moa/deepseek-accounts/accounts.json`，目录/文件权限为 `700` / `600`，不进入数据包、诊断包或 iCloud 数据根迁移。忘记副本不会退出 Harness 当前登录。添加账号时不要使用 Harness 的「退出登录」，它会向服务器注销会话；过期或已注销的登录态需要重新登录并保存。隔离测试覆盖本地切换和回滚；真实 A → B → A 登录、模型请求及服务器是否保留同设备的两个会话，仍需人工验收。本模块暂不提供 DeepSeek 用量统计。

## WorkBuddy

菜单中的「WorkBuddy」和用量洞察中的同名 Tab 专门管理 `com.tencent.workbuddy.mac`。登录文件为 `~/Library/Application Support/CodeBuddyExtension/Data/Public/auth/workbuddy-desktop.info`，数据与密钥来自 `~/.workbuddy`。首次添加多个账号的流程与下方国际版一致，按钮会显示 WorkBuddy 名称；保存、切换、添加新登录及失败回滚都只操作国内版客户端。

国内版账号快照保存在 `~/Library/Application Support/Moa/workbuddy-cn-accounts/accounts.json`，与国际版的 `workbuddy-accounts` 分开；两边的操作锁、加密密钥指纹、账号列表、请求去重、统计缓存、自定义价格和每日提醒也分别管理。保存的快照带有客户端标记，跨版账号库或已知另一版本的登录域会被拒绝。现有未带标记的国际版账号库仍然兼容。

国内版只扫描 `~/.workbuddy/projects/**/*.jsonl` 与该目录下的 `sessions/**/*.jsonl`，国际版继续读取 `~/.workbuddy-ai`。各自 Tab 和导出只包含对应来源；「全部来源」汇总时仍保留两个独立来源，不合并同名模型的两版明细。两边共用公开的美元 API 参考价格目录，但不会继承对方的自定义价格，也不按 WorkBuddy 积分或免费倍率折算。这里不是人民币账单估算。

国内版快照同样使用 `700` / `600` 权限，不随 Moa 数据根搬入 iCloud，也不进入数据包或诊断包。切换国内版不会退出或重写 WorkBuddy AI。

## WorkBuddy AI 国际版

菜单中的 `WorkBuddy AI` 对应国际版 `com.workbuddy.workbuddy-ai`。该国际版入口只操作 `~/Library/Application Support/CodeBuddyExtension/Data/Public/auth/workbuddy-desktop-ai.info`，不修改国内版 `workbuddy-desktop.info`。

首次添加两个账号：

1. 在 WorkBuddy AI 登录账号 A，结束正在运行的任务，在 Moa 选择「WorkBuddy AI → 管理账号…」，然后在 WorkBuddy AI 分组点击「保存当前登录」，填写便于识别的名称。
2. 在同一分组点击「再添加一个账号」。Moa 正常退出客户端，保存当前登录态，移除当前登录文件后打开新的登录页；这不会调用退出登录或撤销凭证。
3. 登录账号 B，再点击「保存当前登录」。之后点击菜单中的账号即可切换，在账号管理窗口重命名或删除已保存副本。

保存和切换都在客户端退出后读取最新凭证，保留 Refresh Token 和整个加密信封。跨 Moa 实例的文件锁会阻止多个副本同时修改账号。切换时会先保存实际使用中的账号；尚未命名的账号会自动保存，避免丢失。客户端未能正常退出时停止操作，启动失败时先保留目标账号可能已刷新的凭证，再恢复原登录文件。删除已保存账号只删除 Moa 的副本，保留客户端的当前登录态。不要在客户端中使用「退出登录」，否则此前保存的凭证可能失效。

快照保存在 `~/Library/Application Support/Moa/workbuddy-accounts/accounts.json`，目录权限 `700`、文件权限 `600`。该目录固定保留在本机，不随 Moa 数据根切换至 iCloud，不进入完整数据包或诊断包。Moa 不复制或解密 `~/.workbuddy-ai/keyblob`，并检查其指纹；更换 keyblob 后需重新登录和保存账号。请勿手动把快照同步到网盘。

用量只读扫描 `~/.workbuddy-ai/projects/**/*.jsonl` 和 `sessions/**/*.jsonl`，汇总本机所有账号已记录的调用，排除重复副本和 `subagents` 中重放的上下文。它不修改会话数据库，也不共享不同账号的会话。今日/累计 Token、缓存命中率和模型明细采用与 Codex 相同的展示口径；费用使用已知模型的 API 参考价格或自定义价格，**不是 WorkBuddy 积分、套餐余额或官方账单**。未定价模型仅计入 Token，会在明细中标出，并排除其费用；因此费用与每日金额提醒可能低于完整用量。日志未记录的调用无法统计。

某个客户端的日志读取失败时，用量窗口会显示对应错误并继续展示其他客户端的数据。WorkBuddy 日志优先按上游请求 ID 或事件 ID 去重，避免时间和 Token 数恰好相同的独立调用被合并；没有 ID 时才使用时间、模型和 Token 数作为去重依据。

## App 身份

Moa 在 bundle、数据根、provider ID 和发布产物里统一使用主 Moa 身份：

- App bundle：`Moa.app`
- Bundle ID：`com.moarliu.moa`
- SwiftPM executable product：`Moa`
- 本地数据根：`~/.moa`
- Application Support：`~/Library/Application Support/Moa`
- iCloud 数据根：`iCloud Drive/Moa`
- 数据包根目录：`MoaDataPackage/.moa`
- Codex 托管 provider ID：`moa-*`
- Claude Desktop 3P config-library profile：`Moa`

Moa 在你执行切换动作时仍会写入真实的 Codex 和 Claude Desktop 配置文件；它自己的 profile 数据库、数据包 manifest、iCloud 状态和诊断包都存放在 Moa 数据根下。

## 数据文件

Moa 的本地数据存放在：

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

Moa 每天按本地时间在 `00:20:01` 检查 Sub2API 同源的 [model-price-repo 价格目录](https://github.com/Wei-Shaw/model-price-repo)；如果当时没有运行，会在该时间之后的下一次启动时补查。价源切换后会立即检查一次。通过校验的新增模型和价格字段变化会合并进本地目录；自定义价格始终优先，官网修正项单独保留，旧缓存与网络故障不会覆盖内置的已核价快照。

开启 iCloud 存储后，Moa 会直接读写 `iCloud Drive/Moa`，不再读写 `~/.moa`。

如果旧版 iCloud 数据的外层目录和嵌套目录都包含数据，Moa 会保留两份目录，不再自动合并，以免恢复已删除的条目。请在更改数据前自行核对旧嵌套目录。迁移 Codex 历史时，请先关闭所有 ChatGPT 和 Codex 桌面端及 CLI 实例，并保持关闭直到迁移结束；Moa 无法阻止其他进程在迁移期间启动。

## 构建

```bash
swift build
swift test
./scripts/run-tests.sh
CODE_SIGN_IDENTITY=- ./scripts/build-menu-bar-app.sh
```

构建结果会输出到 `Moa.app`。

`swift test` 在默认 debug 配置下将各项检查作为独立 XCTest 用例运行，也支持在 Xcode 中发现和调试。脚本保留独立运行器，并核对全部应用源码都参与编译。若当前 Command Line Tools 无法展开 SwiftUI 宏，请设置 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 使用完整 Xcode。价格与故障注入测试包含共享状态，请串行运行测试套件。

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

- Provider API key 只保存在本地。
- 诊断包会脱敏 auth、key、token 字段。
- 打包脚本会拒绝把 `.moa`、`.codex`、`.dsh`、客户端登录/账号库、auth/config/profile 文件、环境变量文件和签名密钥打进发布包。
- Moa 不打包 `MoaMCP`，也不暴露本地 workflow tools。

候选版在 `scripts/version.env` 中使用数字 `APP_VERSION` 作为 macOS 包版本，使用 `APP_RELEASE_VERSION` 作为显示版本、GitHub 标签和 DMG 文件名。两个架构应使用相同的 `APP_BUILD`；确定构建号后，通过 `MOA_AUTO_BUMP_BUILD=0` 避免分别封包时重复递增。
