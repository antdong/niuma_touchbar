#!/bin/bash
# 安装小牛马的 agent 监控 hooks：
#  1. 把 niumabar-hook 装到 ~/.niumabar/bin/
#  2. 合并 Claude Code hooks 到 ~/.claude/settings.json（自动备份，幂等）
#  3. 合并 Codex hooks 到 ~/.codex/hooks.json（自动备份，幂等）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$HOME/.niumabar/bin" "$HOME/.niumabar/state"
install -m 0755 "$ROOT/hooks/niumabar-hook" "$HOME/.niumabar/bin/niumabar-hook"
install -m 0755 "$ROOT/hooks/niumabar-approve" "$HOME/.niumabar/bin/niumabar-approve"
install -m 0755 "$ROOT/hooks/niumabar-tg" "$HOME/.niumabar/bin/niumabar-tg"
echo "✓ hook 脚本 → ~/.niumabar/bin/（niumabar-hook, niumabar-approve, niumabar-tg）"
# Telegram 远程审批配置模板（不覆盖已有配置；默认空=不启用）
if [ ! -f "$HOME/.niumabar/telegram.conf" ]; then
  cp "$ROOT/telegram.conf.example" "$HOME/.niumabar/telegram.conf"
  chmod 600 "$HOME/.niumabar/telegram.conf"
  echo "✓ 远程审批配置模板 → ~/.niumabar/telegram.conf（填好 token 才启用）"
fi

python3 - <<'PY'
import json, os, shutil, time

p = os.path.expanduser("~/.claude/settings.json")
data = {}
if os.path.exists(p):
    bak = p + ".bak-niumabar-" + time.strftime("%Y%m%d%H%M%S")
    shutil.copy(p, bak)
    print(f"  备份 → {bak}")
    with open(p) as f:
        data = json.load(f)

hooks = data.setdefault("hooks", {})
HOOK = os.path.expanduser("~/.niumabar/bin/niumabar-hook")

def entry(mode, matcher=None):
    e = {"hooks": [{"type": "command", "command": f'"{HOOK}" claude {mode}', "timeout": 10}]}
    if matcher is not None:
        e["matcher"] = matcher
    return e

wanted = {
    "UserPromptSubmit": entry("working"),
    "PreToolUse": entry("working", "*"),
    "PostToolUse": entry("post", "*"),
    "Notification": entry("notify"),
    "Stop": entry("stop"),
    "SessionEnd": entry("end"),
}
for ev, ent in wanted.items():
    arr = hooks.setdefault(ev, [])
    arr[:] = [g for g in arr if "niumabar" not in json.dumps(g)]
    arr.append(ent)

# 远程审批：PreToolUse 对敏感工具阻塞等 Telegram 决定，需长 timeout（未配置时秒退、不干预）
APPROVE = os.path.expanduser("~/.niumabar/bin/niumabar-approve")
hooks.setdefault("PreToolUse", []).append({
    "matcher": "*",
    "hooks": [{"type": "command", "command": f'"{APPROVE}"', "timeout": 300}],
})

with open(p, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
print("✓ Claude Code hooks → ~/.claude/settings.json")
PY

python3 - <<'PY'
import json, os, shutil, time

p = os.path.expanduser("~/.codex/hooks.json")
data = {}
if os.path.exists(p):
    bak = p + ".bak-niumabar-" + time.strftime("%Y%m%d%H%M%S")
    shutil.copy(p, bak)
    print(f"  备份 → {bak}")
    try:
        with open(p) as f:
            data = json.load(f)
    except Exception:
        data = {}

hooks = data.setdefault("hooks", {})
HOOK = os.path.expanduser("~/.niumabar/bin/niumabar-hook")

def entry(mode):
    return {"hooks": [{"type": "command", "command": f'"{HOOK}" codex {mode}', "timeout": 10}]}

wanted = {
    "UserPromptSubmit": entry("working"),
    "PreToolUse": entry("working"),
    "PostToolUse": entry("post"),
    "PermissionRequest": entry("approval"),
    "Stop": entry("stop"),
}
for ev, ent in wanted.items():
    arr = hooks.setdefault(ev, [])
    arr[:] = [g for g in arr if "niumabar" not in json.dumps(g)]
    arr.append(ent)

with open(p, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("✓ Codex hooks → ~/.codex/hooks.json")
PY

echo ""
echo "完成。注意："
echo "  · 已在运行的 claude / codex 会话不会热加载 hook，新开会话才生效"
echo "  · claude 里可用 /hooks 查看；codex 需要支持 lifecycle hooks 的较新版本"
echo ""
echo "📱 远程审批（可选，Telegram）："
echo "  1. Telegram 找 @BotFather → /newbot 建 bot，拿 token"
echo "  2. 编辑 ~/.niumabar/telegram.conf 填 TG_TOKEN"
echo "  3. 给 bot 发条消息，运行 ~/.niumabar/bin/niumabar-tg chatid → 把 chat_id 填进配置"
echo "  4. ~/.niumabar/bin/niumabar-tg test 确认能收到带按钮的消息"
echo "  · 不填 token 则远程审批不启用，照旧走本地审批"
