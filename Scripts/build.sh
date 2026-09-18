#!/bin/bash
# 校验脚本 1+2：xcodegen 生成工程后 build + test（0 error、warnings-as-errors）
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo "需要 xcodegen: brew install xcodegen"; exit 1; }
xcodegen generate
xcodebuild -scheme PianoSempai -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -scheme PianoSempai -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
