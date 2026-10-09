import Foundation
import SwiftData

// SwiftData 模型 v1（docs/design-system/data-model.md §2；字段可实现时增补但语义锁定）。
// P1 M3 先落 onboarding 相关表；Take/ScoreFile/Piece 等随曲库/练习批次增补。

/// 单例设置。Key 永不入此模型（Keychain，红线 3）。
@Model
final class AppSettings {
    var onboardingCompleted: Bool = false
    /// onboarding 进行到的阶段（未完成可退出续做，onboarding 域契约）
    var onboardingStage: String = OnboardingStage.welcome.rawValue
    /// 用户中途退出流程（S03 ✕ / S04 稍后评估）→ 直接进框架，S07b「继续定级」恢复
    var onboardingDismissed: Bool = false
    /// 进入定级（S04）的时间戳：S07b「继续定级（还剩 X 分钟）」的诚实估算依据
    var placementStartedAt: Date?
    var weeklyGoal: Int = 3
    var notificationConfigured: Bool = false
    /// M7.2 周报本地通知总开关（PRD 主动性 Q2=A 已认可；默认开，用户可在「通知」页全关）
    var weeklyDigestEnabled: Bool = true
    var createdAt: Date = Date()

    /// 显式 init（@Model 宏对此类的 init 综合失败，原因未明；显式提供绕过）
    init(onboardingCompleted: Bool = false, onboardingStage: String = OnboardingStage.welcome.rawValue, onboardingDismissed: Bool = false, placementStartedAt: Date? = nil, weeklyGoal: Int = 3, notificationConfigured: Bool = false, weeklyDigestEnabled: Bool = true, createdAt: Date = Date()) {
        self.onboardingCompleted = onboardingCompleted
        self.onboardingStage = onboardingStage
        self.onboardingDismissed = onboardingDismissed
        self.placementStartedAt = placementStartedAt
        self.weeklyGoal = weeklyGoal
        self.notificationConfigured = notificationConfigured
        self.weeklyDigestEnabled = weeklyDigestEnabled
        self.createdAt = createdAt
    }

    static func fetchOrCreate(in context: ModelContext) -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let settings = AppSettings()
        context.insert(settings)
        return settings
    }
}

/// onboarding 阶段（AppSettings.onboardingStage 的取值域）
enum OnboardingStage: String {
    case welcome
    case permissions
    case midiWizard
    case placement // S04（自评/视奏/力度校准三小步）
    case result // S05
    case done
}

/// 定级自评（S04）：只作选段先验，不直接决定插入点（onboarding 域契约）
@Model
final class PlacementSelfReport {
    var entityId: UUID = UUID()
    var yearsExperience: String = ""
    var books: [String] = []
    var timesPerWeek: String = ""
    var durationPref: String = ""
    var genres: [String] = []
    var recentPiece: String = ""
    var createdAt: Date = Date()

    /// 显式 init（@Model 宏 init 综合不稳定，显式提供）
    init(entityId: UUID = UUID(), yearsExperience: String = "", books: [String] = [], timesPerWeek: String = "", durationPref: String = "", genres: [String] = [], recentPiece: String = "", createdAt: Date = Date()) {
        self.entityId = entityId
        self.yearsExperience = yearsExperience
        self.books = books
        self.timesPerWeek = timesPerWeek
        self.durationPref = durationPref
        self.genres = genres
        self.recentPiece = recentPiece
        self.createdAt = createdAt
    }

}

/// 定级结果（S05 产出；插入点由 CourseEngine 规则表产出，P1 简化、P2 替换）
@Model
final class PlacementResult {
    var entityId: UUID = UUID()
    var selfReportId: UUID = UUID()
    /// 两段视奏命中率（真实采集：音序简单匹配，非对齐算法；0-1）
    var sightreadHitRates: [Double] = []
    /// 各段期望音符数 / 命中数（供"算法数字可解释"展示）
    var sightreadExpected: [Int] = []
    var sightreadMatched: [Int] = []
    /// 连贯性：停顿次数（相邻音 >2s）
    var pauseCounts: [Int] = []
    /// 综合参考（规则估算，不作过关依据；弱总分脚注见 visual-system §9.10）
    var overallReferenceScore: Int = 0
    /// 规则表产出
    var entryBeyer: Int = 1
    var entryHanon: Int = 1
    var projected599Weeks: Int = 0
    /// 本次评估用时（秒，真实计时）
    var elapsedSeconds: Int = 0
    var velocityCalibrationId: UUID?
    var createdAt: Date = Date()

