# S24 MIDI 诊断（修订版 · 以 code.html 为真值）

- Screen ID：`457958f891634c96ae88206549de6ec9`
- 画布元数据：2560×2064 DESKTOP；实际内容 390 逻辑宽（body 固定 `width:390px`，margin auto），按 390 逻辑宽取值
- 真值文件：`/tmp/stitch-truth/screens/457958f891634c96ae88206549de6ec9/code.html`
- Status：Revised

## 1. 用途

实时验证 V70 的连接、音高/力度/踏板信号与时间戳；内嵌提示、重新校准入口与三条排查入口。诊断数据全部本机。

## 2. 颜色令牌

| Hex / 值 | 语义名 | 使用位置 |
|---|---|---|
| `#1C1917` | bgDark 主背景 | body；读数小格底（/70）；实时行底（/60）；排查行 hover（/40、/70） |
| `#262220` | cardBg 卡片底 | 全部 4 张卡 |
| `#332D29` | cardBorder 发丝边 | 卡边、导航下边（/40）、分隔线（/70、/60）、小格边（/50）、实时行边（/40）、信号条轨道、home indicator |
| `#D4A24E` | amberAccent | 键盘图标、最后事件值、Note/Velocity 条、Velocity 数值、辉光 `0 0 8px rgba(212,162,78,0.5)`、校准按钮边（/50）、touch_app |
| `#7FA97C` | greenAccent | ONLINE 字点、连接 ping 点、延迟值/优字标、监听 pill（底 /10 边 /30）、踏板条/值、脉冲点 |
| `#F5F2ED` | textMain | 标题、主值、C4 值 |
| `#9C948B` | textMuted | 状态栏、小格标签、行标签、时间戳文字、排查图标与 chevron、脚注 |

字体：正文 Inter（config sans），标题/分类 Noto Serif SC，数字 JetBrains Mono + tabular-nums。图标 Material Symbols Outlined。

## 3. 整体结构

- body：390 宽，min-h 844，纵向 `justify-between`。
- 状态栏：高 44，`px-7 pt-2`；9:41 12pt medium primary；右侧三个 Material 图标（15/15/17pt）muted。
- 导航头：`px-5 pt-3 pb-4`，下边线 border/40。
  - 左组 gap 12：返回 32×32（-ml-1.5），图标 `arrow_back_ios_new` 24pt；标题 **serif 21pt semibold** tracking-tight「MIDI 诊断」。
  - 右：8×8 green 点 + 11pt mono medium green「ONLINE」。
- main：`px-4 py-4`，卡间 `space-y-3.5`（14）。
- footer：`px-4 pt-2 pb-2`，居中：脚注 + home indicator（128×4 `#332D29`，mb 4）。

## 4. 逐卡规范

### 4.1 连接卡

- card / border / 圆角 16 / `p-4` / shadow-sm。
- 头条：pb 14，下边线 border/70，左右分布。
  - 左 gap 10：动画点组（10×10：底层 animate-ping green/75 圆 + 上层 green 实点）+ 15pt semibold「特伦斯 V70 已连接」。
  - 右 12pt muted：piano Material 图标 15pt amber（mr 4）+「88键力度键盘」。
- 四读数网格：2 列，`gap-2.5`（10），pt 14。
  - 小格：surface/70 底，圆角 12，`p-2.5`（10），1px border/50。
  - 标签 11pt muted mb 2；值 13.5pt mono medium。
  - 传输协议：`协议 BLE-MIDI` primary。
  - 传输延迟：`延迟 12ms` green + 10pt 徽章「优」（底 green/15、字 green/80、px 4 圆角 2）。
  - 最后事件：`最后事件 刚刚` amber。
  - 本会话吞吐：`事件总数 1,284` primary。

### 4.2 实时信号卡

