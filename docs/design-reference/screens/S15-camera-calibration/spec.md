# S15 机位校准向导（修订 spec · 以 code.html 为真值）

- Screen ID: `5ff50453a5034683abed09338c79ee56`（本批唯一 MOBILE 元数据，780×1768，即 390×884 @2x）
- 真值文件：Stitch code.html
- 画布基准：容器 390 逻辑宽，`min-height:884pt`（含 100dvh 兜底），1px = 1pt
- 展示步：Step 2「取景」
- Status: Final（本文件取代旧 spec）

## 用途一句话

主动录像前置的 4 步向导（摆放/取景/试录/完成）：实时预览 + 琥珀取景框 + 手部骨架 + 检测 chips，引导用户把手机摆到能看见手的位置；底部可跳过。

## 颜色

本屏 config 为完整 Material 3 风格调色板（命名与其他屏不同，映射时注意）。本画布实际使用的 token：

| Token | 值 | 用途 |
|---|---|---|
| `background` / `surface` / `surface-dim` | `#161311` | M3 底色（config 体系） |
| 页面真实底色 | `#1C1917` | body/容器（内联） |
| `surface-container-lowest` | `#100e0c` | 预览底部暗角 |
| `surface-container-low` | `#1e1b19` | — |
| `surface-container` | `#221f1d` | 免责卡底 |
| `surface-container-high` | `#2d2927` | 底部警告条底 |
| `surface-container-highest` / `surface-variant` | `#383432` | — |
| `surface-bright` | `#3c3836` | — |
| `primary` / `primary-fixed-dim` / `surface-tint` | `#f3be67` | M3 主色（本画布正文未直接用，主视觉用 #D4A24E） |
| `primary-container` | `#d4a24e` | **实际主琥珀**（与全局一致） |
| `secondary` / `secondary-fixed-dim` | `#eac085` | — |
| `tertiary` / `tertiary-fixed-dim` | `#e2c37d` | — |
| `tertiary-container` | `#c5a764` | — |
| `outline` | `#9c8f7e` | — |
| `outline-variant` | `#4f4537` | 未来步圆点边框 |
| `on-surface` / `on-background` / `inverse-surface` | `#e9e1dd` | — |
| `on-surface-variant` | `#d3c4b2` | — |
| `error` | `#ffb4ab` | M3 error（未用） |
| `error-container` | `#93000a` | — |

config 中其余 on-*/fixed 色（`#442b00 #604100 #563900 #3f2e00 #690005 #7e5703 #251a00 #614415 #432c00 #ffdead #513c02 #5e4113 #291800 #ffddb2 #ffdad6 #ffdf9a #594409 #281900 #dbb279 #5e4113`）本画布正文未使用，作为 M3 完整令牌保留备查。

内联 hex（画布真正渲染的颜色）：

| Hex | 位置 |
|---|---|
| `#1C1917` | body 底色、chip/图标小盒底、取景标签底 |
| `#F5F2ED` | 主文字、骨架连线、部分关节点 |
| `#9C948B` | 次级文字、步骤文字 |
| `#332D29` | 卡片边框、分隔线、按钮边、home 条 |
| `#D4A24E` | 琥珀：步骤点/取景框/警告/骨架点、主按钮 |
| `#4f4537` | 步骤 3/4 未来圆点边框 |
| `#141210` | 相机预览底 |
| `#100E0C` | 预览底部渐隐暗角 |
| `#262220` | 提示三行卡底色 |
| `#221E1B` | 免责卡底 |
| `#2D2724` | 预览底部警告条底（90%） |
| `#7FA97C` | 绿色通过：键盘可见 chip |
| `#DCD7D0` / `#E5E0DA` | 假白键（交替两种白） |
| `#201D1A` | 假黑键 |
| `#3D3531` | 假黑键底边 |
| `rgba(212,162,78,0.05)` | 骨架掌心填充 |
| `rgba(212,162,78,0.25)` | 免责卡边/警告条边 |
| `rgba(212,162,78,0.35)` | 当前步骤点发光 |
| `rgba(212,162,78,0.5)` | 取景框虚线、警告条边 |

字体：

- 标题 serif：**`"Noto Serif SC"`**（headline/display）
- 正文/label：**`"Noto Sans SC"`**（注意：本屏正文是 Noto Sans SC，不是 Plus Jakarta/Inter）
- 图标：Material Symbols Outlined（FILL0 wght350，1.15rem）

