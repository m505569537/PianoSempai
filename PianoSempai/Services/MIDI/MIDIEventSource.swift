import Foundation

/// MIDI 输入源抽象（brief M1 Spike B 1）：真机 CoreMIDI 源与模拟源可切换，
/// 全 App 只消费此协议产出的事件流。
protocol MIDIEventSource: AnyObject {
    var name: String { get }
    var isSimulated: Bool { get }
    /// 规范化后的事件回调（已经 HeldNoteTracker 双保险处理）
    var onEvent: ((MIDIEvent) -> Void)? { get set }
    /// 连接状态变化（真机源：设备出现/消失；模拟源：恒 connected）
    var onConnectionChanged: ((Bool) -> Void)? { get set }
    func start() throws
    func stop()
}