    /// 显式 init（@Model 宏 init 综合不稳定，显式提供）
    init(entityId: UUID = UUID(), selfReportId: UUID = UUID(), sightreadHitRates: [Double] = [], sightreadExpected: [Int] = [], sightreadMatched: [Int] = [], pauseCounts: [Int] = [], overallReferenceScore: Int = 0, entryBeyer: Int = 1, entryHanon: Int = 1, projected599Weeks: Int = 0, elapsedSeconds: Int = 0, velocityCalibrationId: UUID? = nil, createdAt: Date = Date()) {
        self.entityId = entityId
        self.selfReportId = selfReportId
        self.sightreadHitRates = sightreadHitRates
        self.sightreadExpected = sightreadExpected
        self.sightreadMatched = sightreadMatched
        self.pauseCounts = pauseCounts
        self.overallReferenceScore = overallReferenceScore
        self.entryBeyer = entryBeyer
        self.entryHanon = entryHanon
        self.projected599Weeks = projected599Weeks
        self.elapsedSeconds = elapsedSeconds
        self.velocityCalibrationId = velocityCalibrationId
        self.createdAt = createdAt
    }

}

/// 力度校准（pp/mp/mf 三档中位 velocity；后续力度维度按个人曲线归一）
@Model
final class VelocityCalibration {
    var entityId: UUID = UUID()
    /// 最弱 / 舒适 / 最强 三档的 velocity 中位数（真实采集）
    var ppVelocity: Int = 0
    var mfVelocity: Int = 0
    var ffVelocity: Int = 0
    /// 各档采到的样本数（0 = 未校准，诚实标记）
    var ppSamples: Int = 0
    var mfSamples: Int = 0
    var ffSamples: Int = 0
    var deviceName: String = ""
    var createdAt: Date = Date()

    var isCalibrated: Bool { ppSamples > 0 && mfSamples > 0 && ffSamples > 0 }

    /// 显式 init（@Model 宏 init 综合不稳定，显式提供）
    init(entityId: UUID = UUID(), ppVelocity: Int = 0, mfVelocity: Int = 0, ffVelocity: Int = 0, ppSamples: Int = 0, mfSamples: Int = 0, ffSamples: Int = 0, deviceName: String = "", createdAt: Date = Date()) {
        self.entityId = entityId
        self.ppVelocity = ppVelocity
        self.mfVelocity = mfVelocity
        self.ffVelocity = ffVelocity
        self.ppSamples = ppSamples
        self.mfSamples = mfSamples
        self.ffSamples = ffSamples
        self.deviceName = deviceName
        self.createdAt = createdAt
    }

}

/// 路线状态（单例；只由 CourseEngine 写，红线 3/写入权矩阵）
@Model
final class CoursePathState {
    var entityId: UUID = UUID()
    var currentBeyer: Int = 1
    var currentHanon: Int = 1
    var current599: Int?
    var projected599Week: Int = 0
    var weekNumber: Int = 1
    var placementResultId: UUID?
    var updatedAt: Date = Date()

    /// 显式 init（@Model 宏 init 综合不稳定，显式提供）
    init(entityId: UUID = UUID(), currentBeyer: Int = 1, currentHanon: Int = 1, current599: Int? = nil, projected599Week: Int = 0, weekNumber: Int = 1, placementResultId: UUID? = nil, updatedAt: Date = Date()) {
        self.entityId = entityId
        self.currentBeyer = currentBeyer
        self.currentHanon = currentHanon
        self.current599 = current599
        self.projected599Week = projected599Week
        self.weekNumber = weekNumber
        self.placementResultId = placementResultId
        self.updatedAt = updatedAt
    }

}

/// 今日计划（P1 简化；CourseEngine 唯一写手）
@Model
final class DailyPlan {
    var date: Date = Date()
    var durationChoice: Int = 30
    var warmupTaskId: UUID?
    var mainTaskId: UUID?
    var rewardTaskId: UUID?
    var warmupCompletedAt: Date?
    var gateOverrideId: UUID?
    var generatedFromRulesVersion: String = ""

    /// 显式 init（@Model 宏 init 综合不稳定，显式提供）
    init(date: Date = Date(), durationChoice: Int = 30, warmupTaskId: UUID? = nil, mainTaskId: UUID? = nil, rewardTaskId: UUID? = nil, warmupCompletedAt: Date? = nil, gateOverrideId: UUID? = nil, generatedFromRulesVersion: String = "") {
        self.date = date
        self.durationChoice = durationChoice
        self.warmupTaskId = warmupTaskId
        self.mainTaskId = mainTaskId
        self.rewardTaskId = rewardTaskId
        self.warmupCompletedAt = warmupCompletedAt
        self.gateOverrideId = gateOverrideId
        self.generatedFromRulesVersion = generatedFromRulesVersion
    }

}

/// 门禁/强开事件（kind 语义锁定 data-model §2：warmupBlocked/override/passAssessed）
@Model
final class GateEvent {
    var entityId: UUID = UUID()
    var date: Date = Date()
    /// warmupBlocked / override / passAssessed
    var kind: String = ""
    /// 强开原因标签（S07c 四选一；"其他"时存"other"）
    var reasonTag: String = ""
    /// "其他"的补充一句（可为空）
    var note: String = ""
    /// 周索引（周一起始，供"本周第 N 次"聚合）
    var weekIndex: Int = 0

