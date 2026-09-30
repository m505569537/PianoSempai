import Foundation

// MARK: - Today → 练习室路由（Fix 批次 2026-09-30）
// 根因：TodayView/PracticeHubView 只传 taskType+timeLimitSec，PracticeTask 的 book/number
// 在导航处被丢掉 → PracticeRoomView.load() 拿到全空坐标 → .unavailable → 126 首内置谱不可达。
// 本文件只放纯决策（可单测），不碰视图。

/// Room-entry coordinates resolved from a course PracticeTask (book/number).
/// Only books that ship bundled scores are valid; anything else → nil (honest no-score path).
struct BundledScoreCoordinates: Equatable {
    let book: String
    let number: Int

    static func resolve(book: String?, number: Int) -> BundledScoreCoordinates? {
        guard let book, BundledScore.hasBundled(book: book, number: number) else { return nil }
        return .init(book: book, number: number)
    }
}

/// Disconnected-header subtitle: must reflect the real session phase.
/// Truth S11b only shows "Take · 练习进行中" while a take is actually in progress.
enum PracticeStatusSubtitle {
    static func text(phase: PracticeSession.Phase) -> String {
        switch phase {
        case .counting, .performing, .paused: return "Take · 练习进行中"
        case .idle: return "待开始"
        case .finished: return "已结束"
        }
    }
}

extension LoopConfig {
    /// Dock label for the loop cell. Nil = no honest range to show
    /// (no score loaded, or range invalid for the score).
    func cellLabel(totalMeasures: Int) -> String? {
        guard totalMeasures > 0,
              LoopService.isValid(start: startMeasure, end: endMeasure, totalMeasures: totalMeasures)
        else { return nil }
        return "\(startMeasure)–\(endMeasure)小节"
    }
}
