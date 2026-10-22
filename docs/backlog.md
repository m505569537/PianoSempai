# Backlog — 推迟需求登记本

本文件是 PianoSempai 唯一的「往后挪 / 待补」需求登记本。新增推迟项一律追加到这里，不再散落在临时审计文件里。

## 本轮完成总结（2026-10-15 ~ 2026-10-16）

- **P2**（已弹音符琥珀着色）done：Stage A 接线 + Stage B cursor-driven referenceNotes 过滤双落地。
- **P3**（分手能力）done：顶栏 hand mode chip（双手/右手/左手）+ PracticeScoreScrollView 非激活 hand 灰显。
- **P4**（纸内谱头/页脚）done：header（编号/速度术语/双手 chip/Op. tag/左手提示）+ footer（页码/版权 chip/曲目引用）+ 模型 + BuiltinCatalog 数据。
- **L1**（按状态筛选曲目）done：CatalogService 新增 pieceStatus 重载，LibraryView/PieceDetailView 优先读 Piece.status，绿 pill「已拿下」可达。
- **T1**（三统计卡真实数据）done：TodayView statsRow 接入 weekStreak/本周时长/距 599 真实数据。
- **T2**（真实热身剩余分钟）done：warmupElapsedMin 聚合当日 warmup take，S07c 正文恢复「还差 N 分钟」，次按钮追加分钟后缀。

测试：766/0 全绿。

---

- 建表：2026-09-23。来源：S07/S08/S11/S13b 对齐 Stitch 真值（code.html）后的偏差审计。
- 每条标注：来源屏 / 推迟原因（能力缺口 or 待产品确认）。
- 无真实数据来源的条目：在能力补齐前不渲染，禁止写死或造假。
- 状态约定：`open` 待办 ｜ `blocked` 依赖未做的能力 ｜ `needs-decision` 待产品确认。

---

## 一、练习室（S11 / S11b）

| # | 需求 | 来源 | 状态 | 说明 / 阻塞 |
|---|---|---|---|---|
| P1 | 连续循环遍数机制（3/5 遍、8 小节格、「目标 5 遍全绿通关」面板） | S11 §5 | done | LoopConfig.targetLoopCount + completedLoopCount + auto-finish；S12 卡4「目标遍数」chip（不限/3/5）；练习室顶栏副行「X/Y 遍」+ 循环格 badge；面板纯展示不碰过关判定。+11 测试，755/0。 |
|| P2 | 已弹音符琥珀着色（逐音符命中态） | S11 §4.3 | done | Stage A（App 层接线）+ Stage B（cursor-driven referenceNotes 过滤）双落地：PracticeScoreScrollView 内部维护 referenceNotes/playedNoteIDs；cursor 变化时过滤 referenceNotes 计算 playedNoteIDs；ScoreView 传入 selectionForPlayedNotes() + voiceColorsForPlayedNotes()（amber）。真实演奏时 cursor 基于 .beat(measureIndex, tickInMeasure)，近似标记已过音符；精确命中后续接 NoteAligner 实时结果。e59ba5a，2026-10-15 完成。 |
| P3 | 分手能力（双手 / 右手 / 左手） | S11 §6.1 | done | 练习室顶栏新增 hand mode chip group（双手 / 右手 / 左手）；PracticeScoreScrollView 接收 HandMode 并按 voice→hand 映射着色：非激活 hand 整组变灰（gray/30%），激活 hand 内已弹音符琥珀（P2 复用）。HandMode 枚举落地 ScoringModels.swift；设计坞「分手」格可接入。75a1a3b，2026-10-15 完成。 |
| P4 | 纸内谱头 / 页脚（No.45、速度术语、「双手协同」chip、左手提示、Op. 标记、版权/来源） | S11 §4.2/4.4 | done | Layer 1（App 层叠加）已落地：header 显示编号/速度术语/双手 chip/Op. tag/左手提示；footer 显示页码+版权/来源 chip（copyrightNotice）+ 曲目引用。Piece 新增 opusTag/leftHandNote/copyrightNotice；CatalogEntry/ensurePiece 接通；BuiltinCatalog.json 已填入 Op.101/Op.1 + Public Domain。左手提示真实数据留待产品录入。双手协同真实判分等 P3。0ec8749 + 2c83174 + 20d6358 + 9e1eb21 + 0f448a8 + 9f7089c，2026-10-15。 |
| P5 | 预备拍控件格（hourglass，档显 1 小节） | S11b §6.1 | done | count-in 逻辑已有（LoopConfig.countIn + MetronomeService.countInBars），本次补坞内第 2 格「预备拍」控件（ON 显琥珀高亮，OFF 置灰）。0fca3d4，2026-10-12 完成。 |
| P8 | S11b 断点坐标细节（「21▾」下拉、「断点已缓存」字样） | S11b §5 | done | 产品确认：维持现状，只显遮罩文案，不做坐标下拉/缓存字样。2026-10-12 确认。 |
| P12 | S12 错误热点数据源（解锁「错误热点」chip + 小节条热点标记） | S12 §5.2/5.3 | done | 数据源已接：`TakeAnalysis.hotspotMeasures` 单条最新分析不跨 take 聚合；详情页「只练错误热点」chip + C5「针对问题小节发起专项循环」CTA 启用，进房锁定循环区间（同 G3 矫正进房 `CorrectionEngine.initialLoopRange`）。+4 测试，759/0。 |
| P13 | S12 sheet 传入曲目名（卡1 右注「曲目：xx」） | S12 §5 | done | sheet 加 pieceTitle，右注「曲目：xx · 共 N 小节」，抽出可测 rightCaption；空曲名只显小节，占位「练习」映射回空串。+2 测试，744/0。 |
| P14 | S12 全屏 sheet vs 底部抽屉形态裁定 | S12 §1 | done | 产品确认：改为 390×844 整屏 sheet（与真值对齐）。2026-10-12 确认。 |
| P11 | 速度长按连改、速度自适应 toast、时间到自动保存底部条 | S11 §8 | done | 产品确认：维持现状，等真值画出后再做。2026-10-12 确认。 |
| P15 | 练习室 MetronomeService 直接触发 SineBeep（把 Timer 每拍改走 `SineBeepAudioUnit.triggerNote`，与示范 click 统一到同一合成实现） | 2026-10-09 Stage B | done | MetronomeService 走 SineBeepAudioUnit.triggerNote + async preload + sineBuffer fallback；TakeAnalysisService 新增 formatTakeTime；S13bMarkSheet 显式 init 暴露 takeTime；PracticeRoomView/TakeReportView 接线。P15 commit + M4 commit 双绿，766/0。2026-10-15 完成。 |

