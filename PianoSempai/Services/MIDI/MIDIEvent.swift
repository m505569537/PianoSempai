import Foundation

/// 规范化 MIDI 事件（brief M1 Spike B：noteOn/noteOff/velocity/CC64/hostTime）。
/// 全 App 的 MIDI 输入统一走此模型；真机源与模拟源产出同构事件流。
struct MIDIEvent: Equatable, Sendable, Identifiable {
    enum Kind: Equatable, Sendable {
        case noteOn(note: UInt8, velocity: UInt8)
        case noteOff(note: UInt8, velocity: UInt8)
        /// CC64 延音踏板（单踏板，PRD M1 Q2）
        case sustainPedal(value: UInt8)
    }

    let id: UUID
    let kind: Kind
    let channel: UInt8
    /// 单调时钟纳秒（mach uptime 域；真机源由 MIDITimeStamp 换算，模拟源用 DispatchTime）
    let timeNanos: UInt64
    /// 可疑事件标记（PRD M1：异常音标记"可疑事件"，禁止静默修正）
    let isSuspicious: Bool

    init(id: UUID = UUID(), kind: Kind, channel: UInt8, timeNanos: UInt64, isSuspicious: Bool = false) {
        self.id = id
        self.kind = kind
        self.channel = channel
        self.timeNanos = timeNanos
        self.isSuspicious = isSuspicious
    }

    var note: UInt8? {
        switch kind {
        case let .noteOn(note, _), let .noteOff(note, _): note
        case .sustainPedal: nil
        }
    }

    var structuredDescription: String {
        let seconds = Double(timeNanos) / 1_000_000_000
        let body: String
        switch kind {
        case let .noteOn(note, velocity):
            body = "noteOn note=\(note) vel=\(velocity)"
        case let .noteOff(note, velocity):
            body = "noteOff note=\(note) vel=\(velocity)"
        case let .sustainPedal(value):
            body = "CC64 value=\(value)"
        }
        return String(format: "%.3f", seconds) + " ch\(channel + 1) \(body)" + (isSuspicious ? " [可疑]" : "")
    }
}