    /// 显式 init（@Model 宏 init 综合不稳定，显式提供）
    init(entityId: UUID = UUID(), date: Date = Date(), kind: String = "", reasonTag: String = "", note: String = "", weekIndex: Int = 0) {
        self.entityId = entityId
        self.date = date
        self.kind = kind
        self.reasonTag = reasonTag
        self.note = note
        self.weekIndex = weekIndex
    }
}

/// Take 元数据（P1 简化报告口径：真实统计值；M5 完整判分 P2 补齐）
@Model
final class Take {
    var entityId: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date?
    var durationSec: Int = 0
    /// warmup / main / reward / free
    var taskType: String = ""
    /// 是否有 MIDI 数据（有效练习 = 有 MIDI 且当日累计 ≥10 分钟，M9 口径）
    var hasMidi: Bool = false
    var isFreePlay: Bool = false
    /// 原始 MIDI 事件文件（沙盒相对路径；只追加不可变，红线 4）
    var midiFileURL: String = ""
    /// 练习小节区间（P1 来自循环设置；自由弹奏为 nil）
    var measureFrom: Int?
    var measureTo: Int?
    var tempoAvg: Int = 0
    /// 真实统计（S13 P1 报告）
    var noteCount: Int = 0
    var wrongNoteCount: Int = 0
    var pedalEventCount: Int = 0
    var midiEventCount: Int = 0
    /// 断连区间（秒起点列表，S11b 重连续录标注）
    var interruptionRanges: [Int] = []
    /// 逐音错音明细（"小节:音高"字符串；P1 简化存储，S13b 剔除规则数据源）
    var wrongNoteRecords: [String] = []
    /// 关联曲目/谱（P2 M4：把 take 挂到具体曲目与可跟弹谱；分析缓存外键）
    var pieceId: UUID?
    var scoreFileId: UUID?
    /// 最新 TakeAnalysis 的 entityId（重算幂等 upsert 时更新）
    var analysisId: UUID?
    /// 该 take 是否参与了过关判定（高置信 + 覆盖完整；低置信/无谱 take = false，不计数不清零）
    var isPassEligible: Bool = false
    /// 自由弹奏一句话 / take 标题
    var title: String = ""

    /// 显式 init（@Model 宏 init 综合不稳定，显式提供）
    init(entityId: UUID = UUID(), startedAt: Date = Date(), endedAt: Date? = nil, durationSec: Int = 0, taskType: String = "", hasMidi: Bool = false, isFreePlay: Bool = false, midiFileURL: String = "", measureFrom: Int? = nil, measureTo: Int? = nil, tempoAvg: Int = 0, noteCount: Int = 0, wrongNoteCount: Int = 0, pedalEventCount: Int = 0, midiEventCount: Int = 0, interruptionRanges: [Int] = [], wrongNoteRecords: [String] = [], pieceId: UUID? = nil, scoreFileId: UUID? = nil, analysisId: UUID? = nil, isPassEligible: Bool = false, title: String = "") {
        self.entityId = entityId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSec = durationSec
        self.taskType = taskType
        self.hasMidi = hasMidi
        self.isFreePlay = isFreePlay
        self.midiFileURL = midiFileURL
        self.measureFrom = measureFrom
        self.measureTo = measureTo
        self.tempoAvg = tempoAvg
        self.noteCount = noteCount
        self.wrongNoteCount = wrongNoteCount
        self.pedalEventCount = pedalEventCount
        self.midiEventCount = midiEventCount
        self.interruptionRanges = interruptionRanges
        self.wrongNoteRecords = wrongNoteRecords
        self.pieceId = pieceId
        self.scoreFileId = scoreFileId
        self.analysisId = analysisId
        self.isPassEligible = isPassEligible
        self.title = title
    }
}

