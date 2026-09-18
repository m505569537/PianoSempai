# 档案 Archive（系统层）

覆盖：S20 档案 / S21 双 take 对比 / S22 月报 / S17 Zf 导入。阶段 P5（S20 基础 take 时间线 P1 即可有简版）。

## S20

- 周选择（周一起始）；统计：有效练习天数（MIDI 且 ≥10 分钟）、总时长、完成 take。
- 周观察卡：P3 前为本地规则摘要（如热身完成率），P3 起为 AI 周报摘要；周日 21:00 生成，本地通知一条。
- 趋势：节奏稳定度取 TakeAnalysis.rhythmicDeviationMedianMs 的周聚合（越小越好，转 0–100 稳定分）；手型趋势需 ≥3 条侧拍才显示，否则占位。
- 时间线类型 chip：全部/课程/奖励曲/自由弹奏；行：课程/奖励→S13，自由→take 回放（无报告），有视频→S16 入口。
- 多选 → S21（仅同 pieceId + 同 measureRange 两条；不符置灰并说明）。

## S21

- A=较新 take，B=较旧；图表全部来自两个 TakeAnalysis 差值；不产生新分析、不产生过关判定。
- CTA「针对 21 小节专项循环」→ S12 预填 start/end。

## S22 月报

- 月 1 日生成上月 WeeklyMonthlyAgg(kind=month) + AI 长文观察（引用 take 数/侧拍数必须真实计数）。
- 路线推进从 Piece 状态历史派生（拜厄 43→48 等）；强开次数从 GateEvent 聚合，带原因分布。
- 解锁声明固定为规则引擎；手型段仅建议措辞。
- 导出 PDF：系统图文渲染；「写进笔记」生成 Note(kind=manual 来源=月报摘要)。

## S17 Zf 导入

- 来源：系统相册（PHPicker 授权范围）；选择后复制原片到 video/monthly/yyyy-MM/，retentionCategory=permanent。
- 不压缩默认（设置可改）；不触发任何网络；不自动跑手型。
- 主动标注：从档案视频详情触发端上 MediaPipe → 生成 PostureObservation，呈现同 S16。
- 与 active 视频隔离：active 每曲最近 8 条 LRU；monthly 永久，存储清理设置只清 active。
- 空间不足前置校验（剩余空间 vs 已选大小）。
