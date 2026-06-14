# 🐴 NiuMaBar · Touch Bar 小牛马

一只住在 MacBook Touch Bar 上的像素小牛马，实时反映 Claude Code / Codex agent 的干活状态——agent 在跑它就跑，agent 要审批它就停下来变黄举问号，任务失败它变红。

## 状态一览

| Agent 状态 | 小牛马表现 | 触发来源 |
|---|---|---|
| 🏃 工作中 `working` | 棕色，快速来回飞奔（速度可调） | UserPromptSubmit / PreToolUse / PostToolUse |
| ❓ 等待审批 `approval` | **静止 + 变黄 + 头顶闪烁 "?" + 提示音**（可关） | Claude: Notification(permission)；Codex: PermissionRequest |
| 💥 任务失败 `failed` | **变红 + 头顶 "!" + 提示音**（约 25 秒后自动恢复） | PostToolUse 的 `tool_response.success == false` |
| 😴 空闲/完成 `idle` | 棕色，慢悠悠溜达；从工作/审批**收尾**进入时响**完成提示音** | Stop / 等待输入 |

多个会话并存时按优先级聚合：`approval > failed > working > idle`。

## 精力（token 消耗）

小牛马的精力 = 当前会话的**累计 token 消耗**（所有回合 input + output + cache_creation 之和）。消耗越多越疲倦：

- **变小**：精疲力竭时缩到约 72%，像佝偻下来
- **变暗**：颜色整体压暗（色相不变，仍能看出工作/审批/失败的状态色）
- **变慢**：移动和动画随疲倦放慢
- **旁边显示消耗量**：小牛马右侧实时显示累计 token，<1M 用 k、≥1M 用 M（如 `500k` / `6.0M`）

累计是单调递增的，开**新会话**（含 `/clear`，新 session）才归零、精力恢复。菜单栏顶部也显示「精力 NN% · 消耗 X.XM」。

疲劳度 = 累计消耗 ÷ 上限（默认 3M，可改：`defaults write com.wzd.niumabar energyCap -float 5000000`）。数据取自 Claude transcript 的 `usage`（input+output+cache_creation，**不含** cache_read 的缓存重复读）。**Codex 暂不接入精力**（rollout 格式不同），其会话保持满精力。可用 `NiuMaBar --render-energy` 看五档精力对比图。

**可配置**（菜单）：
- **疲劳表现**：分别开关「变暗 / 变小 / 变慢」——全部关掉则消耗 token **不改变外观**，只在旁边显示数字
- **图标**：把像素牛马换成任意 emoji（🐮🐴🐶🐱🐰🦄🐢🐉🐌🚀），emoji 模式下疲劳用「变淡」表现

## 构建与运行

```bash
cd ~/NiuMaBar
./build.sh                      # 需要 Xcode Command Line Tools
open build/NiuMaBar.app         # 菜单栏出现 🐴，Touch Bar 出现小牛马
```

## 安装 agent 监控 hooks

```bash
./install.sh
```

做三件事（全部幂等、自动备份原配置）：

1. 装 `~/.niumabar/bin/niumabar-hook`（通用 hook 脚本，jq 解析 stdin JSON）
2. 合并 6 个 hook 到 `~/.claude/settings.json`（UserPromptSubmit / PreToolUse / PostToolUse / Notification / Stop / SessionEnd）
3. 合并 5 个 hook 到 `~/.codex/hooks.json`（UserPromptSubmit / PreToolUse / PostToolUse / PermissionRequest / Stop）

> 已在运行的 claude / codex 会话不会热加载 hook，新开会话生效。卸载：`./uninstall.sh`

## 两种视图 & 点击交互

Control Strip 常驻槽位的宽度被系统**死钳在约 55pt**（实测：`intrinsicContentSize` 设成 250，`bounds.width` 仍被压回 55.5——系统固定，**无法加长**）。所以只有两种视图，点击行为按视图区分：

- **Control Strip 常驻（~55pt，默认）**：小牛马住在亮度键旁的小格子。**点一下小牛马 → 展开成整条 Touch Bar**（常驻太窄，点击就用来展开）
- **整条跑道模式**：占据整条 Touch Bar。**点小牛马的左／右 → 引导它朝那侧跑**（冲刺约 1.3 秒，连静止的审批／失败态也会被唤起）；点左侧系统 ✕ 或 `pkill -USR1 NiuMaBar` 收回常驻

屏幕预览窗口里用鼠标点小牛马左右，同样引导方向。

## 菜单栏功能（🐴 图标）

- 实时状态行（含各来源会话数）；图标本身也会变：🐴💨 / 🐴❓ / 🐴❗
- **奔跑速度**：预设 0.6×–3.0× + 滑杆连续调节（持久化）
- **声音提醒**：**审批音**（进入待审批）、**完成音**（收尾回到空闲）、**失败音**（任务失败）三条，可分别开关、各选铃声（Submarine / Glass / Funk / Hero / Ping / Tink / Basso / Sosumi，点击即试听），默认 审批=Submarine、完成=Glass、失败=Basso。只在状态「转变进入」那一刻响一次，天然去重——持续/多会话同态都只响一次；**失败态 25 秒褪色回空闲不会误响完成音**
- **疲劳表现**：消耗 token 时改变「变暗 / 变小 / 变慢」哪些，可分别开关（全关 = 不随消耗变化）
- **图标**：内置像素牛马，或任选 emoji 当宠物
- **测试状态**：不跑 agent 也能手动切四种状态看效果（3 分钟后自动失效）
- 屏幕预览窗口（和 Touch Bar 同款画面，没有 Touch Bar 的 Mac 也能玩）
- 开机自启（macOS 13+，建议先把 app 挪到 /Applications）