/// P2 判分结果（SPEC §8）：派生缓存，可删可重建（原始 jsonl + 谱是唯一真值，红线 3）。
/// 一个 take 至多一份（按 takeId + engineVersion 幂等 upsert）。
@Model
final class TakeAnalysis {
    var entityId: UUID = UUID()
    var takeId: UUID = UUID()
    var analyzedAt: Date = Date()
    /// = "P2-scoring-1.0"（SPEC §8）
    var engineVersion: String = ""
    var confidence: Double = 0
    var lowConfidenceReasons: [String] = []
    // 六维（可空——算不出 = nil，UI 显式「数据不足」，禁止编分，红线 1）
    var pitchScore: Int?
    var rhythmScore: Int?
    var tempoScore: Int?
    var dynamicsScore: Int?
    var continuityScore: Int?
    var handsScore: Int?
    /// 弱总分（非 nil 维度等权；不作过关依据，红线 4）
    var weakTotal: Int?
    var wrongCount: Int = 0
    var missingCount: Int = 0
    var extraCount: Int = 0
    var wrongPitchCount: Int = 0
    /// 评分区间内非 grace 参考音数（错音率分母；S09/S13 重算「差多少」用，§7）
    var referenceNoteCount: Int = 0
    var rhythmMedianMs: Double = 0
    var rhythmMeanMs: Double = 0
    /// tempoScore 的达标布尔（门禁用）
    var tempoTargetHit: Bool = false
    /// 实测平均速度（BPM；0 = 速度维算不出）。S13 速度项展示真实值用
    var avgBPM: Double = 0
    var hotspotMeasures: [Int] = []
    /// 小节热力 JSON（[Int: HeatValue] 结构化序列化）
    var measureHeatJSON: String = ""
    /// 门禁判定（evaluatePass 纯函数产出后回写）
    var canEvaluate: Bool = false
    var passesHardMetrics: Bool = false
    /// 逐音 AlignedNote JSON（永久回看 + S21 对比）
    var alignmentJSON: String = ""

    /// 显式 init（@Model 宏 init 综合不稳定，显式提供）
    init(entityId: UUID = UUID(), takeId: UUID = UUID(), analyzedAt: Date = Date(), engineVersion: String = "", confidence: Double = 0, lowConfidenceReasons: [String] = [], pitchScore: Int? = nil, rhythmScore: Int? = nil, tempoScore: Int? = nil, dynamicsScore: Int? = nil, continuityScore: Int? = nil, handsScore: Int? = nil, weakTotal: Int? = nil, wrongCount: Int = 0, missingCount: Int = 0, extraCount: Int = 0, wrongPitchCount: Int = 0, referenceNoteCount: Int = 0, rhythmMedianMs: Double = 0, rhythmMeanMs: Double = 0, tempoTargetHit: Bool = false, avgBPM: Double = 0, hotspotMeasures: [Int] = [], measureHeatJSON: String = "", canEvaluate: Bool = false, passesHardMetrics: Bool = false, alignmentJSON: String = "") {
        self.entityId = entityId
        self.takeId = takeId
        self.analyzedAt = analyzedAt
        self.engineVersion = engineVersion
        self.confidence = confidence
        self.lowConfidenceReasons = lowConfidenceReasons
        self.pitchScore = pitchScore
        self.rhythmScore = rhythmScore
        self.tempoScore = tempoScore
        self.dynamicsScore = dynamicsScore
        self.continuityScore = continuityScore
        self.handsScore = handsScore
        self.weakTotal = weakTotal
        self.wrongCount = wrongCount
        self.missingCount = missingCount
        self.extraCount = extraCount
        self.wrongPitchCount = wrongPitchCount
        self.referenceNoteCount = referenceNoteCount
        self.rhythmMedianMs = rhythmMedianMs
        self.rhythmMeanMs = rhythmMeanMs
        self.tempoTargetHit = tempoTargetHit
        self.avgBPM = avgBPM
        self.hotspotMeasures = hotspotMeasures
        self.measureHeatJSON = measureHeatJSON
        self.canEvaluate = canEvaluate
        self.passesHardMetrics = passesHardMetrics
        self.alignmentJSON = alignmentJSON
    }
}

/// 会话任务（Swift 原生 Task 类型冲突，故命名 PracticeTask；语义同 data-model Task）
@Model
final class PracticeTask {
    /// warmup / main / reward / free
    var type: String = ""
    /// P1 暂无 Piece 实体，用教材名 + 条目定位；曲库批次接入后换 pieceId
    var book: String = ""
    var number: Int = 0
    var measureFrom: Int?
    var measureTo: Int?
    var tempo: Int?
    var status: String = "pending"
    var taskId: UUID = UUID()

    /// 显式 init（@Model 宏 init 综合不稳定，显式提供）
    init(type: String = "", book: String = "", number: Int = 0, measureFrom: Int? = nil, measureTo: Int? = nil, tempo: Int? = nil, status: String = "pending", taskId: UUID = UUID()) {
        self.type = type
        self.book = book
        self.number = number
        self.measureFrom = measureFrom
        self.measureTo = measureTo
        self.tempo = tempo
        self.status = status
        self.taskId = taskId
    }

}

