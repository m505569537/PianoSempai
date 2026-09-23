# S18b 视频裁切与发送确认（Bottom Sheet）· 修订 spec

> 真值来源：Stitch code.html（MOBILE 稿，viewport 390×844；内部 frame 严格 **390×844**）。
> 页面 = 压暗的 S18 对话背景 + 底部上滑 sheet。

## 1. 用途与页面定位

任何视频离开本机前的唯一闸口：选区间 → 核对提问 → 服务商明示 + 云端删除开关 → 确认发送。
Sheet 为**底部锚定、近全高**（顶部仅留 74pt 背景，sheet 高约 **770pt ≈ 91%**；旧 spec"约 70%"错误）。

## 2. 颜色系统

tailwind.config 定义了整套 Material Design 3 token，但 markup 实际主要使用内联 hex。实际使用色：

| Hex | 语义 | 使用位置 |
|---|---|---|
| `#100E0C` | surface-container-lowest | body 底（frame 外） |
| `#1C1917` | app.bg | 390×844 frame 底；开关滑块、手柄内凹槽 |
| `#161311` | surface-dim / background | 背景对话层底 |
| `#262220` | app.card | **sheet 底**、背景层头像底 |
| `#332D29` | app.border | sheet 顶边/分隔线、全部发丝边 |
| `#D4A24E` | app.amber / primary-container | 手柄、选中态、开关 ON、CTA、图标文字、辉光 |
| `#F3BE67` | primary / primary-fixed-dim | 胶片波形高亮柱（比主琥珀更亮） |
| `#F5F2ED` | app.text | sheet 标题、播放头、提问高亮 |
| `#E9E1DD` | on-surface / inverse-surface | 背景层聊天气泡字 |
| `#9C948B` | app.muted | 标签/时间戳/次要文字 |
| `#1E1B19` | surface-container-low | 胶片轨容器、未选 chip、提问行、服务商卡底、关闭钮底 |
| `#171513` | （内联） | 选区外未激活片段底 |
| `#2D261B` 80% | （内联） | 胶片选中区间底 |
| `#2D2927` | surface-container-high | 背景层用户气泡底 |
| `#3D3531` | （内联） | 背景层用户气泡边框 |
| `#2D2724` | （内联） | 背景层 chat header 边框/底 |
| `#443D37` | （内联） | grab handle、home indicator |
| `#6E6760` | （内联） | 底部安全脚注字色 |
| `#000000` 65% | scrim | 背景遮罩 + backdrop-blur **2pt** |

自定义辉光 `.amber-glow`：`box-shadow: 0 0 20px rgba(212,162,78,0.18)`。
字体：`Noto Sans SC`（正文/label）、`Noto Serif SC`（标题）；MD3 type scale 已配置（headline-sm 20/28、label-sm 11/14 ls+0.08、label-md 12/16 ls+0.06 等）。

## 3. 整体布局层级

```
body (#100E0C, flex 居中)
└─ frame 390×844, bg #1C1917, flex-col justify-between, overflow-hidden
   ├─ 背景层 z=0（压暗的 S18：状态栏 + chat 头 + 2 条历史气泡 + scrim）pointer-events-none
   ├─ 顶部占位  h=74, z=10
   ├─ sheet z=20（rounded-t 28, px=20, pt=12, pb=24）
   │  ├─ grab handle
   │  ├─ 标题行（标题/副标题 | ✕）+ 分隔线
   │  └─ 内容区 pt=14 space-y=16
   │     ├─ 裁切区（标签/区间 badge + 胶片轨 + 时间刻度 + 预设 chips）
   │     ├─ 提问上下文行
   │     ├─ 服务商披露卡（文案 + 分隔 + 删除开关）
   │     └─ CTA / 取消 / 脚注
   └─ home indicator
```

