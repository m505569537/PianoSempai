# Nocturne Minimal · PianoSempai 视觉基座（Foundation）

- 项目：PianoSempai（Stitch project `4122205180823255125`）
- Stitch 设计系统：`assets/f7597603e13249e3bcf37960533ffb92`（displayName: Nocturne Minimal, version 1）
- 基准屏：sample-A 夜琴房 `93a55fdf0f954a59bcc8c314b0c98d16`（2026-09-18 用户拍板）
- 目标设备：iPhone 16 Pro / iOS 17+，竖屏 390 × 844 pt，full-bleed，安全区适配（刘海/灵动岛 + Home indicator）
- 本文档是**所有画布级 spec 的共享视觉真值**。各屏 spec.md 只写本屏布局/组件/状态，token 值一律引用本文档，不得另立色板。

> 真值来源：Stitch designMd（MCP 导出全文）+ 基准屏 code.html DOM（viewport 390×844 已核验）。
> 色彩语义：暖炭/夜色是物理材质隐喻（铸铁琴板、毛毡、玫瑰木、琥珀指示灯），不是纯黑科技风。

## 1. 色板（SwiftUI Color asset 命名建议）

| token | hex | 用途 |
|---|---|---|
| canvas / background | `#1C1917` | 根背景（暖炭；设计系统内另有 surface `#161311` 更深一档，用于浮层底下的压暗区） |
| card / surface-container | `#262220`（系统 `#221F1D`） | 一级卡片、分组容器 |
| card-elevated / surface-high | `#2D2724`（系统 `#2D2927`） | 激活卡、hover/pressed、弹层、浮起 dock |
| sheet-top | `#383432` | 最高层级表面（modal 头部等） |
| border | `#332D29` | 卡片 1px 发丝边（等效 rgba(212,162,78,0.10~0.16)） |
| border-input | `#3D3531` | 输入框、滑块轨道未填充 |
| primary / amber | `#D4A24E`（系统 primary `#F3BE67`） | 主按钮填充、当前态、光标、关键数值；其上文字用深色 `#1C1917` |
| primary-bright | `#E8C882` | hover/微交互高亮、badge、focus ring |
| primary-dim | `#8C6A38` | 次级琥珀、未激活轨道、低优先高光 |
| text-primary | `#F5F2ED`（系统 on-surface `#E9E1DD`） | 标题、主文本 |
| text-body | `#C2BCB4` | 正文次级 |
| text-muted | `#9C948B` | 时间、索引、label、副文案 |
| success | `#7FA97C` | 已连接、通过、达标、ON 开关 |
| danger | `#C97064`（系统 error `#FFB4AB` 仅用于深底小图标） | 断连、强开警示、错误、删除 |
| compare-b | `#8FA3B8` | 双 take 对比中 B（旧次）专用蓝灰，全局仅此一处使用 |
| score-paper | `#F5F0E6` 底 + `#1C1917` 符头 | 五线谱用纸白墨黑，保证读谱对比，不做反色 |

语义辅助：
- 琥珀 8% 描边 = `rgba(212,162,78,0.08)`；激活浮层描边 = `rgba(212,162,78,0.18)`。
- 遮罩 scrim：`rgba(12,10,9,0.6)`，modal/drawer 底；重要弹层可加 `0 8px 32px rgba(12,10,9,0.6)` 暖色底辉（不用冷色投影）。
- 雷达/热力的"空"网格用 `#332D29`，数据序列 A=琥珀、B=蓝灰、danger=红。

## 2. 字体

- 标题/数字展示：Noto Serif（回退 PingFang SC / Noto Serif SC / serif）。用于 display、headline、屏级标题、报告大分。
- 正文/标签/数据：Noto Sans（回退 PingFang SC / Noto Sans SC / sans-serif）。
- 数字一律 `font-variant-numeric: tabular-nums`（等宽数字，BPM/ms/分数/时间）。
- 节奏符号用 ♩= ，不要被渲染成乱码（Stitch 曾把节拍器小字画糊，实现用 SF Symbol / 文本而非图片）。

