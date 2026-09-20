import Foundation

// 演奏解析器（SPEC §4）：[RawMIDIEventRecord] → [PlayedNote]（踏板修正）+ 分段。
// 纯函数、不触库、不发网络（红线 6）。
//
// 口径：
// - 时间归零：PracticeSession 只在 performing 且 connected 时落盘事件，
//   故解析到的首事件即演奏起点，min(t) 归零（§4）。
// - 踏板修正（PRD L187）：damper（CC64 value>=64）踩着时 noteOff 不收音，
//   该音 endSec 延到「noteOff 之后第一次踏板抬起」；期间同 pitch 再按是新音（不合并）。
//   onset 一律用 noteOn（对齐基于 onset；踏板只影响 endSec）。
// - velocity=0 的 noteOn 按 noteOff 处理（上游 HeldNoteTracker 已转，双保险）。
// - 中断区间 take.interruptionRanges（断连秒起点列表）：中断空白内无事件（在线端暂停写），
//   解析按各断连起点把音符切成不连续段（tempo 估计不跨间隙，§5）；段内索引随音符输出。

enum MidiTakeParser {

    struct Result: Equatable, Sendable {
        /// onset 升序
        let notes: [PlayedNote]
        /// 每个音符所属的非中断段号（0-based，按断连起点切分）
        let segmentIndexOfNote: [Int]
        /// 每个非中断段的音符下标范围（对齐引擎按段独立处理）
        let segments: [Range<Int>]
        let pedalEventCount: Int
        let suspiciousCount: Int
    }

    /// - Parameters:
    ///   - events: TakeStore.readEvents 的输出（时间升序不保证，内部排序）
    ///   - interruptionRanges: 断连秒起点列表（Take.interruptionRanges）
    static func parse(events: [RawMIDIEventRecord], interruptionRanges: [Int] = []) -> Result {
        let sorted = events.sorted { $0.t < $1.t }
        guard let first = sorted.first else {
            return Result(notes: [], segmentIndexOfNote: [], segments: [], pedalEventCount: 0, suspiciousCount: 0)
        }
        let baseNanos = first.t
        func sec(_ nanos: UInt64) -> Double {
            Double(nanos &- baseNanos) / 1_000_000_000
        }

        let splits = Array(interruptionRanges.sorted()).filter { $0 >= 0 }

        var notes: [PlayedNote] = []
        var segmentOfNote: [Int] = []
        var pedalEventCount = 0
        var suspiciousCount = 0

        // damper 状态（CC64 value>=64 = 踩下）
        var damperDown = false
        // 正在按住的音实例（同 pitch 多实例按 FIFO，spec：同 pitch 重复是新音不合并）
        var active: [UInt8: [(onset: Double, velocity: UInt8, suspicious: Bool)]] = [:]
        // noteOff 时踏板踩着 → 挂起等抬踏板收音
        var pedalExtended: [(pitch: UInt8, onset: Double, velocity: UInt8, suspicious: Bool)] = []

        func closeNote(_ pitch: UInt8, at time: Double) {
            guard !active[pitch, default: []].isEmpty else { return }
            let instance = active[pitch]!.removeFirst()
            if active[pitch]?.isEmpty == true { active[pitch] = nil }
            if damperDown {
                pedalExtended.append((pitch, instance.onset, instance.velocity, instance.suspicious))
            } else {
                emit(pitch: pitch, onset: instance.onset, end: time,
                     velocity: instance.velocity, suspicious: instance.suspicious)
            }
        }

        func emit(pitch: UInt8, onset: Double, end: Double, velocity: UInt8, suspicious: Bool) {
            let segment = splits.filter { $0 <= Int(onset) }.count
            notes.append(PlayedNote(
                pitch: pitch,
                onsetSec: onset,
                endSec: max(end, onset),
                velocity: velocity,
                isSuspicious: suspicious
            ))
            segmentOfNote.append(segment)
        }

        for event in sorted {
            let t = sec(event.t)
            if event.suspicious { suspiciousCount += 1 }
            switch event.k {
            case "on":
                // velocity=0 的 noteOn 按 noteOff 处理（双保险，§4）
                if event.v == 0 {
                    closeNote(event.n, at: t)
                } else {
                    active[event.n, default: []].append((t, event.v, event.suspicious))
                }
            case "off":
                closeNote(event.n, at: t)
            case "cc64":
                pedalEventCount += 1
                let wasDown = damperDown
                damperDown = event.v >= 64
                if wasDown && !damperDown {
                    // 抬踏板：所有挂起音在此刻收音（PRD L187）
                    for held in pedalExtended {
                        emit(pitch: held.pitch, onset: held.onset, end: t,
                             velocity: held.velocity, suspicious: held.suspicious)
                    }
                    pedalExtended.removeAll()
                }
            default:
                break // 未知 kind 防御性忽略（上游只产 on/off/cc64）
            }
        }

        // 流结束：仍按住/挂起的音在末事件时刻收音（有界，不悬空）
        let endTime = sec(sorted.last!.t)
        for (pitch, instances) in active {
            for instance in instances {
                emit(pitch: pitch, onset: instance.onset, end: endTime,
                     velocity: instance.velocity, suspicious: instance.suspicious)
            }
        }
        for held in pedalExtended {
            emit(pitch: held.pitch, onset: held.onset, end: endTime,
                 velocity: held.velocity, suspicious: held.suspicious)
        }

        // 段范围（按 notes 数组下标；notes 已按 onset 升序 = 事件顺序，段单调）
        var segments: [Range<Int>] = []
        var cursor = 0
        var currentSegment = 0
        for (idx, seg) in segmentOfNote.enumerated() {
            if seg != currentSegment {
                segments.append(cursor..<idx)
                cursor = idx
                currentSegment = seg
            }
            if idx == notes.count - 1 {
                segments.append(cursor..<notes.count)
            }
        }
        if segments.isEmpty && !notes.isEmpty {
            segments = [0..<notes.count]
        }

        return Result(
            notes: notes,
            segmentIndexOfNote: segmentOfNote,
            segments: segments,
            pedalEventCount: pedalEventCount,
            suspiciousCount: suspiciousCount
        )
    }
}
