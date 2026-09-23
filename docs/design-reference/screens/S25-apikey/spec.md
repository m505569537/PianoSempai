# S25 AI 助教 · 服务商（修订版 · 以 code.html 为真值）

- Screen ID：`3053c0a458f842c1b08228d7e5c75f6d`
- 画布元数据：780×1962 MOBILE（Nocturne Palette 稿）。html 内壳为 `max-w-[428px]`（iPhone Max 逻辑宽），两侧带 1px `#332D29` 边；以下尺寸全部取自 html（逻辑 pt）。画布 780 与壳 428 不一致（非整倍数），施工以 html 428 逻辑宽为准
- 真值文件：`/tmp/stitch-truth/screens/3053c0a458f842c1b08228d7e5c75f6d/code.html`
- Status：Revised

## 1. 用途

配置多服务商有序故障转移链：当前主力状态、可拖动排序的 3 个服务商、添加服务商、诊断记录、Keychain 安全声明。

## 2. 颜色令牌（config Material 名 + 内联 hex）

| Hex / 值 | 语义名（config / 实际用途） | 使用位置 |
|---|---|---|
| `#1C1917` | surface / background | body、壳底、顶栏（/90）、徽章底、状态胶囊底、log 卡内底 |
| `#262220` | surface-container-low / card | 全部卡与服务商行底、格式式按钮底 |
| `#332D29` | outline-variant / surface-container-highest | 卡边、行边、分隔线（/60）、顶栏下边、toggle 语义轨道、home indicator（muted/30） |
| `#2D2825` | surface-container-high | 右上角图标盒、序号 2/3 徽章底 |
| `#38312B` | secondary-container | `qwen3-vl` 标签底；安全卡 lock 盒底 |
| `#D4A24E` | primary / tertiary / surface-tint | 返回字、标题点、氛围光（/10）、模型标签边（/25）、speed 图标、首选行边（/50）、序号 1 底、首选标（底 /15 边 /30）、虚线添加按钮（/50）、区块图标、日志链接 |
| `#E6E1DC` | on-surface | 正文主文字、标题、log 模型名 |
| `#C8C2BC` | on-surface-variant | 副说明、log 行常规文字 |
| `#9C948B` | outline | 右值、帮助按钮、手柄、时间、未选标签、home indicator（/30） |
| `#7FA97C` | 成功绿（**内联 hex，不在 config**） | ping 点、「链路正常」、首选绿点、「活跃中」、成功 log、图标 check_circle |
| `#E06D63` | error | 失败 log 图标与文字（ModelNotOpen） |
| `#141210` | surface-container-lowest | config 令牌（本屏未直接使用） |

其他 config 令牌（`#594409` `#432c00` `#ffddb2` `#ffdf9a` `#ffdead` `#93000a` `#690005` `#ffdad6` `#5e4113` `#251a00` 等）本屏 DOM 未使用，落地不引用。

字体：标题 Noto Serif SC；正文 **Noto Sans SC**（本屏 sans 真值，非 Plus Jakarta）；数字/模型 id/log JetBrains Mono。图标 Material Symbols Outlined。

注意 config.borderRadius 被重定义（lg 4 / xl 8 / full 12），但 DOM 全部使用 `rounded-lg/xl/full` 的**任意值/标准类**（Tailwind 默认 8/12/99 观感），以 DOM 类名换算结果为准，见下。

## 3. 整体结构

- 壳：428 宽，min-h 全屏，纵向，1px 左右边 `#332D29`，shadow-2xl，overflow-hidden，`pb-8`。
- 状态栏：`pt-3 px-7`，9:41 14pt semibold muted（tracking tight）；右三 Material 图标 15/15/17pt muted。
- 顶栏（sticky，z-20）：surface/90 + backdrop-blur，下边 border，`px-3`，**高 48（h-12）**。
  - 左返回按钮：chevron_left 24pt + 14pt medium「返回」，amber（按压缩放 opacity 0.6）。
  - 中：6×6 amber 点 + 16pt serif semibold「AI 助教 · 服务商」。
  - 右帮助：40×40，help_outline 20pt muted（hover amber）。
- main：`px-4 pt-3.5`（14），区块间 `space-y-5`（20），纵向滚动（隐藏滚动条）。
- 底部：`pt-4 pb-2`，home indicator 128×4 muted/30 圆角条。

## 4. 状态横幅卡

- card 底 / border / 圆角 12（rounded-xl）/ `p-4` / shadow-lg / overflow-hidden。
- 氛围光：右上 -40/-40，112×112 圆，amber/10，**blur-2xl（≈40px）**。
- 主行：左右分布 gap 12。
  - 左：状态胶囊（surface 底 + border，`px-2.5 py-1` 圆角 99）：8×8 绿色 ping 点（animate-ping green/75 + 实点）+ 12pt medium green「链路正常 · 实时就绪」。
  - 其下 pt 4：14pt semibold「当前主力：百炼」+ 模型标签：mono 12pt 常规 amber，`#38312B` 底、amber/25 边，px 6 py 2 圆角 2「qwen3-vl」。
  - 说明 12pt `#C8C2BC` leading-relaxed mt 4，逐字「提问时按顺序尝试，任一可用即工作，遇到超限或故障毫秒级自动平滑切换。」
  - 右图标盒：36×36 圆角 8，`#2D2825` 底 + border，swap_calls 20pt amber，shadow-inner。
- 延迟行：mt 12，pt 10，顶边 border，11pt `#C8C2BC` 左右分布：左 speed 图标 14pt amber +「响应延迟：~1.8s」；右 mono muted「容灾策略：故障顺延 (Failover)」。

