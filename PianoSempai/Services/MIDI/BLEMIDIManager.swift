import CoreBluetooth
import CoreMIDI
import Foundation

// MARK: - 发现的 BLE-MIDI 外设

/// 扫描到的外设快照。纯数据：故意不放在 @MainActor 的 manager 里，
/// 让列表去重/排序/状态机可以在任何上下文单测。
struct BLEMIDIDevice: Identifiable, Equatable {
    enum State: Equatable {
        case discovered, connecting, connected, failed

        /// 展示排序权重：已连接最前，失败垫底
        var sortRank: Int {
            switch self {
            case .connected: 0
            case .connecting: 1
            case .discovered: 2
            case .failed: 3
            }
        }

        /// 取更"靠前"的状态（重复上报不得把 connected 降级成 discovered）
        static func higher(_ a: State, _ b: State) -> State {
            a.sortRank <= b.sortRank ? a : b
        }
    }

    static let unnamed = "未命名设备"

    let id: UUID
    let name: String
    let rssi: Int
    let state: State
    /// 广播里是否携带 BLE-MIDI service UUID（已确认的 MIDI 外设）。
    /// false = 只是候选：全扫描会捞到附近所有蓝牙设备（耳机/手表…），
    /// 是否 MIDI 设备等用户点「连接」后由 GATT 服务发现判定，不主动连接探测。
    let advertisedMIDIService: Bool

    init(id: UUID, name: String?, rssi: Int, state: State, advertisedMIDIService: Bool = false) {
        self.id = id
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmed.isEmpty ? Self.unnamed : trimmed
        self.rssi = rssi
        self.state = state
        self.advertisedMIDIService = advertisedMIDIService
    }

    /// 同一外设重复上报：名字优先有信息的那个，状态取更靠前的，RSSI 用最新的
    func merged(with other: BLEMIDIDevice) -> BLEMIDIDevice {
        let name = self.name == Self.unnamed ? other.name : self.name
        return BLEMIDIDevice(
            id: id,
            name: name,
            rssi: other.rssi,
            state: State.higher(self.state, other.state),
            // 已确认的永不被降级成候选
            advertisedMIDIService: self.advertisedMIDIService || other.advertisedMIDIService
        )
    }
}

// MARK: - BLE-MIDI 纯逻辑（无 CoreBluetooth、无 actor 隔离，单测直接调）

enum BLEMIDILogic {
    /// 外设状态机事件
    enum Event: Equatable {
        case scanDiscovered, connectStarted, connectSucceeded, connectFailed, disconnected
    }

    /// 新发现的外设并入列表：按 identifier 去重，按状态/名字排序
    static func merged(_ devices: [BLEMIDIDevice], with incoming: BLEMIDIDevice) -> [BLEMIDIDevice] {
        var result = devices
        if let index = result.firstIndex(where: { $0.id == incoming.id }) {
            result[index] = result[index].merged(with: incoming)
        } else {
            result.append(incoming)
        }
        return sortedForDisplay(result)
    }

    static func sortedForDisplay(_ devices: [BLEMIDIDevice]) -> [BLEMIDIDevice] {
        devices.sorted { a, b in
            if a.state.sortRank != b.state.sortRank { return a.state.sortRank < b.state.sortRank }
            if a.name != b.name { return a.name < b.name }
            return a.id.uuidString < b.id.uuidString
        }
    }

    /// 外设状态机（纯函数）
    static func nextState(from: BLEMIDIDevice.State, event: Event) -> BLEMIDIDevice.State {
        switch event {
        case .scanDiscovered:
            // 扫描重复命中不得打断正在连接/已连接的状态
            return (from == .connecting || from == .connected) ? from : .discovered
        case .connectStarted:
            return from == .connected ? .connected : .connecting
        case .connectSucceeded:
            return from == .connecting ? .connected : from
        case .connectFailed:
            return from == .connecting ? .failed : from
        case .disconnected:
            return from == .connected ? .discovered : from
        }
    }

