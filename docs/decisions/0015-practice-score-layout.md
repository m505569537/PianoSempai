# ADR-0015：练习室谱面排版与「控件必须真生效」

日期：2026-11-17
状态：已拍板（真机逐条反馈驱动，用户确认）

## 背景

2026-11-16 ~ 11-17 连续真机试用暴露出两类问题，看起来都是「样式」，追下去都落在渲染/状态语义上：

1. **谱面被自己的 UI 挡住**：纸内谱头（第N条、♩=速度术语、双手 chip）与页脚（共N行）压在第一行/最后一行音符上；简谱/指法两个胶囊压在 3–4 小节上。用户报「有的音符并没有出现在五线谱上」，实际是遮挡 → 一度被误判为渲染丢了音符（解析数据 51 个音符其实完整）。
2. **控件点了没反应**：分手（右手/左手）切换无视觉变化；循环/等待切换要等别的操作才刷新；指法开关永远画不出东西。

## 决策

### 一、谱面排版

1. **不吃满屏宽，但也不套厚边框**。左右各 12pt 卡边 + 卡片内 6pt，圆角 12（continuous）+ 1pt 描边。
   最初是 12（内）+ 20（列）=32pt/侧，白扔 64pt 宽度；一度改成 0 边距 → 白底直贴屏幕边缘与工具条，
   成了「没有边界的硬白板」，更难看。12+6 是两者之间的取值。
2. **纸内不再叠加任何文字**。曲目编号/速度在顶栏副行已有（「1–8 小节 · ♩=72」），
   「共 N 行」「双手」对单人练习是噪音。谱面区域只放谱。
3. **首行缩进归零**：引擎默认 `firstSystemIndent=4sp` / `continuationSystemIndent=2sp`，
   首行比后续行各向内缩一截 → 「第一行和下面几行对不齐」。两者置 0 后三行左右边缘完全一致。
4. **左右居中的补偿不能靠 padding**。每行左端为小节号（1/5/9…）保留 gutter，右侧无对应物，
   实测卡片内左留白 29px / 右 9px。**文档宽度是固定值，padding 只在外围加空白，动不了谱面位置**；
   正确做法是把传给 `rebuild()` 的布局宽度收窄 12pt。修后左 29 / 右 28。
5. **纸色单点定义**。`PracticeScoreScrollView.paper`（用于 `colorMultiply` 叠染引擎硬编码的白底）
   与 `PracticeRoomView.s11Paper`（卡片底色）曾是两个独立字面量，只改一处会露出
   「暖色卡 + 纯白谱面」的接缝。现两处同值 `#EEE7D8`（原 `#FBF8F2` 在深色框架里像发光板）。

### 二、控件必须真生效（不变量）

6. **分手着色只能走 selection**。引擎 `ScoreLayerBuilder` 的上色逻辑是
   `for id in newSelection.selectedIDs { voiceColors[id.voiceIndex] }`——
   `voiceColors` 只决定「选中项用什么颜色」，**未被选中的音符不参与着色**。
   原实现只把已弹音符放进选中集，所以切右手/左手毫无变化。现把**非激活手的全部音符**
   放入选中集。非激活色用不透明 `Color(white: 0.58)`（`gray.opacity(0.3)` 在白底上约 85% 亮度，
   等于让音符消失）。
7. **voiceIndex 在单 part 双谱表下必须唯一**。`voiceColors: [Int: Color]` 没有 staff 维度，
   两个谱表都用 0 号声部会互相覆盖。做法：给第 N 个谱表逐小节插入 N 个空声部
   （空声部无元素、不渲染内容），把真实声部顶到唯一索引。
8. **状态属性漏 `@Published` = 控件假死**。`PracticeSession.mode` 漏标记导致改值不触发
   `objectWillChange`，胶囊选中态要等别的 `@State` 变化才跟着刷新。
9. **没有数据源的能力必须诚实禁用**。指法叠加对随包谱永远为空——引擎的 MusicXML 导入器
   不解析 `<fingering>`（只有 MSCX 解码器支持）。现由 `FingeringAnnotationBuilder` 实测有无标注
   并回报，无标注则 chip 置灰 + 显示「这条谱没有指法标注」，换谱时自动复位开关。
   与既有红线一致：**不提供假开关**。

## 实现落点

| 关注点 | 文件 |
|---|---|
| 卡边/纸色/工具条/空开关禁用 | `Features/Practice/PracticeRoomView.swift` |
| 布局宽度补偿、缩进、voiceIndex 唯一化、part 名剥离、selection 构造 | `Features/Practice/PracticeScoreScrollView.swift` |
| `mode` 的 `@Published` | `Services/Practice/PracticeSession.swift` |
| 设备名不写死型号 | `Services/MIDI/MIDIDeviceLabel.swift` |

## 后果

- 谱面可视宽度比最初多出约 40pt/侧；三行对齐、视觉居中（偏差 ≤1px）。
- 分手/循环等待/指法三个控件的行为与外观一致，不存在「点了没反应」。
- 代价：布局宽度被主动收窄 12pt（约 3%）以换取视觉居中；`systemGap` 由 40 降到 28 更紧凑。
- 未做：深色谱面（P16）、指法数据源（P17），均已登记在 `docs/backlog.md`。

## 验证方式

逐像素测量（窗口截图 → Pillow 取暗像素包围盒）：卡片与谱面的左右留白差、三行 L/R 一致性。
真机核对靠 DEBUG 入口：`--ui.practice <book>:<number>`、`--ui.simulated`、`--ui.hand`。
