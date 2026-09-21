import Foundation

// S22 月报文案层（PRD M8 口径 + S22 首屏：统计 2x2、教材路线、热身与门禁、节奏稳定度、观察引用）。
// 纯函数、无 SwiftUI/UIKit 依赖，可完整单测；数字全部来自 MonthlyReportSnapshot 真实值。
//
// 两个必须如实降级的点（红线 1：不编造）：
// 1. 教材路线：本地只有 CoursePathState「当前值」快照——没有月内起点历史、没有拜厄/哈农总数分母，
//    没有「43→48」这种推进数据。因此本层不产出任何箭头推进文案、不产出进度百分比：
//    只显「拜厄 当前 48」这类当前值；599 未解锁显锁行，projected599Week>0 才带「预计第 N 周解锁」。
// 2. 手型/侧拍：当前无视频/侧拍模型，refsVideoCount 恒 0。观察引用 chip 只渲染 take 那条，
//    侧拍 chip 不渲染（视图侧手型趋势整段隐藏，不在本层出文案）。

struct MonthlyStatCell: Equatable {
    var value: String
    var label: String
}

enum MonthlyReportText {
    // MARK: 固定文案（锁定，含两条红线声明）

    /// 教材路线卡内声明（S22 红线：解锁只由硬数据规则判定，强开记录不影响）
    static let routeDeclaration = "解锁只由硬数据规则判定"
    /// 热身与门禁卡底免责声明
    static let overrideFootnote = "记录只用于你自己观察，不影响解锁。"
    /// 观察正文按首空行拆不出小标题时的兜底标题
    static let observationFallbackTitle = "本月观察"
    /// 节奏分全缺时的如实说明
    static let rhythmInsufficientText = "本月节奏分数据不足"
    /// 当月无 DailyPlan 时的如实说明（不填 0% 冒充有分母）
    static let warmupNoPlanText = "本月暂无计划"
    /// 当月无强开记录
    static let noOverrideText = "本月没有强开记录"
    /// PDF 里观察未生成时的节标题
    static let observationNotGeneratedText = "观察未生成"
    /// 历史月无月报的空态（S22：无数据的历史月）
    static let emptyHistoryText = "这个月还没有月报"

    // MARK: 标题与月份

    /// 首屏标题「2026 年 9 月 · 月度报告」
    static func headerTitle(year: Int, month: Int) -> String {
        "\(year) 年 \(month) 月 · 月度报告"
    }

    /// 月份三段 pill 的短标签：同年「9 月」，跨年「2026 年 12 月」（避免 12→1 看不出跨年）
    static func shortMonthLabel(year: Int, month: Int, sameYear: Bool) -> String {
        sameYear ? "\(month) 月" : "\(year) 年 \(month) 月"
    }

    // MARK: 2x2 统计卡

    static func statCells(_ snapshot: MonthlyReportSnapshot) -> [MonthlyStatCell] {
        [
            MonthlyStatCell(value: "\(snapshot.validDays) 天", label: "有效练习"),
            MonthlyStatCell(value: DurationText.hoursMinutes(snapshot.totalDurationSec), label: "总时长"),
            MonthlyStatCell(value: "\(snapshot.takeCount) take", label: "完成"),
            MonthlyStatCell(value: sessionsPerWeekText(snapshot.avgSessionsPerWeek), label: "平均周频"),
        ]
    }

