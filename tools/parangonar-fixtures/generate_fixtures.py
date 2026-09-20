#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
P2 判分引擎 parangonar 对拍夹具生成器（Hermes 侧权威工具，不进 App target）。

产出 Tests/PianoSempaiTests/Scoring/Fixtures/<case>/ 下：
  reference.json   参考音序列（pitch / onsetBeat / durationBeats / measureIndex / beatInMeasure / hand）
  performance.json 演奏音序列（pitch / onsetSec / endSec / velocity）
  expected.json    parangonar 跑出的三分类 ground truth（match/deletion/insertion 计数 + 明细）

口径（与 docs/p2-scoring/SPEC.md §5 对拍校准一致）：
  parangonar 只有 match/deletion/insertion，无 wrongPitch。
  Swift 投影：match=correct；deletion=missing+wrongPitch(ref侧)；insertion=extra+wrongPitch(演奏侧)。
参考统一 60 BPM（1 拍 = 1 秒），4/4，单 staff（hand=right），故 onsetSec == onsetBeat。
"""
import json
import os
import warnings
from pathlib import Path

warnings.filterwarnings("ignore")

import music21 as m21
import pandas as pd
import parangonar as pa

REPO = Path(__file__).resolve().parents[2]
FIX = REPO / "Tests" / "PianoSempaiTests" / "Scoring" / "Fixtures"

# 16 音参考旋律（C 大调上下行），每个四分音符，4/4，共 4 小节。
REF_PITCHES = [60, 62, 64, 65, 67, 69, 71, 72, 71, 69, 67, 65, 64, 62, 60, 60]
DIVISION = 4  # 每拍 4 个十六分刻度（与 Swift 端约定，仅用于 beat 换算展示）
TEMPO_BPM = 60


def measure_beat(onset_beat: float):
    """4/4：返回 (measureIndex 0-based, beatInMeasure)。"""
    bar = int(onset_beat // 4)
    in_bar = onset_beat - bar * 4
    return bar, round(in_bar, 4)


def write_reference(notes, case_dir: Path):
    """notes: list of dict(pitch, onsetBeat, durationBeats)。"""
    out = []
    for i, n in enumerate(notes):
        bar, in_bar = measure_beat(n["onsetBeat"])
        out.append({
            "id": i,
            "pitch": n["pitch"],
            "onsetBeat": round(n["onsetBeat"], 4),
            "durationBeats": n["durationBeats"],
            "measureIndex": bar,
            "beatInMeasure": in_bar,
            "hand": "right",
            "isGrace": False,
        })
    (case_dir / "reference.json").write_text(
        json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    return out


def write_performance(notes, case_dir: Path):
    """notes: list of dict(pitch, onsetSec, durationSec, velocity)。"""
    out = [{
        "pitch": n["pitch"],
        "onsetSec": round(n["onsetSec"], 4),
        "endSec": round(n["onsetSec"] + n["durationSec"], 4),
        "velocity": n.get("velocity", 80),
        "isSuspicious": False,
    } for n in sorted(notes, key=lambda x: x["onsetSec"])]
    (case_dir / "performance.json").write_text(
        json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    return out


def to_midi(path: Path, pitch_onset_duration, in_seconds=True):
    """把 (pitch, onset, duration) 序列写成单声部 MIDI（60BPM：beat 数 == 秒数）。"""
    s = m21.stream.Score()
    p = m21.stream.Part()
    for pitch, onset, dur in pitch_onset_duration:
        n = m21.note.Note(pitch)
        n.quarterLength = max(dur, 0.01)
        n.offset = onset  # quarter-length 坐标；60BPM 下数值等于秒
        p.append(n)
    s.append(p)
    s.write("midi", fp=str(path))


def run_parangonar(case_dir: Path):
    ref_mid = case_dir / "_ref.mid"
    perf_mid = case_dir / "_perf.mid"
    csv = case_dir / "_align.csv"
    pa.match_midis(str(ref_mid), str(perf_mid), output_file=str(csv))
    df = pd.read_csv(csv)
    detail = []
    for _, r in df.iterrows():
        detail.append({
            "alignmentType": r["alignment_type"],
            "refPitch": (None if pd.isna(r["ref_pitch"]) else int(r["ref_pitch"])),
            "performancePitch": (None if pd.isna(r["performance_pitch"]) else int(r["performance_pitch"])),
            "timingDeviationSec": (None if pd.isna(r["timing_deviation"]) else round(float(r["timing_deviation"]), 4)),
        })
    counts = df["alignment_type"].value_counts().to_dict()
    expected = {
        "matcher": f"parangonar {pa.__version__} / AutomaticNoteMatcher",
        "counts": {
            "match": int(counts.get("match", 0)),
            "deletion": int(counts.get("deletion", 0)),
            "insertion": int(counts.get("insertion", 0)),
        },
        "projectionNote": "match=correct; deletion=missing+wrongPitch(ref); insertion=extra+wrongPitch(perf)",
        "detail": detail,
    }
    (case_dir / "expected.json").write_text(
        json.dumps(expected, ensure_ascii=False, indent=2), encoding="utf-8")
    ref_mid.unlink(missing_ok=True)
    perf_mid.unlink(missing_ok=True)
    csv.unlink(missing_ok=True)
    return expected["counts"]


def ref_notes(pitches):
    return [{"pitch": pc, "onsetBeat": float(i), "durationBeats": 1.0}
            for i, pc in enumerate(pitches)]


CASES = {}

# 1) perfect：逐音一致。
CASES["01_perfect"] = {
    "ref": REF_PITCHES,
    "perf": [(pc, float(i), 0.9, 80) for i, pc in enumerate(REF_PITCHES)],
}

# 2) wrong_pitch：第 3 音 64 弹成 63（错音；parangonar 预期 deletion+insertion）。
wp = list(REF_PITCHES); wp[2] = 63
CASES["02_wrong_pitch"] = {
    "ref": REF_PITCHES,
    "perf": [(pc, float(i), 0.9, 80) for i, pc in enumerate(wp)],
}

# 3) missing：漏弹第 5、第 11 音（67、67），其余保持原 onset（不挤压时间）。
miss_idx = {4, 10}
CASES["03_missing"] = {
    "ref": REF_PITCHES,
    "perf": [(pc, float(i), 0.9, 80) for i, pc in enumerate(REF_PITCHES) if i not in miss_idx],
}

# 4) extra：在第 2 拍后半与第 10 拍后半多弹两个外音（90、91）。
extra = [(pc, float(i), 0.9, 80) for i, pc in enumerate(REF_PITCHES)]
extra += [(90, 1.5, 0.4, 70), (91, 9.5, 0.4, 70)]
CASES["04_extra"] = {"ref": REF_PITCHES, "perf": extra}

# 5) tempo_flex：单调渐慢（rit.），每拍累积延后。验证弹性节奏图会跟随整体速度变化，
#    仍应 16 match、不把渐慢误判成错音/漏音（PRD「不硬套等比」）。
#    注意：局部抢/拖的节奏【残差】评分由 TakeScorer 在 Swift 侧喂受控 deltaMs 单测，
#    parangonar 的弹性 warp 会吸收任何单调整体伸缩，对拍夹具不用于残差数值验收。
tf = []
for i, pc in enumerate(REF_PITCHES):
    onset = i + 0.05 * i          # 渐慢：越往后越拖
    tf.append((pc, onset, 0.9, 80))
CASES["05_tempo_flex"] = {"ref": REF_PITCHES, "perf": tf}

# 6) pedaled：onset 全对，但每个音实际延到下一个音之后（模拟踩踏板抬手不收音）。
ped = [(pc, float(i), 1.8, 80) for i, pc in enumerate(REF_PITCHES)]
CASES["06_pedaled"] = {"ref": REF_PITCHES, "perf": ped}


def main():
    summary = {}
    for case, body in CASES.items():
        case_dir = FIX / case
        case_dir.mkdir(parents=True, exist_ok=True)
        rnotes = ref_notes(body["ref"])
        write_reference(rnotes, case_dir)
        pnotes = write_performance(
            [{"pitch": pc, "onsetSec": o, "durationSec": d, "velocity": v}
             for pc, o, d, v in body["perf"]], case_dir)
        # parangonar 输入 MIDI（秒域 == beat 域，60BPM）
        to_midi(case_dir / "_ref.mid",
                [(n["pitch"], n["onsetBeat"], n["durationBeats"]) for n in rnotes])
        to_midi(case_dir / "_perf.mid",
                [(n["pitch"], n["onsetSec"], n["endSec"] - n["onsetSec"]) for n in pnotes])
        counts = run_parangonar(case_dir)
        summary[case] = counts
        print(f"{case:18s} match={counts['match']:2d} deletion={counts['deletion']} insertion={counts['insertion']}")
    print("\nfixtures ->", FIX)


if __name__ == "__main__":
    main()
