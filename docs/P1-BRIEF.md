# PianoSempai · P1 编码任务书（Foundation 批次）

> 交付对象：Claude Code（绿地 iOS 项目）。Hermes 编写于 2026-09-18。
> 执行方式：按 M0→M7 里程碑推进；每个里程碑独立 commit；M1 spike 结论必须停下产出决策记录后再继续。

## 0. Truth Sources（先全部读完再动手）

| 文件 | 作用 |
|---|---|
| `docs/PRD.md` | 产品决策全集（Grill M1–M9、六条红线、不做清单、P1–P5 分期） |
| `docs/design-reference/foundation/visual-system.md` | 视觉 token、全局组件、§9 文案锁定 10 条（最高视觉真值） |
| `docs/design-reference/screens/Sxx-*/spec.md` | 32 份画布 spec（布局/组件/交互态/红线落点） |
| `docs/design-system/screen-index.md` | 屏幕导航总账、阶段归属 |
| `docs/design-system/data-model.md` | SwiftData 模型、写入权矩阵、沙盒布局、状态机 |
| `docs/design-system/screens/*.md` | 7 份域契约（onboarding/today/library/practice/neko-ai/archive/settings） |

冲突裁决：文案以 visual-system §9 + 画布 spec 为准；行为以 PRD + 域契约为准；设计稿 PNG 仅参考。
发现 spec 自身矛盾 → 记入 `docs/findings.md`（F1/F2…），不要静默选一个。

## 1. 项目初始化（M0）

- 目录：`~/Developer/PianoSempai`（本文件所在仓库根，已是 git repo，docs/ 已入库）。
- 目标：iOS 17+ iPhone app，SwiftUI + SwiftData，竖屏，仅 iPhone，dark-first（系统外观跟随但 UI 恒为 Nocturne 深色）。
- 工程生成：优先 XcodeGen（`brew install xcodegen` 若缺）写 `project.yml` 生成 `PianoSempai.xcodeproj`；bundle id `com.eeexu.pianosempai`；display name `PianoSempai`；版本 0.1.0。
- 依赖（SPM）：MIDI 用 SwiftMIDI（github.com/genedelisa/SwiftMIDI，MIT；先核实包可解析，不行则直接封装 CoreMIDI 的 MIDIManager，不阻塞）。
- 目录结构建议：`App/`、`DesignSystem/`（Color token、字体、复用组件）、`Features/<域>/`（Onboarding/Today/Library/Practice/Archive/Settings）、`Models/`、`Services/`（MIDI、ScoreRendering、TakeStore、Export、Clock）、`Resources/`。
- 三校验脚本写进 README：`xcodebuild -scheme PianoSempai -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build` 必须 0 error；swiftc 严格警告当错误处理（至少不新增 warning）。
- Info.plist：NSBluetoothAlwaysUsageDescription、NSCameraUsageDescription、NSMicrophoneUsageDescription 文案照抄 S02 spec；UILaunchScreen；界面方向仅竖屏。
- Color assets：把 visual-system.md §1 全部 token 建成 xcassets color set（命名用语义名：canvas/card/cardElevated/border/amber/amberBright/textPrimary/textMuted/success/danger/compareB/scorePaper）。
- 字体：Noto Serif SC / Noto Sans SC 不内置版权字体文件——用系统回退方案：标题用 `serif` 系统衬线（New York）、正文 `.rounded`/默认无衬线，在 DesignSystem 里包一层字体语义（DisplaySerif/BodySans/LabelMono），日后可换；tabular数字用 `monospacedDigit()`。
- M0 验收：空白 app 启动为 #1C1917 底色全屏；模拟器 build 通过；git 首个工程 commit。

## 2. M1 · 两个 Spike（先做，结论写 docs/spikes/）

### Spike A：记谱渲染（第一天，最高风险）
1. 调研 swift-sheet-music（GitHub 实测包解析、MusicXML 渲染、能否在 UIView/SwiftUI 承载、是否支持光标定位与 MIDI 导出）。
2. 验收目标：用《拜厄》或任意公版 MusicXML 小样（自备最简 MusicXML，32 小节，含高低音谱号）在模拟器渲染出纸白五线谱；能按小节高亮；能取到每个音符的时间/音高信息用于跟弹。
3. `.mscz` 解压（zip 含 .mscx）解析可行性记录；失败给降级文案承接点（不实现转换）。
4. 失败退路：OSMD（opensheetmusicdisplay）WKWebView 承载方案做最小可行性验证（本地 bundle JS、loadHTML、message handler 驱动光标）。
5. 产出 `docs/spikes/score-rendering.md`：选型、API 面、风险、工时估计；**写完停下**，Hermes/用户确认后再继续（这是唯一强制 checkpoint）。

### Spike B：CoreMIDI/BLE
1. V70 真机无法在模拟器测 → 必须做「模拟 MIDI 源」开关（诊断页里的"模拟输入"，按屏幕琴键或自动回放 .mid 产生同构事件流），全 App 的 MIDI 输入走一个 protocol（如 `MIDIEventSource`），真机源与模拟源可切换。
2. 真机 BLE：CoreMIDI 网络/BLE 发现与连接（MIDICapacity 或自封装），Info.plist 蓝牙用途串。
3. 事件模型：noteOn/noteOff/velocity/CC64/hostTime；BLE 丢 noteOff 用 velocity=0 + 超时截断（800ms）双保险，写单元测试。

M1 验收：spike 文档 + 模拟源在空 app 里能打印结构化 MIDI 事件；超时截断单测通过。

## 3. P1 功能范围（IN）

按域分批，每批独立 commit。视觉一律照画布 spec，文案逐字。

