# 练习与判分 Practice（系统层）

覆盖：tab3 聚合 / S11 练习室 / S11b 断连 / S12 循环 / S13 报告 / S13b 谱错 / S14 自由弹奏。

## tab3 聚合

入口列表：今日主菜续练（有 DailyPlan 时置顶）、选曲练习（跳 S08）、自由弹奏 S14、最近 take（跳 S13）。无独立设计稿，视觉用 S07 卡片语言。

## 练习会话状态机

```
idle → counting(预备拍) → performing ⇄ metronomeOnly(节拍器单独开关)
                   │
                   ├─ disconnected(S11b) ──重连成功──▶ performing(断点续，标 interruptionRanges)
                   ├─ autoSaved(时间到，弹完当前小节)
                   └─ finishedByUser ──▶ 判分 ──▶ S13
```

- 采集：CoreMIDI 事件带 hostTime；CC64 踏板同流；落盘只追加。
- 跟弹：谱面渲染 swift-sheet-music（spike 1 天；失败退 OSMD WKWebView）；在线容错光标（M5），不打断。
- 零打断：错音/慢/错节奏全程无 Alert/红屏/中止；仅静态热点底色与结束后报告。
- 速度自适应（M4）：60–70% 参考速度起步；连续两遍达标 +5（toast 告知）；崩 −5；连崩 2 遍暂停建议休息；速度变化只存本 take 上下文。
- 节拍器：iPhone 本机出声；预备拍 1 小节默认开（S12）。

## S12 循环

loopConfig{start,end,mode(loop/adaptiveUp/adaptiveDown),gapSec,countIn}；连崩 2 遍规则仅 adaptiveDown。

## S13 判分契约（M5）

- 触发：take 结束后本地立即跑（离线 DP 对齐 + 在线容错光标）。
- 输出 TakeAnalysis：六维（音准/节奏/连贯/力度/踏板/读谱）、弱总分、measureHeat(17–24)、wrongNotes[]（小节/拍/期望/实际）、节奏偏差序列（每音 ms，±50 容差带）、速度/力度汇总、alignmentConfidence。
- 踏板：CC64 纳入对齐与评分，置信脚注必显。
- 低置信：缺听清的音符列出，受影响维度降权并明示"仅供参考"；禁止编造纠错结论（红线 2）。
- 过关不在本页判定；连续 2 次达标的事实由课程引擎在 take 写入后消费。
- 报告动作：再练一遍（降速 ♩=60 新 take）/21 小节循环（S12）/问 Neko（S18 带 take 上下文）。

## S13b 疑似谱错

- 触发条件提示：同小节连续 3 take 弹成同一与谱不符的音（引擎给建议，用户确认提交）。
- ScoreErrorMark 提交后：错音率计算剔除被标行（引擎规则），S13 该行显示标签；不影响其他小节判分。

## S14 自由弹奏

- takeType=freePlay：无 scoreId 时仅卷帘；不判分、不产 TakeAnalysis 门禁字段；可写一句话；保存后档案可见。
- 进入即采 MIDI；丢弃走危险确认。

## 断连（S11b/M1）

- 暂停判分不丢事件（断线前事件已落盘）；重连后 take 记 interruptionRanges；带缺口 take 可正常保存（确认文案见画布 spec）。
