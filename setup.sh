#!/bin/bash
# 新 Mac 一键安装 NiuMaBar：检查前提 → 编译 → 验证 → 启动
set -e
cd "$(dirname "$0")"

echo "== [1/4] 检查 Xcode Command Line Tools =="
if ! xcode-select -p >/dev/null 2>&1; then
  echo "  ✗ 未安装。先运行：  xcode-select --install"
  echo "    装完（弹窗里点安装、等几分钟）再重跑本脚本。"
  exit 1
fi
echo "  ✓ $(xcode-select -p)"

echo "== [2/4] 编译 =="
./build.sh

echo "== [3/4] 验证 Touch Bar 私有 API =="
./build/NiuMaBar.app/Contents/MacOS/NiuMaBar --check-touchbar
echo "  注：上面三项 ok 表示 API 可用；能不能看到小牛马还取决于这台机器【有没有物理 Touch Bar】"
echo "      （带 Touch Bar 的是 2016–2020 的 13\"/15\"/部分16\" MacBook Pro；M1 Air、14\"/16\" 都没有）"

echo "== [4/4] 启动 =="
open build/NiuMaBar.app
echo "  ✓ 菜单栏出现 🐴；有 Touch Bar 的话亮度键旁出现小牛马（点一下展开整条）"
echo ""
echo "可选："
echo "  · agent 监控 hooks（需 jq，先 brew install jq）→  ./install.sh  然后【新开】claude 会话"
echo "  · 开机自启 → 菜单 🐴 → 开机自启"
echo "  · 远程审批 → 见 README「远程审批」节，每台机器单独配 ~/.niumabar/telegram.conf"
echo "  · 没有 Touch Bar 的 Mac → 菜单 🐴 → 屏幕预览窗口（同款画面）"
echo ""
echo "完成 🐴"