    /// BLE 连上后是否真的出现了 CoreMIDI 源（轮询判定；不得臆造）
    static func midiSourceAppeared(before: Int, after: Int) -> Bool {
        after > before
    }

    /// 连接成立判据（接管「已被其它 App 建链」的设备时也成立，不得臆造）：
    /// - 源数量真的变多：本 App 这次连接触发 iOS 建源；
    /// - 或源名单里已有与设备名互相匹配的源：设备早已被 GarageBand 等建链，
    ///   源在连接前就存在、数量不会 +1，只能靠名字匹配确认（口径同 S03 名字匹配）。
    /// 未命名/空名的设备不做名字匹配（否则空串会匹配任何源）。
    static func midiSourceConfirmed(countIncreased: Bool, sourceNames: [String], deviceName: String) -> Bool {
        if countIncreased { return true }
        let trimmed = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != BLEMIDIDevice.unnamed else { return false }
        return sourceNames.contains {
            $0.localizedCaseInsensitiveContains(trimmed) || trimmed.localizedCaseInsensitiveContains($0)
        }
    }

    /// GATT 验证未通过（连上了但无 MIDI 服务）：从候选列表移除。
    /// 全扫描会捞到耳机/手表等无关设备，用户点错是噪声不是失败——不置 failed 态。
    static func rejectingCandidate(_ devices: [BLEMIDIDevice], id: UUID) -> [BLEMIDIDevice] {
        devices.filter { $0.id != id }
    }
}

// MARK: - BLE-MIDI 发现与连接（2026-09-21 P0：连上了却没反应 / 扫不到 V70）

/// 为什么 iOS 设置里"已连接"还不够：
/// 在系统设置里配对 BLE 设备**不会**给 App 创建 CoreMIDI 源。BLE-MIDI 必须由 App 侧
/// 对 MIDI BLE service UUID 发起连接，iOS 才会自动创建 CoreMIDI source；随后
/// `CoreMIDISource.handleNotification`（.msgObjectAdded → connectAllSources）收到源并上报
/// 连接态。本类只负责"发现 + 连接"，不绕过、也不伪造那条链路。
///
/// 发现策略（2026-09-21 P0：V70 扫不到）：
/// - **无过滤全扫描**列候选。V70 的广播不携带 MIDI service UUID，按服务过滤必然零命中；
///   是否 MIDI 设备等用户点「连接」后由 GATT 服务发现判定（对齐苹果系统 MIDI 选择器，
///   不主动连接探测附近每一个设备）。
/// - **接管系统层连接**：`retrieveConnectedPeripherals(withServices:)` 取回 GarageBand 等
///   已建链的外设（跨 App 共享的连接），直接复用，不等它再广播。
/// - 连接成立判据见 `BLEMIDILogic.midiSourceConfirmed`：源数量变多，或源名单里已有匹配
///   设备名的源（接管已建链设备时源早已存在、数量不会 +1）。
///
/// 红线：
/// - 连接态唯一事实来源仍是 `MIDIHub.isConnected`（来自源的 onConnectionChanged）；
///   本类即使 BLE 已连上，也不会直接宣称"已连接"——以 CoreMIDI 源真的出现为准。
/// - 日志只打设备名/标识/源数量，不涉任何密钥。
@MainActor
final class BLEMIDIManager: ObservableObject {
    static let shared = BLEMIDIManager()

    /// BLE-MIDI service UUID（连上后 iOS 自动建 CoreMIDI 源）
    static let midiServiceUUID = CBUUID(string: "03B80E5A-EDE8-4B33-A751-6CE4A2337E39")

    enum ScanState: Equatable {
        /// 未开始 / 已停止扫描
        case idle
        case scanning
        case poweredOff
        case unauthorized
    }

    // MARK: - 发布状态

