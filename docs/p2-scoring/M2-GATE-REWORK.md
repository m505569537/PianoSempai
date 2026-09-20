# P2 M2 gate 返修：MidiTakeParser 流结束 flush 乱序

Hermes 独立 gate 发现 1 个真实缺陷（90 tests 全绿，但缺此交错用例）。修完才能进 M3。

## 缺陷
`PianoSempai/Services/Scoring/MidiTakeParser.swift` 流结束（EOS）路径：
当前先 flush 仍按住的 `active`，再 flush 踏板挂起的 `pedalExtended`（约 L112–121）。
当踏板一直踩到录音结束、且存在「被踏板挂起的早 onset 音」+「到结束仍按住的晚 onset 音」时，
输出 notes 不按 onset 升序，违反 `PlayedNote`「onset 升序」契约，并使依赖 emit 顺序==onset 顺序
构建的 segment 范围错误。

## 精确复现（事件，秒；踏板踩下后从不抬起）
```
on 60 v100 @0
cc64 v127 @0.5
off 60 @1.0        // 踏板踩着 → 60 进 pedalExtended，onset=0
on 62 v100 @2.0    // 仍按住，进 active，onset=2（踏板此刻仍 down）
（流在 @3 结束，踏板未抬起）
```
当前输出顺序：先 emit active 的 62@2，再 emit pedalExtended 的 60@0
→ notes = [62@2, 60@0]（乱序）；两者 endSec 都应为 3。

期望：notes 按 onset 升序 = [60@0(end3), 62@2(end3)]。

## 修法（稳健，不依赖 emit 时机）
不要依赖各 flush 分支的 emit 先后。解析全程把每个音连同其所属 segment 一起收集；
全部收集完（含 EOS 两类 flush）后：
1. 对所有音按 `(onsetSec, pitch)` 稳定排序；
2. 排序后再重建 `segmentIndexOfNote` 与 `segments`（每音 segment 仍由其 onset 落在哪个断连切分决定，
   逻辑沿用现有 `splits.filter { $0 <= Int(onset) }.count`，但在排序后的最终序列上重算下标范围）。
注意：抬踏板时的批量 flush 保持现有「同刻收音」语义即可，排序会兜底顺序。

## 验收
- 新增单测：上面这组交错事件，断言 notes.map(onsetSec)==[0,2]、pitch==[60,62]、
  两者 endSec≈3、segments 正确（单段 0..<2）。
- 再补一个带 interruptionRanges 的交错用例，确认排序后段边界仍正确。
- 现有 M2 全部测试保持绿；全套应 = 91（或以上）tests, 0 failures。
- 0 网络、不触库的纯函数性质不变。
- 一个 commit（可 amend 到 M2 或新 commit，自行决定，信息写明 EOS flush ordering fix）。
- 完成后停在输入框，等 Hermes 放行 M3；**不要自行开始 M3**。
