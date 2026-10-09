# Backlog — 推迟需求登记本

本文件是 PianoSempai 唯一的「往后挪 / 待补」需求登记本。新增推迟项一律追加到这里，不再散落在临时审计文件里。

- 建表：2026-09-23。来源：S07/S08/S11/S13b 对齐 Stitch 真值（code.html）后的偏差审计。
- 每条标注：来源屏 / 推迟原因（能力缺口 or 待产品确认）。
- 无真实数据来源的条目：在能力补齐前不渲染，禁止写死或造假。
- 状态约定：`open` 待办 ｜ `blocked` 依赖未做的能力 ｜ `needs-decision` 待产品确认。

---

## 一、练习室（S11 / S11b）

| # | 需求 | 来源 | 状态 | 说明 / 阻塞 |
|---|---|---|---|---|
| P1 | 连续循环遍数机制（3/5 遍、8 小节格、「目标 5 遍全绿通关」面板） | S11 §5 | blocked | 无 pass 计数；依赖尚未做的过关/判分能力。面板在能力就绪前不渲染。 |
| P2 | 已弹音符琥珀着色（逐音符命中态） | S11 §4.3 | blocked | 记谱引擎层不支持逐音符着色，且不能改 swift-sheet-music 包；需 App 层方案。 |
| P3 | 分手能力（双手 / 右手 / 左手） | S11 §6.1 | blocked | App 无 hand 模式；设计坞里的「分手」格因此暂未放置。 |
| P4 | 纸内谱头 / 页脚（No.45、速度术语、「双手协同」chip、左手提示、Op. 标记） | S11 §4.2/4.4 | open | 现由真实记谱引擎渲染，不画假谱头；待引擎元信息或 App 层叠加方案。 |
| P5 | 预备拍控件格（hourglass，档显 1 小节） | S11b §6.1 | open | count-in 逻辑已存在，但坞里的「预备拍」控件未建（当前坞为贴 S11 的 5 格，未含预备拍）。 |
| P8 | S11b 断点坐标细节（「21▾」下拉、「断点已缓存」字样） | S11b §5 | needs-decision | 断点 measureIndex 已用于谱卡遮罩文案；真值的坐标下拉/缓存字样无对应交互，待产品确认。 |
| P12 | S12 错误热点数据源（解锁「错误热点」chip + 小节条热点标记） | S12 §5.2/5.3 | blocked | 现无逐小节常错统计，chip 禁用、小节条无热点点；需真实 per-measure 错误聚合。 |
| P13 | S12 sheet 传入曲目名（卡1 右注「曲目：xx」） | S12 §5 | open | 现仅有 session/totalMeasures，右注只能显示「共 N 小节」；需调用点传真实曲名。 |
| P14 | S12 全屏 sheet vs 底部抽屉形态裁定 | S12 §1 | needs-decision | 真值为 390×844 整屏、现沿用共享底部抽屉；内部规范已对齐，形态待确认。 |
| P11 | 速度长按连改、速度自适应 toast、时间到自动保存底部条 | S11 §8 | needs-decision | 真值 DOM 未画，旧稿约定，待产品确认后再做。 |
| P15 | 练习室 MetronomeService 直接触发 SineBeep（把 Timer 每拍改走 `SineBeepAudioUnit.triggerNote`，与示范 click 统一到同一合成实现） | 2026-10-09 Stage B | blocked | 当前节拍器仍用原有 `MetronomeService.sineBuffer`（功能正常）；SineBeep 的 sequencer 路径已用于示范 click，直接触发路径 `triggerNote` 暂无调用方。阻塞点：①SineBeep 只能 `await Factory.make()` 异步创建，而 MetronomeService 是同步服务、被 3 处同步 `start()`，需改 async 或就绪前 sineBuffer 兜底；②音色/无声只能真机听，开发证书 9/27 过期现无法真机验证。2026-10-09 决策：挂起，等回家重签证书后与真机 V70 端到端一起做。 |

已完成（从原 backlog 移除）：暂停语义 pause/继续、识别中状态指示、纸张卡视觉（纸色/圆角/边框/阴影）；S11b 红色重连横幅、谱卡遮罩、诊断卡（接 MidiDiagnosticsView）、坞禁用态、断点 m.xx 文案（P6/P7/P9/P10）。

---

## 二、首次链路（S03 MIDI 向导）

