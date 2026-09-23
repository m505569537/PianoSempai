# S18 问 Neko（对话页）· 修订 spec

> 真值来源：Stitch code.html（DESKTOP 渲染稿，容器 `max-w-[390px] h-screen`，以 **390×844 逻辑点**为准；整体为带顶部 grab handle 的 sheet 式全屏页）。

## 1. 用途与页面定位

带弹奏上下文的 AI 助教对话：Neko 回答必须引用 take/小节/偏差；支持发送视频（必经 S18b）；低置信时明说"看不清、不能确定"。
从 FAB/报告/练习室进入，**无 tab bar、无返回 chevron**；顶为 grab handle + 关闭 ✕。

## 2. 颜色系统（tailwind.config + 内联 hex）

| Hex | 语义 token | 使用位置 |
|---|---|---|
| `#1C1917` | bgDark | 页面底、header/footer 底（95%+blur）、引用 chip/输入框内底 |
| `#262220` | cardBg | Neko 气泡、上下文 chip、输入框底、关闭钮 hover 底 |
| `#332D29` | cardBorder | 全部发丝边框、分隔线 |
| `#D4A24E` | amberAccent | 头像/发送钮/引用 chip 文字/描边按钮/播放钮、最新态强调 |
| `#F5F2ED` | textMain | 主文字、发送钮图标 |
| `#9C948B` | textMuted | 时间戳、次要文字、图标默认态 |
| `#2E261F` | userBubbleBg | **我方气泡底（深琥珀灰，非琥珀实底）** |
| `#4A3B2C` | userBubbleBorder | 我方气泡边框 |
| `#443E3A` | （内联） | 顶部 grab handle |
| `#2E2822` | （内联） | 视频附件缩略图占位底 |
| `#000000` 70%→transparent | （内联渐变） | 缩略图底部压暗渐变 |

字体：标题 `Noto Serif SC`（500/600/700）；正文/数字 `Inter` 400–600，mono 用于引用 chip。

## 3. 整体布局层级

```
main (390pt, flex-col, overflow-hidden)
├─ header（吸顶：grab handle + 行[头像 标题 | ✕] + 上下文 chip）
├─ 对话滚动区 flex-1（px=16, py=16, 消息间距 16, 13.5pt）
└─ footer（输入框容器 + 脚注）
```

### 3.1 header（吸顶，z=30）
- `pt=12 px=16 pb=10`；bg bgDark **95% + backdrop-blur-md**；底边 cardBorder 60%。
- **grab handle**：40×4 全圆角，色 `#443E3A`，居中，`mb=12`。
- 标题行 flex 两端：
  - 左簇 `gap=10`：头像 **32×32 正圆**，bg 琥珀 15% + 边框琥珀 40%，猫脸 SVG **18pt**（stroke 1.8），琥珀色，shadow-inner。
  - 标题：serif **18pt（text-lg）semibold** tracking-wide「问 Neko」。
  - 右关闭钮：**32×32 正圆**，✕ SVG 20pt（stroke 2），muted；hover text + 底 cardBg。
- 上下文 chip（`mt=10`）：`px=10 py=4` 全圆角，bg cardBg + border，文字 **11pt** muted；前置 **6×6 琥珀圆点（animate-pulse 呼吸）**。
  - 真值文案：「上下文：拜厄45 · 今天 20:31 的 take」。
  - **无 ✕/更换按钮**：旧 spec 的"可换/✕、解绑后自由问答"在真值中不存在 → 待产品确认。

### 3.2 对话滚动区
- `flex-1 overflow-y-auto px=16 py=16 space-y=16`；基准 **13.5pt / 行高 relaxed**。

**我方气泡（右）**：
- 列右对齐，气泡 `max-w=85%`；bg `#2E261F` + 边框 `#4A3B2C`；`px=14 py=10`；圆角 **16pt，右上角 2pt**（rounded-tr-sm）；shadow-sm。
- 时间戳在气泡下：10pt，muted **60%**，`px=4`。

**Neko 气泡（左）**：
- `max-w=92%`；bg cardBg + border；`px=14 py=12`；圆角 **16pt，左上角 2pt**；shadow-sm；气泡内部 `space-y=12`。
- 正文：text 色，行高 **1.6**（第二条为 muted 色）。
- 引用 chips：气泡内 flex-wrap `gap=6 pt=2`；单 chip `px=8 py=2`，圆角 **6pt**，bg bgDark + border，**11pt mono 琥珀字**，前置 12pt 线性图标（时钟/柱状）。
- 署名时间戳：10pt muted 60%，「20:32 · Neko」。

**含视频的我方气泡**：
- 气泡 `p=12 space-y=8`。
- 附件行：flex `gap=10 p=8`，圆角 **12pt**，bg bgDark **90%** + border cardBorder；hover 边框变琥珀 40%。
  - 缩略图：**56×44**，圆角 8，bg `#2E2822` + border，底部黑渐变；中央播放钮 **20×20 正圆**，bg 琥珀 80%，播放三角 bgDark 色（10pt，左偏 2pt）。
  - 文案列：「侧拍 0:32」12pt medium text；「视频 · 1080P」10pt muted。
  - 点击 → 按 S18b 流程/视频回看（真值未画 S18b 跳转态，沿用红线：发送前必经 S18b）。