已完成（从原 backlog 移除）：暂停语义 pause/继续、识别中状态指示、纸张卡视觉（纸色/圆角/边框/阴影）；S11b 红色重连横幅、谱卡遮罩、诊断卡（接 MidiDiagnosticsView）、坞禁用态、断点 m.xx 文案（P6/P7/P9/P10）。

---

## 二、首次链路（S03 MIDI 向导）

| # | 需求 | 来源 | 状态 | 说明 / 阻塞 |
|---|---|---|---|---|
| W2 | 真值文案逐字落地（`连接特伦斯 V70`、`Terence V70`、`蓝牙 MIDI · 信号强`、`未发现其他设备 / 请确认琴已通电`、`找不到设备？查看帮助`） | S03 §4 | blocked | 设备名/信号强度需来自真实 CoreMIDI 源，当前为流程口语化文案；无真机数据时无法逐字落地，不写死 V70。 |
| W3 | 设备行「连接」胶囊按钮 + 4 柱信号强度 + emerald 在线点（#10B981 80%） | S03 §4 | blocked | App 连接由系统蓝牙 MIDI 面板建立，无 App 侧「连接」动作；信号强度无数据源，不画假柱。需真机 CoreMIDI 信号强度数据后实现。 |
|| W5 | 右上 ✕ 关闭按钮 | S03 §2 | done | 产品确认：保留 ✕（样式与返回键同形），允许跳过落 S07b。2026-10-12 确认。 |
| W6 | S05 六维雷达中无真实来源的 3 个轴（节奏 / 速度 / 双手协同）的真实判分 | S05 §3 | blocked | 视觉已对齐（2026-09-23）：`axisScores=[音准,nil,连续性,nil,读谱,nil]`，音准=读谱=视奏命中均值×5（同源恒等），连续性=停顿数换算；数据多边形只连 3 个真实顶点，占位轴仅显标签+「P2」、无顶点无数值。底层节奏/速度判分与双手协同（依赖 P3 hand）仍待 P2 能力，禁止编 5 分制数值。 |
| W8 | S04/S05 评估时长口径最终统一（真值「约 20 分钟」vs 旧流程「3 分钟」） | S04 §9 | done | 产品确认：以「约 20 分钟」为最终口径；导航胶囊与退出弹窗已落地，旧「3 分钟」已停用。2026-10-12 确认。 |