### 3.1 背景层（只读，无交互）
- 状态栏 h=44（pt=12 px=24，9:41 12pt semibold；右图标 15–16pt muted）。
- chat 头：`px=20 py=10`，底边框 `#2D2724`；32×32 圆头像 +「问 Neko」14pt + 10pt 副标题（前置琥珀圆点）「正在分析第21小节连奏手型」；右 `more_horiz`。
- 历史 2 气泡：整体 **opacity 40%**。
- scrim：绝对铺满，黑 65% + backdrop-blur **2px**。

### 3.2 Sheet 容器
- bg `#262220`，**顶部圆角 28pt**，顶边 1pt border，阴影真值 `0 -12pt 32pt rgba(12,10,9,0.75)`；`px=20 pt=12 pb=24`。
- grab handle：40×4 全圆角 `#443D37`，居中，`pb=12`。

### 3.3 Sheet 标题行
- flex 两端，`pb=14`，底边 border **60%**。
- 标题：serif **18pt semibold** tracking-tight「裁切并发送给 Neko」。
- 副标题：**12pt** muted（label-sm），mt=2：「只发送你提问的那一段，原视频不会上传」。
- 关闭钮：**32×32 正圆**，bg `#1E1B19` + border，muted ✕ 18pt；hover bg `#2D2724`，按压缩放 0.95。

### 3.4 裁切区（space-y=10）
- 标签行两端：
  - 左 11pt muted uppercase tracking-wider「片段区间」。
  - 右区间 badge：`px=10 py=4`，圆角 **6pt**，bg 琥珀 **10%** + 边框琥珀 **30%**；内 6×6 琥珀呼吸圆点 + 12pt medium 琥珀字。
  - 真值：「**已选 0:12–0:24（12秒）**」——无文件大小（旧 spec"约 6MB"真值中不存在 → 待产品确认）。
- 胶片轨容器：全宽，**高 62pt**，bg `#1E1B19`，圆角 **8pt**，border，`p=2`。
  - 内轨高 **52pt**，圆角 4，flex，overflow-hidden：
    - 左未激活段 **37.5%**：bg `#171513`，opacity 35%，波形柱 `#332D29`，右侧分隔；覆盖黑 60%。
    - **选中段 37.5%**：bg `#2D261B` 80%，上下 **2pt 琥珀边**，z=10，amber-glow；波形柱 24–40pt 交替 `#D4A24E`/`#F3BE67`（亮柱带 6pt 琥珀辉光）。
      - 左/右裁切手柄：**宽 12pt 通高**，琥珀底（左圆角 4 / 右圆角 4），中央 2×16 凹槽 `#1C1917`；`ew-resize`，shadow-md。
      - 播放头：选区正中，**1.5pt 白线**通高 + 白色辉光 8pt；顶部 10×8 小三角。
    - 右未激活段 **25%**：同左段规格。
  - 三段宽度对应 0:00–0:12 / 0:12–0:24 / 0:24–0:32（源片总时长 **0:32**）。
- 时间刻度行：flex 四点，10pt **mono** muted；选区两端刻度为琥珀 medium：`0:00 / 0:12 / 0:24 / 0:32`。
- 预设 chips 行 `gap=8 pt=2`：
  - 选中 chip「错误热点前后各2小节」：**flex-1**（弹性占满剩余宽），`py=8 px=10`，圆角 **8pt**，bg 琥珀 15% + 边框琥珀，12pt medium 琥珀字，前置琥珀圆点；按压缩放 0.95。
  - 「整段」「手动」：固定宽（`px=14`，同高），bg `#1E1B19` + border，12pt muted；hover text（旧 spec"自定义"真值为「**手动**」）。

### 3.5 提问上下文行
- 全宽，bg `#1E1B19` + border，圆角 **12pt**，`px=12 py=10`，flex 两端。
- 左：`chat_bubble_outline` 18pt 琥珀 + 12pt muted 截断文本：「提问：<text 色>第21小节的转指手型</text>」。
- 右编辑钮：约 28pt 热区，`edit` 16pt muted → hover 琥珀。