## 5. 模型链路（拖动排序）

- 区块头：左 alt_route 18pt amber + 14pt semibold「模型链路（拖动排序）」；右 11pt muted「长按右侧手柄微调优先级」。
- 列表 `space-y-2`（8）。
- 行通用：`p-3.5`（14），card 底，圆角 12，shadow-sm。
  - 左：序号盒 28×28 圆角 8 + 文案组（gap 12）。
  - 右：tune 按钮（`p-1.5`，图标 18pt）+ 拖动手柄（`p-1.5`，drag_indicator 20pt，`touch-none`）。
- 行 1 · 百炼（首选）：边 1px amber/50（hover /80）。
  - 序号盒 amber 底、12pt mono bold surface「1」，shadow-inner。
  - 名 14pt medium「百炼」+ 首选胶囊：10pt medium，底 amber/15、字 amber、边 amber/30，px 6 py 2 圆角 99，内含 4×4 green 点 +「首选生效」。
  - 副行 12pt：mono「qwen3-vl-plus」+ 10pt muted「•」+ 11pt mono green「活跃中」。
- 行 2 · 火山方舟：边 border（hover muted/40）。
  - 序号盒 `#2D2825` 底 + border，12pt mono medium muted「2」。
  - 标签：10pt 常规，surface 底字 muted + border 边，圆角 4「备选 1」。
  - 副行：mono「doubao-seed-2-1-pro」（max-w 150 截断）+「•」+「待命就绪」muted。
- 行 3 · DeepSeek：同备选样式「3」「备选 2」，mono「deepseek-vl2」，「待命就绪」。
- 拖动手柄交互：点击/按住时整行 `ring-2 ring-amber scale-1.01`（html 脚本 300ms 反馈）；hover 手柄变 amber。

### 添加服务商按钮

- 全宽，`py-3 px-4`（高约 44），圆角 12，**1px 虚线 amber/50**（hover 实色 amber），hover 底 amber/10；14pt medium amber；add_circle 18pt（hover scale 110%）。逐字「添加模型服务商」。

## 6. 诊断记录

- 区块头：terminal 图标 18pt amber + 14pt semibold「诊断记录」；右 11pt muted「最近调用与自动化健康探测」。
- 卡：card / border / 圆角 12 / `p-3.5`，内部 mono 12pt，`space-y-2.5`（10）。
- 每行左右分布，pb 8，下边 border/60（末行无）：
  1. 时间 11pt muted「09-20 23:12」+ 模型名 12pt medium「百炼 qwen3-vl-plus」；右 check_circle 14pt + 11pt semibold green「1.8s」。
  2. 「09-20 22:40」+「火山方舟 doubao-seed...」（`#C8C2BC`，截断）；右 cancel 图标 + 11pt `#E06D63`「ModelNotOpen」（title：模型未开通权限或密钥失效）。
  3. 「09-20 21:05」+「百炼 qwen3-vl-plus」；右 green「2.3s」。
- 卡尾链接：pt 6，右对齐按钮：11pt sans amber「查看全部诊断日志」+ chevron_right 14pt（hover /80）。

## 7. Keychain 安全卡

- card / border / 圆角 12 / `p-3.5`，横向 gap 12。
- lock 盒：`p-1.5` 圆角 8，`#38312B` 底 + border，lock 图标 18pt amber。
- 右文：12pt medium 标题「钥匙串硬件加密保障」；11pt `#C8C2BC` leading-relaxed 说明，逐字：
  > 每个 API Key 仅加密存于本机 iOS Keychain，不进入 iCloud 备份、导出包或日志；练习分析视频须经你单独确认后才会传输。

## 8. 全部状态与交互热区

- 返回（整按钮含文字）、帮助 40×40、tune（每行 12pt 区域）、手柄（每行 ≥32pt 热区）、添加按钮、日志链接均可点。
- 行 1=生效中（amber 边 + 首选胶囊 + 绿点活跃）；行 2/3=待命（普通边 + 备选标）。
- 旧 spec 中的「全链失败状态卡变红」「降级命中如实写当前模型」态 html 未呈现 → **待产品确认**（视觉真值仅有正常态）。
- 旧 spec 的服务商行展开详情（Key 掩码/眼睛/删除、多模型、模板、校验）html 无 → 属于子页规格，本屏仅保留入口语义，**待产品确认交互落点**。

## 9. 相对旧 spec 的主要修订

1. 旧 spec 视觉参数全缺/有误：补 428 逻辑宽、顶栏高 48、卡圆角 12、区块间距 20、行内边 14、行间距 8。
2. 状态卡真值含「响应延迟：~1.8s」「容灾策略：故障顺延 (Failover)」与 `qwen3-vl` 标签（`#38312B`），旧 spec 无。
3. 服务商行结构真值：序号盒（28 圆角 8，首选 amber 实心 / 备选 `#2D2825`）+ 名称 + 胶囊 + mono 模型行 + tune + drag_indicator；旧 spec「绿点/灰点/陶土点」语义中灰点 `#524B46` 在真值不存在（备选行无状态点，仅标签）。
4. 失败色真值 `#E06D63`（旧 spec 写陶土红 `#C97064`，错）；成功绿 `#7FA97C` 为内联值。
5. 正文字体真值 Noto Sans SC（非 Plus Jakarta / 系统 Sans）。
6. 安全卡标题「钥匙串硬件加密保障」；lock 盒 `#38312B` 底。
7. 画布 780 与 html 壳 428 不匹配，已按铁律以 html 数值为准并标注。
