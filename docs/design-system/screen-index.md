# PianoSempai · 屏幕索引（系统层）

- Stitch project：`4122205180823255125`；设计系统 Nocturne Minimal
- 视觉真值：`design/reference/foundation/visual-system.md` + 每屏 `design/reference/screens/Sxx-*/spec.md`
- 产品真值：`PRD.md`（Grill 决策全集）
- 本文档只写系统关系（位置/跳转/数据/状态机归属），不写任何像素细节（两 层铁律）。

## 阶段归属

- **P1**：S01–S05 首次链路、S06/S07/S07b 框架与今日、S08/S08b/S09/S10 曲库、S11/S11b/S12/S13/S13b 练习与报告（判分可先用基础规则，完整 M5 在 P2）、S14、S23/S24/S25/S26
- **P2**：M3 课程引擎 + M5 完整判分（门禁、自适应速度、热力、错音清单的完整接线）
- **P3**：S18/S18b 问 Neko（方舟接入）、S19 笔记 AI 周报
- **P4**：S15/S16 主动录像与手型
- **P5**：S17 Zf 导入、S20 趋势完整版、S21 对比、S22 月报

## 屏幕清单与导航归属

| ID | 名称 | 类型 | 父级/入口 | 页面导航 doc |
|---|---|---|---|---|
| S01 | 欢迎 | 全屏流程 | app 首次启动 | onboarding.md |
| S02 | 权限请求 | 全屏流程 | S01 | onboarding.md |
| S03 | MIDI 连接向导（3 步） | 全屏流程 | S02 / 连接胶囊 / S24 | onboarding.md |
| S04 | 定级·自评 1/3 | 全屏流程 | S07b 开始定级 | onboarding.md |
| S05 | 定级结果·你的起点 | 全屏流程 | 定级完成 | onboarding.md |
| S06 | App Frame（5 tab+FAB） | 框架 | — | today.md |
| S07 | 今日（已定级） | tab1 | — | today.md |
| S07b | 今日·定级前空状态 | tab1 态 | 无 PlacementResult | today.md |
| S07c | 热身强开确认 | modal | S07 主菜 CTA（热身未完成） | today.md |
| S08 | 曲库（3 段+筛选） | tab2 | — | library.md |
| S08b | 导入失败 | dialog | 导入解析失败 | library.md |
| S09 | 曲目详情 | 二级页 | S08/S07/S20 行点击 | library.md |
| S10 | PDF 资料库 | 二级页 | S08 段头入口/我的 | library.md |
| S11 | 全屏练习室 | 全屏页 | S07/S09/S12 CTA | practice.md |
| S11b | MIDI 断连态 | S11 覆盖态 | 连接事件 | practice.md |
| S12 | 段落循环设置 | sheet | S11 循环控件 / S21 CTA | practice.md |
| S13 | Take 全量报告 | 全屏页 | S11 结束 / S09/S20 行 | practice.md |
| S13b | 疑似谱错标记 | sheet | S13 行长按/S11 标记/S09 ⚠ | practice.md |
| S14 | 自由弹奏 | 全屏页 | tab3（练习室入口聚合页，见下） | practice.md |
| S15 | 机位校准向导（4 步） | 全屏流程 | "录给 AI 看" | neko-ai.md |
| S16 | 侧拍回看 | 全屏页 | S15 完成 / S13 视频入口 / S18 视频消息 | neko-ai.md |
| S17 | Zf 月度导入 | 二级页 | 我的/档案（P5） | archive.md |
| S18 | 问 Neko 对话 | 全屏页 | FAB / S13 / S11 小猫 / S16 | neko-ai.md |
| S18b | 视频裁切上传确认 | sheet | S18 发送视频前（强制） | neko-ai.md |
| S19 | 练琴笔记 | 二级页 | S23/S18 周报卡 | neko-ai.md |
| S20 | 档案 | tab4 | — | archive.md |
| S21 | 双 take 对比 | 二级页 | S20 多选 / S13 | archive.md |
| S22 | 月报详情 | 二级页 | S20 / 周日通知 | archive.md |
| S23 | 我的 | tab5 | — | settings.md |
| S24 | MIDI 诊断 | 二级页 | S23/S11b/S03 | settings.md |
| S25 | 方舟 API Key | 二级页 | S23 | settings.md |
| S26 | 数据导出/恢复 | 二级页 | S23 | settings.md |

## tab3「练习室」聚合说明

tab3 不是单一页：进入后为入口聚合（今日继续 / 选曲练习 / 自由弹奏 S14 / 最近 take）。P1 可用 S07 主菜 CTA + tab3 简易列表实现，无独立设计稿（复用 S07 卡片语言）；聚合页视觉延用 foundation，不另造风格。

## 全局导航规则

1. 5 tab 只有 S06–框架页系显示；流程/全屏/弹层一律隐藏 tab bar。
2. 问 Neko FAB 在 S11/S14/S15/S16/弹层隐藏（这些页有自己的 Neko 入口或不应被打断）。
3. 所有 sheet/dialog 只能从其规定入口打开；S07c、S18b 是**强制闸口**（无绕过路径）。
4. 深链最小集（P1）：`pianosempai://take/<id>`（通知/分享回放入口）。
