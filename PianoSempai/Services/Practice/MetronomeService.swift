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

    /// 音频图是否已连接（测试宿主无音频输出时为 false，start 应为安全 no-op）
    var graphConnected: Bool { engine.isRunning }

    init() {
        configureAudioSession()
        engine.attach(player)
        // format 在 start 时按 engine 输出连接
    }

    private func configureAudioSession() {
        #if canImport(AVAudioSession)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif
    }

    private var playerConnected = false

    private func connectPlayerOnce() {
        guard !playerConnected else { return }
        let format = engine.outputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        playerConnected = true
    }

    private func ensureBuffers() {
        guard normalBuffer == nil else { return }
        let format = engine.outputNode.outputFormat(forBus: 0)
        normalBuffer = Self.sineBuffer(format: format, frequency: 1000, duration: 0.03)
        accentBuffer = Self.sineBuffer(format: format, frequency: 1500, duration: 0.035)
    }

    private static func sineBuffer(format: AVAudioFormat, frequency: Double, duration: Double) -> AVAudioPCMBuffer {
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
        // player 节点必须先连进音频图（attach ≠ connect；漏连会在 play() 时抛
        // "player started when in a disconnected state"——真机同样会炸）
        connectPlayerOnce()
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
        guard isRunning else { return }
        let interval = 60.0 / Double(max(30, bpm))
        let wasCountIn = countInBeatsRemaining > 0
        play(beatIndex % 4 == 0 && !wasCountIn ? accentBuffer : normalBuffer)
        if wasCountIn {
            countInBeatsRemaining -= 1
            if countInBeatsRemaining == 0 {
                beatIndex = 0
                onCountInFinished?()
            }
        } else {
            beatIndex += 1
        }
        beatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.scheduleNextBeat()
        }
    }

    private func play(_ buffer: AVAudioPCMBuffer?) {
        guard let buffer else { return }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
    }
}
