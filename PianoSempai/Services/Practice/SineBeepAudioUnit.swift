import AVFoundation

// SineBeep MIDI 音频单元（Stage A 核心，未接线任何调用方）：
// 用 AUAudioUnit 子类**合成**被删除的 MetronomeService.sineBuffer 原始电子蜂鸣
// （常拍 1000Hz/30ms、重拍 1500Hz/35ms，线性衰减包络 0.5 → 0）。
//
// 两种驱动方式共用同一条合成路径：
// 1. **Sequencer 驱动**（Stage B：示范的 ch9 click track）：基类在注册为 MusicDevice
//    （kAudioUnitType_MusicDevice）后自动提供 scheduleMIDIEventBlock（SDK 头文件明确：
//    "This is implemented in the base class … Subclasses should not override"），宿主
//    （AVAudioSequencer 经 AVMusicTrack.destinationAudioUnit）排入的 note-on/note-off
//    以 AURenderEvent 链表形式直达 internalRenderBlock——本类的 render block 解析该链表。
// 2. **直接触发**（Stage B：练习 MetronomeService 的 Timer 每拍调一次）：triggerNote 经
//    基类的 scheduleMIDIEventBlock 送一个 3 字节 note-on，与 sequencer 走完全相同的管线。
//
// 实时安全：internalRenderBlock 内零锁、零分配——音符状态是 init 期预分配的固定 4 声部池，
// MIDI 事件在 render block 内就地消费（基类已把它放进实时安全的 render 事件列表，无需自建 FIFO）。
// 相位按 render 时总线格式的真实采样率推进（不写死 44.1k）。
//
// 音色规格（必须与原 sineBuffer 逐样本一致）：sine × 0.5 × (1 - i/frameCount) × min(1, vel/100)，
// frameCount = duration × 采样率；note 76 = 重拍档，其余（含 77）= 常拍档；忽略 MIDI 通道。

// MARK: - AUAudioUnit 子类

/// 合成原始节拍器蜂鸣的进程内 MusicDevice。
/// 子类型/厂商码为本 App 私有 4 字符码：subtype 'SnBe'（0x536E6265）、manufacturer 'PnSm'（0x506E536D）。
final class SineBeepAudioUnit: AUAudioUnit {

    // MARK: 组件描述 / 注册

    /// 注册用的组件描述。componentFlags 置 0：SDK 头文件注明系统在注册 v3 AU 时自动补
    /// kAudioComponentFlag_IsV3AudioUnit 等位；进程内实例化由工厂的 .loadInProcess 选项指定。
    static let componentDescription = AudioComponentDescription(
        componentType: kAudioUnitType_MusicDevice,
        componentSubType: 0x536E_6265, // 'SnBe'
        componentManufacturer: 0x506E_536D, // 'PnSm'
        componentFlags: 0,
        componentFlagsMask: 0,
    )

    // MARK: 音色规格（与原 sineBuffer 一一对应；internal 供测试无音频锁定映射）

    /// note → (频率 Hz, 时长 s)。note 76 = 重拍（1500Hz / 35ms），其余（含 77）= 常拍（1000Hz / 30ms）。
    static func spec(forNote note: UInt8) -> (frequency: Double, duration: Double) {
        note == 76 ? (1500, 0.035) : (1000, 0.030)
    }

    /// 速度 → 振幅系数：min(1, vel/100)。77/80 → 0.8×；76/100 → 1.0×；超过 100 一律封顶 1。
    static func velocityScale(forVelocity velocity: UInt8) -> Double {
        min(1.0, Double(velocity) / 100.0)
    }

    // MARK: 渲染状态（render block 内专用：预分配、零锁零分配）

    /// 固定声部池 + 音符状态。节拍是单音符场景，4 个声部足够混叠；不够时按 round-robin 抢占。
    private final class RenderState {
        struct Voice {
            var active = false
            var note: UInt8 = 0
            var phase = 0.0
            var phaseIncrement = 0.0 // rad / frame，按启动时的真实采样率计算
            var samplesRendered = 0
            var totalSamples = 0
            var velScale = 1.0
            var delayFrames = 0 // 事件在本 render block 内的起始帧偏移（此前输出静音）
        }