| # | 需求 | 来源 | 状态 | 说明 / 阻塞 |
|---|---|---|---|---|
| W2 | 真值文案逐字落地（`连接特伦斯 V70`、`Terence V70`、`蓝牙 MIDI · 信号强`、`未发现其他设备 / 请确认琴已通电`、`找不到设备？查看帮助`） | S03 §4 | open | 现行文案为流程口语化改写；设备名/信号强度来自真实 CoreMIDI 源，不写死 V70。 |
| W3 | 设备行「连接」胶囊按钮 + 4 柱信号强度 + emerald 在线点（#10B981 80%） | S03 §4 | open | 本 App 连接由系统蓝牙 MIDI 面板建立，行内没有 App 侧「连接」动作可挂；信号强度无数据源，不画假柱。 |
| W5 | 右上 ✕ 关闭按钮 | S03 §2 | needs-decision | 真值 HTML 没有 ✕（spec 标「待产品确认」），但 onboarding.md 契约要求「可 ✕ 跳过落 S07b」；现保留 ✕、样式与返回键同形。 |
| W6 | S05 六维雷达中无真实来源的 3 个轴（节奏 / 速度 / 双手协同）的真实判分 | S05 §3 | blocked | 视觉已对齐（2026-09-23）：`axisScores=[音准,nil,连续性,nil,读谱,nil]`，音准=读谱=视奏命中均值×5（同源恒等），连续性=停顿数换算；数据多边形只连 3 个真实顶点，占位轴仅显标签+「P2」、无顶点无数值。底层节奏/速度判分与双手协同（依赖 P3 hand）仍待 P2 能力，禁止编 5 分制数值。 |
| W8 | S04/S05 评估时长口径最终统一（真值「约 20 分钟」vs 旧流程「3 分钟」） | S04 §9 | needs-decision | 代码已落地：导航胶囊显「约 20 分钟」，退出弹窗用分钟中立「进度会保留，随时可以继续评估」；旧「3 分钟」口径已停用，仅留最终口径确认。 |

已完成（对齐落地，非 backlog）：向导导航 32×32 圆角 8 芯片 + 步骤条三态（对勾/扩散环/暗点 + 准备·连接·验证标签）、底部全宽琥珀 CTA（16/24 w500、圆角 8、高 52）与 GarageBand 幽灵按钮、验证步三格（音名/力度/时间戳）+ 2 秒监听窗与「再听一次」、源区「重新扫描」刷新钮、返回键全步可退（第 1 步回 S02）、插画卡（蓝牙波纹 3s 呼吸 + 电钢琴线稿：琴体/双状态点/10 白键 5 黑键/琴架）、帮助行改真值单行链接（`help_outline` + 文案 + `chevron_right`），排查提示含 USB-B 转接线说明移入点按后的小 sheet（内容未删）。

---

## 三、曲库（S08）

| # | 需求 | 来源 | 状态 | 说明 / 阻塞 |
|---|---|---|---|---|
| L1 | 按状态筛选曲目（「已拿下 / 练习中 / 未开始」chips 的过滤行为） | S08 | blocked | CourseEngine.catalogStatus 只产出 练习中/未开始/未解锁，「已拿下」不可达；依赖过关判定。绿 pill 代码保留但不可达。 |
| L2 | 教材 chip 切换的 120ms 淡入 | S08 | open | chip 取消筛选已实现，仅过渡动画未做。 |
| L3 | 「全部导入」段文件类型图标与导入时间列表 | S08 | needs-decision | 真值 html 未呈现，待产品确认布局。 |
| L4 | 行 1「拜厄 第44条 / 第45条」命名口径 | S08 | needs-decision | 以 html「第45条」为准，待产品确认。 |
| L5 | 技术目标元数据（音阶跑动/右手转指/均匀力度 chips） | S09 §3.5 | blocked | Piece/CatalogEntry 无该字段，不编造 chips；需曲目技术标签建模。 |
| L6 | OP 编号标签（「OP.101」） | S09 §3.5 | blocked | 模型无 opus/opusTag 字段；需曲目元数据。 |
| L7 | 八格已练小节 / 热点小节进度网格 | S09 §3.6 | blocked | 无逐小节「已练/在练」聚合（measureHeat 仅按 take 存，未按曲目汇总成格）；需 per-piece 小节进度汇总。 |
| L8 | S09 曲目详情 → Take 报告的跳转 | S09 §4 | open | Take 行现仅展示；报告目的页存在但未在本屏接线（沿用单 ActiveSheet 路由约定，未加第二 sheet）。 |

已完成（移除）：header 搜索钮 + 按曲名本地搜索（S08 v2）。
已解决（移除）：MIDI 连接胶囊——曲库/今日页按各屏真值隐藏全局胶囊，连接态在其余页查看。
导入入口布局已按统一规范定案（「全部导入」为唯一入口 + 空态内联导入卡），不再列为待办。

---

## 四、成绩单 / 谱错标记（S13b）

