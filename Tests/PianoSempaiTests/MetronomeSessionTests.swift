import AVFoundation
import XCTest
@testable import PianoSempai

/// 音频会话守门测试。历史上 `#if canImport(AVAudioSession)` 恒为 false（AVAudioSession 是
/// AVFAudio 里的类，不是模块），把整个会话配置编译掉 → 会话停在默认 .soloAmbient →
/// 真机静音开关一拨就彻底没声。这条测试在修复前的真机与模拟器上都会失败。
final class MetronomeSessionTests: XCTestCase {

    /// 构造即配置：category 必须是 .playback（.soloAmbient 会被静音开关掐掉）。
    /// 顺序无关——只断言构造后的共享会话状态。
    @MainActor
    func testInitConfiguresPlaybackCategory() throws {
        #if os(iOS) || os(tvOS) || os(watchOS)
        _ = MetronomeService()
        XCTAssertEqual(
            AVAudioSession.sharedInstance().category, .playback,
            "节拍器必须在硬件静音开关拨到「静音」时也出声"
        )
        #endif
    }

    /// start() 前会重新激活会话（抢占过后不能留静音）。无音频宿主下也走得到激活这一步，
    /// 所以这条断言不依赖宿主持不持有音频设备。
    @MainActor
    func testStartKeepsPlaybackCategory() throws {
        #if os(iOS) || os(tvOS) || os(watchOS)
        let metronome = MetronomeService()
        metronome.start(bpm: 120, countInBars: 0)
        defer { metronome.stop() }
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)
        #endif
    }
}
