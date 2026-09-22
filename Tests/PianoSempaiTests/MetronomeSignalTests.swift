import AVFoundation
import XCTest
@testable import PianoSempai

/// 信号级验证：混音器上必须真的出现非零样本。
/// graphConnected / isRunning 只能证明「引擎启动了」，证明不了「出声」——这正是旧测试的盲区，
/// 也是节拍器在真机上无声而测试全绿的原因。
///
/// 注意：tap 装在 mainMixerNode 上，取的是硬件之前的图内信号，与系统音量、静音开关、
/// Mac 输出是否静音都无关。所以它证明「图产生了信号」，不证明「喇叭响了」；
/// 路由层由 MetronomeSessionTests（category == .playback）与真机冒烟测试补足。
final class MetronomeSignalTests: XCTestCase {

    @MainActor
    func testClickProducesNonZeroRMSAtMainMixer() throws {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        let format = engine.outputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw XCTSkip("宿主无音频输出（无头 CI）——跳过而非失败")
        }
        engine.connect(player, to: engine.mainMixerNode, format: format)

        let lock = NSLock()
        var peakRMS: Float = 0
        // format 传 nil：让引擎按节点自身输出格式送 tap，避免 format 不匹配的运行时异常。
        // bufferSize 256（≈5.8ms @44.1k）远小于 30ms 的节拍音，才能整块抓到 click；
        // 取 1024+ 会横跨多个 click、把 RMS 摊薄。
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 256, format: nil) { buffer, _ in
            guard let data = buffer.floatChannelData?[0] else { return }
            var sum: Float = 0
            for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
            let rms = sqrt(sum / Float(max(1, buffer.frameLength)))
            lock.lock(); peakRMS = max(peakRMS, rms); lock.unlock()
        }
        defer { engine.mainMixerNode.removeTap(onBus: 0) }

        engine.prepare()
        try engine.start()
        player.play()

        // 打 4 拍，间隔 0.5s（≈120 BPM）：既给渲染线程足够的启动转数，
        // 也保证即使前几拍被 start() 的异步性吃掉，后面仍能采到信号。
        for _ in 0..<4 {
            player.scheduleBuffer(
                MetronomeService.sineBuffer(format: format, frequency: 1000, duration: 0.03),
                at: nil, options: .interrupts
            )
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        player.stop()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15)) // 等最后一个 tap 回调落地

        XCTAssertGreaterThan(
            peakRMS, 1e-3,
            "混音器上必须看到非零 RMS——否则节拍器是真无声，不是「引擎没启动」"
        )
    }
}
