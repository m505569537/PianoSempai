import Foundation

// S15/S16 的纯展示与判定逻辑（可单测，不碰相机、相册与文件）。

/// S15 机位校准四步：摆放 → 取景 → 试录 → 完成
enum CalibrationStep: Int, CaseIterable, Equatable {
    case place
    case frame
    case test
    case done

    var title: String {
        switch self {
        case .place: "摆放"
        case .frame: "取景"
        case .test: "试录"
        case .done: "完成"
        }
    }

    /// 下一步；已是最后一步返回 nil
    func next() -> CalibrationStep? {
        CalibrationStep(rawValue: rawValue + 1)
    }
}

enum VideoUIFormatting {

    /// 秒 → m:ss（65 → "1:05"、3725 → "62:05"；分钟不补零，秒固定两位）
    static func timecode(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }

    /// 视频保留规则文案；未知取值回落到默认规则（"lru8"）
    static func retentionLabel(for mode: String) -> String {
        switch mode {
        case "never": return "不自动清理"
        default: return "每曲最近 8 条"
        }
    }

    /// S16 入口谓词：有视频附件才显示「看录像」
    static func hasVideo(_ take: Take) -> Bool {
        guard let path = take.videoFileURL else { return false }
        return !path.isEmpty
    }
}

/// 录像是否随这次练习开始：只看 S15 是否已把机位准备好（armed）。
/// MIDI 连接不参与——视频与判分是两条路，没有 MIDI 也可以落一条 hasMidi=false 的录像 take（ADR-0010）。
enum RecordingDecision {
    static func shouldStart(armed: Bool, isConnected: Bool) -> Bool {
        armed
    }
}
