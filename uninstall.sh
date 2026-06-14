#!/bin/bash
# 移除 install.sh 写入的所有 niumabar hooks（自动备份），并可选清理 ~/.niumabar
set -euo pipefail

python3 - <<'PY'
import json, os, shutil, time

for p in [os.path.expanduser("~/.claude/settings.json"), os.path.expanduser("~/.codex/hooks.json")]:
    if not os.path.exists(p):
        continue
    bak = p + ".bak-niumabar-" + time.strftime("%Y%m%d%H%M%S")
    shutil.copy(p, bak)
    try:
        with open(p) as f:
            data = json.load(f)
    except Exception:
        continue
    hooks = data.get("hooks", {})
    for ev in list(hooks.keys()):
        hooks[ev] = [g for g in hooks[ev] if "niumabar" not in json.dumps(g)]
        if not hooks[ev]:
            del hooks[ev]
    with open(p, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"✓ 已清理 {p}（备份 → {bak}）")
PY

echo "如需彻底清理：rm -rf ~/.niumabar；并在菜单里关掉开机自启后删除 NiuMaBar.app"