/// 曲目（data-model §2；P1：内置教材由目录 JSON + CoursePathState 派生，导入曲目落库）
@Model
final class Piece {
    var entityId: UUID = UUID()
    var title: String = ""
    /// 拜厄 / 哈农 / 599 / 奖励曲 / 导入
    var book: String = ""
    var number: Int = 0
    var totalMeasures: Int = 0
    /// locked / notStarted / practicing / passed / waived / reviewing（ADR-0003 状态机；只由 CourseEngine 写，红线 1/3）
    var status: String = "notStarted"
    var referenceTempo: Int = 0
    /// 可跟弹谱文件（ScoreFile.entityId）
    var sourceScoreId: UUID?
    var suspectedErrorCount: Int = 0
    /// 过关时的规则版本留痕（SPEC L162；nil = 尚未过关）
    var passedRulesVersion: String?
    /// 下次复习到期时间（ADR-0003 Q6/Q8：过关后按 1/3/7/14 天间隔复习；nil = 不在复习池）
    var nextReviewAt: Date? = nil
    /// 复习间隔档位下标（ADR-0003 Q8/Q14：reviewIntervalDays[stage]，到 14 天档后循环不毕业）
    var intervalStage: Int = 0
    var importedAt: Date = Date()

    /// 显式 init（@Model 宏 init 综合不稳定，显式提供）
    init(entityId: UUID = UUID(), title: String = "", book: String = "", number: Int = 0, totalMeasures: Int = 0, status: String = "notStarted", referenceTempo: Int = 0, sourceScoreId: UUID? = nil, suspectedErrorCount: Int = 0, passedRulesVersion: String? = nil, nextReviewAt: Date? = nil, intervalStage: Int = 0, importedAt: Date = Date()) {
        self.entityId = entityId
        self.title = title
        self.book = book
        self.number = number
        self.totalMeasures = totalMeasures
        self.status = status
        self.referenceTempo = referenceTempo
        self.sourceScoreId = sourceScoreId
        self.suspectedErrorCount = suspectedErrorCount
        self.passedRulesVersion = passedRulesVersion
        self.nextReviewAt = nextReviewAt
        self.intervalStage = intervalStage
        self.importedAt = importedAt
    }
}

/// 谱面文件（data-model §2；沙盒相对路径，DB 只存路径）
@Model
final class ScoreFile {
    var entityId: UUID = UUID()
    /// musicxml / mxl / mscz / mid / pdf
    var kind: String = ""
    /// 沙盒相对路径（scores/ 或 pdfs/ 下）
    var fileURL: String = ""
    var title: String = ""
    /// pdf = false（不能跟弹，只查看）
    var canFollow: Bool = false
    /// ok / failed（失败文件不入库，此字段预留诊断）
    var parseStatus: String = "ok"
    var importedAt: Date = Date()
    var fileExt: String = ""

    /// 显式 init（@Model 宏 init 综合不稳定，显式提供）
    init(entityId: UUID = UUID(), kind: String = "", fileURL: String = "", title: String = "", canFollow: Bool = false, parseStatus: String = "ok", importedAt: Date = Date(), fileExt: String = "") {
        self.entityId = entityId
        self.kind = kind
        self.fileURL = fileURL
        self.title = title
        self.canFollow = canFollow
        self.parseStatus = parseStatus
        self.importedAt = importedAt
        self.fileExt = fileExt
    }
}


/// 疑似谱面错误标记（data-model §2 / S13b：标记不扣分、不影响过关）
@Model
final class ScoreErrorMark {
    var entityId: UUID = UUID()
    /// 曲目标识（P1 用曲目名；Piece 关联随练习批次细化）
    var scoreName: String = ""
    var measure: Int = 0
    /// note / rhythm / fingering
    var type: String = ""
    var note: String = ""
    var occurrenceCount: Int = 1
    /// S13b「同时在下次问 Neko 时带上这个标记」（用户勾选才 true；默认 false，轻量迁移补默认值）
    var includeWithNeko: Bool = false
    var createdAt: Date = Date()

    /// 显式 init（@Model 宏 init 综合不稳定，显式提供）
    init(entityId: UUID = UUID(), scoreName: String = "", measure: Int = 0, type: String = "", note: String = "", occurrenceCount: Int = 1, includeWithNeko: Bool = false, createdAt: Date = Date()) {
        self.entityId = entityId
        self.scoreName = scoreName
        self.measure = measure
        self.type = type
        self.note = note
        self.occurrenceCount = occurrenceCount
        self.includeWithNeko = includeWithNeko
        self.createdAt = createdAt
    }
}

// MARK: - M7.1 AI 助教（多服务商链；docs/decisions/0001）

/// 服务商配置（data-model §2 providerChain 条目 / §5 出站接口）。
/// **只存非密配置**：每商 Key 在 Keychain（ProviderKeyStore，account = providerId），
/// 永不进本表/日志/导出包（红线 2）。
@Model
final class AIProvider {
    var entityId: UUID = UUID()
    /// 稳定唯一标识（"ark"/"bailian"/"deepseek"/自定义 UUID 串）。
    /// Keychain 的 account 用它——改了等于换一条 key 条目，历史 key 不串。
    var providerId: String = ""
    var displayName: String = ""
    /// OpenAI 兼容入口（如 https://ark.cn-beijing.volces.com/api/v3）；
    /// 客户端只拼 "/chat/completions"，尾斜杠有无都容错。模型 id 不写死在 App。
    var baseURL: String = ""
    /// 该商下模型 id，可多个；按数组顺序依次尝试，任一调通即用。
    var modelIds: [String] = []
    var enabled: Bool = true
    /// 链上优先级（升序；同值按录入序，稳定排序不抖动）
    var sortOrder: Int = 0