**琥珀描边操作按钮（Neko 气泡内）**：
- `inline-flex gap=6 px=12 py=6`，圆角 **8pt**，边框 1pt 琥珀，文字/图标琥珀，**12pt medium**；hover bg 琥珀 10%；按压缩放 0.98。
- 图标（重拍/刷新）14pt；文案「重新校准机位」。

### 3.3 真值对话内容

| # | 角色 | 内容要点 |
|---|---|---|
| 1 | 我 | 「第21小节我到底哪里有问题？」20:32 |
| 2 | Neko | 两次接弹慢约 **120ms**，右手 3 指转 1 指；音没弹错；♩=60 单手练 4 遍，±40ms 内再合手。引用 chips：「take 今天20:31」「小节 21 · +120ms」 |
| 3 | 我 | 「我录了侧拍，帮我看看手型」+ 视频附件「侧拍 0:32 · 视频 1080P」20:33 |
| 4 | Neko | 看不清 1 指触键角度（机位被琴谱挡住），「这个问题我不能确定。」+ 描边钮「重新校准机位」 |

### 3.4 footer 输入区
- `px=12 pt=8 pb=20`，bg bgDark，顶边 cardBorder **70%**。
- 输入框容器：flex items-center `gap=8`，bg cardBg + border，圆角 **16pt**，`px=10 py=6`；**focus-within 边框变琥珀 70%**；shadow-inner。
  - 左图标组 `gap=4`，muted：**回形针（附件）** 与 **摄像机（录制视频）** 各 **28×28 正圆**，图标 16pt（stroke 1.9）；hover text + 底 `#332D29` 50%。
  - 输入框：flex-1，透明底，**13.5pt** text；placeholder 色 muted 60%，真值文案「**问问这一段…**」。
  - 发送钮：**32×32，圆角 12pt（非圆形）**，bg 琥珀，发送图标 16pt bgDark 色（stroke 2.2）；hover 琥珀 90%，按压缩放 0.95，shadow-sm。
- 脚注：居中，`mt=10`，**11pt** muted **75%** tracking-tight：
  「Neko 只有建议权，不会替你解锁过关」。

## 4. 全部状态

| 状态 | 表现（真值） |
|---|---|
| 默认 | 如图两组问答；输入框未聚焦 |
| 输入框聚焦 | 边框 → 琥珀 70% |
| 空输入发送钮 | HTML 未画禁用态 → 待产品确认（建议置灰，需产品确认） |
| 上下文 chip 圆点 | 持续呼吸动画（animate-pulse） |
| Neko 思考/打字三点、检索中"在翻你最近的 take…" | HTML 未呈现 → 待产品确认 |
| 失败重试气泡、长回答折叠"展开" | HTML 未呈现 → 待产品确认 |
| 无上下文自由问答态 | HTML 未呈现 → 待产品确认 |

## 5. 交互热区

- 关闭 ✕：32×32 圆。
- 上下文 chip：整体可点（真值未画按钮，跳转/更换动作待产品确认）。
- 引用 chip ×2：点击跳 S13 对应 take/小节（沿用旧 spec 导航定义）。
- 视频附件整行可点（hover 边框反馈）→ 视频预览；发送动作仍走 S18b。
- 「重新校准机位」整钮热区。
- 附件/摄像钮 28×28；发送钮 32×32；输入框文字区域。
- 消息气泡本身无点击态（非热区）。

## 6. 与旧 spec 的主要差异（施工必改）

1. **我方气泡配色方向相反**：旧"琥珀底深字"；真值为**深琥珀灰底 `#2E261F` + 边框 `#4A3B2C` + 浅字**；最大宽 **85%**（旧 78%）。
2. Neko 气泡最大宽 **92%**；引用 chips **在气泡内部**、琥珀 mono 字 + bgDark 底（旧：气泡外胶囊）。
3. **顶部形态**：grab handle + 关闭 ✕ 的 sheet 头，无返回 chevron；旧 spec 的返回布局作废。
4. **输入栏按钮**：真值 = 回形针 + 摄像机；旧 spec 的「+」/麦克风不存在（麦克风语音输入 → 待产品确认）。placeholder 真值为「问问这一段…」。
5. 发送钮 **圆角 12pt 方形**（32×32），非圆形。
6. 脚注真值文案：「Neko 只有建议权，**不会替你解锁过关**」。
7. 旧 spec 缺全部色值/字号/圆角/间距；正文以第 2、3 节为准。
8. 旧 spec 中的打字等待、失败重试、长回答折叠、chip ✕ 解绑等态真值中无，一律标「待产品确认」，不得直接施工。
