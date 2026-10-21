#!/bin/bash
# 下载随包音源 MuseScore_General.sf2（约 206MB，MIT）。
#
# 为什么不入 git：GitHub 硬性拒绝 >100MB 的单文件（历史里也不行），
# 206MB 的 SF2 会让整个 push 失败。详见 docs/decisions/0002-demo-playback-soundfont.md。
#
# 首次 clone / 换机后先跑本脚本再 build。缺文件时 build 仍通过，但示范播放会走
# DemoPlaybackService 的 .unavailable 安全禁用（不崩、不弹 Alert）。
set -euo pipefail
cd "$(dirname "$0")/.."

DEST_DIR="PianoSempai/Resources/SoundFonts"
DEST="$DEST_DIR/MuseScore_General.sf2"
URL="${SOUNDFONT_URL:-https://ftp.osuosl.org/pub/musescore/soundfont/MuseScore_General/MuseScore_General.sf2}"
SHA256="ee51d2c4b1525e70f19a45909c4fd7a2e26d91d115fa89dbf5a6bc413d8b9bf3"

verify() {
  [ -f "$1" ] && [ "$(shasum -a 256 "$1" | awk '{print $1}')" = "$SHA256" ]
}

if verify "$DEST"; then
  echo "音源已就位：$DEST"
  exit 0
fi

mkdir -p "$DEST_DIR"
TMP="$(mktemp "$DEST_DIR/.MuseScore_General.XXXXXX")"
trap 'rm -f "$TMP"' EXIT

echo "下载 $URL"
echo "（约 206MB；中断后重跑会重新开始）"
curl -fL --progress-bar -o "$TMP" "$URL"

if ! verify "$TMP"; then
  echo "校验失败：sha256 不匹配（下载不完整，或上游文件已变）。" >&2
  echo "实际：$(shasum -a 256 "$TMP" | awk '{print $1}')" >&2
  echo "如上游确实换了版本，请同步更新本脚本里的 SHA256。" >&2
  exit 1
fi

mv "$TMP" "$DEST"
trap - EXIT
echo "完成：$DEST"
