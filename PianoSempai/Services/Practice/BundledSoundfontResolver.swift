import Foundation
import SheetMusicAudioCore

// 音源解析（CURRENT.md Issue 2 / docs/decisions/0002-demo-playback-soundfont.md）。
// 随 app 分发 MuseScore_General.sf2（MIT；Frank Wen / Michael Cowgill / S. Christian Collins 等，
// 署名义务见 Resources/SoundFonts/MuseScore_General_License.md 与 S23「关于」）。
//
// 单文件全 GM 音源：per-program 查找一律返回 nil，全部走 defaultGMSoundfontURL。
// （包内文档 SoundfontResolver.swift:10-14 说的 per-program 小文件方案是给「按需加载省内存」
//   的场景；本项目先整文件跑通，P2 再评估裁剪钢琴单 preset 的小音源。）
//
// 🔴 硬约束：本类型只回答「有没有音源」，**不做静默降级**。
// 包内文档 SoundfontResolver.swift:18-52 实测记录：AUMIDISynth 路径上
// defaultGMSoundfontURL 返回 nil 会破坏进程级 CoreAudio 状态，让**下一个** synth 在
// mixer render 里 EXC_BAD_ACCESS，且没有 Swift catch 能接住。
// 因此调用方（DemoPlaybackService）必须在 URL 为 nil 时拒绝 prepare，而不是传一个 nil Resolver 进去。
// （注入 SwiftySynthBackend 的路径不受此影响——它从不实例化 AUMIDISynth；但防线仍统一设在调用方。）

struct BundledSoundfontResolver: SoundfontResolver {

    /// 音源文件位置。生产环境固定为 Bundle 内的 MuseScore_General.sf2；
    /// 测试注入假 URL 或 nil，用于验证「有/无音源」两条分支。
    let url: URL?

    init(url: URL? = Self.bundledURL()) {
        self.url = url
    }

    /// Bundle 内音源 URL（XcodeGen 把 Resources/SoundFonts 下的文件平铺进 .app 根，故不带 subdirectory）。
    /// 找不到时返回 nil——调用方据此禁用示范播放，不得回落静默。
    static func bundledURL() -> URL? {
        Bundle.main.url(forResource: "MuseScore_General", withExtension: "sf2")
    }

    /// 音源是否就位（DemoPlaybackService 的 gate 判据）
    var isAvailable: Bool { url != nil }

    /// per-program 查找：本方案不用（见文件头）
    func soundfontURL(forBank bank: UInt8, program: UInt8, isDrums: Bool) -> URL? {
        nil
    }

    var defaultGMSoundfontURL: URL? {
        url
    }
}
