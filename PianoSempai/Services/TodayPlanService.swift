import Foundation
import SwiftData

// 今日域可测服务：时长分配、streak 聚合、周进度（today.md 数据依赖）。
// 口径锁定：有效练习 = 有 MIDI 且当日累计 ≥10 分钟（M9）。

enum TodayPlanService {

    // MARK: - 时长分配（热身固定 8–12 分钟不被压缩；主菜/奖励按剩余分配）

    struct TaskDurations: Equatable {
        /// 热身固定展示区间（分钟）
        let warmupLabel: String
        /// 主菜分钟数（分配结果）
        let mainMinutes: Int
        /// 奖励曲副标题（spec 锁定文案："剩多少时间算多少"）
        let rewardLabel: String
    }

    /// 主菜分钟 = (choice − 10) × 3/4，5 分钟取整，下限 5。
    /// 例：30 → 约 15（与 S07 spec 示例一致）；15 → 5；45 → 25。
    static func durations(forChoiceMinutes choice: Int) -> TaskDurations {
        let main = max(5, ((choice - 10) * 3 / 4 / 5) * 5)
        return TaskDurations(
            warmupLabel: "8–12 分钟",
            mainMinutes: main,
            rewardLabel: "剩多少时间算多少"
        )
    }

    // MARK: - streak（本周 7 灯，周一起始，真实 Take 聚合）

    struct WeekStreak: Equatable {
        /// 周一→周日 7 天；true = 该日有有效练习（琥珀点）
        let litDays: [Bool]
        /// 各灯当日有效练习分钟数（tooltip 用；未练为 0）
        let minutesPerDay: [Int]
        /// 今天在 7 天中的下标（周一=0）
        let todayIndex: Int
    }

    /// 有效练习：有 MIDI 且当日累计 ≥10 分钟（任务练习与自由弹奏都计）。
    static func weekStreak(takes: [Take], today: Date, calendar: Calendar = .current) -> WeekStreak {
        var cal = calendar
        cal.firstWeekday = 2
        let weekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today

        var minutes = [Int](repeating: 0, count: 7)
        for take in takes where take.hasMidi {
            guard let interval = cal.dateInterval(of: .day, for: take.startedAt) else { continue }
            let dayOffset = cal.dateComponents([.day], from: weekStart, to: interval.start).day ?? -1
            guard (0..<7).contains(dayOffset) else { continue }
            minutes[dayOffset] += take.durationSec / 60
        }
        let lit = minutes.map { $0 >= 10 }
        let todayIndex = (cal.dateComponents([.day], from: weekStart, to: cal.startOfDay(for: today)).day ?? 0)
        return WeekStreak(
            litDays: lit,
            minutesPerDay: minutes,
            todayIndex: min(6, max(0, todayIndex))
        )
    }

    // MARK: - 周进度（真实 Take 聚合）

    /// 本周有效练习总分钟；目标 = weeklyGoal 次 × 每次时长选择（分钟）。
    /// 与 streak 同口径：仅计入"当日累计 ≥10 分钟"的有效练习日（M9）。
    static func weekProgress(takes: [Take], weeklyGoal: Int, dailyChoiceMinutes: Int, today: Date, calendar: Calendar = .current) -> (doneMinutes: Int, targetMinutes: Int) {
        let streak = weekStreak(takes: takes, today: today, calendar: calendar)
        let done = streak.minutesPerDay.filter { $0 >= 10 }.reduce(0, +)
        return (done, weeklyGoal * dailyChoiceMinutes)
    }
}
