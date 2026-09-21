import Foundation

// M7.2 月报快照（PRD M8 月报口径 + S22 月度报告详情首屏）。
// 纯值类型：聚合层 MonthlyReportBuilder 只产 Snapshot（不碰 ModelContext），
// 持久化由 @Model MonthlyReport 的 init(snapshot:) 完成——Builder 只读输入、不回写任何状态（红线 3）。
// Snapshot 是冻结语义来源：月报落库即当时快照，算法升级后不重算已出月报（PRD）。
// 口径全部来自真实 take/analysis/plan/gate/pathState，缺数据给 nil/0，不编造百分比（红线 1）。

struct MonthlyReportSnapshot: Equatable {
    var year: Int
    var month: Int
    /// "yyyy-MM"（MonthlyCalendar.periodKey）
    var periodKey: String
    // 统计
    /// 当月有有效 take 的 distinct 日历日数
    var validDays: Int
    /// 当月有效 take 时长之和（秒）
    var totalDurationSec: Int
    /// 当月全部 take 数（含无效，如实）
    var takeCount: Int
    /// 有效 take 数 / 当月覆盖周数（月内每天归周后 distinct 周数；保留原始 Double，视图决定显示位数）
    var avgSessionsPerWeek: Double?
    // 教材路线（快照当前真实值；解锁只由硬数据规则判定，强开记录不影响，S22 红线）
    var beyerCurrent: Int
    var hanonCurrent: Int
    var unlocked599: Bool
    var projected599Week: Int
    // 热身与门禁
    /// 有 DailyPlan 的当月 = 热身完成天数 / 计划天数 * 100（四舍五入）；无计划 → nil，不填 0
    var warmupCompletionPct: Int?
    var overrideCount: Int
    /// 强开原因分布：reasonTag 去空格后为空或 "other" 统一键 "other"，其它真实标签保留
    var overrideReasons: [String: Int]
    // 节奏趋势（月内按周分组，周均 rhythmScore；nil = 该周无分析）
    var rhythmFirstWeekScore: Int?
    var rhythmLastWeekScore: Int?
    /// 月内各周（按 weekStart 升序）的 rhythmScore 周均
    var weeklyRhythmScores: [Int?]
    // AI 观察（b2 才生成；本 Stage 占位：空正文 + pending + 引用数取真实 take 数）
    var observationTitle: String
    var observationBody: String
    /// 本次实际命中的「服务商·模型」（b2 写入；占位 nil）
    var observationProviderModel: String?
    var refsTakeCount: Int
    /// 无视频批次（Zf 侧拍在 M6），恒 0
    var refsVideoCount: Int
    /// pending / ok / failed
    var observationStatus: String
    var generatedAt: Date

    /// periodKey 省略时由 year/month 推导（零填充 "yyyy-MM"）
    init(
        year: Int,
        month: Int,
        periodKey: String? = nil,
        validDays: Int = 0,
        totalDurationSec: Int = 0,
        takeCount: Int = 0,
        avgSessionsPerWeek: Double? = nil,
        beyerCurrent: Int = 1,
        hanonCurrent: Int = 1,
        unlocked599: Bool = false,
        projected599Week: Int = 0,
        warmupCompletionPct: Int? = nil,
        overrideCount: Int = 0,
        overrideReasons: [String: Int] = [:],
        rhythmFirstWeekScore: Int? = nil,
        rhythmLastWeekScore: Int? = nil,
        weeklyRhythmScores: [Int?] = [],
        observationTitle: String = "",
        observationBody: String = "",
        observationProviderModel: String? = nil,
        refsTakeCount: Int = 0,
        refsVideoCount: Int = 0,
        observationStatus: String = "pending",
        generatedAt: Date = Date()
    ) {
        self.year = year
        self.month = month
        self.periodKey = periodKey ?? MonthlyCalendar.periodKey(year: year, month: month)
        self.validDays = validDays
        self.totalDurationSec = totalDurationSec
        self.takeCount = takeCount
        self.avgSessionsPerWeek = avgSessionsPerWeek
        self.beyerCurrent = beyerCurrent
        self.hanonCurrent = hanonCurrent
        self.unlocked599 = unlocked599
        self.projected599Week = projected599Week
        self.warmupCompletionPct = warmupCompletionPct
        self.overrideCount = overrideCount
        self.overrideReasons = overrideReasons
        self.rhythmFirstWeekScore = rhythmFirstWeekScore
        self.rhythmLastWeekScore = rhythmLastWeekScore
        self.weeklyRhythmScores = weeklyRhythmScores
        self.observationTitle = observationTitle
        self.observationBody = observationBody
        self.observationProviderModel = observationProviderModel
        self.refsTakeCount = refsTakeCount
        self.refsVideoCount = refsVideoCount
        self.observationStatus = observationStatus
        self.generatedAt = generatedAt
    }
}
