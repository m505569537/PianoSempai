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
    var createdAt: Date = Date()

    /// 显式 init（@Model 宏对此类的 init 综合失败，原因未明；显式提供绕过）
    init(onboardingCompleted: Bool = false, onboardingStage: String = OnboardingStage.welcome.rawValue, onboardingDismissed: Bool = false, placementStartedAt: Date? = nil, weeklyGoal: Int = 3, notificationConfigured: Bool = false, createdAt: Date = Date()) {
        self.onboardingCompleted = onboardingCompleted
        self.onboardingStage = onboardingStage
        self.onboardingDismissed = onboardingDismissed
        self.placementStartedAt = placementStartedAt
        self.weeklyGoal = weeklyGoal
        self.notificationConfigured = notificationConfigured
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
    /// 自由弹奏一句话 / take 标题
    var title: String = ""

    /// 显式 init（@Model 宏 init 综合不稳定，显式提供）
    init(entityId: UUID = UUID(), startedAt: Date = Date(), endedAt: Date? = nil, durationSec: Int = 0, taskType: String = "", hasMidi: Bool = false, isFreePlay: Bool = false, midiFileURL: String = "", measureFrom: Int? = nil, measureTo: Int? = nil, tempoAvg: Int = 0, noteCount: Int = 0, wrongNoteCount: Int = 0, pedalEventCount: Int = 0, midiEventCount: Int = 0, interruptionRanges: [Int] = [], wrongNoteRecords: [String] = [], title: String = "") {
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
        self.title = title
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
    /// locked / notStarted / practicing / passed（只由 CourseEngine 写，红线 1/3）
    var status: String = "notStarted"
    var referenceTempo: Int = 0
    /// 可跟弹谱文件（ScoreFile.entityId）
    var sourceScoreId: UUID?
    var suspectedErrorCount: Int = 0
    var importedAt: Date = Date()

    /// 显式 init（@Model 宏 init 综合不稳定，显式提供）
    init(entityId: UUID = UUID(), title: String = "", book: String = "", number: Int = 0, totalMeasures: Int = 0, status: String = "notStarted", referenceTempo: Int = 0, sourceScoreId: UUID? = nil, suspectedErrorCount: Int = 0, importedAt: Date = Date()) {
        self.entityId = entityId
        self.title = title
        self.book = book
        self.number = number
        self.totalMeasures = totalMeasures
        self.status = status
        self.referenceTempo = referenceTempo
        self.sourceScoreId = sourceScoreId
        self.suspectedErrorCount = suspectedErrorCount
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
    var createdAt: Date = Date()

    /// 显式 init（@Model 宏 init 综合不稳定，显式提供）
    init(entityId: UUID = UUID(), scoreName: String = "", measure: Int = 0, type: String = "", note: String = "", occurrenceCount: Int = 1, createdAt: Date = Date()) {
        self.entityId = entityId
        self.scoreName = scoreName
        self.measure = measure
        self.type = type
        self.note = note
        self.occurrenceCount = occurrenceCount
        self.createdAt = createdAt
    }
}
