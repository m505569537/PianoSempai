# Spike A · 记谱渲染选型（docs/spikes/score-rendering.md）

- 日期：2026-09-18 · 执行：Claude Code（P1 M1）
- 结论：**采用 swift-sheet-music（jiyimeta/swift-sheet-music，MIT）作为 P1 记谱渲染引擎**，OSMD 兜底无需启用。
- ⚠ 强制 checkpoint：本文件写完即停，Hermes/用户确认选型后才进入 S11 练习室实装。

## 1. 验收证据（全部实机/单测通过）

| 验收项 | 结果 |
|---|---|
| SPM 包解析 + 编译（Xcode 26.6 / swift-tools 6.2） | ✅ pin 到 commit `2a3a6f7`（2026-09-18 HEAD，上游无 tag），build 0 error 0 warning |
| 32 小节双谱表（高低音谱号）MusicXML 渲染 | ✅ 模拟器截图：纸白底、Bravura 字体谱号/符头、小节号、拍号齐全，真实刻谱非图片 |
| 光标跟进 + 当前小节 | ✅ `ScoreView(playbackCursor:)` 琥珀光标按拍推进；`cursor.measureIndex` 报告"当前小节 3/32"（footer 实拍） |
| 音符时间/音高信息（跟弹用） | ✅ 遍历 `Score.parts[].staves[].measures[].voices[].elements` 取 MIDI 音高（256 音符全对：C5=72、G5=79）；`score.seconds(at:)` / `score.cursor(atSeconds:)` 提供 notated 秒 ↔ 光标双向映射 |
| .mscz 解压解析 | ✅ 单测 `testMsczZipLoads`：`ScoreLoader.sniff` 识别 zip 容器 → 直接解析出 Score。**App 内无需自己解压** |
| 单元测试 | ✅ `ScoreLoaderSpikeTests` 3 条全过（MusicXML 32 小节/256 音符、mscz 加载、时间映射单调性） |

测试样例：`PianoSempai/Resources/SampleScores/SpikeSample32.musicxml`（自备公版小样，非教材内容）。

## 2. API 面（P1 会用到的部分）

- `ScoreLoader.loadScore(contentsOf:)` / `loadScoreWithDiagnostics`：sniff `.mscx/.mscz/.musicxml/.mxl/.mid` 五格式，**S08b 导入失败的具体错误码可从 diagnostics 取**。
- `ScoreView(score:options:playbackCursor:playbackCursorColor:availableWidth:)`：SwiftUI 原生视图，竖排 wrap 或横排单系统两种模式；内置 Bravura SMuFL 字体，无需自带。
- `ScoreCursor`：`.item(ScoreItemID)` / `.beat(measureIndex:tickInMeasure:)`，带 `measureIndex`；小节级高亮可用 `playbackCursorColor`（列级）+ 自绘小节底色（需 LayoutDocument 几何，见风险 3）。
- `Score` 模型：音符 = `Chord.notes: RandomAccessCollection<Note>`，`Note.pitch`（MIDI 0-127）；MIDI 导出 `exportMIDI`（P1 用不上但可作校验）。
- 主题/纸色：谱区底色由宿主控制（我们包 `Color.scorePaper`）；引擎主题字号可对齐 label-sm/body-sm（实装时调）。

## 3. 风险与对策

1. **单人项目、8★、无 tag**：上游活跃（今日仍有 commit）但无版本号。→ pin commit；升级走显式 bump + 回归 3 条 spike 单测。若上游断更，fork 自持（MIT 允许）。
2. **Swift 6.2 工具链要求**：本机 Xcode 26.6 满足；CI/其他机器需 Xcode 16+。已写入 README。
3. **小节级琥珀高亮没有现成 API**（光标是列级半透明条）：P1 方案 = `cursor.measureIndex` + 我们的 footer/外部指示；若 spec 要求谱区内小节底色，用 `LayoutDocument` 几何自绘 overlay（`ScoreHitTester` 证明几何可查）。工作量 +0.5~1 天，不阻塞。
4. **真实 MuseScore 导出的 .mscz 未验证**（本机无 MuseScore；单测用的是包内 .mscx 手工打 zip）。格式 sniff 逻辑与 MuseScore 4 容器一致；风险留给 S08 导入实测，失败降级文案承接点：曲库导入失败页（S08b）+ 指引用 MuseScore 导出 MusicXML。
5. **OSMD 兜底未实测**：主选一次通过，按 brief"失败退 OSMD"条款无需启用。OSMD 方案要点已备（WKWebView + 本地 JS + message handler 驱动光标），若 P2 前主选暴雷再切换。

## 4. 工时估计（S11 实装，基于本 spike 的 API 认知）

| 项 | 估时 |
|---|---|
| 谱面渲染接入 S11 + 主题对齐 Nocturne | 0.5 天 |
| 光标跟进（MIDI 在线匹配 → cursor 推进） | 1 天 |
| 小节高亮 overlay（若 spec 强制谱区内高亮） | 0.5–1 天 |
| 错误热点小节淡红底 | 0.5 天 |
| 合计 | **2.5–3 天** |

## 6. Hermes 独立验证与 gate 裁决（2026-09-18 17:35）

独立复核（不只凭 CC 自报）：
- 通读 `ScoreLoaderSpikeTests.swift` 三条单测，断言真实（32 小节 / 256 音符、mscz sniff+解析、秒→小节单调性）。
- 亲验模拟器截图 `/tmp/spikeA-render.png`：纸白雕版谱、4 组高低音大谱表、小节号/拍号齐全、琥珀垂直光标位于第 3 小节、footer 实显"当前小节 3/32 · 音符总数 256"、深炭 #1C1917 底。确认非图片非占位。

裁决：
1. ✅ 选型通过：采用 swift-sheet-music（pin `2a3a6f7`），OSMD 不启用。
2. ✅ 接受 commit pin；升级须显式 bump + 回归这 3 条 spike 单测。8★ 单人无 tag 风险已知，MIT 可 fork 自持，纯自用可接受。
3. ✅ 高亮方案：P1 用现有拍级琥珀光标条（已落在当前小节内）+ footer 小节指示；谱区内小节底色 overlay 与"错误热点淡红底"随 P2 完整判分一起做（P1 报告本就是简化占位），不在 P1 追加这 0.5–1 天。
4. 挂账：真实 MuseScore 4 导出 .mscz 在 S08 导入时实测，失败走 S08b + 引导导出 MusicXML。

**gate 放行：可进入 P1 功能实装。**
