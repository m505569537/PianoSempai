# S08b 乐谱导入失败（居中 Dialog·真值修订版）

- 真值来源：Stitch `code.html`（body 固定 390 × 844，overflow hidden）
- Status: Revised

## 用途一句话

MusicXML/.mxl/.mscz/.mid 解析失败时，居中 dialog 给出错误位置、错误代码、文件信息、格式说明与三条出路；不静默跳过、不把失败文件塞进曲库。

## 总体层级

```
背景曲库页（opacity-40 + blur 1.5pt + scale .99，不可点）
scrim：bg-black/75 + backdrop-blur 6pt（z-10）
状态栏（z-20，浮层上的 9:41）
居中 Dialog（z-20，左右 margin 16pt）
底部 Home Indicator（z-20，色 #4A443F）
```

## 1. 背景层（曲库页虚化）

- `absolute inset-0 bg-[#1C1917] opacity-40 blur-[1.5px] scale-[0.99]`，内含简化曲库页（状态栏、曲库标题+Library、三枚胶囊、三条曲目行），仅供层级参考，施工以 S08 为准。

## 2. Scrim 与浮层状态栏

- 遮罩：`absolute inset-0 bg-black/75 backdrop-blur-[6px] z-10`。
- 状态栏（relative z-20，h-11 = 44pt，px-7 pt-3）：左「9:41」13pt semibold `tracking-tight` `#F5F2ED`；右侧蜂窝/Wi-Fi/电池（边框 `#F5F2ED/80`）。

## 3. Dialog 卡片

- 定位容器：`relative z-20 flex-1 flex items-center justify-center px-4 py-2`。
- 卡片：宽 = 390 − 32 = **358pt**，`bg-[#262220]`，1pt 边框 `#332D29`，**`rounded-[22px]`（圆角 22pt）**，`shadow-2xl`，`p-5` = 20pt，flex-col `space-y-4` = 16pt。

### 3.1 头部（居中）

- 错误图标托：**48 × 48pt**，`rounded-2xl` 16pt，底 `rgba(201,112,100,0.12)`（errorRedBg），1pt 边框 `#C97064/30`，`shadow-inner`；内含文件警告线性 SVG 24pt，stroke-width 1.8，色 `#C97064`。mb-3。
- 标题「这个文件没能解析」：serif **19pt semibold**，`tracking-tight`，`#F5F2ED`。

### 3.2 文件信息行

- 容器：`px-3.5` 14pt、`py-2.5` 10pt，`rounded-xl` 12pt，`bg-[#1C1917]`，边框 `#332D29/80`，flex items-center。
- 文档图标托：32 × 32pt，`rounded-lg` 8pt，`bg-[#262220]`，边框 `#332D29`，文档 SVG 16pt stroke-width 2，琥珀 `#D4A24E`；mr-3。
- 文案列 flex-1：文件名「summer_扒谱.mxl」**13.5pt medium** `#F5F2ED` truncate；「2.3 MB · 刚刚」11pt **mono** muted。
- 右徽章：10pt **mono uppercase**，`px-2 py-0.5`，`bg-[#C97064]/15`，文字 `#C97064`，边框 `#C97064/25`，4pt 圆角：「MXL 错误」。

### 3.3 错误详情框

- 容器：`p-3` 12pt，`rounded-xl` 12pt，`bg-[#1C1917]`，**左 2pt 红边 `#C97064`** + 上下/右 1pt 边框 `#332D29`，`space-y-1.5`。
- 错误位置行：**12.5pt mono** `leading-snug`：前缀「错误位置：」`#C97064` semibold；正文「第 34 小节 · 声部缺少闭合标签」色 **`#F1ECE1`**（暖白，内联色）。
- 错误代码行：11pt mono muted：「错误代码 PARSE_XML_34 · 已随诊断日志保存到本机」。

### 3.4 解释正文

- 12.5pt，`#9C948B`，`leading-relaxed`：
  「谱面文件可能损坏或不是标准 MusicXML。你可以换一个文件，或先在 Mac 上用制谱软件另存为 `.musicxml`（mono 主文字色）再导入。」

### 3.5 格式提示（pt-1，顶边 1pt `#332D29/60`，space-y-2）

- 提示1（11.5pt muted）：16pt 圆托 `bg-[#D4A24E]/10` + 琥珀对勾 SVG 10pt（stroke 2.5）；文案「支持格式：`.musicxml` / `.mxl` / `.mid`（mono 主文字/90）（**`.mscz`（mono 琥珀）** 兼容性试用中）」。
- 提示2：16pt 圆托 `bg-[#332D29]` + info SVG 10pt muted（stroke 2）；文案「PDF 请放进 **PDF 资料库**（主文字色、下划线 underline-offset-2、下划线色 `#332D29`），不能跟弹。」

### 3.6 按钮组（pt-2，flex-col space-y-2）