        /// 在 allocateRenderResources 时从总线格式捕获；不写死 44.1k。
        var sampleRate: Double = 44100
        var voices: [Voice] = (0 ..< 4).map { _ in Voice() }
        var nextVictim = 0

        /// MIDI note-on / note-off（0x9n / 0x8n；通道忽略；note-on velocity 0 视作 note-off）。
        func handleMIDI(status: UInt8, data1: UInt8, data2: UInt8, delayFrames: Int) {
            switch status & 0xF0 {
            case 0x80:
                release(note: data1)
            case 0x90:
                if data2 == 0 { release(note: data1) } else { start(note: data1, velocity: data2, delayFrames: delayFrames) }
            default:
                break // 节拍只需 note on/off；其余消息忽略
            }
        }

        func start(note: UInt8, velocity: UInt8, delayFrames: Int) {
            let spec = SineBeepAudioUnit.spec(forNote: note)
            let index: Int
            if let free = voices.firstIndex(where: { !$0.active }) {
                index = free
            } else {
                index = nextVictim
                nextVictim = (nextVictim + 1) % voices.count
            }
            var voice = voices[index]
            voice.active = true
            voice.note = note
            voice.phase = 0
            voice.phaseIncrement = 2 * Double.pi * spec.frequency / sampleRate
            voice.totalSamples = max(1, Int((spec.duration * sampleRate).rounded()))
            voice.samplesRendered = 0
            voice.velScale = SineBeepAudioUnit.velocityScale(forVelocity: velocity)
            voice.delayFrames = max(0, delayFrames)
            voices[index] = voice
        }

        /// note-off（或 vel 0 的 note-on）：让同音符的活跃声部在下一帧终止
        /// （等效"下一个 render block 停止"；没有 note-off 时声部也会在时长耗尽处自动停止）。
        func release(note: UInt8) {
            for index in voices.indices where voices[index].active && voices[index].note == note {
                voices[index].samplesRendered = voices[index].totalSamples
            }
        }

        /// 把全部活跃声部按包络求和混入第 0 通道缓冲（每样本 `sin(phase) × 0.5 × (1 - i/total) × velScale`）。
        func renderVoices(into out: UnsafeMutablePointer<Float>, frameCount: Int) {
            for index in voices.indices {
                var voice = voices[index]
                guard voice.active || voice.delayFrames > 0 else { continue }
                for frame in 0 ..< frameCount {
                    if voice.delayFrames > 0 {
                        voice.delayFrames -= 1
                        continue
                    }
                    guard voice.active else { break }
                    let progress = Double(voice.samplesRendered) / Double(voice.totalSamples)
                    let gain = 0.5 * (1.0 - progress) * voice.velScale
                    out[frame] += Float(sin(voice.phase) * gain)
                    voice.phase += voice.phaseIncrement
                    if voice.phase > 2 * Double.pi { voice.phase -= 2 * Double.pi }
                    voice.samplesRendered += 1
                    if voice.samplesRendered >= voice.totalSamples { voice.active = false }
                }
                voices[index] = voice
            }
        }
    }

    private let renderState = RenderState()
    private var outputBus: AUAudioUnitBus!
    private var outputBusArray: AUAudioUnitBusArray!

    override var outputBusses: AUAudioUnitBusArray { outputBusArray }

