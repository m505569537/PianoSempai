import Foundation
import SheetMusicCore

// 谱面 → 跟弹期望序列（每小节期望音数组，两声部都计入；真实解析非硬编码）。

enum ScoreExpectedPitches {
    static func extract(score: Score) -> [[UInt8]] {
        guard let staff = score.parts.first?.staves.first else { return [] }
        var result: [[UInt8]] = []
        for measure in staff.measures {
            var pitches: [UInt8] = []
            for voice in measure.voices {
                for element in voice.elements {
                    if case let .chord(chord) = element {
                        pitches.append(contentsOf: chord.notes.map { UInt8($0.pitch) })
                    }
                }
            }
            result.append(pitches)
        }
        return result
    }

    static func measureCount(score: Score) -> Int {
        score.parts.first?.staves.first?.measures.count ?? 0
    }
}