已完成（对齐落地，非 backlog）：向导导航 32×32 圆角 8 芯片 + 步骤条三态（对勾/扩散环/暗点 + 准备·连接·验证标签）、底部全宽琥珀 CTA（16/24 w500、圆角 8、高 52）与 GarageBand 幽灵按钮、验证步三格（音名/力度/时间戳）+ 2 秒监听窗与「再听一次」、源区「重新扫描」刷新钮、返回键全步可退（第 1 步回 S02）、插画卡（蓝牙波纹 3s 呼吸 + 电钢琴线稿：琴体/双状态点/10 白键 5 黑键/琴架）、帮助行改真值单行链接（`help_outline` + 文案 + `chevron_right`），排查提示含 USB-B 转接线说明移入点按后的小 sheet（内容未删）。

---

## 三、曲库（S08）

| # | 需求 | 来源 | 状态 | 说明 / 阻塞 |
|---|---|---|---|---|
| L1 | 按状态筛选曲目（「已拿下 / 练习中 / 未开始」chips 的过滤行为） | S08 | done | CatalogService 新增 catalogStatus(pieceStatus:...) 重载；LibraryView/PieceDetailView 优先读 Piece.status（passed/practicing/notStarted/locked），退回 number/current 推断。绿 pill「已拿下」可达。41e2677，2026-10-15 完成。 |
| L2 | 教材 chip 切换的 120ms 淡入 | S08 | done | chip 取消筛选已实现，补 `withAnimation(.easeIn(0.12))`；搜索/segment 行为不动。744/0。 |
| L3 | 「全部导入」段文件类型图标与导入时间列表 | S08 | done | 产品确认：维持现状，只保留「全部导入」入口。2026-10-12 确认。 |
| L4 | 行 1「拜厄 第44条 / 第45条」命名口径 | S08 | done | 产品确认：以「第45条」为准。2026-10-12 确认。 |
| L5 | 技术目标元数据（音阶跑动/右手转指/均匀力度 chips） | S09 §3.5 | blocked | Piece/CatalogEntry 无该字段，不编造 chips；需曲目技术标签建模。 |
| L6 | OP 编号标签（「OP.101」） | S09 §3.5 | done | Piece/CatalogEntry 已加 opusTag；P4 纸内谱头已渲染 Op. 标记。0ec8749 + 2c83174 + 0f448a8 + 9f7089c，2026-10-15。 |
| L7 | 八格已练小节 / 热点小节进度网格 | S09 §3.6 | done | 由 `PracticeHeatCell.swift` 统一实现（详情页 8 格 + 报告页热点双条）；`PieceDetailView.practiceProgressCard` + `TakeReportView.heatDeltaSection` 接入 `TakeAnalysis.measureHeatJSON` / `alignmentJSON`；热点行取 `latestHotspotMeasures`；+5 测试，764/0 全绿。2026-10-12 完成。 |
| L8 | S09 曲目详情 → Take 报告的跳转 | S09 §4 | done | take 行改 Button + chevron，sheet(item:) 开 TakeReportView，与 Archive/Notes/报告内全 app 统一（非 NavigationLink）；仍单 sheet 路由。744/0。 |

已完成（移除）：header 搜索钮 + 按曲名本地搜索（S08 v2）。
已解决（移除）：MIDI 连接胶囊——曲库/今日页按各屏真值隐藏全局胶囊，连接态在其余页查看。
导入入口布局已按统一规范定案（「全部导入」为唯一入口 + 空态内联导入卡），不再列为待办。

---

## 四、成绩单 / 谱错标记（S13b）

| # | 需求 | 来源 | 状态 | 说明 / 阻塞 |
|---|---|---|---|---|
| M1 | 纸质谱面谱条真实渲染（替换示意/占位） | S13b | blocked | 无来源不画假谱条；接真实谱渲染能力。当前为红虚线圈诚实占位。 |
| M4 | 副标 take 时间数据 | S13b | done | TakeAnalysisService.formatTakeTime + takeTimeFormatter；PracticeRoomView/TakeReportView 均传真实 take.startedAt；S13bMarkSheet 加显式 init 暴露 takeTime；无 endedAt 时诚实返回 HH:mm，有时长追加 (N min)。+0 测试（视图层），766/0 全绿。2026-10-15 完成。 |
| M8 | 提交成功态 / 提交后规则 | S13b | done | 产品确认：维持现状，提交后关闭抽屉。2026-10-12 确认。 |
| M9 | includeWithNeko 纳入导出 DTO | S13b | done | ErrorMarkDTO 加 includeWithNeko，collect/restore 全链路补齐；自定义 init(from:) decodeIfPresent ?? false，旧包向后兼容不升 formatVersion。+3 测试含 round-trip，744/0。 |

