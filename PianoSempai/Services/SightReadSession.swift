import Foundation
import SheetMusicCore
import SheetMusicLoader

// 视奏采集（S04 第 2 小步，简化评估态）：按 brief「仅采原始数据」，
// 期望音符取自内置样例谱的小节区间；命中率用音序简单匹配（P1 简化，非对齐算法，M5/P2 升级）。
// 所有数字均来自真实 MIDI 事件，无随机/伪造（红线 2）。

struct SightReadSegment {
    let title: String
    let measureRange: ClosedRange<Int> // 1-based 小节号（展示用）
    let expectedPitches: [UInt8] // 谱面期望音（两声部都计入，按出现顺序）
}

struct SightReadSegmentResult {
    let expected: Int
    let matched: Int
    let pauses: Int
    /// 音序简单匹配命中率 0-1；expected == 0 时返回 nil（不编数字）
    var hitRate: Double? {
        expected > 0 ? Double(matched) / Double(expected) : nil
    }
}

/// 一次视奏采集会话：挂到 MIDIHub.onEvent 上收集 played 音，结束时分段结算。
@MainActor
final class SightReadSession: ObservableObject {
    @Published private(set) var collectedPitches: [UInt8] = []
    @Published private(set) var isCollecting = false
    /// 最近一个音的音名（实时反馈用，诚实显示实际收到的音）
    @Published private(set) var lastNoteName: String?

    private var startNanos: UInt64 = 0
    private var lastNoteNanos: UInt64 = 0
    private var notes: [(pitch: UInt8, nanos: UInt64)] = []

    func start() {
        notes = []
        collectedPitches = []
        isCollecting = true
        startNanos = DispatchTime.now().uptimeNanoseconds
        lastNoteNanos = 0
    }

    func handle(_ event: MIDIEvent) {
        guard isCollecting, case let .noteOn(note, velocity) = event.kind, velocity > 0 else { return }
        let nanos = event.timeNanos
        notes.append((note, nanos))
        collectedPitches.append(note)
        lastNoteName = Self.noteName(note)
        lastNoteNanos = nanos
    }

    func stop(expectedPitches: [UInt8]) -> SightReadSegmentResult {
        isCollecting = false
        // 音序贪心匹配：期望序列逐个在 played 里找第一次出现（从上个匹配点之后）
        var pointer = 0
        var matched = 0
        for expected in expectedPitches {
            if let idx = collectedPitches[pointer...].firstIndex(of: expected) {
                matched += 1
                pointer = idx + 1
            }
        }
        // 停顿：相邻两音间隔 > 2s
        var pauses = 0
        if notes.count > 1 {
            for i in 1..<notes.count where notes[i].nanos - notes[i - 1].nanos > 2_000_000_000 {
                pauses += 1
            }
        }
        return SightReadSegmentResult(expected: expectedPitches.count, matched: matched, pauses: pauses)
    }

    /// MIDI 音高 → 音名（如 C4），实时反馈用。纯函数：非隔离，供 S13 呈现层复用
    nonisolated static func noteName(_ midi: UInt8) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return names[Int(midi) % 12] + "\(Int(midi) / 12 - 1)"
    }

    /// 从内置样例谱取小节区间的期望音序列（真实解析，非硬编码）
    static func loadExpectedPitches(measures: ClosedRange<Int>) -> [UInt8] {
        guard let url = Bundle.main.url(forResource: "SpikeSample32", withExtension: "musicxml"),
              let score = try? ScoreLoader.loadScore(contentsOf: url) else { return [] }
        var pitches: [UInt8] = []
        for staff in score.parts.first?.staves ?? [] {
            for (idx, measure) in staff.measures.enumerated() where measures.contains(idx + 1) {
                for voice in measure.voices {
                    for element in voice.elements {
                        if case let .chord(chord) = element {
                            pitches.append(contentsOf: chord.notes.map { UInt8($0.pitch) })
                        }
                    }
                }
            }
        }
        return pitches
    }
}