| 级别 | 字级/行高 | 字重 |
|---|---|---|
| display-lg（手机） | 32/40，tracking -0.01em | 400 serif |
| headline-lg（手机） | 24/32 | 400 serif |
| headline-sm | 20/28 | 500 serif |
| title-md | 16/24，tracking 0.01em | 500 sans |
| body-lg | 16/26 | 400 sans |
| body-md | 14/22 | 400 sans |
| body-sm | 12/18 | 400 sans |
| label-md | 12/16，tracking 0.06em | 500 sans |
| label-sm | 11/14，tracking 0.08em | 500 sans |

拉丁标题可微负字距；中文标题靠字重与字间留白，不压缩字距。

## 3. 间距与圆角

- 外边距 guttering：手机 20px（设计系统 margin-sm 1.25rem），卡间 gutter 16px。
- 内部尺度：xs 4 / sm 8 / md 16 / lg 24 / xl 40。
- 圆角：sm 4px（输入框、tag、滑块头）；DEFAULT/md 6px；lg 8px（卡片、sheet、专辑/谱面容器）；xl 12px（高浮层菜单、FAB 胶囊、底部 dock）；full 9999（胶囊 chip、开关、圆形按钮）。
- 形状语法克制（roundedness 低），不要大圆角软糖风。

## 4. 海拔（不用冷色模糊投影）

1. canvas `#1C1917`
2. card `#262220` + 1px `#332D29`
3. elevated `#2D2724` + 1px rgba(212,162,78,0.18) + 暖色底辉
4. 所有面板可加 inset 顶部 1px rgba(255,255,255,0.04) 模拟顶光（可选）

## 5. 全局组件视觉规范

**主按钮 Primary**：填充 `#D4A24E`，文字 `#1C1917` bold，圆角 8（卡片内）/12（底部固定 CTA），高度 50，全宽；pressed 亮到 `#E8C882` + 16px 25% 琥珀辉光；disabled 填充 `#3D3531` 文字 `#9C948B`。
**次按钮 Secondary**：透明底 + 1px rgba(212,162,78,0.3) + 文字 `#C2BCB4`；pressed 描边变 0.7 琥珀、底变 `#262220`。
**幽灵按钮 Ghost**：无底，文字 `#C2BCB4`，pressed 变琥珀。
**危险按钮**：文字/描边 `#C97064`，不使用满填充大红（除删除确认按钮可实心 `#C97064` + `#1C1917` 字）。

**卡片**：`#262220` + 1px `#332D29`，圆角 8，内边距 16；可按下行 pressed 底 `#2D2724` + 左缘 2px 琥珀。
**列表行**：行间 1px 发丝分割（同卡片底色，不要高对比灰线）；左列可放 tabular 索引（muted），右列放数值/时间/chevron。

**Chip/筛选项**：full 圆角；未选 = surface-low 底 + body 字色；选中 = 琥珀底 + `#1C1917` 字。
**单选/复选**：16px 框，4px 圆角，`#262220` 底 + rgba(212,162,78,0.25) 边；选中琥珀填充 + 深色对勾/圆点。
**输入框/多行**：`#262220` 底 + 1px `#3D3531`，文字 `#F5F2ED`，占位 `#9C948B`；focus 边琥珀 + 1px 琥珀光环。
**开关**：ON 琥珀（或 success 绿用于"推荐/安全"项），OFF `#3D3531`。

**滑块/进度条**：轨道 2–4px `#3D3531`，填充琥珀，端头 8–10px `#F5F2ED` 带琥珀芯。
**热力条**：按强度从 `#3D3531` → 琥珀 → `#E8C882`；最热小节可加红 `#C97064` 仅在"错误热点"语境。
**波形/音符微可视化**：未触发竖线 `#3D3531`，触发 `#D4A24E`。

## 6. 全局导航（App Frame，详见 S06 spec）