config 字号令牌（施工可直接引用）：display-lg-mobile 32/40 −0.01em；display-lg 48/60 −0.02em；headline-lg 32/42 −0.01em；**headline-lg-mobile 24/32**（本屏 H1 实际渲染）；headline-md 24/32；headline-sm 20/28；title-md 16/24 0.01em 500；body-lg 16/26；**body-md 14/22**；**body-sm 12/18**（本屏正文）；label-md 12/16 0.06em；**label-sm 11/14 0.08em**（步骤/小标签）。
config borderRadius：DEFAULT 2pt / lg 4pt / xl 8pt / full 12pt（即本屏圆角整体偏小，别套用其他屏的 16pt 卡圆角）。

## 页面结构

```
容器（390 满宽，px16 pt12 pb24，flex col justify-between）
├ 上区
│   ├ 状态栏
│   ├ 4 步进度条
│   ├ 标题区
│   ├ 相机预览卡（4:3）
│   ├ 三行提示卡
│   └ 免责卡
└ 底部操作（双按钮 + home 条）
```

### 1. 状态栏

px4，pt4 pb12，12px muted：左「9:41」13px medium `#F5F2ED`；右三图标（signal_cellular_4_bar 14、wifi 14、battery_full 16）opacity .8。

### 2. 4 步进度条（pt4 pb16）

- 行容器 px8，label-sm 11px tracking-wider，flex between：
  - Step1「摆放」完成态（整组 opacity .6）：16pt 圆点，1pt 边 amber 50%，内「✓」9px amber；字 muted
  - 连接线：24×1pt `#332D29`（共 3 段）
  - Step2「取景」当前态：16pt 圆点**实心 amber**，内「2」10px bold `#1C1917`，发光 `0 0 8px rgba(212,162,78,.35)`；字 `#F5F2ED` medium
  - Step3「试录」/ Step4「完成」未来态（opacity .4）：16pt 圆点 1pt 边 `#4f4537`，数字 9px
- 注意：真值**没有「‹ 退出」按钮**（旧 spec 示意有）；退出入口待产品确认。

### 3. 标题区（px4 pt4 pb16）

- H1「让手机能看到你的手」headline-lg-mobile **24pt** Noto Serif，regular tracking-tight，mb6pt
- 副文 body-sm **12pt** muted/relaxed：「你只需要跟着画面挪手机，不用记任何规则。」

### 4. 相机预览卡（核心）

- 容器：满宽 **aspect 4:3**（390−32 = 358 × 268.5pt），圆角 8pt（config xl），底 `#141210`，1pt 边 #332D29，shadow-2xl，p 14pt，overflow-hidden，relative
- 背景模拟层（absolute inset-0，opacity .85）：
  - 上下渐隐遮罩：`#1C1917` 70% → 透明 → `#100E0C` 90%
  - 扫描光束：h56pt 纵向条，`translateY(-100%→1000%)` **8s 线性循环**，中段 amber 5%
  - 透视键盘（底部 h128pt，整体 opacity .4）：13 个白键（24pt 宽、h112，交替 `#DCD7D0/#E5E0DA`，底圆角 2pt，间距 2pt）；黑键行 h64 × 14pt 宽 `#201D1A`（间距 10pt，底 1pt 边 `#3D3531`，底圆角 1pt）
- 手部骨架 SVG（absolute，viewBox `360×270`，z10，opacity .7）：
  - 普通骨骼连线 `#F5F2ED` 1.2pt round；掌心路径填充 amber 5%
  - 拇指/食指/中指/无名指四指路径；**小指路径用 amber 1.6pt**（漂出框外）
  - 关节点 amber r2–2.5；指尖点 `#F5F2ED` r2.5
  - 小指尖 (294,132)：amber r3.5 点带 `animate-ping` + 实心 r2.5 底点
- 取景框（absolute，inset-x32，top28 bottom48）：1pt **虚线** amber 50%，圆角 12pt，z20；内含：
  - 四角：14×14pt **2pt 实心琥珀** L 形角标
  - 中置标签：底 `#1C1917` 80% + `backdrop-blur(md)`（~16pt），1pt 边 amber 25%，px8 py2，10px label-sm amber，tracking-widest 大写：「手部区域」
- 检测 chips（相对定位 z30）：
  - 顶部通过 chip：左对齐，胶囊，底 `#161412` 85% + 背景模糊，1pt 边 `#7FA97C` 40%，字 `#7FA97C` 11px medium，px10 py4；「✓」12px bold +「键盘完整可见」
  - 底部警告条：满宽，底 `#2D2724` 90% + 模糊，1pt 边 amber 50%，px10 py6，圆角；flex between：
    - 左 11px amber medium：6×6pt 琥珀点（**2.4s gentlePulse**：opacity .9→.45、scale 1→.98）+「⚠ 指尖略出框，请向左转一点」
    - 右 `rotate_left` 15px amber opacity .8

