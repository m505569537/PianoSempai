#!/bin/bash
# 校验脚本 1+2：xcodegen 生成工程后 build + test（0 error、warnings-as-errors）
#
# 模拟器用 UDID 指定：多运行时并存的机器上 `name=iPhone 17 Pro` 会被归一成
# OS:latest 而该机型未必装了最新运行时，name 匹配直接失败（exit 70）。
#
# 覆盖方式：SIM_ID=<udid> Scripts/build.sh
# 不传则自动取第一台已 boot 的 iPhone，没有则取第一台可用的 iPhone。
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo "需要 xcodegen: brew install xcodegen"; exit 1; }

SIM_ID="${SIM_ID:-$(xcrun simctl list devices booted available | awk -F '[()]' '/iPhone/{print $2; exit}')}"
[ -n "$SIM_ID" ] || SIM_ID="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/{print $2; exit}')"
[ -n "$SIM_ID" ] || { echo "找不到可用的 iPhone 模拟器"; exit 1; }
echo "使用模拟器 UDID: $SIM_ID"

xcodegen generate
xcodebuild -skipMacroValidation -scheme PianoSempai -destination "platform=iOS Simulator,id=$SIM_ID" build
xcodebuild -skipMacroValidation -scheme PianoSempai -destination "platform=iOS Simulator,id=$SIM_ID" test