    override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)
        // 默认双声道 44.1k：宿主 connect(format: nil) 时由引擎按总线格式覆盖；
        // 真实采样率在 allocateRenderResources 里捕获进 RenderState。
        let defaultFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        outputBus = try AUAudioUnitBus(format: defaultFormat)
        outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
    }

    required init?(coder: NSCoder) {
        fatalError("SineBeepAudioUnit 不支持 NSCoding 初始化")
    }

    override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        let sampleRate = outputBus.format.sampleRate
        if sampleRate > 0 {
            renderState.sampleRate = sampleRate
        }
    }

    /// 直接触发一个 note-on（无需 sequencer）：经基类的 scheduleMIDIEventBlock 送 3 字节
    /// note-on（通道 0、音高 note、力度 velocity），与 sequencer 驱动共用同一条合成路径。
    /// block 为 nil（未按 MusicDevice 配置/未就绪）时静默——与节拍器的 no-output 安全语义一致。
    func triggerNote(_ note: UInt8, velocity: UInt8) {
        scheduleMIDIEventBlock?(AUEventSampleTimeImmediate, 0, 3, [0x90, note, velocity])
    }

    // MARK: 渲染

    override var internalRenderBlock: AUInternalRenderBlock {
        let state = renderState
        // 强捕获 state（弱引用会在 render 中途变成 nil——Apple 文档允许强捕获）。
        return { [state] _, timestamp, frameCount, _, outputData, realtimeEventListHead, _ in
            let blockStart = timestamp.pointee.mSampleTime

            // 1) 消费宿主/基类排入的 render 事件链表：只认 note-on (0x9n) / note-off (0x8n)，
            //    通道忽略；事件帧偏移夹到本 block 内。
            var eventCursor = realtimeEventListHead
            while let event = eventCursor {
                let head = event.pointee.head
                if head.eventType == .MIDI {
                    let midi = event.pointee.MIDI
                    var offset = Int(midi.eventSampleTime) - Int(blockStart)
                    if offset < 0 { offset = 0 }
                    if offset > Int(frameCount) { offset = Int(frameCount) - 1 }
                    if midi.length >= 3 {
                        state.handleMIDI(status: midi.data.0, data1: midi.data.1, data2: midi.data.2, delayFrames: offset)
                    }
                }
                eventCursor = head.next.map { UnsafePointer($0) }
            }

            // 2) 渲染：声部求和进第 0 通道 → 夹到 [-1, 1] → 复制到其余通道（AUv3 契约：
            //    非交错 Float32，每个 AudioBuffer 一个声道）。
            let buffers = UnsafeMutableAudioBufferListPointer(outputData)
            guard buffers.count > 0, let channel0 = buffers[0].mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            for frame in 0 ..< Int(frameCount) { channel0[frame] = 0 }
            state.renderVoices(into: channel0, frameCount: Int(frameCount))
            for frame in 0 ..< Int(frameCount) {
                channel0[frame] = max(-1, min(1, channel0[frame]))
            }
            for bufferIndex in 1 ..< buffers.count {
                guard let channelN = buffers[bufferIndex].mData?.assumingMemoryBound(to: Float.self) else { continue }
                for frame in 0 ..< Int(frameCount) { channelN[frame] = channel0[frame] }
            }
            return noErr
        }
    }
}

// MARK: - 工厂 + AVAudioUnit 包装 API

/// SineBeep 单元的进程内注册（dispatch-once）与异步工厂。
/// 实例化是异步的（AVAudioUnit.instantiate），**不要**在主线程同步等待——用 `make()`。
enum SineBeepAudioUnitFactory {

    /// 注册子类（static let 的惰性初始化即 dispatch-once；重复注册会崩，故只跑一次）。
    private static let registration: Void = {
        AUAudioUnit.registerSubclass(
            SineBeepAudioUnit.self,
            as: SineBeepAudioUnit.componentDescription,
            name: "PianoSempai.SineBeepAudioUnit",
            version: 1,
        )
    }()

    enum FactoryError: Error {
        case instantiationFailed
    }

    /// 异步创建并返回包装好的 AVAudioUnit。失败抛错（含单元创建失败）。
    static func make() async throws -> AVAudioUnit {
        _ = registration
        return try await withCheckedThrowingContinuation { continuation in
            AVAudioUnit.instantiate(
                with: SineBeepAudioUnit.componentDescription,
                options: [],
            ) { unit, error in
                if let unit {
                    continuation.resume(returning: unit)
                } else {
                    continuation.resume(throwing: error ?? FactoryError.instantiationFailed)
                }
            }
        }
    }
}

extension AVAudioUnit {
    /// 直接触发一拍（无需 sequencer）：转发到底层 SineBeepAudioUnit 的同一 MIDI 合成路径。
    /// 非 SineBeep 单元上是安全 no-op。
    func triggerNote(_ note: UInt8, velocity: UInt8) {
        (auAudioUnit as? SineBeepAudioUnit)?.triggerNote(note, velocity: velocity)
    }
}