### 5. 三行提示卡（mt14）

- 容器 bg `#262220`，圆角 **12pt**，1pt 边 #332D29，px12；行间分隔 1pt #332D29 60%
- 每行 py10，gap10：
  - 图标盒 24×24pt，底 `#1C1917`，1pt 边 #332D29，圆角 4pt；图标 14px amber：`videocam` / `menu_book` / `timer`
  - 文案 12px（body-sm）`#F5F2ED` leading-tight：
    1. 「手机架在琴右侧，镜头朝键盘」
    2. 「不用买支架，靠在谱架上就行」
    3. 「每次校准 30 秒，只在你主动录像时需要」

### 6. 免责卡（mt12）

- bg `#221E1B`，圆角 8pt，1pt 边 **amber 20%**，p10，flex gap8
- `info` 15px amber 80%
- 文案 11px Noto Sans SC muted，行高 17pt，逐字：
  「单个摄像头有死角：手掌遮挡、触键深度永远无法判断，手型建议不会影响过关。」

### 7. 底部操作区（pt16，mt-auto）

- grid-cols-2 gap10：
  - 「跳过，直接试录」：py12，圆角 **8pt**，透明底、1pt 边 #332D29，13px body-md medium muted；hover 字主色 + 边 amber 40%；active scale .98
  - 「按建议调整」：py12，圆角 8pt，底 `#D4A24E`（hover `#E8C882`），字 `#1C1917` 13px medium；发光 `0 0 16px rgba(212,162,78,.25)`
- home 条：128×4pt `#332D29` 全圆角，居中 mt16 opacity .5

## 全部状态与交互热区

| 元素 | 热区 | 状态 |
|---|---|---|
| 步骤点 | 非按钮（指示用） | 完成 .6 / 当前实心发光 / 未来 .4 |
| 预览卡 | — | 扫描光束 8s 循环；小指 ping 脉冲；警告点 2.4s 脉冲 |
| 通过 chip | 展示（html 未绑事件） | 绿 |
| 警告条 | 展示 | 琥珀脉冲；rotate_left 是否可点待产品确认 |
| 跳过 / 按建议调整 | 各半宽 ≥48pt 高 | hover / active scale .98 |

全通过后（键盘完整 / 双手在框 / 指尖不切边）主按钮文案变「下一步：试录」；step1 摆放静态示意、step3 5 秒试录回放、step4「机位已记住」不自动开录；任何步可跳过。以上沿用旧 spec 流程描述（html 仅画 step2，无矛盾）。

## 相对旧 spec 的主要修订

1. 顶部真值**无退出按钮**；状态栏为 9:41 + 图标，4 步条直接其下。
2. 步骤点尺寸/状态精确化：16pt 圆点；完成=琥珀描边 ✓（opacity .6）、当前=实心 amber 黑字 + 8pt 发光、未来=边 `#4f4537`（opacity .4）；连接线 24pt 宽 #332D29。
3. H1 真值 **24pt**（旧 spec 未给字号）；正文字体 **Noto Sans SC 12pt**（旧 spec 无字体）。
4. 预览比例真值 **4:3（358×268.5pt）、圆角 8pt、底 #141210**；旧 spec「16:9 或 4:3」取 4:3。
5. 取景框真值：虚线 1pt amber 50%、圆角 12pt、inset-x32/top28/bottom48；四角是 **14pt 2pt 实心角标**；标签「手部区域」带模糊底。旧 spec「2pt 虚线」改 1pt。
6. 骨架：真值**连线为白色 1.2pt、关节点琥珀**（旧 spec「绿连线」错误——本屏没有绿色骨架，绿仅用于通过 chip）；小指 amber 1.6pt + ping 点。
7. chips 位置真值为**预览内左上（绿胶囊）+ 底部通栏警告条**（旧 spec 说左下）；警告文案「⚠ 指尖略出框，请向左转一点」+ rotate_left 图标；绿 chip 色 `#7FA97C`。
8. 三行提示：真值为带分隔线的单卡、24pt 方形图标盒（videocam/menu_book/timer），文案逐字更新（含「不用买支架，靠在谱架上就行」）。
9. 免责卡：底 `#221E1B`、边 amber 20%、圆角 8pt；文案真值含「**触键深度永远无法判断**」，旧 spec 文案过简。
10. 底部按钮圆角真值 **8pt**（非 12），高度 py12（~48pt）；补主按钮发光参数。
11. 新增 M3 完整色板与字号令牌清单（config 真值）。

## 红线落点

- 相机只在主动流程内使用；免责声明常驻本屏。
- 「手型建议不会影响过关」逐字保留；单摄死角（手掌遮挡、触键深度）明说。