- card / border / 圆角 16 / `p-4` / shadow-sm。
- 头 mb 12：
  - 左：serif 15pt semibold「实时信号」+ 徽章「CH 1」：10pt mono uppercase tracking-widest，底 border、字 muted，px 6 py 2 圆角 2。
  - 右监听 pill：底 green/10、边 green/30、px 8 py 2 圆角 99；6×6 green 脉冲点（自定义 2s 动画：opacity 1→0.4、scale 1→0.85）+ 11pt medium green「正在监听」。
- 三行实时数据容器 `space-y-3`（12），pt 4。每行：surface/60 底，圆角 12，`p-2.5`，1px border/40。
  - 标签行 12pt mb 6：左 muted，右 13pt mono semibold。
  - 条：全宽，轨道 `#332D29` 高 6（h-1.5），圆角 99，裁剪；填充 transition 150ms。
  - 音高：值 `C4 · 60` primary；填充 amber 宽 48%。
  - 力度：值 `96 / 127` amber；填充 amber 宽 75% + amber 辉光。
  - 踏板：值 `127 踩下` green；填充 green 宽 100%。
- 时间戳行：mt 12，pt 10，顶边 border/60，11pt muted：左 schedule 图标 13pt +「时间戳 hostTime」；右 mono「184,332,901,221」。

### 4.3 提示卡

- card / border / 圆角 16 / `p-4` / shadow-sm。
- 提示文：mb 12，左 touch_app 19pt amber（mr 10），12.5pt primary/90 leading-relaxed，逐字：
  > 随便弹几个音、踩一下踏板，四个数值都应该跟着动。力度不准可回到上一级做 2 分钟个人校准。
- 按钮：全宽，`py-2 px-3`，圆角 12，1px 边 amber/50，12pt medium amber；hover 底 amber/10，按压缩放 0.99；tune 图标 16pt +「重新校准力度」。

### 4.4 常见排查指引卡

- card / border / 圆角 16 / overflow-hidden / shadow-sm，无内边距。
- 卡头：`px-4 pt-3.5 pb-2`，serif 11.5pt semibold uppercase tracking-wider muted，逐字「常见排查指引」。
- 三行（行间 border/70 分隔）：`px-4 py-3`（12 上下），左图标 18pt muted + 13.5pt primary 条目，右 chevron 18pt muted；hover surface/40，active surface/70。
  1. bluetooth_searching「蓝牙搜不到设备」
  2. volume_off「有声音但没有信号」
  3. speed「声音断续或拖拍」

## 5. 脚注

- 居中 11.5pt muted，shield 图标 14pt + 逐字「诊断信息不会上传，仅用于本机排查」，mb 12。

## 6. 全部状态与交互热区

- 返回 32×32 热区。
- 三条信号条随事件实时驱动（150ms 过渡）；踏板 html 呈现为 0–100% 连续条（值 127），旧 spec 要求「0/127 开关样式」→ **待产品确认**。
- 排查三行整行可点进入指引详情（详情页不在本批）。
- 重新校准按钮进入力度校准流程（旧 spec：S03 第 3 步同款最弱/最强/舒适三档采样）。
- 旧 spec 的「无事件 3 秒提示『还没收到信号』」html 无此态 → **待产品确认**。

## 7. 相对旧 spec 的主要修订

1. 旧 spec 结构与真值偏差大：真值有 4 张卡（连接 / 实时 / 提示 / 排查），旧 spec 把排错写成静态三条文案；真值排错为可点行卡（图标 + chevron）。
2. 标题字号 21pt serif（非标准导航 17pt）；右侧 ONLINE 绿色状态。
3. 连接卡四读数补全：BLE-MIDI / 12ms 优 / 刚刚 / 1,284，小格圆角 12、surface/70、border/50。
4. 信号条轨道高 6（旧 spec 4px，错），行容器圆角 12 + surface/60 + 边；「CH 1」徽章与「正在监听」脉冲 pill。
5. hostTime 真值「184,332,901,221」（旧 spec 写 128492.441ms，错）。
6. 校准入口为提示卡内描边按钮（旧 spec 独立行），文案「重新校准力度」。
7. 连接点带 animate-ping 动效。