    @Published private(set) var devices: [BLEMIDIDevice] = []
    @Published private(set) var scanState: ScanState = .idle
    /// 上次连接成功、用于自动重连的标识
    @Published private(set) var lastConnectedID: UUID?
    /// 最近一次探测到的 CoreMIDI 源数量（BLE 连上后 iOS 建源 → 变大）
    @Published private(set) var midiSourceCount = 0

    // MARK: - CoreMIDI 源计数探测（测试注入假实现）

    protocol SourceProbe {
        func numberOfSources() -> Int
    }

    struct SystemSourceProbe: SourceProbe {
        func numberOfSources() -> Int {
            MIDIGetNumberOfSources()
        }
    }

    // MARK: - 内部状态

    private let queue = DispatchQueue(label: "com.eeexu.pianosempai.ble-midi")
    private let bridge = BLEMIDIManagerBridge()
    private var central: CBCentralManager?
    /// 强引用已连接/正在连接的外设（CoreBluetooth 的 delegate 是 weak，外设本身不 retain）
    private var peripherals: [UUID: CBPeripheral] = [:]
    private let probe: SourceProbe
    private let store: LastDeviceStore
    private var verifyTask: Task<Void, Never>?
    /// 连接前记录的源数量，用于判定"iOS 是否真的建了源"
    private var sourceCountBeforeConnect = 0
    /// 本轮里自动重连失败过的设备：不再自动重试，等用户显式点「连接」或「重新扫描」
    private var autoConnectBlocked: Set<UUID> = []
    /// 正在等待 GATT 服务发现回调（didDiscoverServices）的外设：超时判定用
    private var pendingGATTVerification = Set<UUID>()
    /// 每个外设的 GATT 验证超时任务（didConnect 后 ~8s 无服务回调即失败）
    private var gattTimeoutTasks: [UUID: Task<Void, Never>] = [:]

    init(probe: SourceProbe = SystemSourceProbe(), store: LastDeviceStore = LastDeviceStore()) {
        self.probe = probe
        self.store = store
        self.lastConnectedID = store.id
    }

    // MARK: - 扫描生命周期

    /// 开始（幂等）。S03 向导 / S24 诊断页出现时调用；只扫不连，
    /// 连接动作由用户点「连接」或自动重连触发。
    func start() {
        ensureCentral()
        if central?.state == .poweredOn {
            beginScanning()
        }
    }

    /// 停止扫描但**保留**已有连接（离开页面不等于断开琴）
    func stopScanning() {
        central?.stopScan()
        scanState = .idle
    }

    /// 重新扫描（诊断页「重新扫描」按钮）；同时解除自动重连的失败屏蔽
    func rescan() {
        autoConnectBlocked.removeAll()
        guard central?.state == .poweredOn else { return }
        central?.stopScan()
        beginScanning()
    }

    private func ensureCentral() {
        guard central == nil else { return }
        bridge.onState = { [weak self] state in
            Task { @MainActor in self?.handleBluetoothState(state) }
        }
        bridge.onDiscover = { [weak self] id, name, rssi, advertisedServices, connectable in
            Task { @MainActor in
                self?.handleDiscovery(id: id, name: name, rssi: rssi, advertisedServices: advertisedServices, connectable: connectable)
            }
        }
        bridge.onConnect = { [weak self] id in
            Task { @MainActor in self?.handleConnected(id: id) }
        }
        bridge.onConnectFailure = { [weak self] id in
            Task { @MainActor in self?.handleConnectFailure(id: id) }
        }
        bridge.onDisconnect = { [weak self] id in
            Task { @MainActor in self?.handleDisconnected(id: id) }
        }
        bridge.onServices = { [weak self] id, serviceUUIDs in
            Task { @MainActor in self?.handleServices(id: id, serviceUUIDs: serviceUUIDs) }
        }
        bridge.onRSSI = { [weak self] id, rssi in
            Task { @MainActor in self?.handleRSSI(id: id, rssi: rssi) }
        }
        central = CBCentralManager(delegate: bridge, queue: queue)
    }

