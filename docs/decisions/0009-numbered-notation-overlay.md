# ADR-0009 — 简谱叠加层（G7，反转 PRD「不做简谱」）

- 状态：accepted
- 日期：2026-10-10
- 关联：竞品差距 G7（docs/competitive-gap.md P2-2）；**本 ADR 明确反转早期 PRD「P1 不做简谱」的决定**。

## 背景与反转理由

早期 PRD 把简谱列入「不做」（担心强化简谱依赖、不利五线谱读谱成长）。竞品调研指出：本人会简谱、国内成人学琴普遍依赖简谱，且「五线谱一键转简谱」是虫虫/懂音律等国内产品核心卖点、西式产品完全不支持。经 Grill，用户拍板：**做，但以「五线谱为主体、简谱为可关闭的叠加辅助层」形态落地**——既利用既有简谱能力降低上手门槛，又不取代五线谱主体、不削弱读谱训练。这是对旧 PRD 的有意反转，非偏离。

## 决策（两轮 Grill 8 项用户口径）

1. **形态：五线谱之上叠加简谱数字**（逐音符标注），保留五线谱为绝对主体；不做纯简谱视图。
2. **谱源：只覆盖已解析 MusicXML**（`canFollow`：内置教材 + 导入的 MusicXML）。**PDF 只指引、不转换**——PDF 转简谱需 OMR，是红线，不做。
3. **开启：默认关闭，用户手动打开**；不干扰默认五线谱视图。
4. **唱名法：固定调（C 调）**：数字对应实际音名（C=1…B=7），不按调号移调，无需提取调号、最简单不易错。不做首调。
5. **黑键音：数字 + 升降记号**，忠实实际音高（C♯=♯1、B♭=♭7、F♯=♯4…）；不忽略升降、不留空。
6. **八度：数字上方/下方加圆点**（国内简谱惯例）区分高低八度；不裸标 1–7。
7. **和弦：每个符头都标**（和弦多个音垂直错开各标一个数字），不只标旋律音。
8. **开关：只在练习室设一个「简谱」开关，即时切换、不持久化**（不记全局/每曲偏好，最轻）。注：bottom-up 实证曲目详情页（PieceDetailView）**不渲染谱面**（全 app 的 ScoreView 只在练习室、今日视奏卡、定级向导三处），故详情页无可叠加对象、不设开关；2026-10-10 经用户确认将原「练习室+详情页各自开关」收窄为仅练习室。

## 技术形态（已 bottom-up 坐实可行性）

关键事实（读包源码，路径在 DerivedData SourcePackages/checkouts/swift-sheet-music）：
- `ScoreView`（SheetMusicUI）**无公开逐音符标注注入点**（内部仅 BreakIndicator overlay），故不改包、不往 ScoreView 内塞内容。
- 可行路径：宿主用与渲染**同一份 `LayoutDocument`**（ScoreView 的 document: 初始化器支持外部传入预计算文档），经 **`ScoreHitTester(document:).elementHitRect(for:)` / elementHitRects** 拿到每个元素在文档坐标的 `CGRect`；在 ScoreView 之上叠一个**几何对齐的同级 overlay 层**（ZStack，frame 与 doc.size 一致），把简谱数字定位到各符头上方。文档坐标与视图一致（ScoreView body 即按 doc 尺寸/offset 渲染），故坐标可直接用。
- 音高：遍历 `Score` 取每个音符音高（对齐 G4 `SightReadSession.expectedPitches(score:)` 已验证的提取路径），得到 MIDI note（或 step+octave+alter）。

固定调映射（纯函数，可单测）：
- MIDI note n：`pc = ((n % 12) + 12) % 12`；自然音名 C D E F G A B → 数字 1 2 3 4 5 6 7。
- 黑键：按实际音名取升降——用「该音在本音列的拼写」决定 ♯/♭（首选谱面音符自带 alter：+1→♯、−1→♭；只有音高无拼写作信息时用确定性等音规则，如 C♯/D♭ 类按固定表给一个，并在测试钉死，保证不摇摆）。
- 八度点：以基准（如 C4=中央 C 所在八度）为参照，n 每高一个八度数字上方加一个点、每低一个八度下方加一个点（实现给常量基准、测试覆盖高/低各一）。
- 休止符不标；连音/同音仍按每个符头标注（每个发声音符一个数字）。

新增内容（新模块允许新文件，Hermes xcodegen 纳入）：
- `NumberedNotation` 核心纯逻辑：MIDI/音高 → 简谱标签（数字+升降+八度点）。
- `NumberedAnnotationBuilder`：Score + LayoutDocument → 每个符头的 [CGRect : 标签]（含和弦垂直错开布局，避免重叠）。
- UI：仅练习室 `PracticeScoreScrollView`（已持有 displayScore + document）加一个「简谱」开关 + ScoreView 外的 overlay 层（复用其已有 LayoutDocument，避免二次 layout）；详情页不渲染谱、不改动。

红线：不改 Piece.status、不写 Take/TakeAnalysis、不触发过关/推进/streak/铺路/矫正；不改 swift-sheet-music 包源码；不做 OMR/PDF 转换；不加 debug 种子。

## 非目标

纯简谱视图、首调唱名、PDF/图片转简谱（OMR）、简谱编辑/输入、简谱播放跟唱；持久化开关偏好。

## 验证

- 纯逻辑单测：12 半音 → 数字/升降（C=1、E=3、C♯=♯1、B♭=♭7、F♯=♯4…）；八度点（中央 C 基准，高/低八度各一）；黑键等音确定性（同输入永不摇摆）；和弦每符头一个标签；休止符不标。
- overlay 构建：给定 Score+LayoutDocument，标签数 == 发声符头数；每个标签 CGRect 落在对应符头 hit rect 邻近（上方）；和弦多标签不重叠（几何定量，吸取 ego 教训：用 rect 相交断言而非视觉口报）。
- 独立全新全量 xcodebuild test（先 xcodegen），总数在 723 基础上 +新增、0 failures。