    /// 平均周频保留 1 位小数；nil（本层不补 0）显「—」
    static func sessionsPerWeekText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f次", value)
    }

    // MARK: 教材路线（只显当前值，不显推进百分比）

    struct RouteRow: Equatable {
        var title: String
        var detail: String
        /// 锁行：视图按 spec 整体 0.5 透明
        var isLocked: Bool
    }

    static func routeRows(_ snapshot: MonthlyReportSnapshot) -> [RouteRow] {
        [
            RouteRow(title: "拜厄", detail: "当前 \(snapshot.beyerCurrent)", isLocked: false),
            RouteRow(title: "哈农", detail: "当前 \(snapshot.hanonCurrent)", isLocked: false),
            route599Row(snapshot),
        ]
    }

    private static func route599Row(_ snapshot: MonthlyReportSnapshot) -> RouteRow {
        // 已解锁：显真实当前首号；current599 缺（脏数据）时不编首号，只说「已开始」
        if snapshot.unlocked599 {
            let detail = snapshot.current599.map { "已开始 第 \($0) 首" } ?? "已开始"
            return RouteRow(title: "车尔尼599", detail: detail, isLocked: false)
        }
        // 锁行：只有真实预计周数才带预计；0 = 没有预计数据，不编月份
        let detail = snapshot.projected599Week > 0 ? "预计第 \(snapshot.projected599Week) 周解锁" : ""
        return RouteRow(title: "车尔尼599 🔒", detail: detail, isLocked: true)
    }

    // MARK: 热身与门禁

    /// 热身完成率：无计划 → 「本月暂无计划」（不填 0%）；有计划如实显 pct
    static func warmupText(_ snapshot: MonthlyReportSnapshot) -> String {
        guard let pct = snapshot.warmupCompletionPct else { return warmupNoPlanText }
        return "\(pct)%"
    }

    static func overrideText(_ snapshot: MonthlyReportSnapshot) -> String {
        snapshot.overrideCount == 0 ? noOverrideText : "强开主菜 \(snapshot.overrideCount) 次"
    }

    /// 强开原因标签分布：真实 reasonTag，「other」显「其他」；按次数降序、同次数按标签排序（稳定）
    static func overrideReasonChips(_ snapshot: MonthlyReportSnapshot) -> [String] {
        snapshot.overrideReasons
            .sorted { lhs, rhs in
                lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
            }
            .map { reasonChip(tag: $0.key, count: $0.value) }
    }

    static func reasonChip(tag: String, count: Int) -> String {
        "\((tag == "other" ? "其他" : tag))×\(count)"
    }

    // MARK: 节奏稳定度

    enum Rhythm: Equatable {
        /// 全月无节奏分（全空 / 全 nil）：如实说数据不足，不画趋势、不编差值
        case insufficient
        /// 首末非 nil 的周均分；delta = last - first（带符号）
        case trend(weeks: Int, first: Int, last: Int, delta: Int)
    }

    static func rhythm(_ snapshot: MonthlyReportSnapshot) -> Rhythm {
        guard let first = snapshot.rhythmFirstWeekScore,
              let last = snapshot.rhythmLastWeekScore else { return .insufficient }
        return .trend(weeks: snapshot.weeklyRhythmScores.count, first: first, last: last, delta: last - first)
    }

    static func rhythmText(_ rhythm: Rhythm) -> String {
        switch rhythm {
        case .insufficient: return rhythmInsufficientText
        case let .trend(weeks, first, last, delta): return "\(weeks) 周 \(first)→\(last)（\(signed(delta))）"
        }
    }

    /// 带符号差值：0 也显「+0」（本月持平，不是缺数据）
    static func signed(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : "\(value)"
    }

    // MARK: Neko 观察引用 chip（红线 2：无证据不结论）

    enum ChipKind: Equatable {
        case takes
        case videos
    }

    struct ObservationChip: Equatable {
        var text: String
        var kind: ChipKind
    }

    /// 引用 chip 列表：只渲染有真实证据的那几条。
    /// refsVideoCount 恒 0（无视频批次）→ 侧拍 chip 不渲染（不是渲染「引用 0 条侧拍」）。
    static func observationChips(_ snapshot: MonthlyReportSnapshot) -> [ObservationChip] {
        var chips: [ObservationChip] = []
        if snapshot.refsTakeCount > 0 {
            chips.append(ObservationChip(text: "引用 \(snapshot.refsTakeCount) 个 take", kind: .takes))
        }
        if snapshot.refsVideoCount > 0 {
            chips.append(ObservationChip(text: "引用 \(snapshot.refsVideoCount) 条侧拍", kind: .videos))
        }
        return chips
    }
}
