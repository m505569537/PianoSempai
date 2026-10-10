import SwiftData
import SwiftUI

@main
struct PianoSempaiApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // UI 恒为 Nocturne 深色，不随系统外观（brief §1）。
                // 注意：此修饰符只能加在根上一次——嵌套叠加在 iOS 26 会触发 SIGSEGV（M2 调试记录）。
                .preferredColorScheme(.dark)
                .modelContainer(for: [
                    AppSettings.self,
                    PlacementSelfReport.self,
                    PlacementResult.self,
                    VelocityCalibration.self,
                    CoursePathState.self,
                    DailyPlan.self,
                    PracticeTask.self,
                    GateEvent.self,
                    Take.self,
                    Piece.self,
                    ScoreFile.self,
                    ScoreErrorMark.self,
                    TakeAnalysis.self,
                    // M7.1 AI 助教（多服务商链；只存非密配置，Key 在 Keychain）
                    AIProvider.self,
                    ChatThread.self,
                    ChatMessage.self,
                    PracticeNote.self,
                    // M7.2 月报（每月 1 号生成上月；快照冻结，算法升级不重算）
                    MonthlyReport.self,
                    // G4 日常视奏训练留痕（ADR-0004；旁观察样本，不碰过关链路）
                    SightReadDrillRecord.self,
                    // G3 矫正处方（ADR-0005；诊断→处方→复查，不锁过关红线 4）
                    CorrectionPrescription.self,
                    // G5 奖励曲难度评估与铺路卡（ADR-0006；非门禁，不碰 Piece.status）
                    RewardDifficultyAssessment.self,
                    RewardPavingCard.self,
                ])
        }
    }
}