    /// 显式 init（@Model 宏 init 综合不稳定，显式提供）
    init(entityId: UUID = UUID(), providerId: String = "", displayName: String = "", baseURL: String = "", modelIds: [String] = [], enabled: Bool = true, sortOrder: Int = 0) {
        self.entityId = entityId
        self.providerId = providerId
        self.displayName = displayName
        self.baseURL = baseURL
        self.modelIds = modelIds
        self.enabled = enabled
        self.sortOrder = sortOrder
    }
}

/// 问答会话（data-model §2 ChatThread）。标题不存（Stage B 由首条消息派生）。
@Model
final class ChatThread {
    var entityId: UUID = UUID()
    /// nil = 全局自由问答；非 nil = 挂在某个 take 上（S18b 上下文）
    var takeContextId: UUID?
    var createdAt: Date = Date()

    /// 显式 init（@Model 宏 init 综合不稳定，显式提供）
    init(entityId: UUID = UUID(), takeContextId: UUID? = nil, createdAt: Date = Date()) {
        self.entityId = entityId
        self.takeContextId = takeContextId
        self.createdAt = createdAt
    }
}

/// 对话消息（data-model §2 ChatMessage）。两个 JSON 字段是字符串，
/// 便于 SwiftData 直接存/导出（结构定义在 Services/AI/AIModels.swift）。
@Model
final class ChatMessage {
    var entityId: UUID = UUID()
    var threadId: UUID = UUID()
    /// user / neko
    var role: String = ""
    var text: String = ""
    /// 附件 id 数组 JSON。M7.1 恒 "[]"（视频阶段才经 S18b 确认后写入，本 Stage 不做视频）
    var attachmentsJSON: String = "[]"
    /// EvidenceRef 数组 JSON（{takeId, measure, deviationMs?}）
    var evidenceRefsJSON: String = "[]"
    /// 本次实际命中「服务商·模型」（运行时写入，非写死）；user 消息为 ""
    var providerModel: String = ""
    var createdAt: Date = Date()

    /// 显式 init（@Model 宏 init 综合不稳定，显式提供）
    init(entityId: UUID = UUID(), threadId: UUID = UUID(), role: String = "", text: String = "", attachmentsJSON: String = "[]", evidenceRefsJSON: String = "[]", providerModel: String = "", createdAt: Date = Date()) {
        self.entityId = entityId
        self.threadId = threadId
        self.role = role
        self.text = text
        self.attachmentsJSON = attachmentsJSON
        self.evidenceRefsJSON = evidenceRefsJSON
        self.providerModel = providerModel
        self.createdAt = createdAt
    }
}

/// 练琴笔记（data-model §2 Note 语义；类名避开 Swift 原生 Note，与 PracticeTask 风格一致）。
/// 问答沉淀（Q11）与手动笔记都落这里；只由用户/AI 助教域写，不碰课程状态。
@Model
final class PracticeNote {
    var entityId: UUID = UUID()
    /// manual / weeklyReport / issue
    var kind: String = "manual"
    var title: String = ""
    var body: String = ""
    var linkedTakeId: UUID?
    /// 周报所属周（weekStart 的 "yyyy-MM-dd"，周一起始；M7.2 周报按此去重，其它类型笔记为 nil）
    var weekKey: String?
    /// open / resolved
    var status: String = "open"
    var createdAt: Date = Date()

    /// 显式 init（@Model 宏 init 综合不稳定，显式提供）
    init(entityId: UUID = UUID(), kind: String = "manual", title: String = "", body: String = "", linkedTakeId: UUID? = nil, weekKey: String? = nil, status: String = "open", createdAt: Date = Date()) {
        self.entityId = entityId
        self.kind = kind
        self.title = title
        self.body = body
        self.linkedTakeId = linkedTakeId
        self.weekKey = weekKey
        self.status = status
        self.createdAt = createdAt
    }
}

