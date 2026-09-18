import Foundation

/// BLE 丢 noteOff 双保险（PRD M1 + brief M1 Spike B 3）：
/// 1. Note On velocity=0 视为 Note Off（标准 MIDI 惯例）；
/// 2. 超时截断：held 音超过 `timeoutNanos`（brief 锁定 800ms）无 noteOff，
///    在 800ms 处补发合成 noteOff 并标记"可疑事件"，禁止静默修正。
/// 纯逻辑、无 UI 依赖，供单元测试直接驱动。
final class HeldNoteTracker {
    static let defaultTimeoutNanos: UInt64 = 800_000_000 // 800ms

    private let timeoutNanos: UInt64
    /// 正在按住的音：note -> 开始时间（同一 note/channel 视为同一个键）
    private var held: [UInt8: UInt64] = [:]

    init(timeoutNanos: UInt64 = HeldNoteTracker.defaultTimeoutNanos) {
        self.timeoutNanos = timeoutNanos
    }

    var heldNoteCount: Int { held.count }

    /// 输入一条原始事件，返回 0..n 条规范化事件。
    /// 可能先截断同音的旧实例（重复 noteOn 视为 BLE 丢了前一个 noteOff）。
    func process(_ raw: MIDIEvent) -> [MIDIEvent] {
        var out: [MIDIEvent] = []

        switch raw.kind {
        case let .noteOn(note, velocity):
            if velocity == 0 {
                // 双保险 1：velocity=0 noteOn == noteOff
                held.removeValue(forKey: note)
                out.append(noteOff(from: raw, note: note, velocity: 0, suspicious: raw.isSuspicious))
            } else {
                // 同音重复 noteOn：先补发前一个 noteOff（可疑）
                if held[note] != nil {
                    out.append(syntheticNoteOff(note: note, at: raw.timeNanos))
                }
                held[note] = raw.timeNanos
                out.append(raw)
            }

        case let .noteOff(note, velocity):
            held.removeValue(forKey: note)
            out.append(noteOff(from: raw, note: note, velocity: velocity, suspicious: raw.isSuspicious))

        case .sustainPedal:
            out.append(raw)
        }
        return out
    }

    /// 泵当前时间，截断超时未结束的音（真机由定时器驱动，测试直接传时间）。
    func truncateExpired(now: UInt64) -> [MIDIEvent] {
        var out: [MIDIEvent] = []
        for (note, start) in held where now >= start + timeoutNanos {
            // 截断点严格落在 start + timeout（事件时间取截断时刻）
            out.append(MIDIEvent(
                kind: .noteOff(note: note, velocity: 0),
                channel: 0,
                timeNanos: start + timeoutNanos,
                isSuspicious: true
            ))
            held.removeValue(forKey: note)
        }
        return out
    }

    private func syntheticNoteOff(note: UInt8, at timeNanos: UInt64) -> MIDIEvent {
        MIDIEvent(
            kind: .noteOff(note: note, velocity: 0),
            channel: 0,
            timeNanos: timeNanos,
            isSuspicious: true
        )
    }

    private func noteOff(from raw: MIDIEvent, note: UInt8, velocity: UInt8, suspicious: Bool) -> MIDIEvent {
        MIDIEvent(
            kind: .noteOff(note: note, velocity: velocity),
            channel: raw.channel,
            timeNanos: raw.timeNanos,
            isSuspicious: suspicious
        )
    }
}
