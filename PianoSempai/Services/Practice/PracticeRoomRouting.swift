import Foundation
import SwiftData

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

extension CourseEngine {
    /// 房间条目懒解析（Stage B §2a）：今日/聚合进房外部未传 piece 时，按 book+number
    /// 解析出 room piece，take 才有 pieceId（过关判定的归属前提）。
    /// - 命中已有 Piece 行 → 原样返回（不改状态，红线 1）；
    /// - 未命中但内置目录有该条 → `ensurePiece` 建档（notStarted）返回；
    /// - 目录里也没有（异常，如越界号）→ nil（take 不带 pieceId，诚实降级）。
    static func resolveRoomPiece(book: String, number: Int, in context: ModelContext) -> Piece? {
        let descriptor = FetchDescriptor<Piece>(
            predicate: #Predicate { $0.book == book && $0.number == number }
        )
        if let existing = (try? context.fetch(descriptor))?.first { return existing }
        guard let entry = CatalogLoader.loadBuiltin().first(where: { $0.book == book && $0.number == number })
        else { return nil }
        return ensurePiece(for: entry, in: context)
    }
}

/// 当日复习卡条目选择（Stage B §3a）：status==reviewing 中 nextReviewAt 最早者；无则 nil。
/// 「今日至多 1 条复习」由该选择落地（ADR-0003 派生规则）；nextReviewAt 为 nil 的
/// reviewing 排最后（理论上 roll 之后不会出现，防御性处理）。
enum TodayReviewPicker {
    static func pick(_ pieces: [Piece]) -> Piece? {
        pieces
            .filter { $0.status == CourseEngine.statusReviewing }
            .min { a, b in
                switch (a.nextReviewAt, b.nextReviewAt) {
                case let (l?, r?): return l < r
                case (.some, .none): return true
                case (.none, .some): return false
                default: return false
                }
            }
    }
}

// MARK: - G5 Stage B 铺路展示决策（ADR-0006 决策二/八；纯决策，可单测，不碰视图）

/// 今日铺路卡展示决策
enum RewardPavingDisplay {
    /// 取当天 prescribedAt、未关闭、未完成的那张；无则 nil。
    static func todayCard(_ cards: [RewardPavingCard], now: Date) -> RewardPavingCard? {
        cards.first {
            $0.closedAt == nil && $0.completedAt == nil
                && Calendar.current.isDate($0.prescribedAt, inSameDayAs: now)
        }
    }

    /// 曲库档位文案：nil（无评估/无法相对定级）→ 暂无法分析（诚实，决策一/四）。
    static func gradeLabel(_ grade: RewardDifficulty.Grade?) -> String {
        switch grade {
        case .play: return "现在能弹"
        case .stretch: return "偏难"
        case .far: return "远超当前"
        case nil: return "暂无法分析"
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