已完成（移除）：M2「反馈给 Neko」chip、M3 勾选行真实落库（新增 includeWithNeko 字段）、M5 备注聚焦态、M6 chip 选中圆点、M7 抽屉参数对齐（顶圆角 28、black/60 scrim、#262220、40×4 #463F3A 抓手）。

---

## 五、今日页（S07b / S07c）

| # | 需求 | 来源 | 状态 | 说明 / 阻塞 |
|---|---|---|---|---|
| T1 | 三统计卡真实数据（本周 streak / 本周时长 / 距 599） | S07b §3.3 | done | TodayView.statsRow 接入真实数据：streak 来自 TodayPlanService.weekStreak(takes:today:)（周一起始，>=10min 算达标）；时长 = minutesPerDay 求和；距 599 = CourseEngine.projected599WeeksLabel(pathState:)（约 N 周后 / 无数据时诚实显示「—」）。b239dfb，2026-10-16 完成。 |
| T2 | 真实热身剩余分钟（恢复正文「还差 N 分钟」、补热身钮分钟后缀） | S07c §3.3 | done | TodayPlanService.warmupElapsedMin(takes:today:) 聚合当日 warmup take 已练分钟；GateService.checkMainAccess 新增 warmupElapsedMin 参数，remaining = max(0, 10 - elapsed)；S07cOverrideModal 正文动态拼接「还差 N 分钟」，次按钮追加「（N 分钟）」。9221430，2026-10-16 完成。 |
| T3 | 未连 MIDI 时主按钮仍可点（自评不需琴，视奏步再引导连接） | S07b | done | 产品确认：维持现状，主钮始终可点，不硬拦。2026-10-12 确认。 |
| T4 | 逛曲库为只读浏览，未解锁教材详情 CTA 引导先定级 | S07b | done | 产品确认：维持现状，不做只读限制。2026-10-12 确认。 |
| T5 | 强开原因「未选即 disabled」规则 | S07c §3.4 | done | 产品确认：维持现状，默认预选第一项，确认钮默认可点。2026-10-12 确认。 |

已完成（移除）：S07b 问候/日期 header、绿色 MIDI 胶囊（真实状态）、160×112 线稿真实绘制、顺序/圆角/mono「—」对齐、续定级剩余分钟；S07c 贴底硬拦截 sheet、红锁、默认预选、radio 选中态、留痕发丝边框（真实周计数 + ≥3 次变体）、按钮顺序、保留「其他」输入与必填校验。

---

## 六、跨页能力缺口（优先排期候选）

下列是多个面板共同依赖、一旦补齐即可解锁多条 backlog 的底层能力：

1. 过关 / 判分与 pass 计数 —— 解锁 P1、L1（循环遍数面板、「已拿下」状态与筛选）。
2. 逐音符命中着色（App 层） —— 解锁 P2。
3. 分手（hand 模式） —— 解锁 P3。
4. 纸质谱条真实渲染 —— 解锁 M1。

---

## 七、相机与视频（S15 / S16 / S18b / S17）

2026-10-22 用户拍板开启「相机大批次」，先 V1+V2 闭环（ADR-0010 `docs/decisions/0010-camera-video-loop.md`），V3 发送与 V7 Zf 导入留到下一批。本批不含 MediaPipe 手型（V8）。

