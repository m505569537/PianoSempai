# S06 全局导航骨架 App Frame（线框真值修订版）

- 真值来源：Stitch `code.html`（线框稿，390 × 844 逻辑画布；外层桌面画布 2560×2048，居中展示）
- Status: Revised（布局/尺寸/色值以 code.html 为真值；旧 spec 中与 html 不符处已修正，旧 spec 独有的产品规则保留并标注）

## 用途一句话

定义 5 tab + 问 Neko FAB + 顶部 MIDI 连接胶囊的全局骨架；本屏是线框占位稿，内容块以各 tab 正稿为准。

## 画布与设备外壳（仅线框演示用，App 内不实现）

- 桌面衬底色：`#12100E`；body flex 居中。
- 设备容器：390 × 844 pt，`rounded-[50px]`（外壳圆角 50），`border-[8px]` 边框色 `#2A2624`，`shadow-2xl`，`overflow-hidden`。
- 容器底色：`#1C1917`（app 主背景 token `bg`），默认文字色 `#F5F2ED`。
- 真实 App 落地：以 390 逻辑宽满屏实现，不画外壳/圆角/边框。

## 布局结构（自上而下，flex-col justify-between）

### 1. 状态栏（z-30，shrink-0）

- 内边距：`pt-3` = 12pt 顶，`px-7` = 28pt 左右。
- 左侧时间「9:41」：15pt，semibold(600)，`tracking-tight`，`#F5F2ED`，`ml-1`。
- 灵动岛：112 × 26pt（`w-28 h-[26px]`），纯黑 `#000000`，full 圆角，绝对定位水平居中、`top-2.5` = 10pt。
- 右侧系统图标组：蜂窝 / Wi-Fi（各 16pt SVG）+ 电池：外框 22 × 11pt，边框 1pt `#F5F2ED`，圆角 3，内芯圆角 1.5；电池凸点宽 1.5、高 4，间距 1。全部 `#F5F2ED`，图标间距 8pt。

### 2. 顶部导航区（shrink-0）

- 内边距：`px-6` = 24pt，`pt-5` = 20pt，`pb-3` = 12pt；`flex justify-between items-end`。
- 页面标题「今日」：Noto Serif SC，`text-3xl` = 30pt，semibold(600)，`tracking-tight`，`#F5F2ED`。
- MIDI 连接胶囊（右）：
  - 容器：`px-2.5` = 10pt、`py-1` = 4pt，`bg-[#262220]`，1pt 边框 `#332D29`，full 圆角，`shadow-sm`。
  - 状态点：6 × 6pt（`w-1.5`），full 圆角，`bg-[#D4A24E]`，`animate-pulse`（线框稿为琥珀点；非绿点）。
  - 文案「已连接 · 特伦斯 V70」：11pt，regular(400)，`#9C948B`，`tracking-wide`。

### 3. 主内容滚动区（flex-1）

- `main`：`px-5` = 20pt，`py-2` = 8pt，`flex flex-col gap-4` = 16pt 行距，`overflow-y-auto`。
- 三块占位卡结构完全一致（外卡 + 内嵌虚线框）：
  - 外卡：`bg-[#262220]`，1pt 边框 `#332D29`，`rounded-2xl` = **16pt 圆角**，`p-2.5` = 10pt。
  - 内嵌框：1pt **虚线**边框 `#3A332E`，`rounded-xl` = 12pt，`bg-[#211E1C]/60`（60% 透明），居中。
  - 占位文字：14pt，medium(500)，`tracking-wider`，`#9C948B`。
  - 高度：
    - 块1「占位 · 本周打卡」：`h-32` = **128pt**
    - 块2「占位 · 今日任务」：`h-44` = **176pt**
    - 块3「占位 · 开始练习」：`h-24` = **96pt**

### 4. FAB「问 Neko」（绝对定位，z-40）

- 位置：`right-5` = 20pt，`bottom-[98px]` = 距底部 98pt（tab bar 顶缘之上约 16pt）。
- 形态（真值）：**56 × 56pt 纯圆形图标按钮**（`w-14 h-14 rounded-full`），无线框稿中无「问 Neko」文字。
- 材质：`bg-[#262220]`，**2pt** 描边 `#D4A24E`（`border-2`），文字/图标 `#D4A24E`，`shadow-lg`。
- 猫脸图标：28pt（`w-7`），线性 SVG，`stroke-width 1.8`，round 端点/转角；眼睛为实心琥珀点。
- 交互：`active:scale-95`，transition-transform。`aria-label="问 Neko"`。

### 5. 底部 Tab Bar（shrink-0，z-30）