| # | 需求 | 来源 | 状态 | 说明 / 阻塞 |
|---|---|---|---|---|
| M1 | 纸质谱面谱条真实渲染（替换示意/占位） | S13b | blocked | 无来源不画假谱条；接真实谱渲染能力。当前为红虚线圈诚实占位。 |
| M4 | 副标 take 时间数据 | S13b | blocked | S13bMarkSheet 已支持可选 takeTime，但现有调用点（练习室/报告页）都未传；接真实 take 时间后显示，禁止写死。 |
| M8 | 提交成功态 / 提交后规则 | S13b | needs-decision | 提交后去向待产品确认；当前提交后关闭抽屉。 |
| M9 | includeWithNeko 纳入导出 DTO | S13b | open | 勾选字段已落库（ScoreErrorMark.includeWithNeko），ExportService DTO 未含；要随导出包再补。 |

已完成（移除）：M2「反馈给 Neko」chip、M3 勾选行真实落库（新增 includeWithNeko 字段）、M5 备注聚焦态、M6 chip 选中圆点、M7 抽屉参数对齐（顶圆角 28、black/60 scrim、#262220、40×4 #463F3A 抓手）。

---

## 五、今日页（S07b / S07c）

| # | 需求 | 来源 | 状态 | 说明 / 阻塞 |
|---|---|---|---|---|
| T1 | 三统计卡真实数据（本周 streak / 本周时长 / 距 599） | S07b §3.3 | blocked | 定级前无来源，现值恒「—」；需接真实周聚合（streak/时长）与过关进度（距 599）。 |
| T2 | 真实热身剩余分钟（恢复正文「还差 N 分钟」、补热身钮分钟后缀） | S07c §3.3 | blocked | 无热身进度数据源，当前用不写死分钟的诚实文案 + TODO；需记录热身已练时长。 |
| T3 | 未连 MIDI 时主按钮仍可点（自评不需琴，视奏步再引导连接） | S07b | needs-decision | 旧稿约定、真值 html 未表态；当前主钮不依赖连接。待产品确认。 |
| T4 | 逛曲库为只读浏览，未解锁教材详情 CTA 引导先定级 | S07b | needs-decision | 旧稿约定、真值未画。待产品确认。 |
| T5 | 强开原因「未选即 disabled」规则 | S07c §3.4 | needs-decision | 真值为默认预选第一项（已按真值实现、确认钮默认可点）；旧「未选 disabled」规则被真值覆盖，留此备查。 |

已完成（移除）：S07b 问候/日期 header、绿色 MIDI 胶囊（真实状态）、160×112 线稿真实绘制、顺序/圆角/mono「—」对齐、续定级剩余分钟；S07c 贴底硬拦截 sheet、红锁、默认预选、radio 选中态、留痕发丝边框（真实周计数 + ≥3 次变体）、按钮顺序、保留「其他」输入与必填校验。

---

## 六、跨页能力缺口（优先排期候选）

下列是多个面板共同依赖、一旦补齐即可解锁多条 backlog 的底层能力：

1. 过关 / 判分与 pass 计数 —— 解锁 P1、L1（循环遍数面板、「已拿下」状态与筛选）。
2. 逐音符命中着色（App 层） —— 解锁 P2。
3. 分手（hand 模式） —— 解锁 P3。
4. 纸质谱条真实渲染 —— 解锁 M1。

---

## 七、相机与视频（S15 / S16 / S18b）· 整块 blocked

真机/模拟器均无相机采集、视频回看、视频发送实现（2026-09-23 grep 实证：`Features/AI/ChatView.swift`、`ChatStore.swift` 内无 videoUrl/AVAsset/trim/附件上传链路）。真值要求的视觉在此能力落地前一律不画，禁止造假波形/假进度/假服务商命中。

| # | 需求 | 来源 | 状态 | 说明 / 阻塞 |
|---|---|---|---|---|
| V1 | S15 机位校准向导（侧拍/整机位、向导步骤、校准确认） | S15 | blocked | 相机采集能力未实现；无采集源，校准流程无从挂起。 |
| V2 | S16 视频回看（take 视频列表/回放/选段预览） | S16 | blocked | 无视频文件来源（依赖 V1 采集落盘）。 |
| V3 | S18b 视频裁切并发送给 Neko（近全高 sheet：胶片轨双手柄/区间 badge/预设 chips/提问上下文/服务商披露/删除开关/CTA） | S18b | blocked | 无视频源、无裁切（AVAsset trim）、无视频上传链路，sheet 整体不能建。 |
| V4 | S18b 服务商命中名实时显示（真值写死「火山方舟（字节跳动）」） | S18b §3.6 | needs-decision | 接入时必须改为 `ProviderChainRuntime` 真实命中服务商，不写死；现连发送链路都没有。 |
| V5 | S18b 上传中/可取消/失败重试/完成后「云端片段已删除」视觉 | S18b §4 | needs-decision | 真值 HTML 未呈现这些态，仅有默认展开态；待补视觉稿 + 上传能力。 |
| V6 | S18b 最小裁切时长 2s 报错、开关 OFF「云端保留」态、下滑关闭/播放头可拖 | S18b §4/§5 | needs-decision | 真值 HTML 均未画，待产品确认后再做。 |
| V7 | S17 月度录像导入（从系统相册挑尼康 Zf 视频复制本机永久归档，不上传/不判分/不自动分析手型；sticky 底部操作区） | S17 | blocked | grep 实证无 PhotosUI/PHAsset/PhotoKit 代码；与采集/回看同属视频批次，能力未建。 |

