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
    static func parse(data: [UInt8], timeStamp: MIDITimeStamp, timebase: mach_timebase_info_data_t) -> [MIDIEvent] {
        let nanos = timeStamp * UInt64(timebase.numer) / UInt64(timebase.denom)
        var events: [MIDIEvent] = []
        var i = 0
        while i < data.count {
            let status = data[i]
            guard status & 0x80 == 0x80 else { i += 1; continue } // 跳过 running status 尾巴
            let type = status & 0xF0
            let channel = status & 0x0F
            let twoByte = (type == 0xC0 || type == 0xD0)
            guard i + (twoByte ? 1 : 2) < data.count else { break }
            switch type {
            case 0x90:
                let note = data[i + 1], velocity = data[i + 2]
                if velocity == 0 {
                    events.append(MIDIEvent(kind: .noteOff(note: note, velocity: 0), channel: channel, timeNanos: nanos))
                } else {
                    events.append(MIDIEvent(kind: .noteOn(note: note, velocity: velocity), channel: channel, timeNanos: nanos))
                }
            case 0x80:
                events.append(MIDIEvent(kind: .noteOff(note: data[i + 1], velocity: data[i + 2]), channel: channel, timeNanos: nanos))
            case 0xB0:
                if data[i + 1] == 64 {
                    events.append(MIDIEvent(kind: .sustainPedal(value: data[i + 2]), channel: channel, timeNanos: nanos))
                }
            default:
                break
            }
            i += twoByte ? 2 : 3
        }
        return events
    }
}

enum MIDIError: Error {
    case coreMIDI(status: OSStatus, where: String)
}