| # | 需求 | 来源 | 状态 | 说明 / 阻塞 |
|---|---|---|---|---|
| V1 | S15 机位校准向导（侧拍/整机位、向导步骤、校准确认） | S15 | in-progress | ADR-0010：本批做真实相机预览 + 静态取景框 + 提示/免责卡 + 4 步流程（摆放/取景/试录/完成）；**不画 MediaPipe 骨架与检测 chips**（见 V8），无数据源不造假。 |
| V2 | S16 视频回看（take 视频列表/回放/选段预览） | S16 | in-progress | ADR-0010：AVPlayer + scrubber + 时码 + 「重新校准」；卡②手型观察与骨架不渲染（V8）；「问 Neko」按钮本批隐藏（V3 未做，不留死按钮）。 |
| V3 | S18b 视频裁切并发送给 Neko（近全高 sheet：胶片轨双手柄/区间 badge/预设 chips/提问上下文/服务商披露/删除开关/CTA） | S18b | blocked | 无视频源、无裁切（AVAsset trim）、无视频上传链路，sheet 整体不能建。 |
| V4 | S18b 服务商命中名实时显示（真值写死「火山方舟（字节跳动）」） | S18b §3.6 | done | 产品确认：维持现状，保持写死/隐藏，等发送链路再做。2026-10-12 确认。 |
| V5 | S18b 上传中/可取消/失败重试/完成后「云端片段已删除」视觉 | S18b §4 | done | 产品确认：维持现状，先不画，等上传能力。2026-10-12 确认。 |
| V6 | S18b 最小裁切时长 2s 报错、开关 OFF「云端保留」态、下滑关闭/播放头可拖 | S18b §4/§5 | done | 产品确认：维持现状，先不画，等上传能力。2026-10-12 确认。 |
| V7 | S17 月度录像导入（从系统相册挑尼康 Zf 视频复制本机永久归档，不上传/不判分/不自动分析手型；sticky 底部操作区） | S17 | blocked | 下一批（V1+V2 之后）。数据归属已定：复用 Take（`taskType="zfImport"`、`hasMidi=false`、挂视频附件、不进判分但进档案时间线与月报）。实现需 PhotoKit/PhotosPicker + NSPhotoLibrary 相关键（当前均无）。 |
| V8 | MediaPipe 21 点骨架与手型检测（S15 校准页实时骨架、S16 回看页卡②「这一段的观察」3 条带置信度） | S15/S16 · PRD M6/P4 | blocked | 2026-10-22 用户拍板本批不含：SDK 接入 + 端上推理 + 检测项标定成本高，且与采集/回看不是同一批可交付物。骨架层、检测 chips、观察卡在能力落地前不渲染（无数据源禁止造假）。 |
| V9 | 视频保留规则持久化（设置页「每曲最近 8 条 / 不自动清理」） | S23 | in-progress | 真缺口实证：`RetentionRuleSheet` 只用 `@State`，选完退页即丢。随 ADR-0010 本批修：`AppSettings.videoRetentionMode`（lru8/never）+ 保存视频后按 pieceId 分组执行 `VideoRetentionService` 淘汰。 |

本批执行顺序：V1 采集+V2 回看（进行中）→ V3 发送闸口 → V7 Zf 导入；V8 手型单独成批（需先评估 MediaPipe SDK 体积与真机性能）。

---

## 八、双 Take 对比（S21）

真值 `/tmp/stitch-truth/revised/S21.md`：同曲目同小节段两次 take 的进步对比——样本选择、六维叠加雷达、速度双线、错音热力双条、关键 delta；只展示不产生过关判定，CTA 针对问题小节发起专项循环。降级版已落地（072cc7b + 436b79f，2026-10-12）：入口在 TakeReportView「对比」。

| # | 需求 | 来源 | 状态 | 说明 / 阻塞 |
|---|---|---|---|---|
| C1 | 双 take 选择器（同曲目/同小节段，配对） | S21 | done | 降级版配对口径=同一 take 的 pieceId + measureFrom/To 相同（canCompare 纯判定 + 候选列表同口径过滤）；报告页入口预填 takeA。2026-10-12 落地。 |
| C2 | 六维叠加雷达（两次同图叠加） | S21 | done | 沿用 S13 六维真实维度（音高/节奏/连续性/速度稳定性/读谱/双手协同，经 TakeReportPresentation），无可评维度不画数值。2026-10-12 落地。 |
| C3 | 速度双线（两次 avgBPM/逐句速度） | S21 | blocked | 降级版已接两次 avgBPM 单点双值对比；逐句速度曲线需逐句对齐数据（暂无）；CTA 卡 TODO 预填热点留待锁定能力确认。 |
| C4 | 错音热力双条 + 关键 delta 列表 | S21 | done | measureHeatJSON 双条 + 错音率/平均速度/弱总分 delta 列表 + 综合±分；无数据显「—/数据不足」不造假。2026-10-12 落地。 |
| C5 | 「针对问题小节发起专项循环」CTA | S21 | done | 与 P12 同一 card/同一数据源；详情页 CTA + chip 均已启用，进房锁定循环区间。49fa1d4。 |