- 底部 5 tab，顺序与中文标签**写死**：`今日 / 曲库 / 练习室 / 档案 / 我的`。图标：日历 / 翻开的乐谱书 / 钢琴键盘 / 档案(历史时钟-归档盒，非奖杯非商店) / 头像。激活 = 琥珀图标+文字 + 顶部小圆点；未激活 = muted。
- 「问 Neko」FAB：独立悬浮于 tab 栏**上方**偏右（不进 5 tab），猫脸线稿 + 胶囊"问 Neko"，elevated 琥珀描边；任何页不得让它压住主 CTA（被压时该页隐藏或上移 CTA）。
- 顶部连接状态胶囊：右上线框胶囊，已连接=绿点+"特伦斯 V70 已连接"；未连接=红点+"未连接"；断连瞬间切红横幅态（见 S11-disconnected）。
- 二级页/弹层/全屏流程页**不带底部 tab**（welcome/权限/向导/练习室/报告/弹层/对比/月报/设置内页等）。

## 7. 五线谱渲染区（强约束）

- 设计稿里的五线谱是**视觉示意**。实现必须由真实记谱引擎渲染（M2：首选 swift-sheet-music，失败退 OSMD WKWebView），数据来自 MusicXML/.mscz/.mid，禁止用 AI 位图当谱面。
- 谱区底色用纸白 `#F5F0E6`、符头/线用墨黑 `#1C1917`；当前小节琥珀高亮（`#D4A24E` 25% 底 + 琥珀小节框）；错误热点小节可加淡红底；光标用琥珀细线。
- 谱号、调号、拍号、小节号、连音线/指法数字由引擎绘制；字号在引擎主题里对齐 label-sm/body-sm。

## 8. 动效与语气

- 动效缓、短（150–250ms，ease-out），仅用于状态切换/弹层进出场/光标；无弹跳、无彩带、无幼稚卡通。
- 庆祝克制：达标可用一次轻琥珀辉光/勾选，不做 confetti。
- 文案语气温柔但守门坚决（红线 6）；断练/弱表现只陈述事实，禁用 guilt trip 句式。

## 9. 文案锁定（Stitch 多次走样，实现必须以本表为准）

Stitch 出图系统性随机改写以下文案，SwiftUI 直接写死中文字面：

1. 5 tab = 今日 / 曲库 / 练习室 / 档案 / 我的。**永不出现**：商城、商店、市场、社区、榜单、收藏、统计、训练营、电子琴 等任何替代词。
2. 今日三段任务卡固定术语：热身 / 主菜 / 奖励曲。
3. S11 节拍器控件标签 = "节拍器"（不是 MNOME/metronome 图）；S11 错误热点高亮小节 = **21**（样图误亮 19，以数据为准）。
4. S13 报告脚注 = "对齐置信度高 · 踏板已计入判分"（不是"解答已计入得分"）；示例 take 时长 = 2分14秒。
5. 强开弹层周报称呼 = "Neko 周报"（不是 Meiko/周报以外的名字）。
6. S22 Neko 观察中速度 = "主菜速度不要超过 ♩=76"（样图一处作 70，以 76 为准）。
7. 空状态定级内容 = "自评 1 分钟 + 视奏 2 段 + 力度校准 2 分钟"；连接胶囊 = "特伦斯 V70 已连接"（不是"特权版 V10 已配置"等幻觉）。
8. 设备名全应用统一 "特伦斯 V70"；供应商统一 "火山方舟"；模型文字 "doubao-seed-2.0-pro（文字/数据）" 与 "豆包视觉理解（视频帧）"。
9. 手型免责两句必须逐字可达："手型观察仅供参考，永远不会影响过关；单摄有死角，看不清的我会直接说。"
10. 弱总分脚注："综合分仅参考，过关只看连续达标的硬指标。"

## 10. 本 spec 的覆盖范围

本文档只定义跨屏共享的视觉 token 与全局组件。每屏的布局结构、本屏组件清单、本屏交互态见 `design/reference/screens/<Sxx-slug>/spec.md`。
系统层（数据模型/状态机/跳转/API/课程规则）不在本层，见 `docs/design/` 下页面导航级文档与 `PRD.md`。