/// 月报（PRD M8：每月 1 号生成上月；S22 月度报告详情）。
/// 快照语义：落库即冻结，算法升级后不重算已出月报（PRD）——字段是当时的真实统计，
/// 不是课程/判分状态的引用。只由 M9 聚合域写（从 take 派生，可重建），不碰课程/判分/计划状态（红线 3）。
/// 两个结构化字段（原因分布 / 周均节奏可空数组）存 JSON 字符串，与 ChatMessage 同风格：
/// SwiftData 直存、导出包可读，映射见 `snapshot` 与 `init(snapshot:)`。
@Model
final class MonthlyReport {
    var entityId: UUID = UUID()
    /// "yyyy-MM"（MonthlyCalendar.periodKey）；一个月一条，按此去重
    var periodKey: String = ""
    var year: Int = 0
    var month: Int = 0
    /// 当月有有效 take 的 distinct 日历日数
    var validDays: Int = 0
    /// 当月有效 take 时长之和（秒）
    var totalDurationSec: Int = 0
    /// 当月全部 take 数（含无效，如实）
    var takeCount: Int = 0
    /// 有效 take 数 / 当月覆盖周数
    var avgSessionsPerWeek: Double?
    // 教材路线（快照值；解锁只由硬数据规则判定，强开记录不影响）
    var beyerCurrent: Int = 1
    var hanonCurrent: Int = 1
    var unlocked599: Bool = false
    /// 599 已开始时的当前首号（未解锁存 nil）
    var current599: Int? = nil
    var projected599Week: Int = 0
    // 热身与门禁
    /// 热身完成天数 / 计划天数 * 100；当月无计划存 nil（不填 0）
    var warmupCompletionPct: Int?
    var overrideCount: Int = 0
    /// [reasonTag: 次数] JSON（空/other 已合并为 "other"）
    var overrideReasonsJSON: String = "{}"
    var rhythmFirstWeekScore: Int?
    var rhythmLastWeekScore: Int?
    /// [Int?] JSON：月内各周（按 weekStart 升序）的 rhythmScore 周均；null = 该周无分析
    var weeklyRhythmScoresJSON: String = "[]"
    // AI 观察（b2 才起草；本 Stage 恒空正文 + pending）
    var observationTitle: String = ""
    var observationBody: String = ""
    /// 本次实际命中的「服务商·模型」（b2 写入）
    var observationProviderModel: String?
    var refsTakeCount: Int = 0
    /// 无视频批次，恒 0
    var refsVideoCount: Int = 0
    /// pending / ok / failed
    var observationStatus: String = "pending"
    var generatedAt: Date = Date()

    /// 显式 init（@Model 宏 init 综合不稳定，显式提供）；默认值即「空月报」的安全形态
    init(
        entityId: UUID = UUID(),
        periodKey: String = "",
        year: Int = 0,
        month: Int = 0,
        validDays: Int = 0,
        totalDurationSec: Int = 0,
        takeCount: Int = 0,
        avgSessionsPerWeek: Double? = nil,
        beyerCurrent: Int = 1,
        hanonCurrent: Int = 1,
        unlocked599: Bool = false,
        current599: Int? = nil,
        projected599Week: Int = 0,
        warmupCompletionPct: Int? = nil,
        overrideCount: Int = 0,
        overrideReasonsJSON: String = "{}",
        rhythmFirstWeekScore: Int? = nil,
        rhythmLastWeekScore: Int? = nil,
        weeklyRhythmScoresJSON: String = "[]",
        observationTitle: String = "",
        observationBody: String = "",
        observationProviderModel: String? = nil,
        refsTakeCount: Int = 0,
        refsVideoCount: Int = 0,
        observationStatus: String = "pending",
        generatedAt: Date = Date()
    ) {
        self.entityId = entityId
        self.periodKey = periodKey
        self.year = year
        self.month = month
        self.validDays = validDays
        self.totalDurationSec = totalDurationSec
        self.takeCount = takeCount
        self.avgSessionsPerWeek = avgSessionsPerWeek
        self.beyerCurrent = beyerCurrent
        self.hanonCurrent = hanonCurrent
        self.unlocked599 = unlocked599
        self.current599 = current599
        self.projected599Week = projected599Week
        self.warmupCompletionPct = warmupCompletionPct
        self.overrideCount = overrideCount
        self.overrideReasonsJSON = overrideReasonsJSON
        self.rhythmFirstWeekScore = rhythmFirstWeekScore
        self.rhythmLastWeekScore = rhythmLastWeekScore
        self.weeklyRhythmScoresJSON = weeklyRhythmScoresJSON
        self.observationTitle = observationTitle
        self.observationBody = observationBody
        self.observationProviderModel = observationProviderModel
        self.refsTakeCount = refsTakeCount
        self.refsVideoCount = refsVideoCount
        self.observationStatus = observationStatus
        self.generatedAt = generatedAt
    }