- **App 骨架**：S06 frame（5 tab 写死：今日/曲库/练习室/档案/我的；问 Neko FAB 视觉在但 P1 点击弹"AI 助教将在后续版本开放"toast）；连接胶囊；无 tab 页隐藏 tab bar 的路由机制。
- **Onboarding**：S01→S02（真实蓝牙/通知授权流程，相机麦克风授权可先不请求只展示）→S03（真实 BLE 发现/连接/验证 + 模拟源兜底）→S04 自评→简化视奏（用模拟源或真机弹 2 段，仅采原始数据）→力度校准（最弱/最强/舒适三档 2 分钟，存 VelocityCalibration）→S05 结果页（插入点先用规则表：自评+视奏命中率映射拜厄条目，算法写死但集中在 CourseEngine.swift 一处，P2 替换）。未完成可退出续做。
- **今日**：S07b 空状态（未定级）/S07 常态（DailyPlan 生成、时长三选联动、三任务卡、周 streak 7 灯从真实 take 聚合）；S07c 热身强开（原因必填、GateEvent 落库、本周计数）；热身未完成进主菜必须被拦（负例也要测：未完成时直接触发不了练习）。
- **曲库**：S08 三段+筛选（内置公版教材元数据先放本地 JSON：拜厄/哈农条目，599 仅锁定占位）；导入 .xml/.mxl（Files + Share 扩展可只做 Files 入口）；解析失败 S08b（具体错误码）；S09 详情（过关标准展示、小节选择器、最近 take ≤3）；S10 PDF 库（QuickLook 查看、明确不判分双声明）。
- **练习室**：S11（真实记谱渲染 + 当前小节高亮 + 节拍器本机声 + ♩= 步进 + 标记按钮 + 结束出报告）；S12 循环 sheet（起终点/三模式 UI 与循环回放，自适应 +5/−5 P1 做规则但无完整 M5 时只按错误计数简化，挂 TODO 注释）；S11b 断连（模拟源可造断连用于验收）；时间到自动保存。
- **Take 与报告（P1 简化版）**：原始 MIDI 落沙盒只追加；take 元数据 SwiftData；S13 报告 P1 先给：时长、音符数、错音数（与谱面对比的简单匹配，不要求 DP 对齐质量）、速度、踏板事件数、MIDI 事件数；六维雷达/热力/节奏偏差/弱总分在 P1 可显示"P2 完整判分"占位态（用 spec 里的占位视觉语言，不得编造假分数——宁可显示"分析将在 P2 提供"）。S13b 疑似谱错：P1 做标记入库与"不计入错音"展示。
- **自由弹奏 S14**：模拟卷帘用简单条形视图（不需钢琴卷帘库），仅 MIDI 记录+一句话+保存/丢弃确认。
- **档案 S20 P1 简版**：本周统计 + take 时间线（筛选 chips），趋势图/周报入口置"后续版本"；S21/S22 不做（路由可预留禁用态）。
- **设置**：S23 全部分组；S24 诊断全功能实时（音高/力度/CC64/hostTime/模拟源开关/重校力度）；S25 Key 页做 UI + Keychain 存取/掩码/替换/删除（发测试消息按钮显示"P3 开放"）；S26 导出 zip 真做（JSON+midi+scores+pdfs，视频勾选无视频时置灰；恢复功能 P1 做整库恢复）；隐私红线静态页（六条原文从 PRD 摘）。
- **笔记 S19**：P1 只做本地笔记（manual/issue），周报类型置灰。
- **不做（P1 OUT，UI 不得出现入口）**：AI 对话真实功能、视频/相机/MediaPipe、Zf 导入、月报、对比、账号、云、商店、麦克风音频判定、瀑布流、OMR。

## 4. 工程红线（违反即返工）

1. 课程状态只有 `CourseEngine`（M3 的 P1 简化版）能写；任何 View/AI 占位代码不得直接改 Piece.status。
2. 无假数据冒充真分析：P1 算不出的指标显示"后续版本提供"，不生成随机/示例分数。
3. Key 只在 Keychain；日志里不打印；导出包不含。
4. 原始 MIDI 文件只追加不可变；SwiftData 存元数据与文件 URL。
5. 文案逐字锁定（visual-system §9），特别 5 tab、热身/主菜/奖励曲、特伦斯 V70、火山方舟、手型免责、弱总分脚注。
6. 谱面必须由 Spike A 选定的真实引擎渲染，不得用图片/PDF 截图当跟弹谱。
7. 不引入除系统库与已批准 SPM 外的第三方（尤其不上传/统计/崩溃 SDK）。
8. 所有破坏性操作（删除 take/Key/恢复库/丢弃录音）二次确认，默认焦点在取消。

## 5. 验收（Hermes 独立验证会跑）

- `xcodebuild` 模拟器 build 0 error；核心规则（热身门禁、noteOff 超时、错音剔除、zip 内容）有单元测试。
- 模拟器走通：首次链路（模拟 MIDI 源）→ 定级 → 今日三段 → 练习（自带示例 MusicXML）→ take 落盘 → 报告 → 导出 zip，全程不断在假按钮上（每个按钮都要有真实行为或明确的禁用态）。
- 负例：热身未完成主菜被拦；未授权蓝牙仍可进曲库；未连接设备练习 CTA 禁用；占位指标不显示假数字；tab 第 4 个始终是"档案"。
- 每屏过一遍对应画布 spec 的"红线落点"清单。

## 6. 节奏与汇报

- 每个 M 结束：自检报告（做了什么/偏离/findings/下一步）+ commit，停在输入框等 Hermes 验证，不自动连开下一里程碑。
- 长文档若被截断，主动报告，不要基于残缺内容决策。
- Git：工作区干净再 commit；发现非自己产生的 dirty 文件先报告。