### 3.6 服务商披露卡
- bg `#1E1B19`，**左 2pt 琥珀竖边**，右侧圆角 **12pt**（左侧无圆角），`p=14 space-y=12`。
- 文案行：`verified_user` 17pt 琥珀 + **12pt** muted / relaxed：
  「服务商：火山方舟（字节跳动）· 视频将上传至其服务器用于本次分析，不会用于训练你的账号之外的用途」。
  - 注意：真值将服务商**写死为火山方舟**，与旧 spec/红线"链路实时命中、不写死"冲突 → **待产品确认**；施工先按真值文案，接入时必须改为运行时命中名。
- 开关行：顶边 border 70%，`pt=8`，两端对齐。
  - 标签 12pt medium text「分析后删除云端视频（推荐）」。
  - **开关：40×20 全圆角，ON=琥珀底**（非绿色！旧 spec"success 绿"错误），`p=2`；滑块 **16×16 正圆 bg `#1C1917`**，shadow-md；200ms 位移动画。

### 3.7 CTA 区（space-y=8）
- 主 CTA：全宽，**`py=14`**，bg 琥珀（hover `#E8C882`），文字 bg 色 **14pt semibold**，圆角 **12pt**，`send` 18pt 图标，amber-glow + shadow-lg，按压缩放 0.99。文案「确认裁切并发送」。
- 「取消」：全宽文字钮，`py=6`，12pt muted（hover text）。
- 安全脚注：居中 11pt `#6E6760` tracking-wide：「PianoSempai 自己不存储任何视频副本」。
- home indicator：128×4 `#443D37` 全圆角，居中（`pt=12`）。

## 4. 全部状态

| 状态 | 表现（真值） |
|---|---|
| 默认展开 | 选中区间 0:12–0:24、预设选中"错误热点前后各2小节"、删除开关 ON |
| 拖手柄 | `ew-resize`，区间 badge/刻度实时更新（最小时长 2s、行内红字报错为旧 spec，HTML 无 → 待产品确认） |
| 未选预设 chips | hover 字变 text |
| 开关 OFF | 真值未画 OFF 态及"云端保留"红字 → 待产品确认 |
| 上传中进度态 / 可取消 / 失败重试 / 完成后"云端片段已删除" | HTML 未呈现 → 待产品确认（旧 spec 有，保留逻辑但需补视觉稿） |

## 5. 交互热区

- scrim/背景：`pointer-events-none`（点背景不关闭——关闭仅 ✕/取消；下滑关闭行为待产品确认）。
- ✕ 32×32、取消全宽 h≈32、编辑钮 28 热区。
- 双手柄：12pt 宽 × 52pt 高（实际触摸热区应外扩至 ≥44 高）。
- 播放头为展示元素，非热区（真值如此；是否可拖动待产品确认）。
- 3 个预设 chips 高 ≈33（触摸热区按 44 兜底）。
- 开关 40×20；CTA 全高 ≈49。

## 6. 与旧 spec 的主要差异（施工必改）

1. **开关颜色**：旧"ON=success 绿"；真值 **ON=琥珀 `#D4A24E`**，深色滑块。
2. **Sheet 高度**：旧 70%；真值顶部仅留 **74pt（≈91% 高）**，顶部圆角 **28pt**。
3. **区间 badge 无文件大小**；真值仅「已选 0:12–0:24（12秒）」，琥珀 10% 底 + 30% 边。
4. **胶片轨**给出精确结构：62pt 容器/52pt 内轨、37.5%/37.5%/25% 三段、12pt 手柄、中置白线播放头、`#F3BE67` 亮波柱 + amber-glow——旧 spec 全部缺失。
5. 预设第三项真值为「**手动**」非"自定义"；选中 chip flex-1。
6. 服务商文案真值写死「火山方舟（字节跳动）」，与"实时命中"红线冲突，标待产品确认，不得当成最终实现文案。
7. 脚注/卡片/背景的全部色值、圆角、字号旧 spec 缺失，以第 2、3 节为准。
