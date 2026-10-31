# Moa

**在一个 macOS 菜单栏中管理多个 AI Agent 的账号、服务商和本地用量。**

[English](README.md) · [下载最新版](https://github.com/MoarLiu/Moa/releases/latest) · [更新日志](CHANGELOG.md)

Moa 是面向多 AI Agent 用户的本地管理工具，将 ChatGPT / Codex、Claude Desktop、Antigravity App、DeepSeek Harness、WorkBuddy 国内版、WorkBuddy AI 国际版及 ZCode 汇集到统一的菜单栏、账号窗口和用量总览中。各客户端继续独立运行会话和任务，Moa 负责它们已适配的账号、配置及维护操作。

## 快速开始

1. 从 [GitHub Releases](https://github.com/MoarLiu/Moa/releases/latest) 下载 DMG：Apple 芯片选择 `arm64`，Intel Mac 选择 `x86_64`。需要 macOS 12 或更新版本，同时提供 `.sha256` 校验文件。
2. 将 **Moa.app** 拖入「应用程序」后打开。从 1.6.6 起，发行包持续使用同一张本地代码签名证书，但不具备 Developer ID 分发签名或公证；首次运行可能需要在「系统设置 → 隐私与安全性」中允许打开。从旧版 ad-hoc 签名升级到 1.6.6 时，请从 DMG 手动安装，旧版自动更新器无法完成这次签名迁移。
3. 安装并登录需要使用的客户端。在 Moa 菜单选择「账号…」，保存已支持客户端的登录或配置服务商。切换账号前请先结束客户端中的活动任务。
4. 打开「用量总览…」查看支持的本地用量来源；各客户端子菜单提供切换、启动及专属选项。

## 客户端支持范围

每种客户端的适配能力不同。账号切换保存并恢复受支持的本地登录快照；服务商配置用于选择 API 端点。各客户端的账号和历史保持独立。

| 客户端 | 账号与服务商 | 本地用量 | 其他功能 |
| --- | --- | --- | --- |
| ChatGPT / Codex | 官方登录；直连 Responses 服务商配置；配置导入导出 | Token、缓存、模型及 API 费用估算 | 打开／重开；可选生成速率状态栏 |
| Claude Desktop / Claude Code | Desktop 3P 网关配置；复制 Claude Code 环境变量片段 | Claude Code 日志用量及 API 费用估算 | 打开／重开 Desktop；配置导入导出 |
| Antigravity App 2.x | Google 登录保存、添加、切换、重命名／忘记 | 暂不支持 | 打开／重开；本地钥匙串快照 |
| DeepSeek Harness | 登录保存、添加、切换、重命名／忘记 | 暂不支持 | 打开／重开；本地账号快照 |
| WorkBuddy 国内版 | 登录保存、添加、切换、重命名／忘记 | 独立的 Token、模型及费用估算 | 打开／重开；独立账号库 |
| WorkBuddy AI 国际版 | 登录保存、添加、切换、重命名／忘记 | 独立的 Token、模型及费用估算 | 打开／重开；独立账号库 |
| ZCode | 暂不支持账号／服务商管理 | 本地数据库用量及 API 费用估算 | 打开／重开及文件夹入口 |

## 核心功能

- **账号与服务商管理**：按客户端分组的统一窗口、菜单一键切换、已支持服务商的编辑及导入导出、进行中状态和失败恢复提示。
- **用量与费用分析**：汇总已支持的本地来源，查看模型和缓存明细，导出 CSV / Markdown，设置自定义价格及每日用量提醒。费用来自本地记录与 API 参考价格，不等同于订阅账单、积分或账号余额。
- **模型价格更新**：「Moa → 更新价格」下载 Sub2API 参考使用的公开价格目录，支持的美元 Token 单价立即生效并持久保存。自定义价格优先；下载失败保留原表；支持每日自动检查。
- **数据与维护**：Moa 数据包导入导出、脱敏诊断、共享数据根的可选 iCloud 存储，以及 GitHub Release 应用更新。不同凭据的存储和同步范围见[安全与凭据存储](#安全与凭据存储)。

Moa 的当前定位是客户端管理和本地用量分析。Agent 执行、会话和服务认证由对应客户端负责；Codex 的可选生成速率状态栏是其中一项客户端专属功能。

## 日常使用

- 主菜单顶部显示版本和构建号，并提供“账号管理…”和“用量总览…”，各客户端仍保留用量摘要、刷新和一键切换；打开客户端、文件夹等辅助动作直接列在各客户端二级菜单底部，不再折叠。
- 账号操作在菜单与窗口共享进行中状态；账号行保留“切换”，重命名、编辑、删除归入操作菜单。
- 成功与普通信息使用不抢焦点的提示，长表单正文可滚动且保存、取消始终可见；用量窗口支持较窄窗口。
- 快捷键：`⌘U` 用量总览、`⌘⇧A` 账号管理、`⌘R` 刷新当前用量窗口（其他场景刷新各来源用量）。
- 维护入口位于主菜单的“Moa”子菜单，包括价格更新、更新检查与数据管理。

## ChatGPT 客户端兼容

客户端通过 `com.openai.codex` Bundle ID 定位，兼容 `ChatGPT.app` 和旧版 `Codex.app`，也支持 `CODEX_APP` 指定安装位置。内部配置和登录数据仍位于 `~/.codex`，或 `CODEX_HOME` 指定的目录。

Moa 1.5.0 移除了快速模式和远程连接设置入口、对应实现及旧无界面命令。这些偏好由 ChatGPT 自己管理；已有设置保留。切换服务商以客户端当前配置为基础，保留其他设置、未知字段和其他服务商配置。

用量读取兼容 `token_usage_record` 和旧 `token_count`，避免双重计数，分别保留缓存读取、缓存写入和每次请求的用量。费用按单次请求判断长上下文档位；内置 API 价格表覆盖 OpenAI、Claude、GLM 及 WorkBuddy 模型，并保留缓存与 Fast 参数，可通过「更新价格」获取最新支持的目录；详见[完整模型价格与来源](MODEL_PRICING.md)。这些是本地 Codex 任务的 API 标准价格估算，不是 ChatGPT 订阅账单。

### 生成速率状态栏（实验功能）

在 Moa 的 **Codex → 显示生成速率（估算）** 开启，再在 **状态栏设置 → 重新打开 ChatGPT 以应用** 正常重开客户端。请先结束活动任务；客户端拒绝退出时会停止操作，不会为开启此功能强制终止。也可开启请求 Token、上下文估计和输入缓存命中率；footer 不兼容时可选择“在输入框下方显示（兼容布局）”。此功能默认关闭。

如果状态提示无法关闭或请手动退出，先等待当前回复和其他活动任务结束，在 ChatGPT 按 `⌘Q` 完成退出，再选择 **Moa → Codex → 打开 Codex**，确保本次启动带入增强参数。隐藏的快捷聊天预热窗口和宠物窗口不计作额外主聊天页面。

状态栏读取当前聊天的本地日志，以同一轮相邻记录的输出 Token 增量除以时间间隔，再对最近三个有效区间按时间加权，显示 `~80 t/s`。它包含等待与工具执行时间，用量写入后才更新，不是单次回答逐 Token 的精确解码速度。第一条记录显示 `--`；切换会话、模型或轮次会重新采样。上下文百分比是最近请求用量除以日志中的窗口大小，不是下一次请求的精确上下文。

增强模式会让 Moa 以本机回环调试参数启动官方客户端，并通过隔离的页面脚本添加状态栏；不修改安装文件、账号或供应商请求路径，不启动代理或 HTTP 服务。只连接 Moa 本次启动的进程，目前只接受唯一的主聊天页面；多窗口、远程聊天或无法识别的页面会显示不可用状态。Moa 重新启动后需再次通过 Moa 重开客户端。`CODEX_HOME` 必须对应实际客户端的日志目录，否则显示未找到记录。

关闭后会移除显示并停止采集；再次正常重开客户端才能撤掉进程级调试监听。Moa 意外退出后，页面脚本租约到期会自行移除。日志、WebSocket 协议与隔离 HTML 页面已有自动测试，预览版也已在一个客户端版本上实测显示；其他客户端版本和布局的兼容性可能不同。

## Antigravity App

保存或切换登录、启动应用，以及为缺失的当前登录创建钥匙串访问控制前，Moa 会验证应用和 language server 的签名来自 Google Developer ID。被修改、自签名或冒用身份的安装会被拒绝。已有钥匙串访问控制保持不变；新建当前登录条目时，为兼容客户端的 keyring 访问，仍信任 `/usr/bin/security`。这不构成对同一 macOS 用户下所有软件的凭据隔离。

「Antigravity」菜单适配 Antigravity App 2.x（`com.google.antigravity`），兼容性调研基于 macOS App `2.28.0`。它管理登录钥匙串中 `service=gemini`、`account=antigravity` 的 OAuth 登录，不编辑 Antigravity IDE 使用的 `state.vscdb`。企业账号／ADC 和 API Key 管理不在本适配器范围内。

1. 在 Antigravity 登录 Google 账号 A。结束进行中的任务，关闭 `agy` 和 Antigravity IDE 扩展，然后在 Moa 选择「Antigravity → 管理账号… → 保存当前登录」。填写便于识别的名称；macOS 请求钥匙串访问时按需授权。
2. 点击「再添加一个账号」。Moa 正常退出 Antigravity，保存最新登录，移除当前钥匙串登录条目及独立备用令牌文件，再重新打开 Google 登录界面。登录 B 后，在 Moa 保存 B。这个过程不会调用 Google 的令牌撤销接口，也不调用 Antigravity 的退出登录和缓存清理流程。
3. 此后在 Antigravity 菜单选择 A 或 B。Moa 退出应用，保存当前登录，同时替换钥匙串和备用文件中的目标凭据后重新打开。请核对应用显示的 Google 账号并实际发送一次请求。在账号窗口可以重命名或忘记保存的登录；忘记不会改变当前登录。

完整凭据及未知字段保存在 Moa 专用钥匙串服务 `com.moa.antigravity.accounts`，不请求 iCloud 钥匙串同步。名称、可用的邮箱标签、身份哈希和时间等信息保存在 `~/Library/Application Support/Moa/antigravity-accounts/accounts.json`，目录／文件权限为 `700`／`600`。这个目录不进入数据导出包、诊断包和 Moa 的 iCloud 数据根目录迁移。打开菜单时只在后台进行不弹授权框的刷新；保存和切换可能请求钥匙串授权，Moa 构建签名变化后也可能需要重新授权。

存在 Google ID Token 时按其用户标识识别账号，否则按刷新授权的指纹识别登录。如果没有 ID Token 且授权发生变化，Moa 会另存一份，避免猜测并覆盖其他账号。适配器只接受已支持的 OAuth 格式，保存和恢复原始完整字节。设置和会话保持共享且不会被修改；此功能不隔离历史，也不增加用量统计。

独立备用文件 `~/.gemini/jetski-standalone-oauth-token` 也是登录来源。Moa 会将与当前钥匙串不同、且尚未保存过的备用账号另存到钥匙串；旧备用文件不会覆盖已有账号快照。切换时写入匹配账号的完整 JSON，添加账号时移除两个登录来源。钥匙串更新失败时，先恢复备用文件再重开；跨账号切换启动失败时恢复之前两份凭据，同账号重启失败时保留当前已刷新的登录，并同步两个登录来源，避免重试时退回旧令牌。已有 `.gemini` 目录权限保持不变，令牌文件使用私有权限写入。Gemini CLI 的 `oauth_creds.json` 和 CLI 专用令牌文件不会被修改。通过环境变量注入凭据或自定义凭据根目录的配置不在支持范围内。

App、CLI 或扩展实例可能共享当前登录。Moa 会在修改前检查运行中的程序路径，并在替换前复查凭据；操作锁只协调 Moa 实例。拒绝退出或检测到其他写入进程时停止修改。启动失败时，先保留启动期间可能刷新的凭据，再恢复之前的账号；无法确认恢复成功时保持客户端关闭并给出恢复提示。隔离测试覆盖这些路径、账号信息写入失败和存储排除。账号添加和多账号切换已通过真机测试；不同签名下的钥匙串授权／访问控制、各目标账号的实际请求，以及服务端过期或撤销后的会话有效性仍属于手动验收范围。适配器不会自行刷新令牌，也不承诺切换时保持正在执行的任务。

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

## 切换、恢复与用量限制

Codex 切换和当前配置编辑会先请求客户端正常退出，再保存配置并重新打开。客户端拒绝退出或超时后，Moa 会停止操作，不会强制终止任务。更改失败且确认原配置仍可用时，Moa 会重新打开先前运行的客户端，并明确提示更改失败；回滚失败或无法确认配置状态时，客户端会保持关闭，并提示检查配置。配置已保存但启动失败时，会明确提示手动打开客户端。请先结束活动任务，并关闭其他共享同一配置目录的桌面或 CLI 实例。

保存当前官方登录只保存账号快照，不回写客户端凭据。配置和导出文件支持父目录符号链接，保留第三方目录的既有权限，并拒绝将目标文件符号链接作为写入目标。

自动生成的导入及 iCloud 切换回滚包存放在 `~/Library/Application Support/Moa/Recovery`，仅本机保留最近 12 份，目录权限为 `700`、文件权限为 `600`。清理时会继续处理其他文件，并记录个别文件的失败。手动导出仍使用用户选择的位置。旧版本已写入 Downloads 的备份不会自动删除：请检查旧的 `Moa-Data-Rollback-*.zip` 和 `Moa-Data-Before-iCloud-*.zip`，不再需要时手动删除，其中包含未加密凭据。

用量扫描会跳过超大记录以限制内存占用。Claude 中超过 8 MiB 的记录，以及 Codex 中超过 512 KiB 的用量记录不会计入，因此本地统计可能少计这部分用量；较大的 Codex 模型上下文记录会单独读取。历史迁移使用独立读取路径。

旧版 `MoaApplyProfileID` 环境变量命令会请求 ChatGPT 正常退出、应用配置，然后直接退出，不重新打开客户端。失败时向标准错误输出原因并返回非零退出码。需要自动重开的场景请使用菜单切换。

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
- `~/Library/Application Support/Moa/Recovery/*.zip`：仅本机保存的凭据恢复包，不进入 iCloud 同步或导出的数据包；目录/文件权限为 `700`/`600`，目标保留最近 12 份

Moa 每天按本地时间在 `00:20:01` 检查 Sub2API 同源的 [model-price-repo 价格目录](https://github.com/Wei-Shaw/model-price-repo)；如果当时没有运行，会在该时间之后的下一次启动时补查。价源切换后会立即检查一次。通过校验的新增模型和价格字段变化会合并进本地目录；自定义价格始终优先，官网修正项单独保留，旧缓存与网络故障不会覆盖内置的已核价快照。

开启 iCloud 存储后，Moa 会直接读写 `iCloud Drive/Moa`，不再读写 `~/.moa`。

如果旧版 iCloud 数据的外层目录和嵌套目录都包含数据，Moa 会保留两份目录，不再自动合并，以免恢复已删除的条目。请在更改数据前自行核对旧嵌套目录。迁移 Codex 历史时，请先关闭所有 ChatGPT 和 Codex 桌面端及 CLI 实例，并保持关闭直到迁移结束；Moa 无法阻止其他进程在迁移期间启动。

## 构建

```bash
swift build
swift test
./scripts/run-tests.sh
./scripts/build-menu-bar-app.sh
```

构建结果会输出到 `Moa.app`。

应用构建、Run 按钮、冒烟检查和 DMG 打包默认使用已有的 `Moa Local Development Code Signing` 证书。新开发机首次配置时运行一次 `./scripts/setup-local-code-signing.sh`；后续持续保留同一张证书及私钥，找不到证书或存在同名歧义时会停止构建。可用 `CODE_SIGN_IDENTITY`（或 `MOA_CODE_SIGN_IDENTITY`）指定身份；只有显式设置 `CODE_SIGN_IDENTITY=-` 才使用 ad-hoc 签名。本地签名不具备 Developer ID 的分发信任或公证资格，`NOTARIZE=1` 需要 Developer ID Application 身份和公证配置。

使用证书签名的安装只接受符合当前应用签名身份要求的更新。已有 ad-hoc 安装首次迁移到本地证书时，需要手动安装第一个证书签名版本。如果 Antigravity 钥匙串中的旧 Moa 授权仍绑定同一路径的早期构建，安装后运行 `/Applications/Moa.app/Contents/MacOS/Moa --repair-antigravity-keychain-access`。此显式维护命令只替换已有的 Moa 受信任应用项，保留其他访问控制和凭据内容；macOS 可能请求授权。普通菜单刷新禁止传统钥匙串弹窗；主动保存或切换时，macOS 还有独立的程序哈希分区校验，重新构建后仍可能需要授权一次。

`swift test` 在默认 debug 配置下将各项检查作为独立 XCTest 用例运行，也支持在 Xcode 中发现和调试。脚本保留独立运行器，并核对全部应用源码都参与编译。若当前 Command Line Tools 无法展开 SwiftUI 宏，请设置 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 使用完整 Xcode。价格与故障注入测试包含共享状态，请串行运行测试套件。

生成 DMG：

```bash
./scripts/package-dmg.sh
```

DMG 会输出到 `dist/Moa-<release-version>-macos-<arch>.dmg`，并生成匹配的 SHA-256 文件。

当前 Mac 的本机构建会更新 `Moa.app`。把 `APP_ARCH` 设成其他架构时，产物写到 `build/macos-<arch>/Moa.app`，不会替换本机应用；DMG 封好后会删除这个跨架构 bundle。在 Apple 芯片上打开仅含 Intel 架构的 Moa 时，macOS 27 会提示它无法在 macOS 28 中打开，所以在这台 Mac 上只启动原生 `arm64` bundle。


## Codex 本地运行按钮

Codex app 的 Run 按钮通过以下文件接入：

- `script/build_and_run.sh`
- `.codex/environments/environment.toml`

脚本会构建 `Moa.app`，停止正在运行的 Moa 进程，然后启动新 bundle。

## 安全与凭据存储

凭据按客户端分别存储，并非所有凭据都进入钥匙串。

| 数据 | 保存位置 | iCloud／数据包范围 |
| --- | --- | --- |
| 服务商 API Key、已保存的 Codex 登录 | Moa 当前数据根中的文件 | 启用 iCloud 后同步；完整导出及回滚包包含未加密凭据 |
| Antigravity 已保存登录 | 本地登录钥匙串；名称和身份元数据在 Application Support | Moa 不请求钥匙串同步；排除在 Moa 数据导出及数据根迁移之外 |
| WorkBuddy 两个版本、DeepSeek 账号快照 | Application Support 下各自独立的本地账号库 | 排除在 Moa 数据导出及数据根迁移之外 |
| 自动回滚包 | 本地 Application Support/Moa/Recovery，目标保留 12 份 | 排除在 Moa 的 iCloud 存储及完整导出之外；可能包含未加密凭据 |

- Moa 不会把凭据上传到自有服务器。请妥善保管完整导出及回滚包，只导入可信来源的数据包。Schema 2 的 SHA-256 用于检测内容不一致，不验证作者身份，也不提供加密。
- 敏感配置和供应商 profile JSON 导出通过创建时即为 `600` 的临时文件原子替换，权限设置失败会中止保存。客户端和导出目录保留既有权限，Moa 自有私有目录使用 `700`。
- 自动更新从 GitHub Release 下载，并使用配套 SHA-256 检查完整性。从 1.6.6 起，证书签名的安装还会验证新应用是否满足当前应用的签名身份要求，拒绝不同证书或降级为 ad-hoc 签名。旧版 ad-hoc 安装没有稳定签名身份，首次证书签名版本需从可信来源手动安装。本地签名不具备 Developer ID 分发信任或公证，独立的更新文件签名系统尚未部署。
- 诊断包会脱敏 auth、key、token 字段。
- 打包脚本会拒绝把 `.moa`、`.codex`、`.dsh`、客户端登录/账号库、auth/config/profile 文件、环境变量文件和签名密钥打进发布包。
- Moa 不打包 `MoaMCP`，也不暴露本地 workflow tools。

候选版在 `scripts/version.env` 中使用数字 `APP_VERSION` 作为 macOS 包版本，使用 `APP_RELEASE_VERSION` 作为显示版本、GitHub 标签和 DMG 文件名。两个架构应使用相同的 `APP_BUILD`；确定构建号后，通过 `MOA_AUTO_BUMP_BUILD=0` 避免分别封包时重复递增。


## 旧版本迁移说明

### Provider Bridge

1.3.2 移除了 Provider Bridge、本地 HTTP 服务、协议转换和相关配置入口。Codex 服务商现在直接使用支持 OpenAI Responses 的端点；连接测试只验证 Responses，不再回退到 Chat Completions。

如果此前使用 Provider Bridge，请在 Codex 菜单中选择已有的 Responses 配置，或添加服务商提供的 Responses Base URL；也可以选择官方模式。旧桥接配置不会自动转换为直连配置。旧配置文件保留在磁盘，1.3.2 不再读取独立桥接配置库；混合配置库中的桥接项仍保留在本地，但不再显示或导出，导入此类配置会提示重新添加 Responses 端点。升级本身不会改写当前 Codex 配置，完成上述选择后才会更新客户端配置并重新打开客户端。
