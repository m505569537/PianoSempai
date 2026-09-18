import Dispatch
import Foundation

/// 模拟 MIDI 源（brief M1 Spike B 1）：屏幕琴键按压 + 自动回放两条路，
/// 产出与真机源同构的事件流（V70 真机无法在模拟器测，全链路验收走此源）。
final class SimulatedMIDIEventSource: MIDIEventSource {
    let name = "模拟输入"
    let isSimulated = true
    var onEvent: ((MIDIEvent) -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?

    /// 自动回放用的定时器集合（断连模拟/停止时统一 cancel）
    private var timers: [DispatchSourceTimer] = []
    private let lock = NSLock()

    func start() throws {
        onConnectionChanged?(true)
    }

    func stop() {
        cancelTimers()
        onConnectionChanged?(false)
    }

    // MARK: - 屏幕琴键

    func press(note: UInt8, velocity: UInt8 = 88, channel: UInt8 = 0) {
        emit(.noteOn(note: note, velocity: velocity), channel: channel)
    }

    func release(note: UInt8, channel: UInt8 = 0) {
        emit(.noteOff(note: note, velocity: 0), channel: channel)
    }

    func setSustain(_ value: UInt8, channel: UInt8 = 0) {
        emit(.sustainPedal(value: value), channel: channel)
    }

    // MARK: - 自动回放（固定序列，验收"模拟源打印结构化事件"用）

    /// 回放一段上行音阶（八分音符 @120bpm = 250ms/事件），可中途停止。
    func autoReplayScale(startNote: UInt8 = 60, count: Int = 8, noteInterval: TimeInterval = 0.5) {
        cancelTimers()
        for i in 0..<count {
            let note = startNote + UInt8(i)
            let onAt = UInt64(i * 2) * 250_000_000
            let offAt = UInt64(i * 2 + 1) * 250_000_000
            schedule(afterNanos: onAt) { [weak self] in
                self?.press(note: note)
            }
            schedule(afterNanos: offAt) { [weak self] in
                self?.release(note: note)
            }
        }
    }

    /// S11b 断连验收钩子：发出 connectionChanged(false)，不产生事件。
    func simulateDisconnect() {
        onConnectionChanged?(false)
    }

    // MARK: - 私有

    private func emit(_ kind: MIDIEvent.Kind, channel: UInt8) {
        let event = MIDIEvent(
            kind: kind,
            channel: channel,
            timeNanos: DispatchTime.now().uptimeNanoseconds
        )
        lock.lock()
        let handler = onEvent
        lock.unlock()
        handler?(event)
    }

    private func schedule(afterNanos nanosFromNow: UInt64, _ block: @escaping () -> Void) {
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + .nanoseconds(Int(clamping: nanosFromNow)))
        timer.setEventHandler { block() }
        timer.resume()
        lock.lock()
        timers.append(timer)
        lock.unlock()
    }

    private func cancelTimers() {
        lock.lock()
        timers.forEach { $0.cancel() }
        timers = []
        lock.unlock()
    }
}