    /// 快照 → 模型（显式 init；JSON 编码，纯值转换不碰 ModelContext）
    init(snapshot: MonthlyReportSnapshot, entityId: UUID = UUID()) {
        self.entityId = entityId
        self.periodKey = snapshot.periodKey
        self.year = snapshot.year
        self.month = snapshot.month
        self.validDays = snapshot.validDays
        self.totalDurationSec = snapshot.totalDurationSec
        self.takeCount = snapshot.takeCount
        self.avgSessionsPerWeek = snapshot.avgSessionsPerWeek
        self.beyerCurrent = snapshot.beyerCurrent
        self.hanonCurrent = snapshot.hanonCurrent
        self.unlocked599 = snapshot.unlocked599
        self.current599 = snapshot.current599
        self.projected599Week = snapshot.projected599Week
        self.warmupCompletionPct = snapshot.warmupCompletionPct
        self.overrideCount = snapshot.overrideCount
        self.overrideReasonsJSON = Self.encode(snapshot.overrideReasons) ?? "{}"
        self.rhythmFirstWeekScore = snapshot.rhythmFirstWeekScore
        self.rhythmLastWeekScore = snapshot.rhythmLastWeekScore
        self.weeklyRhythmScoresJSON = Self.encode(snapshot.weeklyRhythmScores) ?? "[]"
        self.observationTitle = snapshot.observationTitle
        self.observationBody = snapshot.observationBody
        self.observationProviderModel = snapshot.observationProviderModel
        self.refsTakeCount = snapshot.refsTakeCount
        self.refsVideoCount = snapshot.refsVideoCount
        self.observationStatus = snapshot.observationStatus
        self.generatedAt = snapshot.generatedAt
    }

    /// 模型 → 快照（JSON 解码；损坏给安全空值 [:]/[]，不崩溃——坏一行不等于坏整份月报）
    var snapshot: MonthlyReportSnapshot {
        MonthlyReportSnapshot(
            year: year,
            month: month,
            periodKey: periodKey,
            validDays: validDays,
            totalDurationSec: totalDurationSec,
            takeCount: takeCount,
            avgSessionsPerWeek: avgSessionsPerWeek,
            beyerCurrent: beyerCurrent,
            hanonCurrent: hanonCurrent,
            unlocked599: unlocked599,
            current599: current599,
            projected599Week: projected599Week,
            warmupCompletionPct: warmupCompletionPct,
            overrideCount: overrideCount,
            overrideReasons: Self.decode(String.self, Int.self, from: overrideReasonsJSON) ?? [:],
            rhythmFirstWeekScore: rhythmFirstWeekScore,
            rhythmLastWeekScore: rhythmLastWeekScore,
            weeklyRhythmScores: Self.decode(Int?.self, from: weeklyRhythmScoresJSON) ?? [],
            observationTitle: observationTitle,
            observationBody: observationBody,
            observationProviderModel: observationProviderModel,
            refsTakeCount: refsTakeCount,
            refsVideoCount: refsVideoCount,
            observationStatus: observationStatus,
            generatedAt: generatedAt
        )
    }

    // MARK: - JSON 编解码（[String: Int] / [Int?]；本地时区无关，用普通 JSONEncoder）

    private static func encode<T: Encodable>(_ value: T) -> String? {
        // 失败给 nil（不是空串）：调用方的 `?? "{}"` / `?? "[]"` 兜底才生效
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from json: String) -> [T]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([T].self, from: data)
    }

    private static func decode<K: Hashable & Decodable, V: Decodable>(_ keyType: K.Type, _ valueType: V.Type, from json: String) -> [K: V]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([K: V].self, from: data)
    }
}

/// 日常视奏训练留痕（ADR-0004）：只读谱能力的旁观察样本。
/// 不写 Take/TakeAnalysis、不触发过关、不推进课程、不计 streak（brief G4 铁律）。
@Model
final class SightReadDrillRecord {
    var entityId: UUID = UUID()
    /// 拜厄 / 哈农（选片只走内置教材两轨）
    var book: String = ""
    var pieceNumber: Int = 0
    /// 片段起点小节（1-based）
    var measureStart: Int = 0
    var measureCount: Int = 0
    /// 期望音个数（来自真实谱解析；0 = 无期望音）
    var expected: Int = 0
    var matched: Int = 0
    /// 相邻音间隔 > 2s 的次数（现有口径）
    var pauses: Int = 0
    /// 音序贪心匹配命中率 0-1；expected==0 时 nil（不编数字，红线 2）
    var hitRate: Double? = nil
    /// start→stop 真实用时（秒，四舍五入）
    var elapsedSeconds: Int = 0
    /// 复习性视奏（候选带耗尽后复用历史条目）true
    var isReview: Bool = false
    var createdAt: Date = Date()

    /// 显式 init（@Model 宏 init 综合不稳定，显式提供）
    init(entityId: UUID = UUID(), book: String = "", pieceNumber: Int = 0, measureStart: Int = 0, measureCount: Int = 0, expected: Int = 0, matched: Int = 0, pauses: Int = 0, hitRate: Double? = nil, elapsedSeconds: Int = 0, isReview: Bool = false, createdAt: Date = Date()) {
        self.entityId = entityId
        self.book = book
        self.pieceNumber = pieceNumber
        self.measureStart = measureStart
        self.measureCount = measureCount
        self.expected = expected
        self.matched = matched
        self.pauses = pauses
        self.hitRate = hitRate
        self.elapsedSeconds = elapsedSeconds
        self.isReview = isReview
        self.createdAt = createdAt
    }
}