    private func beginScanning() {
        guard let central, central.state == .poweredOn else { return }
        scanState = .scanning
        adoptSystemConnectedPeripherals()
        // 自动重连：iOS 记得已配对的外设，不必等它再广播
        if let last = store.id, peripherals[last] == nil,
           let remembered = central.retrievePeripherals(withIdentifiers: [last]).first {
            peripherals[last] = remembered
            print("[BLE] 自动重连上次设备 \(last.uuidString)")
            connect(peripheral: remembered)
        }
        // 无过滤全扫描（P0 修复）：V70 的 service UUID 不在广播包里，按服务过滤必然零命中。
        // 捞到的外设全部列为候选，是否 MIDI 设备由用户点「连接」后的 GATT 服务发现判定
        //（对齐苹果系统 MIDI 选择器；不主动连接探测附近每个设备）。
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    /// 接管系统层已连接的 BLE-MIDI 外设（GarageBand / 系统连接过留下的连接）。
    /// `retrieveConnectedPeripherals` 取回的是**任何 App** 连接过的外设，且已按 MIDI 服务过滤，
    /// 故取回项即已确认是 BLE-MIDI 设备；已被连接的不会再回调 didConnect，必须直接验服务。
    private func adoptSystemConnectedPeripherals() {
        guard let central else { return }
        for peripheral in central.retrieveConnectedPeripherals(withServices: [Self.midiServiceUUID]) {
            guard peripherals[peripheral.identifier] == nil else { continue }
            peripherals[peripheral.identifier] = peripheral
            peripheral.delegate = bridge
            devices = BLEMIDILogic.merged(devices, with: BLEMIDIDevice(
                id: peripheral.identifier,
                name: peripheral.name,
                rssi: 0, // 接管来的外设没有扫描 RSSI，随后 readRSSI 补真值
                state: .connecting,
                advertisedMIDIService: true
            ))
            print("[BLE] 接管系统层已连接设备 \(peripheral.identifier.uuidString)")
            peripheral.readRSSI()
            if peripheral.state == .connected {
                // 别人已连上：didConnect 不会再回调，直接做服务发现
                sourceCountBeforeConnect = probe.numberOfSources()
                armGATTVerificationTimeout(for: peripheral.identifier)
                peripheral.discoverServices([Self.midiServiceUUID])
            } else {
                connect(peripheral: peripheral)
            }
        }
    }

    /// GATT 服务发现超时（didConnect 后 ~8s 仍无 didDiscoverServices 回调）：
    /// 用户主动点了「连接」，超时是真实失败 → .failed 可重试并断开，避免卡在「连接中」。
    private func armGATTVerificationTimeout(for id: UUID) {
        pendingGATTVerification.insert(id)
        gattTimeoutTasks[id]?.cancel()
        gattTimeoutTasks[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, !Task.isCancelled else { return }
            guard self.pendingGATTVerification.contains(id) else { return }
            self.pendingGATTVerification.remove(id)
            print("[BLE] 服务发现超时 \(id.uuidString)")
            self.apply(.connectFailed, to: id)
            if let peripheral = self.peripherals[id] { self.central?.cancelPeripheralConnection(peripheral) }
        }
    }

    // MARK: - 连接 / 断开

    func connect(_ device: BLEMIDIDevice) {
        // 用户显式点击：解除该设备的自动重连屏蔽，允许重试
        autoConnectBlocked.remove(device.id)
        // 扫描阶段不强引用外设，这里按 identifier 取回（iOS 记得扫到过的外设）
        guard let central else { return }
        guard let peripheral = peripherals[device.id]
            ?? central.retrievePeripherals(withIdentifiers: [device.id]).first else {
            print("[BLE] 取回外设失败 \(device.id.uuidString)，请重新扫描")
            apply(.connectFailed, to: device.id)
            return
        }
        connect(peripheral: peripheral)
    }

    private func connect(peripheral: CBPeripheral) {
        guard let central else { return }
        peripherals[peripheral.identifier] = peripheral
        peripheral.delegate = bridge
        sourceCountBeforeConnect = probe.numberOfSources()
        apply(.connectStarted, to: peripheral.identifier)
        if peripheral.state == .connected {
            // 已被系统/其它 App 连接（接管路径）：didConnect 不会再回调，直接验服务
            armGATTVerificationTimeout(for: peripheral.identifier)
            peripheral.discoverServices([Self.midiServiceUUID])
        } else {
            print("[BLE] 连接 \(peripheral.identifier.uuidString)（连接前 CoreMIDI 源数量 \(sourceCountBeforeConnect)）")
            central.connect(peripheral, options: nil)
        }
    }

    /// 用户主动断开：清掉自动重连记录，避免立刻又连上
    func disconnect(_ device: BLEMIDIDevice) {
        store.clear()
        lastConnectedID = nil
        if let peripheral = peripherals[device.id] {
            central?.cancelPeripheralConnection(peripheral)
        }
        peripherals.removeValue(forKey: device.id)
        pendingGATTVerification.remove(device.id)
        gattTimeoutTasks[device.id]?.cancel()
        gattTimeoutTasks.removeValue(forKey: device.id)
        verifyTask?.cancel()
        apply(.disconnected, to: device.id)
        if central?.state == .poweredOn { beginScanning() }
    }

    // MARK: - 委托回调（已切回主线程）

    private func handleBluetoothState(_ state: CBManagerState) {
        switch state {
        case .poweredOn:
            beginScanning()
        case .poweredOff:
            central?.stopScan()
            scanState = .poweredOff
        case .unauthorized:
            // 授权被拒（CBManager.authorization == .denied）：扫不了，如实告知
            central?.stopScan()
            scanState = .unauthorized
        case .unsupported, .resetting, .unknown:
            central?.stopScan()
            scanState = .idle
        @unknown default:
            central?.stopScan()
            scanState = .idle
        }
    }

    private func handleDiscovery(id: UUID, name: String?, rssi: Int, advertisedServices: [CBUUID], connectable: Bool) {
        // 不可连接的广播（iBeacon / 只读广播）永远成不了外设，直接忽略
        guard connectable else { return }
        // 候选列表：全扫描会捞到附近所有蓝牙设备，广播带 MIDI 服务 UUID 的算已确认，
        // 其余列为候选——是否 MIDI 设备等用户点「连接」后由 GATT 服务发现判定。
        let isConfirmed = advertisedServices.contains(Self.midiServiceUUID)
        devices = BLEMIDILogic.merged(
            devices,
            with: BLEMIDIDevice(id: id, name: name, rssi: rssi, state: .discovered, advertisedMIDIService: isConfirmed)
        )
        // 自动重连：上次连过的设备一出现就重连（同一轮里失败过的不再自动重试）
        let isFreshDiscovery = devices.first(where: { $0.id == id })?.state == .discovered
        if store.id == id, !autoConnectBlocked.contains(id), isFreshDiscovery {
            print("[BLE] 发现上次设备，自动重连 \(id.uuidString)")
            reconnectToRemembered(id: id)
        }
    }

    /// 接管来的外设没有扫描 RSSI：readRSSI 回调补真值（拿不到就保持未知）
    private func handleRSSI(id: UUID, rssi: Int) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        let current = devices[index]
        devices[index] = BLEMIDIDevice(
            id: current.id,
            name: current.name,
            rssi: rssi,
            state: current.state,
            advertisedMIDIService: current.advertisedMIDIService
        )
    }