## 远程审批（Telegram，可选）

人离开电脑时让审批走手机：agent 要执行敏感操作（Bash/Edit/Write…）时，推一条带「✅ 批准 / ❌ 拒绝」按钮的消息到你的 Telegram，点一下决定放不放行。**本地全程只发出站请求，无需公网回调/内网穿透**。

原理：Claude Code 的 PreToolUse hook 能返回 `permissionDecision`，所以 `niumabar-approve` 拦截敏感工具 → `sendMessage` 推送 → 轮询 `getUpdates` 等你点按钮 → 返回 `allow`/`deny`。

### 启用
1. Telegram 找 **@BotFather**，`/newbot` 建一个 bot，拿到 token
2. 编辑 `~/.niumabar/telegram.conf`，填 `TG_TOKEN`
3. 给你的 bot 发条消息，跑 `~/.niumabar/bin/niumabar-tg chatid`，把显示的 `chat_id` 填进配置
4. `~/.niumabar/bin/niumabar-tg test` 确认手机收到带按钮的消息
5. **新开** claude 会话生效

> ⚠️ **务必新开会话**：装了 hook 的当前会话若继续用，agent 自己的命令也会触发审批、把自己拦住，和测试调用嵌套时审批消息还会错乱。装完就开新会话。

### 审批消息的按钮
- **✅ 批准** —— 本次放行
- **❌ 拒绝** —— 本次拒绝
- **♾️ 永久允许此命令** —— 本次放行，并把该命令（精确匹配 `工具<TAB>命令`）记入 `~/.niumabar/approve-allow.list`，之后**同样的命令自动放行、不再推送**

### 失败 / 完成推送（纯通知，无按钮）
agent 任务**失败**（❌）或**收尾完成回到空闲**（✅）时，额外推一条纯通知到 Telegram。`telegram.conf` 里 `NOTIFY_FAILED=0` / `NOTIFY_DONE=0` 可分别关闭。

### 行为 & 安全
- **总开关 `APPROVE_ENABLED`**（默认 1）：设 `0` 则完全不走远程审批、立即回落本地终端审批，失败/完成通知（`NOTIFY_*`）不受影响——「只要通知不要审批」就这么配
- 只对 `APPROVE_TOOLS`（默认 Bash/Edit/Write/MultiEdit/NotebookEdit）走远程审批，其余工具不拦
- **超时（默认 250s）或不可达 → 回落本地终端审批；绝不自动放行、绝不误阻断**（未配 token 时 hook 秒退）
- 消息里显示**具体命令**；`telegram.conf` 权限 600
- 仅 **Claude Code**（Codex 的 PreToolUse 能否回传决定未验证，暂不支持远程批，仍走本地）
- 永久允许列表 `~/.niumabar/approve-allow.list`（每行 `工具<TAB>命令`）可随时编辑/删除；**精确整行匹配**，`rm -rf /` 不会被 `date` 的白名单误放行
- ⚠️ 能远程批准 = 能让 agent 在你电脑上跑命令，bot token / chat id 务必保密；永久允许某命令前想清楚后果

## 状态协议（接入任何工具）

任何程序都可以驱动小牛马——往 `~/.niumabar/state/` 写 JSON 文件即可：

```bash
printf '{"state":"working","ts":%s,"source":"myci","session":"job42"}' "$(date +%s)" \
  > ~/.niumabar/state/myci-job42.json
```

`state` ∈ `working | approval | failed | idle`；可选 `tokens`（整数，累计消耗 token 数）驱动小牛马精力，越大越疲倦。应用监听目录变化（含 2 秒兜底轮询），按 TTL 自动过期：working 30 分钟、approval 6 小时、failed 25 秒后转 idle、超过 24 小时的文件自动清理。

## 工作原理

- Touch Bar 常驻项用的是 DFRFoundation 私有 API（`NSTouchBarItem +addSystemTrayItem:` + `DFRElementSetControlStripPresenceForIdentifier`），整条跑道用 `presentSystemModalTouchBar:systemTrayItemIdentifier:`，与 Pock / Dozer 同源，运行时 `dlopen`/`dlsym` 获取，不依赖 SDK 头文件
- 像素小牛马是代码内置的 17×12 调色板位图，三套配色（棕/黄/红）+ 四帧动画（站立/伸展/收腿/散步），无插值缩放保持像素感
- hook 脚本永远 `exit 0` 且单次 ~10ms，不会拖慢或阻塞 agent

## 已知限制

- **审批后长任务**：批准后要等该工具跑完（PostToolUse）才会从黄色恢复，期间小牛马保持举问号
- **失败检测范围**：依赖 `tool_response.success/is_error` 字段，Bash 命令非零退出不一定上报为失败
- Codex 没有 SessionEnd 事件，靠 TTL 过期清理；Codex 需要支持 lifecycle hooks 的较新版本
- 精力（token）目前只接 Claude（从 transcript 的 `usage` 取上下文占用）；Codex rollout 格式不同，其会话精力保持满
- 精力用"累计消耗"（input+output+cache_creation 全量累加），单调递增、开新会话归零；hook 每次全量读 transcript（大会话稍慢，本会话 6MB ~50ms）。不含 cache_read（缓存重复读，不算真消耗）
- 修改 hooks 后已开的会话要重开（Claude Code 里可用 `/hooks` 查看）
- 排错：`build/NiuMaBar.app/Contents/MacOS/NiuMaBar --check-touchbar | --dump-state`，hook 细节用 `claude --debug`
- 声音没响？菜单确认「声音提醒」已开；播放诊断会写到系统日志，用 `log stream --predicate 'eventMessage CONTAINS "NiuMaBar"'` 查看「▶ 播放提示音」行
