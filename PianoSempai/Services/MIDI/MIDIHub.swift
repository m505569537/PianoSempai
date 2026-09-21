import Combine
import Foundation

/// MIDI 中枢：持有当前事件源（真机/模拟可切换），
/// 全部事件过 HeldNoteTracker 双保险后分发（回调 + 结构化日志）。
///
/// 连接态状态机（2026-09-20 真机 P0 修复）：
/// - isConnected 的唯一事实来源是当前激活源的 onConnectionChanged 回调；
///   切源瞬间先归零，再由新源 start 上报真值——杜绝上一源残留与模式臆断。
/// - 启动默认模式：真机 = .real（立即扫描系统源，无设备即「未连接」）；
///   模拟器 = .simulated（无 CoreMIDI 设备，视觉验收依赖屏幕模拟键，文案如实标「模拟输入」）。
///   用 targetEnvironment(simulator) 区分，不用 DEBUG（真机 debug 也必须默认 real）。
/// - CoreMIDI 初始化失败 → 占位源（恒 disconnected），绝不借模拟源冒充 V70（红线 2）。
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

    /// 初始模式解析（纯函数，可单测）：模拟器环境 → .simulated，真机 → .real
    static func initialMode(isSimulatorEnvironment: Bool) -> Mode {
        isSimulatorEnvironment ? .simulated : .real
    }

    private static var runsInSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    @Published private(set) var events: [MIDIEvent] = []
    @Published private(set) var isConnected = false
    /// 系统 CoreMIDI 源名单（真机源每次 connectAllSources 时刷新——含外部建链/断开）。
    /// 统一事实源：界面订阅它即可在 GarageBand 等外部建立连接时自动刷新，不存局部快照。
    @Published private(set) var systemSourceNames: [String] = []
    @Published var mode: Mode {
        didSet { installSource(mode) }
    }
    /// 跟弹/判分消费的事件出口
    var onEvent: ((MIDIEvent) -> Void)?

    private(set) var source: MIDIEventSource?
    /// HeldNoteTracker 不在源内而在中枢：模拟源与真机源走同一套双保险
    private var tracker = HeldNoteTracker()
    private var truncationPump: Timer?
    private let maxLogEvents = 100

    // 源工厂（测试注入 fake 源；生产走真实现）
    private let makeRealSource: () -> MIDIEventSource?
    private let makeSimulatedSource: () -> MIDIEventSource

    init(
        initialMode: Mode? = nil,
        makeRealSource: @escaping () -> MIDIEventSource? = { CoreMIDISource() },
        makeSimulatedSource: @escaping () -> MIDIEventSource = { SimulatedMIDIEventSource() }
    ) {
        self.makeRealSource = makeRealSource
        self.makeSimulatedSource = makeSimulatedSource
        let resolved = initialMode ?? MIDIHub.initialMode(isSimulatorEnvironment: Self.runsInSimulator)
        mode = resolved
        installSource(resolved)
    }

    var connectedDeviceName: String? {
        source?.name
    }

    /// 显式切源（S03 选卡/练习室重连入口）。didSet 触发 installSource。
    func switchSource(_ mode: Mode) {
        self.mode = mode
    }

    /// 安装当前模式对应的源。连接态唯一事实来源 = 源的 onConnectionChanged 回调。
    private func installSource(_ newMode: Mode) {
        truncationPump?.invalidate()
        source?.stop()
        tracker = HeldNoteTracker() // 换源时清 held 状态
        isConnected = false // 切源瞬间先归零：不沿用上一个源的残留 true

        let newSource: MIDIEventSource
        switch newMode {
        case .simulated:
            // 仅当用户主动选择模拟源时才会走到这里；其 start 自报 connected 是真值
            newSource = makeSimulatedSource()
        case .real:
            if let real = makeRealSource() {
                newSource = real
            } else {
                // CoreMIDI 初始化失败：占位源恒 disconnected。
                // 不回退模拟源——否则它的 start 回调 true 会让胶囊冒充「特伦斯 V70 · 已连接」（红线 2）
                newSource = DisconnectedPlaceholderSource()
            }
        }
        newSource.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleTracked(event)
            }
        }
        newSource.onConnectionChanged = { [weak self] connected in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.isConnected = connected
                }
            } else {
                Task { @MainActor in
                    self?.isConnected = connected
                }
            }
        }
        // 真机源随连接态附报系统源名单（外部建链时名单变化，界面据此刷新）
        if let realSource = newSource as? CoreMIDISource {
            realSource.onSourcesChanged = { [weak self] names in
                if Thread.isMainThread {
                    MainActor.assumeIsolated {
                        self?.systemSourceNames = names
                    }
                } else {
                    Task { @MainActor in
                        self?.systemSourceNames = names
                    }
                }
            }
        }
        try? newSource.start()
        source = newSource

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

    /// 模拟源专用便捷入口（屏幕琴键/自动回放/断连模拟）；CoreMIDI 失败 fallback 下为 nil
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
        // 结构化打印（红线 3：日志不涉 Key；MIDI 日志仅诊断用）
        print("[MIDI] \(event.structuredDescription)")
    }
}

/// CoreMIDI 初始化失败时的占位源：恒 disconnected、零事件。
/// 结构上排除「fallback 模拟源冒充真机已连接」的可能（红线 2）。
final class DisconnectedPlaceholderSource: MIDIEventSource {
    let name = "未发现设备"
    let isSimulated = false
    var onEvent: ((MIDIEvent) -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?

    func start() throws {
        onConnectionChanged?(false)
    }

    func stop() {
        onConnectionChanged?(false)
    }
}
