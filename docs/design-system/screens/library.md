# 曲库 Library（系统层）

覆盖：S08 曲库 / S09 曲目详情 / S10 PDF 资料库 / S08b 导入失败。

## 三段内容来源

- 训练教材：课程内置公版教材元数据（拜厄/哈农/599），Piece.status 由课程引擎维护；锁/预计周由 CoursePathState 派生。
- 奖励曲库：手动导入的非公版谱（Piece.sourceScoreId 指向可跟弹 ScoreFile）。
- 全部导入：设备上全部 ScoreFile（按类型）。

## 导入契约（M2）

- 入口：Files/iCloud 选择器、分享面板"拷贝到 PianoSempai"、S08 虚线卡。
- 支持：.xml/.mxl（v1 必达）、.mscz（spike 验证，失败文案引导导出 mxl）、.mid（简易跟弹：无指法/教材归属）。
- 解析成功 → ScoreFile(canFollow=true) + Piece(book=导入, status=notStarted)。
- 解析失败 → S08b：必须给定位（小节/标签）+ 错误码；不产生假曲目。
- PDF → ScoreFile(kind=pdf, canFollow=false)，只出现在 S10；不 OMR、不猜分轨、不猜指法。

## S09 数据与动作

- 头部元数据来自 Piece + ScoreFile；疑似谱错计数来自 ScoreErrorMark。
- 过关标准为 M3 硬阈值（错音率 ≤2% / 节奏偏差中位 ≤50ms / 速度 ≥♩=72 且连续 2 遍）；本页只读展示，判定在引擎。
- 小节段选择驱动练习任务范围（17–24 默认当前段，21 为最近热点，热点由 TakeAnalysis.measureHeat 计算）。
- 最近 take：Take 列表（≤3 概览，全部去档案）；行 → S13。
- 「只练错误热点」→ S11（mode=hotspot，预填循环段）；「开始练习」→ S11。

## 状态流转

locked → notStarted（路线到达自动）→ practicing（首个 take 后）→ passed（引擎）。奖励曲无 locked/passed，只有 practicing/归档。