完整版（逐句速度曲线、CTA 预填热点）待数据/能力确认后升级；不再要求先 Grill（降级版口径已由产品确认）。

---

## 九、竞品差距分析新增功能（2026-10-09）

来源：`docs/competitive-gap.md`（西式 6 家 + 国内 12 家调研 + 本仓 grep 核查）。编号 G 系列。

| # | 需求 | 对应缺口 | 优先级 | 状态 | 说明 |
|---|---|---|---|---|---|
| G1 | 可练谱获取指引页（在哪找现成 MusicXML / Mac 端 MuseScore 转换 / 导回 app） | D2 | P0 | done | 指引已存在于 PDF 资料库第二 tab，本次从 3 条提纲升级为三途径实战 SOP + 自查清单。2026-10-09 完成。 |
| G2 | 接通一键「只练错误热点」：最近一次 `TakeAnalysis.hotspotMeasures` 喂给 LoopService | D1 / P12 | P0 | done | 新增 LoopService.hotspotRange/latestHotspotMeasures，S12 chip 按真实数据启用。616/0 全绿。2026-10-09 完成。 |
| G3 | 错误类型 → 矫正练习处方引擎（映射教材条目/针对性小节，连续不过自动插） | D3 | P1 | done | ADR-0005 已定（用户 8 项口径全拍板）。全量 8 类错误归并（错音/漏音/多弹/节奏/速度/力度/连续性/双手）+手工练习法表（慢练比/分手/节拍器/目标，针对 hotspot 不跨曲）；连续 2 次可评不过触发，低置信/不可评不计；矫正卡插主菜之前、非门禁不锁过关；进房锁 hotspot + 最保守速度，练完一遍即完成；通过即 resolve 清零。Stage A c8734bd + Stage B 界面，663/0 全绿。2026
10: 10 完成。 |
| G4 | 日常视奏训练（复用 SightReadSession，今日可选项 + 命中率趋势，对标 SASR） | D4 | P1 | done | ADR-0004 已定。素材=拜厄/哈农超前条（number>current 的 locked 谱，窗口 current+3~+8）；口径=命中率+用时+停顿数。Stage A 核心层+Stage B 界面，632/0 全绿。2026-10-09 完成。 |
| G5 | 奖励曲难点段落自动混入热身 | D5 | P1 | done | 兑现 PRD M3 Q4=A。ADR-0006 八项口径：相对当前课程进度三档（≤B×1.15 能弹 / ≤B×1.8 偏难 / 否则远超，边界含 1e-9 浮点容差）；热身卡后独立铺路卡复用矫正卡外壳；每天最多 1 首 1 段（2–4 小节）；PDF/不可解析诚实标「暂无法分析」；难点=小节静态难度（黑键比+密度+音程跳+和弦厚度）；练完一遍即完成不看达标；仅偏难铺路、远超只标档；完成不催/升能弹即关卡。Stage A 04528ea（687/0）+ Stage B 691/0 全绿。2026-10-10 完成。 |
| G6 | 轻量练耳/视唱（听音辨音程、节奏型模仿） | — | P2 | done | ADR-0008（2f48c68）。首批只做听音辨音程（节奏模仿/视唱留二期；视唱需麦克风为红线不做）：一个八度内 12 个唯一中文标签（半音数 6 统一「三全音」避免两个正确答案）、只弹上行旋律音程、4 选 1、随拜厄进度三档自动解锁（≤30 {2,3,4,7,12}、31–60 +{1,5,9,10}、>60 全开）、每轮 10 题记录命中率与最近 20 轮趋势、选错即时高亮+可再听、无需连琴（app 自发声）。Stage A 6b640ed（核心层，718/0）、Stage B（隔离轻量 IntervalTonePlayer+练耳页+「我的」入口，723/0）。2026-10-10 完成。 |
| G7 | 简谱层（五线谱转简谱/简谱视图） | done | P2 | done | 反转 PRD「不做简谱」，ADR-0009 `3163f3d`。形态=五线谱上叠加固定调数字（逐音符**上方**）：数字 1-7 + ♯♭𝄪𝄫♮（黑键必带）+ 上下八度点；每个符头都标（和弦垂直错开）。仅覆盖已解析 MusicXML/canFollow，PDF 不转（OMR 红线）。仅练习室「简谱」胶囊开关、即时切换不持久化默认关（详情页不渲染谱、不设开关）。几何自遍历 document 的 system/measure/.chord（note.origin+mirrorDx）；注 `elementHitRect` 对 note 无效（elementID=nil），grace 跳过。两阶段：Stage A `a981822`（纯标签，732/0）、Stage B 见提交（739/0，+7）。 |
| G8 | 连续达标周数等轻激励补全 | — | P2 | done | ADR-0007（b594543）。达标周=周一→周日有效练习日（有MIDI且当日累计≥10分钟）数≥weeklyGoal；只数已结束完整周（本周达标也等周日过后才计入，数字不回退）；今日页 StreakRow 标题右侧填真实「连续达标 N 周」；中断归零、档案页另存「历史最长连续达标 N 周」。纯函数 TodayPlanService.weeklyGoalStreak 从全部 Take 现算，零新模型/持久化/状态写，+9 测试，700/0 全绿。2026-10-10 完成。 |

