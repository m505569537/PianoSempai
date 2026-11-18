#!/usr/bin/env bash
# 跑全量测试，并在常见"卡死"场景给出明确诊断而不是让人干等。
#
# 背景（2026-11-18 复盘）：`xcodebuild test` 反复卡在
# `PruneExplicitPrecompiledModules` 或 `The test runner hung before establishing connection`。
# 真正的原因是**磁盘接近满**（当时 460GB 只剩 17GB，使用率 96%），
# 而 Prune 阶段要遍历上 GB 构建产物 → APFS 元数据操作严重降速 → 看起来像"卡死"。
# 其次才是模拟器服务状态与机器负载（8 核跑到 load 200+ 时同样会超时）。
#
# 用法：
#   Scripts/test.sh              # 全量
#   Scripts/test.sh --only LibraryPieceStatusMapTests
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

ONLY=""
if [[ "${1:-}" == "--only" && -n "${2:-}" ]]; then ONLY="$2"; fi

MIN_FREE_GB=20
DD_PATH="build/dd"
SIM_ID="${SIM_ID:-}"

fail() { echo "✗ $*" >&2; exit 1; }
info() { echo "· $*"; }

# ---------- 1. 磁盘 ----------
FREE_GB=$(df -g /System/Volumes/Data 2>/dev/null | awk 'NR==2 {print $4}')
USED_PCT=$(df -h /System/Volumes/Data 2>/dev/null | awk 'NR==2 {print $5}')
info "磁盘可用 ${FREE_GB}GB（已用 ${USED_PCT}）"
if [[ -n "$FREE_GB" && "$FREE_GB" -lt "$MIN_FREE_GB" ]]; then
  cat >&2 <<EOF
✗ 可用空间不足 ${MIN_FREE_GB}GB。Xcode 在这种状态下会表现出"构建卡死"。
  先清可再生的缓存（都能重新生成，不碰源码）：
    rm -rf build/dd build/dd3 build/dd4 build/export build/*.xcarchive
    rm -rf ~/Library/Developer/Xcode/DerivedData/*
    xcrun simctl delete unavailable
    # 过期 iOS 符号目录（设备升级后旧的就没用了）
    ls -d ~/Library/Developer/Xcode/iOS\\ DeviceSupport/*/
EOF
  exit 1
fi

# ---------- 2. 负载 ----------
NCpu=$(sysctl -n hw.ncpu)
LOAD1=$(sysctl -n vm.loadavg | awk '{print $2}' | cut -d. -f1)
info "8 核机器 1 分钟负载 ${LOAD1}"
if [[ -n "$LOAD1" && "$LOAD1" -gt $((NCpu * 3)) ]]; then
  info "⚠️  负载偏高，测试可能很慢或超时（有其它重 I/O 程序在跑）"
fi

# ---------- 3. 模拟器 ----------
if [[ -z "$SIM_ID" ]]; then
  SIM_ID=$(xcrun simctl list devices booted 2>/dev/null | grep -oE '[0-9A-F-]{36}' | head -1)
fi
if [[ -z "$SIM_ID" ]]; then
  SIM_ID=$(xcrun simctl list devices available 2>/dev/null | grep -E "iPhone" | grep -oE '[0-9A-F-]{36}' | head -1)
fi
[[ -n "$SIM_ID" ]] || fail "找不到可用的 iPhone 模拟器（xcrun simctl list devices available）"
info "模拟器 $SIM_ID"

xcrun simctl boot "$SIM_ID" 2>/dev/null || true
# 关键：等设备真正 booted 再交给 xcodebuild，否则会报
# "Unable to find a device matching the provided destination specifier"
xcrun simctl bootstatus "$SIM_ID" -b >/dev/null 2>&1 || fail "模拟器启动失败"
# bootstatus 返回后 CoreSimulator 仍可能没收尾，紧接着的 xcodebuild 会报
# "Unable to find a device matching the provided destination specifier"（实测高发）。
sleep 3
info "模拟器已就绪"

# ---------- 4. 清掉可能已死锁的构建服务 ----------
# 采样证实：卡住时 xcodebuild 主线程等在 waitForBuildWithBuildLog，而
# SWBBuildService 既无子进程、CPU 也是 0、只在 mach_msg 上空等 —— 死锁而非在工作。
# 此时唯一有效的恢复是杀掉服务让它重启（服务按需重新拉起）。
# 更常见的原因：上一次构建没退干净，**两个 xcodebuild 共享同一个 derived data**
# → SWBBuildService 死锁（实测 unified log 里能看到两个 pid 同时操作 build/dd，
#   并伴随 XPC_ERROR_CONNECTION_INTERRUPTED）。所以先清掉残留构建进程。
STALE=$(pgrep -f "xcodebuild" | wc -l | tr -d ' ')
if [[ "$STALE" -gt 0 ]]; then
  info "清理 ${STALE} 个残留 xcodebuild 进程（并发构建会死锁）"
  pkill -9 -f "xcodebuild" 2>/dev/null || true
fi
if pgrep -qf "SWBBuildService"; then
  info "重置构建服务（SWBBuildService）"
  pkill -9 -f "SWBBuildService" 2>/dev/null || true
fi
sleep 2

# ---------- 5. 跑测试 ----------
LOG="build/test-$(date +%H%M%S).log"
mkdir -p build
# macOS 自带 bash 3.2：set -u 下空数组 `"${EXTRA[@]}"` 会报 unbound，
# 因此用条件展开写法；也顺手避免 `&&` 后半句失败导致 set -e 语义歧义。
EXTRA=()
if [[ -n "$ONLY" ]]; then EXTRA=(-only-testing:"PianoSempaiTests/$ONLY"); fi

info "开始（日志 ${LOG}）"
xcodebuild -skipMacroValidation -scheme PianoSempai \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -derivedDataPath "$DD_PATH" \
  -clonedSourcePackagesDirPath build/device/SourcePackages \
  -disableAutomaticPackageResolution \
  SWIFT_ENABLE_EXPLICIT_MODULES=NO \
  ${EXTRA[@]+"${EXTRA[@]}"} test >"$LOG" 2>&1
RC=$?

PASSED=$(grep -cE 'Test Case .* passed' "$LOG" || true)
FAILED=$(grep -cE 'Test Case .* failed' "$LOG" || true)
echo
echo "passed=$PASSED failed=$FAILED  (exit=$RC)"

if [[ $RC -ne 0 ]]; then
  echo "----- 诊断 -----"
  if grep -q "PruneExplicitPrecompiledModules" "$LOG" && [[ $PASSED -eq 0 ]]; then
    echo "卡在 PruneExplicitPrecompiledModules：SWBBuildService（Xcode 26 新构建引擎）"
    echo "在显式模块裁剪阶段死锁。已在命令里加 SWIFT_ENABLE_EXPLICIT_MODULES=NO 规避；"
    echo "若仍出现，再检查磁盘可用空间（<20GB 会显著放大该问题）。"
  elif grep -q "hung before establishing connection" "$LOG"; then
    echo "测试运行器没连上模拟器：simctl shutdown all + 重新 boot，再跑一次。"
  elif grep -q "Unable to find a device matching" "$LOG"; then
    echo "destination 解析失败：确认 simctl list 里该 UDID 存在且已 booted。"
  else
    echo "首条错误："
    grep -m3 -E "error:" "$LOG" | sed 's/^/  /'
  fi
  exit "$RC"
fi
echo "✓ 全绿"