    private func reconnectToRemembered(id: UUID) {
        guard let central else { return }
        guard let remembered = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        connect(peripheral: remembered)
    }

    private func handleConnected(id: UUID) {
        print("[BLE] 已连接 \(id.uuidString)，发现 MIDI 服务")
        guard let peripheral = peripherals[id] else {
            // 极端情况：外设引用已丢（理论上 connect 前一定持有）
            apply(.connectFailed, to: id)
            return
        }
        armGATTVerificationTimeout(for: id)
        peripheral.discoverServices([Self.midiServiceUUID])
    }

    private func handleServices(id: UUID, serviceUUIDs: [CBUUID]?) {
        pendingGATTVerification.remove(id)
        gattTimeoutTasks[id]?.cancel()
        gattTimeoutTasks.removeValue(forKey: id)
        guard let serviceUUIDs else {
            // 发现服务失败：用户主动发起的连接，按真实失败处理（可重试）
            print("[BLE] 服务发现失败 \(id.uuidString)")
            apply(.connectFailed, to: id)
            if let peripheral = peripherals[id] { central?.cancelPeripheralConnection(peripheral) }
            return
        }
        guard serviceUUIDs.contains(Self.midiServiceUUID) else {
            // 连上了但不是 MIDI 外设：全扫描会捞到耳机/手表等无关设备，
            // 用户点错是噪声不是失败——静默断开并从候选列表移除，不冒充、不置 failed。
            print("[BLE] 设备无 MIDI 服务 \(id.uuidString)，移出列表")
            if let peripheral = peripherals[id] { central?.cancelPeripheralConnection(peripheral) }
            peripherals.removeValue(forKey: id)
            autoConnectBlocked.remove(id)
            devices = BLEMIDILogic.rejectingCandidate(devices, id: id)
            verifyTask?.cancel()
            return
        }
        verifyCoreMIDISource(for: id)
    }

