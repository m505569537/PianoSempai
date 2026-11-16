#!/usr/bin/env python3
"""把外部 MusicXML / .mxl 规范化成随包谱（Resources/BundledScores）。

用途：教材曲目（如车尔尼 599）需要按 app 的命名约定落盘，且必须是能被
swift-sheet-music 解析的纯 MusicXML。本脚本负责三件事：

1. `.mxl`（压缩包）→ 解出真正的 MusicXML 文本
2. 文件名规范化：`<prefix>_<NN>.musicxml`（如 c599_01.musicxml）
3. 结构校验：能被 XML 解析、有 part/measure、音符数为正；并打印每首的小节数/音符数

用法：
    python3 Scripts/import_bundled_scores.py --book 599 --src ./musescore-599
    python3 Scripts/import_bundled_scores.py --book 599 --src ./x --dry-run
    python3 Scripts/import_bundled_scores.py --book 599 --src ./x --map 3=5 --map 4=7

编号推断顺序：`--map` 显式指定 > 文件名里的数字 > 报错要求手填。
"""

from __future__ import annotations

import argparse
import re
import sys
import zipfile
from pathlib import Path
from xml.etree import ElementTree

# 教材 → 资源名前缀 + 合法编号区间（与 BundledScore.resourceName 保持一致）
BOOKS: dict[str, tuple[str, range]] = {
    "599": ("c599", range(1, 11)),
    "849": ("c849", range(1, 31)),
}

MUSICXML_SUFFIXES = {".musicxml", ".xml"}


def extract_musicxml(path: Path) -> bytes:
    """读出一个谱文件里的 MusicXML 字节。.mxl 走 META-INF/container.xml。"""
    if path.suffix.lower() != ".mxl":
        return path.read_bytes()

    with zipfile.ZipFile(path) as zf:
        # Compressed MusicXML 规范：META-INF/container.xml 指向根谱文件
        root_name = None
        if "META-INF/container.xml" in zf.namelist():
            container = ElementTree.fromstring(zf.read("META-INF/container.xml"))
            for node in container.iter():
                if node.tag.endswith("rootfile"):
                    root_name = node.get("full-path")
                    break
        if not root_name:
            candidates = [
                n for n in zf.namelist()
                if Path(n).suffix.lower() in MUSICXML_SUFFIXES and not n.startswith("META-INF/")
            ]
            if not candidates:
                raise ValueError(f"{path.name}: .mxl 里找不到 MusicXML")
            root_name = candidates[0]
        return zf.read(root_name)


def inspect(data: bytes) -> tuple[int, int, bool]:
    """返回 (小节数, 音符数, 是否两部/双谱表)。解析失败抛异常。"""
    root = ElementTree.fromstring(data)
    measures = [e for e in root.iter() if e.tag.endswith("measure")]
    notes = [e for e in root.iter() if e.tag.endswith("note")]
    staves = {e.text for e in root.iter() if e.tag.endswith("staves")}
    two_staff = any((s or "").strip() == "2" for s in staves)
    return len(measures), len(notes), two_staff


def number_from_name(path: Path) -> int | None:
    """从文件名推断条目编号。

    先剥掉作品号（`Op.599` / `op599` / `Op 599`），再取剩余数字里**最后一个**。
    否则 `Czerny ... No 1 Op 599.mxl` 会误取 599（作品号）而不是 1（条目号）。
    """
    stem = path.stem
    stem = re.sub(r"(?i)\bop\.?\s*\d+", " ", stem)
    candidates = re.findall(r"(?<!\d)(\d{1,3})(?!\d)", stem)
    if not candidates:
        return None
    return int(candidates[-1])


def main() -> int:
    parser = argparse.ArgumentParser(description="规范化随包 MusicXML")
    parser.add_argument("--book", required=True, choices=sorted(BOOKS), help="教材编号（599 / 849）")
    parser.add_argument("--src", required=True, type=Path, help="源目录（含 .mxl / .musicxml）")
    parser.add_argument("--dry-run", action="store_true", help="只检查不写盘")
    parser.add_argument("--map", action="append", default=[], metavar="N=M",
                        help="强制映射：源文件推断出的编号 N → 目标编号 M，可重复")
    args = parser.parse_args()

    prefix, valid_range = BOOKS[args.book]
    forced = {}
    for item in args.map:
        try:
            src_no, dst_no = (int(x) for x in item.split("=", 1))
        except ValueError:
            print(f"--map 格式应为 N=M，收到：{item}", file=sys.stderr)
            return 2
        forced[src_no] = dst_no

    if not args.src.is_dir():
        print(f"源目录不存在：{args.src}", file=sys.stderr)
        return 2

    sources = sorted(
        p for p in args.src.iterdir()
        if p.suffix.lower() in MUSICXML_SUFFIXES | {".mxl"} and not p.name.startswith(".")
    )
    if not sources:
        print(f"{args.src} 下没有 .mxl / .musicxml 文件", file=sys.stderr)
        return 2

    out_dir = Path(__file__).resolve().parent.parent / "PianoSempai" / "Resources" / "BundledScores"
    written: dict[int, str] = {}
    problems: list[str] = []

    for src in sources:
        try:
            data = extract_musicxml(src)
            measures, notes, two_staff = inspect(data)
        except Exception as exc:  # noqa: BLE001 - 逐文件报错，不中断整批
            problems.append(f"{src.name}: {exc}")
            continue

        if measures == 0 or notes == 0:
            problems.append(f"{src.name}: 解析成功但内容为空（小节 {measures} / 音符 {notes}）")
            continue

        inferred = number_from_name(src)
        target = forced.get(inferred) if inferred is not None else None
        if target is None:
            target = inferred
        if target is None:
            problems.append(f"{src.name}: 文件名里没有编号，请用 --map 指定")
            continue
        if target not in valid_range:
            problems.append(
                f"{src.name}: 编号 {target} 不在 {prefix} 的合法区间 "
                f"{valid_range.start}-{valid_range.stop - 1}"
            )
            continue
        if target in written:
            problems.append(f"{src.name}: 编号 {target} 与 {written[target]} 冲突")
            continue

        dest = out_dir / f"{prefix}_{target:02d}.musicxml"
        written[target] = src.name
        staff_note = "双谱表" if two_staff else "单谱表"
        print(f"  {src.name}  ->  {dest.name}   小节 {measures:>3} · 音符 {notes:>4} · {staff_note}")
        if not args.dry_run:
            out_dir.mkdir(parents=True, exist_ok=True)
            # 统一写成 UTF-8 文本，避免 BOM/编码差异影响解析
            text = data.decode("utf-8", errors="replace")
            if text.startswith("\ufeff"):
                text = text.lstrip("\ufeff")
            dest.write_text(text, encoding="utf-8")

    expected = set(valid_range)
    missing = sorted(expected - set(written))
    extra = sorted(set(written) - expected)

    print()
    print(f"完成：{len(written)} 首{'（dry-run，未写盘）' if args.dry_run else ''}")
    if missing:
        print(f"缺少编号：{', '.join(map(str, missing))}")
    if extra:
        print(f"区间外编号：{', '.join(map(str, extra))}")
    if problems:
        print("问题：")
        for line in problems:
            print(f"  - {line}")
    return 0 if not problems else 1


if __name__ == "__main__":
    raise SystemExit(main())