---

## 变更记录
- 2026-10-19（巡检沉淀，无代码改动）：Hermes 巡检确认工作区干净、HEAD `817a73a`、测试函数 766 与 766/0 基线一致；剩余 10 条 blocked（W2/W3/W6/L5/M1/C3/V1/V2/V3/V7）、0 条 needs-decision。真机项仍挂起（开发证书 2026-09-27 过期、无 iPhone 连接）。进度日志同步到 vault `Projects/piano-sempai/progress.md`（此前停在 10-12）。
- 2026-10-12（对账同步，无新代码）：P5 状态改 done（坞内预备拍控件格 0fca3d4 已提交，表漏更新）；第八节 S21 整节按降级版落地状态对账——C1/C2/C4 改 done、C3 收窄为「仅逐句曲线 blocked」（双 take 选择器/同段配对/六维真实雷达/速度单点/热力双条/delta 已落地），并移除「须先 Grill」限制（降级口径已产品确认）。
- 2026-09-23：建表。清洗原 25 条审计 backlog：移除已完成 5 项（曲库搜索、暂停、识别中、纸张卡、MIDI 胶囊处理），新增 P3 分手能力，重组为练习室/曲库/成绩单/跨页能力四节。
- 2026-09-23：P0 测试链路 7 屏（S07/S07b/S07c/S08/S11/S11b/S13b）全部对齐。清洗回写：移除 S11b 横幅/遮罩/诊断/禁用、S07b/S07c 视觉等已完成项；新增今日页小节（T1–T5）与 M9（includeWithNeko 导出）。
- 2026-09-23：S12 段落循环三卡对齐（共享抽屉连带核对），544 全绿；新增 P12–P14（错误热点数据源/传入曲名/形态裁定）。
- 2026-09-23：S03 MIDI 向导对齐（导航/步骤条/底部 CTA/验证三格 + 2 秒监听窗，判定抽成 MIDIVerifyGate 并补 4 条回归测试）；新增首次链路小节（W1–W5：插画卡、真值文案、设备行连接钮与信号柱、单行帮助链接、✕ 去留）。
- 2026-09-23：S03 补齐 W1 插画卡与 W4 帮助行（单行链接 + 点按小 sheet 承接真实排查提示，USB-B 内容保留）；sheet 改单一 `ActiveSheet` 枚举路由（一个视图只挂一个 .sheet）。W1/W4 移入已完成，余 W2/W3/W5。
- 2026-09-23：S19 练琴笔记三态视觉对齐（chips 改 12pt 圆角/选中琥珀，卡 #221F1D/8，日期在左 R2 徽章在右，底部按真实课后/周报/未处理分态，「标记于练琴中」无来源不画，FAB 56/12），548 全绿。
- 2026-09-23：补登相机与视频整块（新增第七节 V1–V6）：S15 机位校准 / S16 视频回看 / S18b 裁切发送均无实现，grep 实证无视频采集/裁切/上传链路，整块 blocked 待拍板开「相机大批次」。
- 2026-09-23：第二批 10 屏对齐，主会话逐项独立构建。S05（诚实 3 轴雷达+占位轴标 P2，W6 更新）、S13（六维诚实雷达+真实逐音节奏折线+BPM 环，两文件 +1417/-350）、S14（流动卷帘，无力度不画）、S18（对话视觉，修 2 处真编译错；视频附件归 S18b）、S20（周翻页+三统计+weakTotal 趋势，无分析显占位环）、S22（月报补真实节奏稳定度趋势卡，weeklyRhythmScores [Int?]，min/max 归一化、nil 不补点）、S24（诊断四卡：ONLINE 仅真机、延迟显「—」、音高/力度/踏板真实 fraction）、S08b（导入失败 r22 dialog：真实码徽章/左红边详情/文件大小诚实省略/三按钮堆叠）、S23（我的：实心琥珀头像+5 组 r16+12 sheet 不回归，周数/校准日/首选模型/通知/存储全真值）、S10（PDFKit 真页数/双段/真实标题搜索/明示 PDF 不进判分）、S26（真实文件体积/视频行置灰/仅PDF不支持即禁用 CTA）。补登 V7（S17 相册视频导入 blocked）与第八节 S21（双 take 对比 C1–C5，全新功能须先 Grill/PRD）。
- 2026-09-23：修复备份丢数据真 bug——take MIDI 落 midi/yyyy/MM/ 嵌套目录，ExportService 旧非递归 contentsOfDirectory 只读顶层、restore 又限 parts.count==2，导致真机 take MIDI 从不进备份、恢复丢练习数据。改递归枚举（enumerator 保留相对路径）+ restore 支持任意深度（带路径穿越防护），新增 ExportServiceNestedMidiTests round-trip 回归 2 例；xcodegen 注册后 550/550 全绿（548→550）。
- 备注：W1/W4 已在 2026-09-23 条目移入完成（第二节仅余 W2/W3/W5），无残留待清洗项。
- 2026-09-23 夜：真机验收两处层级 bug。①档案页双「问 Neko」FAB——AppFrameView 全局 FAB 对 5 tab 常驻、ArchiveView 又自带 S20 真值琥珀 FAB；改为全局 FAB 仅今日/练习渲染（曲库/我的真值无 FAB 一并修正），档案保留琥珀款。②S07c 热身强开弹层盖不住 tab bar/FAB——原用 TodayView 内 .overlay（层级低于 AppFrameView 的 safeAreaInset 底栏）；新增 WarmupOverridePresenter（environmentObject），modal 提升到 AppFrameView safeAreaInset 之后的顶层 .overlay 渲染，真实今日页压暗透在 scrim 后，硬拦截点外部不关。两修均 550/550 全绿。
- 2026-10-09 夜：P0 两项完成并独立验证（616/0，TEST EXECUTE SUCCEEDED）。G1 把 PDF 资料库第二 tab 的可练谱指引升级为三途径实战 SOP（找现成工程文件 / Mac MuseScore OMR 转谱 / .mid 兜底 + 自查清单）；G2 接通一键只练错误热点（LoopService.hotspotRange 0-based→1-based 区间、单热点扩 1、越界钳制；latestHotspotMeasures 按曲目 join Take/TakeAnalysis 取最新非空；S12 chip 按真实数据启用），新增 9 个单测（607→616）。期间两次构建失败均为环境问题（Xcode 更新后本地包模块缓存不兼容→清 DerivedData；模拟器 boot XPC 断连→shutdown/boot 重置），非代码缺陷。
- 2026-10-09 夜：G4 日常视奏训练完成（P1，ADR-0004）。分两 Stage：Stage A 核心层（SightReadDrillRecord 模型 + SightReadPicker 教材超前条选片/去重/两轨到底兜底 + SightReadDrillStore.save 诚实口径 + SightReadTrend 最近20条升序趋势；expectedPitches/loadExpectedPitches 泛化到全 staff 并标 nonisolated）；Stage B 界面（今日可选卡 + 独立 fullScreenCover 路由，裁剪 4 小节并在首小节回填生效调号/拍号/谱号，MIDIHub 采集落库，无输入诚实提示，命中率+用时+停顿轻量结果与升序柱状趋势，Neko 文案）。新增 16 个单测（616→632：Stage A +10、Stage B +6）。期间三轮构建失败均为真实编译错误并已修：测试缺 import SheetMusicLoader / 纯静态函数 MainActor 隔离（补 import+nonisolated）；TodayView 缺 SheetMusicUI/Layout import + sightReadCard 多语句缺显式 return；测试对元组 (Int,Int) 用 XCTAssertEqual（拆分量断言）。裁剪谱可见模拟器肉眼核对受「全新模拟器无定级→今日页空态不渲染视奏卡」限制，核心回填正确性已由 6 个单测锁定，ScoreView 组合风险低，端到端肉眼项留给用户回家定级后核对。