    /// 轮询 CoreMIDI 源：iOS 在 BLE 连接建立后自动建源，
    /// 以"源数量真的变多、或源名单里已有匹配本设备名的源"作为连接成立的依据（不乐观、不伪造）。
    /// 第二条判据服务接管路径：设备早已被 GarageBand 等建链，源在连接前就存在、数量不会 +1。
    private func verifyCoreMIDISource(for id: UUID) {
        verifyTask?.cancel()
        let before = sourceCountBeforeConnect
        verifyTask = Task { @MainActor [weak self, probe] in
            guard let self else { return }
            let deviceName = self.devices.first(where: { $0.id == id })?.name ?? BLEMIDIDevice.unnamed
            // 250ms × 24 ≈ 6s：BLE-MIDI 建源通常几百毫秒内完成
            for _ in 0..<24 {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 250_000_000)
                let after = probe.numberOfSources()
                self.midiSourceCount = after
                let countIncreased = BLEMIDILogic.midiSourceAppeared(before: before, after: after)
                // 数量没变时才查源名单（接管已建链设备的路径）
                if countIncreased || BLEMIDILogic.midiSourceConfirmed(
                    countIncreased: false,
                    sourceNames: MIDIHub.systemSourceNames(),
                    deviceName: deviceName
                ) {
                    self.store.save(id: id, name: deviceName)
                    self.lastConnectedID = id
                    self.apply(.connectSucceeded, to: id)
                    print("[BLE] CoreMIDI 源已确认（\(before) → \(after)），连接成立")
                    return
                }
            }
            print("[BLE] 等待 CoreMIDI 源超时（仍为 \(probe.numberOfSources())），连接不成立")
            self.apply(.connectFailed, to: id)
            if let peripheral = self.peripherals[id] { self.central?.cancelPeripheralConnection(peripheral) }
        }
    }

    private func handleConnectFailure(id: UUID) {
        print("[BLE] 连接失败 \(id.uuidString)")
        apply(.connectFailed, to: id)
        resumeScanningIfPossible()
    }

    private func handleDisconnected(id: UUID) {
        print("[BLE] 断开 \(id.uuidString)")
        verifyTask?.cancel()
        pendingGATTVerification.remove(id)
        gattTimeoutTasks[id]?.cancel()
        gattTimeoutTasks.removeValue(forKey: id)
        peripherals.removeValue(forKey: id)
        apply(.disconnected, to: id)
        // 非用户主动断开（琴关机/走远）：保留记录，继续扫以便自动重连
        resumeScanningIfPossible()
    }

    private func resumeScanningIfPossible() {
        guard central?.state == .poweredOn else { return }
        beginScanning()
    }

    private func apply(_ event: BLEMIDILogic.Event, to id: UUID) {
        devices = devices.map { device in
            guard device.id == id else { return device }
            return BLEMIDIDevice(
                id: device.id,
                name: device.name,
                rssi: device.rssi,
                state: BLEMIDILogic.nextState(from: device.state, event: event)
            )
        }
        switch event {
        case .connectFailed:
            // 失败过就不再自动重连，避免扫描-重连-失败的循环
            autoConnectBlocked.insert(id)
        case .connectSucceeded:
            autoConnectBlocked.remove(id)
        case .scanDiscovered, .connectStarted, .disconnected:
            break
        }
        // 已连接就停扫（省电）；断开/失败后由 resumeScanningIfPossible 恢复
        if devices.contains(where: { $0.state == .connected }) {
            central?.stopScan()
            scanState = .idle
        }
    }
}

