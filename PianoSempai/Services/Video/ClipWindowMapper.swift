import Foundation

// 热点小节 → 视频内秒区间（ADR-0011「热点→时间换算」，纯函数，不碰 AVFoundation/SwiftData）。
// 服务 S18b 的三个预设 chips：「错误热点前后各 2 小节」/「整段」/「手动」。
// 算不出就返回 nil → chip 置灰；绝不造假区间（红线 2）。

/// 拍号（4/4 → beats 4, beatUnit 4；缺拍号时调用方按 4/4 传入）
struct MeasureTiming: Equatable, Sendable {
    var beats: Int
    var beatUnit: Int
}

enum ClipWindowMapper {

    /// 每小节秒数 = beats * (60/bpm) * (4/beatUnit)。
    /// 拍号/速度非法时返回 0（调用方视为算不出）。
    static func measureSeconds(timing: MeasureTiming, bpm: Int) -> Double {
        guard bpm > 0, timing.beats > 0, timing.beatUnit > 0 else { return 0 }
        return Double(timing.beats) * (60.0 / Double(bpm)) * (4.0 / Double(timing.beatUnit))
    }

    /// 热点小节（1-based，可多段）→ 视频内秒区间，前后各扩 `paddingMeasures` 小节。
    /// v1 把多段热点合并成 [min...max] 一个区间（不产生互不相连的多段视频）。
    ///
    /// - Parameters:
    ///   - hotspots: 1-based 热点小节（来自 TakeAnalysis.hotspotMeasures 最新一条）
    ///   - totalMeasures: 曲目总小节数（钳制边界）
    ///   - timing: 拍号；缺拍号按 4/4
    ///   - bpm: 练习实测速度（take.tempoAvg 或曲目参考速度）
    ///   - videoStartedAtOffset: 录像相对练习起点的偏移秒数
    ///   - videoDurationSec: 视频总时长（钳制边界）
    ///   - paddingMeasures: 前后各扩的小节数
    /// - Returns: 视频内秒区间；空热点 / 非法参数 / 钳制后不足 2 秒 → nil
    static func window(
        hotspots: [Int],
        totalMeasures: Int,
        timing: MeasureTiming,
        bpm: Int,
        videoStartedAtOffset: Double,
        videoDurationSec: Double,
        paddingMeasures: Int = 2
    ) -> ClosedRange<Double>? {
        guard !hotspots.isEmpty, totalMeasures > 0, videoDurationSec > 0 else { return nil }

        let valid = hotspots.filter { $0 >= 1 && $0 <= totalMeasures }
        guard let first = valid.min(), let last = valid.max() else { return nil }

        let secondsPerMeasure = measureSeconds(timing: timing, bpm: bpm)
        guard secondsPerMeasure > 0 else { return nil }

        let padding = max(0, paddingMeasures)
        let startMeasure = max(1, first - padding)
        let endMeasure = min(totalMeasures, last + padding)

        // 小节边界：第 1 小节从 0s 起；第 N 小节结束于 N * 每小节秒数
        let lower = max(0, Double(startMeasure - 1) * secondsPerMeasure + videoStartedAtOffset)
        let upper = min(videoDurationSec, Double(endMeasure) * secondsPerMeasure + videoStartedAtOffset)

        guard upper > lower, upper - lower >= 2.0 else { return nil }
        return lower...upper
    }
}
