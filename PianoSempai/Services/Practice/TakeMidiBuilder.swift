import Foundation
import SheetMusicMIDI

// Take 重放：解析后的演奏 → SMF（CURRENT.md Issue 2 · Stage A）。
//
// 输入是 MidiTakeParser.parse 的输出（[PlayedNote]：onsetSec/endSec/velocity/pitch，
// 踏板修正与断连分段都已处理过）。本类型只做「音符 → SMF 事件」的纯转换，不读盘、不触库。
//
// 核心口径：**按真实墙钟时序回放**。
// MidiTakeParser 把时间归零到首事件（min(t) rebase），但断连区间只影响段号、不压缩时间轴，
// 所以 onsetSec 之间的差值就是真实时间差。要原样还原，就需要一个「已知且恒定」的 tempo：
// 这里把整曲跨度 span 对齐到 ceil(span) 个四分音符（名义 120 BPM 下 1 拍 = 1 秒），
// 再反推 microsecondsPerQuarter = span × 1e6 / beats。
// 于是 totalTicks 个 tick 恰好占 span 秒，每个音的 tick = (onset − firstOnset)/span × totalTicks，
// 时序与录音逐毫秒一致——不依赖 take 是否弹得稳（若按 take.tempoAvg 定 tempo，
// 弹得不匀的地方会被"修正"掉，那就不是"我听我自己弹的"了）。
//
// 两个硬约束（都是包内 MidiWriter 的 precondition，踩了直接 trap）：
// 1. 事件必须按 tick 升序（MidiWriter.swift:26 `precondition(delta >= 0)`）。
// 2. 同一 tick 上 noteOff 必须排在 noteOn 之前（同音重复articulation时顺序反了会吃掉一个音）。
//
// 空 take / 零时长 take 都要返回「可写、可加载、不出声」的最小合法文件，不能除零。

enum TakeMidiBuilder {

    /// 默认 PPQ。取 480（与 MusicXML 渲染管线的常用值一致；本项目拜厄/哈农谱实际 division
    /// 由 ScoreLoader 决定，这里只做重放，无需与谱面对齐）。
    static let defaultDivision = 480

    /// SMF tempo 是 3 字节，上限 0xFFFFFF 微秒/四分音符
    private static let maxTempo = 0xFF_FFFF

    /// 零时长 take 的兜底 tempo（120 BPM）。只在 span ≤ 0 时用到。
    private static let fallbackTempo = 500_000

    /// 把一次演奏重建成单轨 SMF（format 0）。
    /// - Parameters:
    ///   - notes: MidiTakeParser 的输出；本函数会自行按 (onset, pitch) 稳定排序，不依赖调用方顺序。
    ///   - division: PPQ（每四分音符 tick 数）
    /// - Returns: 可直接交给 `SwiftySynthBackend.loadSequence(_:timeline:)` 的 MidiFile。
    static func build(notes: [PlayedNote], division: Int = defaultDivision) -> SheetMusicMIDI.MidiFile {
        let div = max(1, division)

        // 空 take：一条空轨（writer 会自动补 endOfTrack）。不出声，但文件合法。
        guard !notes.isEmpty else {
            return SheetMusicMIDI.MidiFile(
                division: div, format: 0,
                tracks: [SheetMusicMIDI.MidiTrack(events: [])])
        }

        let ordered = notes.sorted { lhs, rhs in
            if lhs.onsetSec != rhs.onsetSec { return lhs.onsetSec < rhs.onsetSec }
            return lhs.pitch < rhs.pitch
        }
        let firstOnset = ordered[0].onsetSec
        let lastEnd = ordered.map(\.endSec).max() ?? firstOnset
        let span = lastEnd - firstOnset

        // 跨度对齐到整数拍，反推 tempo。span ≤ 0（整曲零时长）时走兜底 tempo，所有音落在 tick 0。
        let beats: Int
        let tempo: Int
        if span > 0 {
            beats = max(1, Int(span.rounded(.up)))
            tempo = clampedTempo(span * 1_000_000 / Double(beats))
        } else {
            beats = 1
            tempo = fallbackTempo
        }
        let totalTicks = beats * div

        func tick(_ seconds: Double) -> Int {
            guard span > 0 else { return 0 }
            let raw = ((seconds - firstOnset) / span * Double(totalTicks)).rounded()
            return min(max(0, Int(raw)), totalTicks)
        }

        // 事件收集：tempo + program change 在 tick 0，随后每个音一对 noteOn/noteOff。
        var events: [(tick: Int, order: Int, event: SheetMusicMIDI.MidiEvent)] = []
        events.append((0, 0, .meta(.tempo(microsecondsPerQuarter: tempo))))
        // 显式声明钢琴音色：不依赖合成器的 GM 默认 program（GM program 0 = Acoustic Grand Piano）。
        events.append((0, 1, .programChange(channel: 0, program: 0)))

        for note in ordered {
            let on = tick(note.onsetSec)
            // 至少给 1 tick，否则零时值音符可能不被发音
            let off = max(on + 1, tick(note.endSec))
            let velocity = max(1, min(127, Int(note.velocity)))
            let pitch = max(0, min(127, Int(note.pitch)))
            events.append((on, 2, .noteOn(channel: 0, pitch: pitch, velocity: velocity)))
            events.append((off, 0, .noteOff(channel: 0, pitch: pitch, velocity: 0)))
        }

        // 排序：tick 升序；同 tick 上 noteOff(order 0) < 元信息/音色(1) < noteOn(2)。
        events.sort { lhs, rhs in
            if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
            return lhs.order < rhs.order
        }

        let track = SheetMusicMIDI.MidiTrack(
            events: events.map { SheetMusicMIDI.TimedMidiEvent(tick: $0.tick, event: $0.event) })
        return SheetMusicMIDI.MidiFile(division: div, format: 0, tracks: [track])
    }

    private static func clampedTempo(_ micros: Double) -> Int {
        guard micros.isFinite, micros > 1 else { return 1 }
        return min(maxTempo, Int(micros.rounded()))
    }
}