// MARK: - 上次连接设备持久化（UserDefaults，非 keychain）

/// 只存外设标识 UUID 与显示名——不涉密钥，故用 UserDefaults 而非 keychain。
struct LastDeviceStore {
    private let defaults: UserDefaults
    private let idKey = "ble-midi.last-device-id"
    private let nameKey = "ble-midi.last-device-name"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var id: UUID? {
        guard let raw = defaults.string(forKey: idKey) else { return nil }
        return UUID(uuidString: raw)
    }

    var name: String? {
        defaults.string(forKey: nameKey)
    }

    func save(id: UUID, name: String) {
        defaults.set(id.uuidString, forKey: idKey)
        defaults.set(name, forKey: nameKey)
    }

    func clear() {
        defaults.removeObject(forKey: idKey)
        defaults.removeObject(forKey: nameKey)
    }
}

// MARK: - CoreBluetooth 委托桥（回调在后台队列 → 跳回 @MainActor）

final class BLEMIDIManagerBridge: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var onState: ((CBManagerState) -> Void)?
    /// 发现外设：标识 / 名字 / RSSI / 广播声明的服务 UUID / 是否可连接
    var onDiscover: ((UUID, String?, Int, [CBUUID], Bool) -> Void)?
    var onConnect: ((UUID) -> Void)?
    var onConnectFailure: ((UUID) -> Void)?
    var onDisconnect: ((UUID) -> Void)?
    /// 服务发现结果；serviceUUIDs 为 nil 表示发现过程出错
    var onServices: ((UUID, [CBUUID]?) -> Void)?
    /// readRSSI 结果（接管来的外设没有扫描 RSSI，用它补真值）
    var onRSSI: ((UUID, Int) -> Void)?

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onState?(central.state)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // 优先广播里的本地名（peripheral.name 有时要连上才有）
        let advertised = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let connectable = (advertisementData[CBAdvertisementDataIsConnectable] as? Bool) ?? true
        onDiscover?(peripheral.identifier, advertised ?? peripheral.name, RSSI.intValue, serviceUUIDs, connectable)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        onConnect?(peripheral.identifier)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        onConnectFailure?(peripheral.identifier)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        onDisconnect?(peripheral.identifier)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let uuids = error == nil ? peripheral.services?.map(\.uuid) : nil
        onServices?(peripheral.identifier, uuids)
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else { return }
        onRSSI?(peripheral.identifier, RSSI.intValue)
    }
}
