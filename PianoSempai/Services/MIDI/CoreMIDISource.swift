import CoreMIDI
import Foundation

/// 真机 MIDI 源：CoreMIDI 直封（brief M1 允许的 fallback；PRD 的 SwiftMIDI 包选型矛盾记 docs/findings.md F1）。
/// 枚举系统全部 MIDI 输入源（含已配对的 BLE MIDI、USB、网络会话），逐个连接收包。
/// 模拟器无设备 → sources 为空、连接态 false；V70 真机验证项在 PRD"开工前实机验证"。
final class CoreMIDISource: MIDIEventSource {
    let name = "CoreMIDI（真机）"
    let isSimulated = false
    var onEvent: ((MIDIEvent) -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?

    private var client: MIDIClientRef = 0
    private var port: MIDIPortRef = 0
    private var connectedEndpoints: Set<MIDIEndpointRef> = []
    private let queue = DispatchQueue(label: "com.eeexu.pianosempai.midi")
    /// MIDITimeStamp（mach ticks）→ 纳秒换算
    private var timebase = mach_timebase_info_data_t()

    init?() {
        guard mach_timebase_info(&timebase) == KERN_SUCCESS else { return nil }
    }

    func start() throws {
        let status = MIDIClientCreateWithBlock("PianoSempai MIDI" as CFString, &client) { [weak self] notification in
            self?.handleNotification(notification.pointee)
        }
        guard status == noErr else {
            throw MIDIError.coreMIDI(status: status, where: "MIDIClientCreateWithBlock")
        }

        let inputStatus = MIDIInputPortCreateWithBlock(client, "PianoSempai In" as CFString, &port, { [weak self] packetList, _ in
            self?.handle(packetList: packetList)
        })
        guard inputStatus == noErr else {
            throw MIDIError.coreMIDI(status: inputStatus, where: "MIDIInputPortCreateWithBlock")
        }
        connectAllSources()
    }

    func stop() {
        for endpoint in connectedEndpoints {
            MIDIPortDisconnectSource(port, endpoint)
        }
        connectedEndpoints = []
        onConnectionChanged?(false)
    }

    /// 当前系统 MIDI 输入源名单（S03 向导设备列表用；BLE 设备需系统配对后才会出现）
    var sourceNames: [String] {
        (0..<MIDIGetNumberOfSources()).compactMap { i in
            let endpoint = MIDIGetSource(i)
            var name: Unmanaged<CFString>?
            guard MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name) == noErr, let name else { return nil }
            return name.takeRetainedValue() as String
        }
    }

    /// 是否发现疑似 V70 的源（名字含 v70，大小写不敏感）
    var hasV70Source: Bool {
        sourceNames.contains { $0.localizedCaseInsensitiveContains("V70") }
    }

    private func connectAllSources() {
        let count = MIDIGetNumberOfSources()
        for i in 0..<count {
            let endpoint = MIDIGetSource(i)
            if MIDIPortConnectSource(port, endpoint, nil) == noErr {
                connectedEndpoints.insert(endpoint)
            }
        }
        onConnectionChanged?(count > 0)
    }

    /// 源增减（BLE 配对/断开）→ 重新枚举并连接全部源；S03 实装时接重连逻辑
    /// （spike 范围：仅刷新，Hermes 验收用模拟源）
    private func handleNotification(_ notification: MIDINotification) {
        switch notification.messageID {
        case .msgSetupChanged, .msgObjectAdded, .msgObjectRemoved:
            connectAllSources()
        default:
            break
        }
    }

    private func handle(packetList: UnsafePointer<MIDIPacketList>) {
        let timebase = timebase
        var packet = packetList.pointee.packet
        for _ in 0..<packetList.pointee.numPackets {
            let length = Int(packet.length)
            var data = [UInt8](repeating: 0, count: length)
            withUnsafeBytes(of: packet.data) { buffer in
                for i in 0..<min(length, buffer.count) {
                    data[i] = buffer[i]
                }
            }
            let events = Self.parse(data: data, timeStamp: packet.timeStamp, timebase: timebase)
            if !events.isEmpty {
                queue.async { [weak self] in
                    for event in events {
                        self?.onEvent?(event)
                    }
                }
            }
            packet = MIDIPacketNext(&packet).pointee
        }
    }

    /// 解析原始 MIDI 字节流。只关心 note on/off 与 CC64；program change/pitch bend
    /// 按 PRD"记录但不依赖"——P1 spike 先忽略，S24 诊断页实装时补。
    ///
    /// 支持 MIDI 1.0 running status：CoreMIDI 交的是原始 cable 字节（不展开），BLE-MIDI
    /// （V70 链路）在多个消息共用同一时间戳时会省略 status 字节。省略时沿用上一个
    /// channel status（0x80...0xEF）解析，且不消耗 status 字节。
    static func parse(data: [UInt8], timeStamp: MIDITimeStamp, timebase: mach_timebase_info_data_t) -> [MIDIEvent] {
        let nanos = timeStamp * UInt64(timebase.numer) / UInt64(timebase.denom)
        var events: [MIDIEvent] = []
        var i = 0
        /// 最近一个 channel status 字节（0x80...0xEF），nil 表示尚未见过任何 status
        var runningStatus: UInt8?
        while i < data.count {
            let byte = data[i]
            let status: UInt8
            if byte & 0x80 == 0x80 {
                guard byte < 0xF0 else {
                    // 系统消息本解析器忽略。按 MIDI 1.0：0xF0–0xF7（含 SysEx）取消
                    // running status，0xF8–0xFF（实时消息）不影响它。
                    if byte < 0xF8 { runningStatus = nil }
                    i += 1
                    continue
                }
                runningStatus = byte
                status = byte
                i += 1
            } else if let last = runningStatus {
                status = last // running status：不消耗 status 字节
            } else {
                i += 1
                continue // 没有任何 status 在前，不能凭空发明一个
            }
            let type = status & 0xF0
            let channel = status & 0x0F
            let twoByte = (type == 0xC0 || type == 0xD0)
            // 此处 i 指向第一条数据字节（status 已被消耗，running status 则从未占用）
            guard i + (twoByte ? 1 : 2) <= data.count else { break }
            switch type {
            case 0x90:
                let note = data[i], velocity = data[i + 1]
                if velocity == 0 {
                    events.append(MIDIEvent(kind: .noteOff(note: note, velocity: 0), channel: channel, timeNanos: nanos))
                } else {
                    events.append(MIDIEvent(kind: .noteOn(note: note, velocity: velocity), channel: channel, timeNanos: nanos))
                }
            case 0x80:
                events.append(MIDIEvent(kind: .noteOff(note: data[i], velocity: data[i + 1]), channel: channel, timeNanos: nanos))
            case 0xB0:
                if data[i] == 64 {
                    events.append(MIDIEvent(kind: .sustainPedal(value: data[i + 1]), channel: channel, timeNanos: nanos))
                }
            default:
                break
            }
            i += twoByte ? 1 : 2 // 只跨数据字节：status 已在上面消耗（running status 则本就没占）
        }
        return events
    }
}

enum MIDIError: Error {
    case coreMIDI(status: OSStatus, where: String)
}
