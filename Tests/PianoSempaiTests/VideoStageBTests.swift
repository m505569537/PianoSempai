import SwiftData
import XCTest
@testable import PianoSempai

// M8b Stage B 验收：只测纯展示/判定逻辑（S15 步骤、时间码、保留文案、入口谓词、录像判定）。
// 相机、相册、AVPlayer 与 SwiftUI 视图不在单测范围（需真机与系统授权，Hermes 截图验收）。

final class VideoStageBTests: XCTestCase {

    // MARK: ① 四步顺序

    func testCalibrationStepOrderAndNext() {
        XCTAssertEqual(CalibrationStep.allCases, [.place, .frame, .test, .done])
        XCTAssertEqual(CalibrationStep.allCases.map(\.rawValue), [0, 1, 2, 3])
        XCTAssertEqual(CalibrationStep.place.next(), .frame)
        XCTAssertEqual(CalibrationStep.frame.next(), .test)
        XCTAssertEqual(CalibrationStep.test.next(), .done)
        XCTAssertNil(CalibrationStep.done.next(), "最后一步没有下一步")
    }

    // MARK: ② 步骤文案

    func testCalibrationStepTitles() {
        XCTAssertEqual(CalibrationStep.place.title, "摆放")
        XCTAssertEqual(CalibrationStep.frame.title, "取景")
        XCTAssertEqual(CalibrationStep.test.title, "试录")
        XCTAssertEqual(CalibrationStep.done.title, "完成")
    }

    // MARK: ③ 时码（mm:ss 口径：分钟不补零、秒两位）

    func testTimecodeFormatting() {
        XCTAssertEqual(VideoUIFormatting.timecode(0), "0:00")
        XCTAssertEqual(VideoUIFormatting.timecode(5), "0:05")
        XCTAssertEqual(VideoUIFormatting.timecode(59), "0:59")
        XCTAssertEqual(VideoUIFormatting.timecode(60), "1:00")
        XCTAssertEqual(VideoUIFormatting.timecode(65), "1:05")
        XCTAssertEqual(VideoUIFormatting.timecode(3725), "62:05")
        XCTAssertEqual(VideoUIFormatting.timecode(-5), "0:00", "负值收敛到 0，不显负时码")
    }

    // MARK: ④ 保留规则文案

    func testRetentionLabels() {
        XCTAssertEqual(VideoUIFormatting.retentionLabel(for: "lru8"), "每曲最近 8 条")
        XCTAssertEqual(VideoUIFormatting.retentionLabel(for: "never"), "不自动清理")
        // 未知取值与空串都回落到默认规则，绝不显示空白
        XCTAssertEqual(VideoUIFormatting.retentionLabel(for: "bogus"), "每曲最近 8 条")
        XCTAssertEqual(VideoUIFormatting.retentionLabel(for: ""), "每曲最近 8 条")
    }

    // MARK: ⑤ 回看入口谓词

    func testVideoReviewEntryPredicate() {
        XCTAssertTrue(VideoUIFormatting.hasVideo(Take(videoFileURL: "videos/2026/10/video-a.mov")))
        XCTAssertFalse(VideoUIFormatting.hasVideo(Take()), "无视频不显示「看录像」")
        XCTAssertFalse(VideoUIFormatting.hasVideo(Take(videoFileURL: "")))
    }

    // MARK: ⑥ 录像是否随练习开始

    func testRecordingDecisionDependsOnArmedOnly() {
        XCTAssertTrue(RecordingDecision.shouldStart(armed: true, isConnected: true))
        // 视频与 MIDI 是两条路：没有 MIDI 也可以录（落 hasMidi=false 的 take）
        XCTAssertTrue(RecordingDecision.shouldStart(armed: true, isConnected: false))
        XCTAssertFalse(RecordingDecision.shouldStart(armed: false, isConnected: true))
        XCTAssertFalse(RecordingDecision.shouldStart(armed: false, isConnected: false))
    }

    // MARK: ⑦ 录像会话标记默认值

    func testRecordingSessionFlagDefaultsOff() {
        XCTAssertFalse(Take().isRecordingSession)
        XCTAssertTrue(Take(isRecordingSession: true).isRecordingSession)
        // 默认 take 仍然照常参与过关判定（普通会话行为不变）
        XCTAssertFalse(Take().isPassEligible)
    }
}