- 材质（真值）：`bg-[#211E1C]/90`（90% 不透明）+ **`backdrop-blur-md`**（材料模糊，半径约 12 一档），顶部 1pt 边框 `#332D29`。
- 内边距：`pt-2` = 8pt，`pb-7` = **28pt**（ Home Indicator 区），`px-3` = 12pt。
- Tab 布局：`grid grid-cols-5` 等宽，每 tab `flex-col items-center gap-1` = 图标/文字间距 4pt。
- 图标：20pt（`w-5`）线性，`stroke-width 1.8`；文字 11pt，`tracking-tight`。
- 状态：
  - 激活（今日）：图标+文字 `#D4A24E`，文字 medium(500)。
  - 未激活：`#9C948B`，文字 regular；`hover`（桌面态）变 `#F5F2ED`，150ms 过渡。
- 五 tab 顺序与图标写死：今日（日历）/ 曲库（翻开的书）/ 练习室（钢琴键盘）/ 档案（柱状图线稿）/ 我的（头像）。**第 4 tab 是「档案」**——Stitch 历史上画成商城/社区/榜单等全部作废。
- Home Indicator：128 × 4pt（`w-32 h-1`），`bg-[#F5F2ED]/30`，full 圆角，`mt-4` = 16pt，居中。

## 颜色 Token 总表（本屏全部色值）

| Hex | 语义 token | 使用位置 |
|---|---|---|
| `#12100E` | page-backdrop | 桌面画布衬底（App 不实现） |
| `#2A2624` | device-bezel | 设备外壳 8pt 边框（App 不实现） |
| `#1C1917` | bg / app-background | 设备容器底色（App 主背景） |
| `#262220` | card | 占位卡外卡、MIDI 胶囊、FAB 底 |
| `#211E1C` | surface-deep | 占位内框（/60）、tab bar（/90） |
| `#332D29` | card-border | 卡片/胶囊/tab bar 1pt 边框 |
| `#3A332E` | placeholder-dashed | 占位内框虚线边 |
| `#D4A24E` | amber（品牌强调色） | FAB 描边与图标、连接点、激活 tab |
| `#F5F2ED` | text-primary | 标题、时间、系统图标、Home 指示（/30） |
| `#9C948B` | text-muted | 占位文字、胶囊文案、未激活 tab |
| `#000000` | dynamic-island | 灵动岛 |

## 字体

- 中文标题：Noto Serif SC（serif token），30pt semibold（页标题）。
- 其余：Noto Sans SC（sans token），11–15pt。
- iOS 落地映射：serif → `Font.system(.serif)` 或项目自定 Songti/Noto Serif SC 字体包；sans → SF Pro / 项目 Noto Sans SC。

## 交互热区

- 5 个 tab：每格宽 = (390 − 24) / 5 = 73.2pt，热区含图标+文字整体。
- FAB：56pt 圆形热区，距底 98pt、距右 20pt。
- MIDI 胶囊：仅状态展示（线框稿未定义点击行为）。
- 占位卡：无交互（线框）。

## 与旧 spec 的主要差异（修正点）

1. **Tab bar 底色错误**：旧 spec 写 `#1C1917`，真值为 `#211E1C/90` + `backdrop-blur-md`。
2. **FAB 形态错误**：旧 spec 写「elevated 胶囊 + 猫脸 18pt + 问 Neko 文字」，真值为 **56pt 纯圆形图标按钮、2pt 琥珀描边、无文字**（带文字的胶囊 FAB 出现在 S07b，勿混用）。
3. **连接点颜色**：线框稿状态点为琥珀 `#D4A24E`；旧 spec「已连接=绿点」属产品规则（绿点版见 S07b），本线框以 html 为准，两种连接态配色待产品确认后统一。
4. 旧 spec ASCII 图把日期行放在状态栏位置，且缺灵动岛/设备外壳；已按真值重写。
5. 补充占位卡精确高度（128/176/96）、双层圆角（外 16/内 12）、虚线内框等全部遗漏数值。
6. 补充 tab bar `pb-7` = 28pt 安全区、Home Indicator 128×4、图标 20pt / 文字 11pt。

## 保留的旧产品规则（html 中无，待产品确认，勿删）

- MIDI 未连接=红点 + muted 文字；断开练习时升级为顶部全宽红横幅（见 S11）。
- FAB 在全屏练习室/视频播放/弹层页面隐藏或让位。
- 今日/练习室 tab 未连接设备时主 CTA disabled + 引导去 S03。
- 切 tab 150ms 变色、无 tab 栏页面清单（S01–S05、S11+ 等）。