整块待用户拍板开启「相机大批次」：建议顺序 V1 采集 → V2 回看 → V3 发送闸口。

---

## 八、双 Take 对比（S21）· 全新功能（须先 Grill/PRD）

grep 实证仓库无任何 take 对比代码（无 CompareTake/TakeComparison）。真值 `/tmp/stitch-truth/revised/S21.md`：同曲目同小节段两次 take 的进步对比——样本选择、六维叠加雷达、速度双线、错音热力双条、关键 delta；只展示不产生过关判定，CTA 针对问题小节发起专项循环。

| # | 需求 | 来源 | 状态 | 说明 / 阻塞 |
|---|---|---|---|---|
| C1 | 双 take 选择器（同曲目/同小节段，配对） | S21 | open | 需先定配对口径（measureFrom/To 相同？标题相同？）；属全新交互。 |
| C2 | 六维叠加雷达（两次同图叠加） | S21 | blocked | 沿用 S13/S05 诚实轴映射；缺轴（节奏/速度判分、双手）依旧只画真实轴，缺口见 W6 与相机批次。 |
| C3 | 速度双线（两次 avgBPM/逐句速度） | S21 | open | 仅有 TakeAnalysis.avgBPM 单点；逐句速度曲线需对齐数据，不足则降级单线/占位。 |
| C4 | 错音热力双条 + 关键 delta 列表 | S21 | blocked | 依赖 per-measure 错误聚合（同 P12）。 |
| C5 | 「针对问题小节发起专项循环」CTA | S21 | blocked | 循环遍数/过关机制未做（P1）。 |

按开发铁律：绿地功能先 Grill/PRD 多轮 → Stitch → design-to-spec → CC 编码，不在本批直接写。

---

## 九、竞品差距分析新增功能（2026-10-09）

来源：`docs/competitive-gap.md`（西式 6 家 + 国内 12 家调研 + 本仓 grep 核查）。编号 G 系列。

| # | 需求 | 对应缺口 | 优先级 | 状态 | 说明 |
|---|---|---|---|---|---|
| G1 | 可练谱获取指引页（在哪找现成 MusicXML / Mac 端 MuseScore 转换 / 导回 app） | D2 | P0 | done | 指引已存在于 PDF 资料库第二 tab，本次从 3 条提纲升级为三途径实战 SOP + 自查清单。2026-10-09 完成。 |
| G2 | 接通一键「只练错误热点」：最近一次 `TakeAnalysis.hotspotMeasures` 喂给 LoopService | D1 / P12 | P0 | done | 新增 LoopService.hotspotRange/latestHotspotMeasures，S12 chip 按真实数据启用。616/0 全绿。2026-10-09 完成。 |
| G3 | 错误类型 → 矫正练习处方引擎（映射教材条目/针对性小节，连续不过自动插） | D3 | P1 | open | 需先 Grill 错误分类口径与映射表。 |
| G4 | 日常视奏训练（复用 SightReadSession，今日可选项 + 命中率趋势，对标 SASR） | D4 | P1 | done | ADR-0004 已定。素材=拜厄/哈农超前条（number>current 的 locked 谱，窗口 current+3~+8）；口径=命中率+用时+停顿数。Stage A 核心层+Stage B 界面，632/0 全绿。2026-10-09 完成。 |
| G5 | 奖励曲难点段落自动混入热身 | D5 | P1 | open | 兑现 PRD M3 Q4=A。 |
| G6 | 轻量练耳/视唱（听音辨音程、节奏型模仿） | — | P2 | needs-decision | 需先 Grill；P1 乐理课未做。 |
| G7 | 简谱层（五线谱转简谱/简谱视图） | — | P2 | needs-decision | PRD P1 明确不做，属后置反转，需专门议。 |
| G8 | 连续达标周数等轻激励补全 | — | P2 | open | 现 WeekStreak 诚实留白、无数字。 |

---

## 变更记录
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