- 主按钮「我知道了」：全宽 **h-11 = 44pt**，`rounded-xl` 12pt，`bg-[#D4A24E]`，文字 `#1C1917` medium **14.5pt**，`shadow-lg shadow-[#D4A24E]/10`；active opacity-90 / scale .99。
- 次按钮「重新选择文件」：全宽 **h-10 = 40pt**，12pt 圆角，透明底，1pt 边框 `#332D29`，13.5pt medium `#F5F2ED`；hover 边框 `#D4A24E/40`，active 底 `#1C1917/40`。
- 幽灵按钮「查看导入帮助」：全宽 **h-8 = 32pt**，透明底，12.5pt muted，hover 琥珀。

## 4. 底部 Home Indicator

- footer h-7 = 28pt，pb-2 居中；指示条 128 × 4pt full 圆角，色 **`#4A443F`**（深灰棕，非白色透明）。

## 颜色 Token 总表

| Hex / rgba | 语义 token | 使用位置 |
|---|---|---|
| `#1C1917` | bgDark | 背景/信息行与详情框底/次按钮按压/按钮文字色 |
| `#262220` | cardDark | Dialog 底、文档图标托 |
| `#332D29` | borderDark | Dialog 边框、信息行（/80）、详情框三边、提示分隔（/60） |
| `#D4A24E` | amberAccent | 主按钮、文档图标、对勾托（/10）、.mscz 强调、阴影（/10） |
| `#F3E5AB` | amberLight | **config 定义但本屏未使用** |
| `#C97064` | errorRed | 错误图标/徽章/详情左缘（各透明度 12%/15%/25%/30%） |
| `rgba(201,112,100,0.12)` | errorRedBg | 图标托底 |
| `#F5F2ED` | textPrimary | 标题、文件名、次按钮文字 |
| `#9C948B` | textMuted | 正文/副信息/幽灵钮 |
| `#6E665E` | textDim | **config 定义但本屏未使用** |
| `#F1ECE1` | error-text-warm | 错误位置正文（内联色） |
| `#4A443F` | home-indicator-solid | Home 指示条 |
| `rgba(0,0,0,0.75)` | scrim | 遮罩 |

## 字体

- serif：Noto Serif SC——标题 19 semibold。
- sans：**Noto Sans SC**（本屏 sans 非 Plus Jakarta）——10–14.5pt。
- mono：**JetBrains Mono**——文件名副信息、错误位置/代码、徽章、格式名。

## 交互热区

- 三按钮：44 / 40 / 32pt 高，全宽 358pt（幽灵钮 32pt 不满足 44pt 标准，按 html 真值施工，可点击热区以整行计）。
- Dialog 外 scrim：html 未定义点击行为（待产品确认是否可关闭）。

## 与旧 spec 的主要差异（修正点）

1. **Dialog 尺寸错误**：旧 spec「宽 320、圆角 12」→ 真值 **358pt 宽（满宽 − 左右各 16）、圆角 22pt、p-5（20）、shadow-2xl**。
2. **头部图标形态补全**：真值 **48×48 红色图标托（16pt 圆角、errorRedBg、红/30 边、内阴影）+ 文件警告 SVG**，非笼统「⚠ 红色文档图标」。
3. **文件信息行独立成卡**：真值含 32pt 文档图标托、13.5pt 文件名、mono「2.3 MB · 刚刚」、右侧 mono 大写徽章「MXL 错误」；旧 spec 仅一行「summer_扒谱.mxl · 2.3MB」。
4. **错误详情框**：真值左 2pt 红边、12.5pt mono、错误位置正文暖白 `#F1ECE1`、代码文案「PARSE_XML_34 · 已随诊断日志保存到本机」；旧 spec 无尺寸/无日志保存文案。
5. **按钮排布与主次错误**：旧 spec「三按钮（帮助/重选/知道了）横排或上下、知道了为琥珀文字」→ 真值为**三按钮全宽上下堆叠：知道了=44pt 琥珀实心深字（主位）、重选=40pt 描边、帮助=32pt 幽灵**。
6. **遮罩参数**：真值 `black/75 + blur 6pt`；背景层 blur 1.5 + scale .99（旧 spec 无参数）。
7. 补全两条格式提示的完整构成（圆托图标 + mono 格式名 + .mscz 琥珀试用中 + PDF 资料库链接下划线）。
8. Home Indicator 真值为实色 `#4A443F`（非常规白/20）。

## 旧 spec 有、html 无（待产品确认，勿删）

- 「在 MuseScore 里打开这个文件，检查第 34 小节后另存为 .musicxml」的 MuseScore 专指文案（真值改为「Mac 上用制谱软件」）。
- 「重新选择」直接开 Files；「导入帮助」跳 S10 对应区。
- .mscz 失败时额外提示「MuseScore 工程文件兼容有限，可导出 .mxl」。
- 支持格式旧文案含 `.xml`（真值为 `.musicxml`，命名以 html 为准）。
- scrim 点击行为、弹层取消方式均未定义。
