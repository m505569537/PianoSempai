import Combine
import Foundation

/// MIDI 中枢（spike 版）：持有当前事件源（真机/模拟可切换），
/// 全部事件过 HeldNoteTracker 双保险后分发（回调 + 结构化日志）。
/// P1 功能实装时 TakeStore/练习室从 onEvent 消费。
@MainActor
final class MIDIHub: ObservableObject {
    /// App 单例（AppFrame 与 onboarding 流程共享同一事件流与连接态）
    @MainActor static let shared = MIDIHub()
    enum Mode: String, CaseIterable, Identifiable {
        case simulated
        case real
        var id: Self { self }
        var label: String {
            switch self {
            case .simulated: "模拟输入"
            case .real: "真机（CoreMIDI）"
            }
        }
    }

    @Published private(set) var events: [MIDIEvent] = []
    @Published private(set) var isConnected = false
    @Published var mode: Mode = .simulated {
        didSet { switchSource(mode) }
    }
    /// 跟弹/判分消费的事件出口（spike 阶段 UI 也从这里拿）
    var onEvent: ((MIDIEvent) -> Void)?

    private(set) var source: MIDIEventSource?
    /// HeldNoteTracker 不在源内而在中枢：模拟源与真机源走同一套双保险
    private var tracker = HeldNoteTracker()
    private var truncationPump: Timer?
    private let maxLogEvents = 100

    init() {
        switchSource(.simulated)
    }

    var connectedDeviceName: String? {
        source?.name
    }

    func switchSource(_ mode: Mode) {
        truncationPump?.invalidate()
        source?.stop()
        tracker = HeldNoteTracker() // 换源时清 held 状态

        let newSource: MIDIEventSource
        switch mode {
        case .simulated:
            newSource = SimulatedMIDIEventSource()
        case .real:
            if let core = CoreMIDISource() {
                newSource = core
            } else {
                // CoreMIDI 初始化失败：回退模拟源，真实连接态 false
                newSource = SimulatedMIDIEventSource()
            }
        }
        newSource.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleTracked(event)
            }
        }
        newSource.onConnectionChanged = { [weak self] connected in
            Task { @MainActor in
                self?.isConnected = connected
            }
        }
        try? newSource.start()
        source = newSource
        isConnected = mode == .simulated

        // 超时截断由定时器泵驱动（100ms 粒度，截断点仍精确到 start+800ms）
        let pump = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let truncated = self.tracker.truncateExpired(now: DispatchTime.now().uptimeNanoseconds)
                truncated.forEach(self.distribute)
            }
        }
        RunLoop.main.add(pump, forMode: .common)
        truncationPump = pump
    }

    /// 模拟源专用便捷入口（屏幕琴键/自动回放/断连模拟）
    var simulated: SimulatedMIDIEventSource? {
        source as? SimulatedMIDIEventSource
    }

    /// 真机源便捷入口（S03 设备列表）
    var real: CoreMIDISource? {
        source as? CoreMIDISource
    }

    /// S03 用：临时构建真机源查看系统设备名单（不影响当前源）
    static func systemSourceNames() -> [String] {
        guard let probe = CoreMIDISource() else { return [] }
        return probe.sourceNames
    }

    private func handleTracked(_ raw: MIDIEvent) {
        for normalized in tracker.process(raw) {
            distribute(normalized)
        }
    }

    private func distribute(_ event: MIDIEvent) {
        events.append(event)
        if events.count > maxLogEvents {
            events.removeFirst(events.count - maxLogEvents)
        }
        onEvent?(event)
        // 结构化打印（红线 3：日志不涉 Key；MIDI 日志仅 spike 诊断用）
        print("[MIDI] \(event.structuredDescription)")
    }
}
