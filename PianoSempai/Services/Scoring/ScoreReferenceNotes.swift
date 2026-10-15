import Foundation
import SheetMusicCore

// 参考谱提取器（SPEC §3）：Score → [ReferenceNote]，带 onset/时值/小节·拍/左右手。
// 纯函数、不触库、不发网络（红线 6）。
//
// 关键口径（M1 FINDINGS D-1，按包源码校准）：
// - VoiceElement **唯一占拍的 case 是 .chord(Chord)**；休止符 = 空 chord
//   （`chord.notes.isEmpty` / `element.isRest`），不存在 `.rest` case——空 chord
//   同样推进游标但不产音。
// - 其余 case（keySignature/timeSignature/clef/barLine/dynamic/spanner/fermata/
//   breath/harmony/…）是不占拍的标注：游标不推进、不产音，直接跳过。
// - `.locationShift(delta)`：按包语义平移该 voice 游标 delta 拍（钳制 ≥0）。
// - 时值必须先 `duration.resolved(in: effectiveMeasureDuration)` 再 `.ticks(division:)`
//   （`.measure` 不 resolved 会 trap，包内文档明示）。
// - 倚音（graceNotesBefore/After）标 isGrace=true，挂在宿主 chord 的 onset 上，不占正拍游标。

enum ScoreReferenceNotes {

    struct Output: Equatable {
        let notes: [ReferenceNote]
        /// 双谱表判定（staffIndex 0=右手、1=左手；单 staff → hand=unknown，§1）
        let isTwoStaff: Bool
    }

    /// - Parameters:
    ///   - score: 已解析的谱面
    ///   - measureRange: 评分区间（0-based 闭区间；nil = 全曲）。区间起点拍归零（rebased）
    ///   - division: PPQ（缺省取 score.division，测试可注入）
    static func extract(
        score: Score,
        measureRange: ClosedRange<Int>? = nil,
        division: Int? = nil
    ) -> Output {
        let div = division ?? score.division
        guard let part = score.parts.first else { return Output(notes: [], isTwoStaff: false) }
        let staves = part.staves
        guard !staves.isEmpty else { return Output(notes: [], isTwoStaff: false) }
        let isTwoStaff = staves.count >= 2

        // 有效小节时值（Fraction，含拍号变化/不规则小节）；下标按绝对小节号。
        // 包 API 在 [Measure] 上（每 staff 各自算，拍号随 staff 携带）

        let totalMeasures = staves.first?.measures.count ?? 0
        let range: ClosedRange<Int> = measureRange ?? 0...(max(0, totalMeasures - 1))
        guard range.lowerBound >= 0, range.upperBound < max(totalMeasures, 1), totalMeasures > 0 else {
            return Output(notes: [], isTwoStaff: isTwoStaff)
        }

        var result: [ReferenceNote] = []

        for (staffIdx, staff) in staves.enumerated() {
            let hand: Hand = isTwoStaff ? (staffIdx == 0 ? .right : .left) : .unknown
            let measureDurations = staff.measures.effectiveMeasureDurations()

            // 区间起点之前的全局 tick（绝对游标；onsetBeat 最后 rebased）
            var startTick: Int = 0
            for m in 0..<range.lowerBound where measureDurations.indices.contains(m) {
                startTick += measureDurations[m].ticks(division: div)
            }

            var globalTick = startTick
            for m in range {
                guard staff.measures.indices.contains(m) else { break }
                let measureDuration: Fraction = measureDurations.indices.contains(m)
                    ? measureDurations[m]
                    : Fraction(numerator: 4, denominator: 4)
                let measureDurationTicks = measureDuration.ticks(division: div)

                for (voiceIndex, voice) in staff.measures[m].voices.enumerated() {
                    var tickInMeasure = 0
                    for (elementIndex, element) in voice.elements.enumerated() {
                        switch element {
                        case let .chord(chord):
                            let resolved = chord.duration.resolved(in: measureDuration)
                            let durationTicks = resolved.ticks(division: div)
                            // 空 chord = 休止：推进游标，不产音（D-1 口径）
                            if !chord.notes.isEmpty {
                                let onsetBeat = Double(globalTick + tickInMeasure) / Double(div) - Double(startTick) / Double(div)
                                let beatInMeasure = Double(tickInMeasure) / Double(div)
                                let durationBeats = Double(durationTicks) / Double(div)

                                // 倚音：挂宿主 chord onset，isGrace=true，不占正拍游标（§3）
                                for grace in chord.graceNotesBefore {
                                    for note in grace.notes {
                                        result.append(ReferenceNote(
                                            id: 0, pitch: UInt8(max(0, min(127, note.pitch))),
                                            onsetBeat: onsetBeat, durationBeats: durationBeats,
                                            measureIndex: m, beatInMeasure: beatInMeasure,
                                            hand: hand, isGrace: true
                                        ))
                                    }
                                }
                                for (noteIndexInChord, note) in chord.notes.enumerated() {
                                    result.append(ReferenceNote(
                                        id: 0,
                                        noteID: NoteID(
                                            staff: StaffAddress(partIndex: 0, staffIndexInPart: staffIdx),
                                            measureIndex: m,
                                            voiceIndex: voiceIndex,
                                            elementIndex: elementIndex,
                                            noteIndexInChord: noteIndexInChord
                                        ),
                                        pitch: UInt8(max(0, min(127, note.pitch))),
                                        onsetBeat: onsetBeat,
                                        durationBeats: durationBeats,
                                        measureIndex: m,
                                        beatInMeasure: beatInMeasure,
                                        hand: hand,
                                        isGrace: false
                                    ))
                                }
                                for grace in chord.graceNotesAfter {
                                    for note in grace.notes {
                                        result.append(ReferenceNote(
                                            id: 0, pitch: UInt8(max(0, min(127, note.pitch))),
                                            onsetBeat: onsetBeat, durationBeats: durationBeats,
                                            measureIndex: m, beatInMeasure: beatInMeasure,
                                            hand: hand, isGrace: true
                                        ))
                                    }
                                }
                            }
                            tickInMeasure += durationTicks
                        case let .locationShift(delta):
                            // 包语义：平移该 voice 游标 delta 拍（钳制 ≥0，防负游标）
                            tickInMeasure = max(0, tickInMeasure + delta.ticks(division: div))
                        default:
                            // 不占拍标注：跳过（游标不推进、不产音）
                            break
                        }
                    }
                }
                globalTick += measureDurationTicks
            }
        }

        // 稳定排序 + 顺序赋 id（「提取顺序稳定 id」）
        let sorted = result.sorted {
            if $0.onsetBeat != $1.onsetBeat { return $0.onsetBeat < $1.onsetBeat }
            if $0.hand != $1.hand { return handOrder($0.hand) < handOrder($1.hand) }
            if $0.pitch != $1.pitch { return $0.pitch < $1.pitch }
            return $0.isGrace && !$1.isGrace
        }
        let withIDs = sorted.enumerated().map { idx, note in
            ReferenceNote(
                id: idx, noteID: note.noteID, pitch: note.pitch, onsetBeat: note.onsetBeat,
                durationBeats: note.durationBeats, measureIndex: note.measureIndex,
                beatInMeasure: note.beatInMeasure, hand: note.hand, isGrace: note.isGrace
            )
        }
        return Output(notes: withIDs, isTwoStaff: isTwoStaff)
    }

    private static func handOrder(_ hand: Hand) -> Int {
        switch hand {
        case .right: 0
        case .left: 1
        case .unknown: 2
        }
    }
}
