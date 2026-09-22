import AVFoundation
import Foundation

// 节拍器（M1 Q3=A：iPhone 本机出声，节拍音不进 take 数据）。
// AVAudioEngine + 播放节点，PCM 正弦短音：重音 1500Hz / 常拍 1000Hz，30ms。
// 预备拍 1 小节（S12 countIn 默认开）。

final class MetronomeService {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var normalBuffer: AVAudioPCMBuffer?
    private var accentBuffer: AVAudioPCMBuffer?
    private var beatTimer: Timer?
    private(set) var bpm: Int = 72
    private(set) var isRunning = false
    private var beatIndex = 0
    /// S12 预备拍剩余拍数（测试可见；1 小节 = 4 拍）
    private(set) var countInBeatsRemaining = 0
    var onCountInFinished: (() -> Void)?
    /// 每打一拍回调（拍响时同步调用）。用于测试断言打拍数 / 将来的可视化节拍指示。
    var onBeat: (() -> Void)?

    /// 音频图是否已连接（测试宿主无音频输出时为 false，start 应为安全 no-op）
    var graphConnected: Bool { engine.isRunning }

    init() {
        configureAudioSession()
        engine.attach(player)
        observeInterruptions()
        observeRouteChanges()
        // format 在 start 时按 engine 输出连接
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// 音频会话配置。注意：AVAudioSession 是 AVFAudio 里的「类」而不是「模块」，
    /// `canImport(AVAudioSession)` 恒为 false——那会把整个函数体编译掉，会话停在默认的
    /// .soloAmbient，真机静音开关一拨就彻底没声（这就是历史上节拍器无声的根因）。
    private func configureAudioSession() {
        #if os(iOS) || os(tvOS) || os(watchOS)
        let session = AVAudioSession.sharedInstance()
        do {
            // .playback：静音开关拨到「静音」时仍然出声（.soloAmbient 会被静音开关掐掉）
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // 不吞：真机上这条错误就是「无声」的唯一信号
            NSLog("[Metronome] AVAudioSession 配置失败: \(error.localizedDescription)")
        }
        #endif
    }

    /// 每次 start 前重新激活：构造期激活过，也可能已被来电/Siri/别的 App 抢占而停用。
    private func activateSession() {
        #if os(iOS) || os(tvOS) || os(watchOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    /// 来电 / Siri / 别的 App 抢占后会话被停用，引擎还在跑但不出声——抢占结束即重新激活。
    private func observeInterruptions() {
        #if os(iOS) || os(tvOS) || os(watchOS)
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw),
                  type == .ended else { return }
            try? AVAudioSession.sharedInstance().setActive(true)
        })
        #endif
    }

    /// 路由变化（插耳机/蓝牙接入）后硬件采样率可能变 → 丢掉按旧 format 建的连接与缓冲，
    /// 下次 start 会按当前 outputNode format 重连重建。
    private func observeRouteChanges() {
        #if os(iOS) || os(tvOS) || os(watchOS)
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.invalidateGraphCache()
        })
        #endif
    }

    private var observers: [NSObjectProtocol] = []

    /// 路由变化后调用：丢弃粘性的「已连接」标记与缓冲，迫使重连重建。
    private func invalidateGraphCache() {
        playerConnected = false
        normalBuffer = nil
        accentBuffer = nil
    }

    private var playerConnected = false

    /// 幂等连接：每次 start 都按当前 outputNode format 连一次。
    /// 旧实现只在第一次连（playerConnected 粘性 true），路由/采样率变化后旧 format 失效 → 静音。
    private func connectPlayer() {
        let format = engine.outputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        engine.disconnectNodeOutput(player) // 重连前摘掉旧连接，避免重复连接
        engine.connect(player, to: engine.mainMixerNode, format: format)
        playerConnected = true
    }

    private func ensureBuffers() {
        guard normalBuffer == nil else { return }
        let format = engine.outputNode.outputFormat(forBus: 0)
        normalBuffer = Self.sineBuffer(format: format, frequency: 1000, duration: 0.03)
        accentBuffer = Self.sineBuffer(format: format, frequency: 1500, duration: 0.035)
    }

    /// 测试可见：构造与 connect 用的正弦短音缓冲（RMS tap 测试复用同一构造函数）
    static func sineBuffer(format: AVAudioFormat, frequency: Double, duration: Double) -> AVAudioPCMBuffer {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            data[i] = Float(sin(2 * .pi * frequency * t) * 0.5 * (1 - Double(i) / Double(frameCount)))
        }
        buffer.frameLength = frameCount
        return buffer
    }

    /// 开始：bpm；countInBars > 0 时先打预备拍（4/4 一小节），结束回调 onCountInFinished
    func start(bpm: Int, countInBars: Int = 0) {
        stop()
        activateSession()
        // player 节点必须先连进音频图（attach ≠ connect；漏连会在 play() 时抛
        // "player started when in a disconnected state"——真机同样会炸）
        connectPlayer()
        ensureBuffers()
        self.bpm = bpm
        beatIndex = 0
        countInBeatsRemaining = countInBars * 4
        do {
            if !engine.isRunning {
                try engine.start()
            }
            // 无音频输出的宿主：引擎可能"启动"但图不可用——保持安全 no-op（不崩溃）
            guard engine.isRunning, playerConnected else {
                engine.stop()
                return
            }
            player.play()
        } catch {
            engine.stop()
            return
        }
        isRunning = true
        scheduleNextBeat()
    }

    func stop() {
        beatTimer?.invalidate()
        beatTimer = nil
        if player.isPlaying { player.stop() }
        engine.stop() // 释放音频图（下次 start 重建）
        isRunning = false
        countInBeatsRemaining = 0
    }

    private func scheduleNextBeat() {
        guard isRunning, engine.isRunning else { return }
        // player.play() 只在首个 start 调过一次；节点一旦被打断（来电/路由变化），后续
        // scheduleBuffer 会全部静默丢弃而 isRunning 仍为 true。这里兜底重拉，避免「假运行」。
        if !player.isPlaying { player.play() }
        let interval = 60.0 / Double(max(30, bpm))
        let wasCountIn = countInBeatsRemaining > 0
        play(beatIndex % 4 == 0 && !wasCountIn ? accentBuffer : normalBuffer)
        onBeat?()
        if wasCountIn {
            countInBeatsRemaining -= 1
            if countInBeatsRemaining == 0 {
                beatIndex = 0
                onCountInFinished?()
            }
        } else {
            beatIndex += 1
        }
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.scheduleNextBeat()
        }
        // .common：滚谱/拖拽时主循环进 .tracking 模式，.default 模式的 timer 会停摆 → 节拍器静音
        // （与 MIDIHub 的截断泵同一处理，见 MIDIHub.swift:148）
        RunLoop.main.add(timer, forMode: .common)
        beatTimer = timer
    }

    private func play(_ buffer: AVAudioPCMBuffer?) {
        guard let buffer else { return }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
    }
}
