# ADR-0014：练习室指法叠加层（G11 前半：显示先行，.mscz 立即可用）

日期：2026-11-09
状态：已拍板（用户四项口径全拍推荐，2026-11-09）

## 背景

G11（backlog）原判「blocked 等上游」：上游 swift-sheet-music（pin `2a3a6f7`）的 MusicXML 解码器不解析 `<notations><technical><fingering>`，`.musicxml`/`.mxl` 导入丢指法（上游 issue #25，2026-10-31 提交，截至 2026-11-09 仍 open / 0 回复 / main tip 未修）。

2026-11-09 bottom-up 复核推翻「只能等」的判断，三个实证事实：

1. **数据模型早已就位**：`Note.fingerings: [Fingering]`（SheetMusicCore/Score/Note.swift:86）完整存在，含 text/role/位置属性。
2. **.mscz 路径已通**：MSCXDecoder+Fingering.swift 解析 `<Fingering>`（探针测试 FingeringProbeTests 实证：FingeringFixture.mscz 三音 pitch 60/61/62 → 指法 1/2/3 全部抵达 Score；ScoreLoader 按 ZIP magic 分发，.mscz 优先走 MSCX）。绕行指引已在 2026-10-31 落地（途径 A/D 提示「带指法优先下 .mscz」）。
3. **渲染层是 app 侧缺口而非上游**：grep 全上游 Sources，SheetMusicLayout/SheetMusicUI 对 fingerings 零消费——即使上游修了 MusicXML 解码，包的谱面渲染也不画指法。指法显示本来就只能走 app 层叠加（与 G7 简谱同几何路径），不依赖上游任何改动。

## 决策（用户 2026-11-09 四项全拍推荐）

1. **推进范围**：G11 指法显示先行（app 层叠加层，.mscz 立即可用）；上游 MusicXML 解析修复另行以 PR 补丁推进；V8 手型骨架本轮不动。
2. **入口形态**：练习室「指法」胶囊开关，与「简谱」并列（PracticeScoreScrollView 现有 NocturneChip 模式），默认关、即时切换、不持久化（同 G7/ADR-0009 口径）。
3. **位置冲突**：简谱标符头**上方**（G7 既有，sp*1.6 上移），指法标符头**下方**（本 ADR，约 sp*1.4 下移），天然零冲突、两开关独立可同开；右手谱指法可能被符干挡住，属可接受取舍（不为此改几何）。
4. **上游修复路径**：Hermes 起草补丁 PR（`gh auth login` 需用户做一次）；PR 合并并出新 revision 前，app 继续用绕行口径（.musicxml/.mxl 无指法，开关对这类谱自然无标注、不报错）。

## 实现要点（Stage A 纯逻辑 / Stage B 视图，红线同 G7）

- **Stage A**：`FingeringAnnotation`（frame + text + role）与 `FingeringAnnotationBuilder.build(score:document:)` 纯函数——几何遍历完全照抄 NumberedAnnotationBuilder（system→measure→`.chord` 11 槽位 pattern match；中心 = system.origin + measure.origin + note.origin + mirrorDx(stem:sp:)；`score[note.noteID]` 取 nil 跳过；grace 合成 noteID 天然跳过）。指法文本取 `noteModel.fingerings`（可能多条，取 role == .fingering 的首条；无则跳过该音）。
- **Stage B**：PracticeScoreScrollView 加 `showFingerings` @State + 「指法」NocturneChip（与「简谱」同 overlay 挂 ScrollView，两 chip HStack 排列）；overlay view 照 NumberedNotationOverlayView 模式（.position 定位、Color.scoreInk 墨色、allowsHitTesting(false)、字号约 sp*1.2）。
- **红线**：不改 Piece.status / Take / TakeAnalysis / 判分链 / CourseEngine；不改 swift-sheet-music 包源码；无 fingerings 数据源的谱（.musicxml/.mxl/.mid 导入、126 首内置拜厄/哈农——BundledScores 均为 MusicXML 转换产物）开关点了也不报错、只是没有标注；禁止造假装饰。
- **测试**：Stage A 对 builder 用 FingeringFixture 数据断言（3 音 3 指法、无指法音跳过、grace 跳过）；Stage B 断言开关状态切换与 overlay 挂载条件（无 UI 快照）。

## 后果

- 指法显示与上游解耦：上游 PR 合并与否不影响本批交付（只影响 .musicxml/.mxl 也能显示）。
- G11 拆成两半登记：显示层（本 ADR）与上游解析修复（PR 跟踪）；backlog G11 行同步更新。
- 真机验收追加 V15（3 项：有指法 .mscz 显示正确 / 双开简谱+指法上下并存 / 无指法谱开关无效果不崩）。
