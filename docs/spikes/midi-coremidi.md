# Spike B · CoreMIDI/BLE 与模拟源（docs/spikes/midi-coremidi.md）

- 日期：2026-09-18 · 执行：Claude Code（P1 M1）
- 结论：**MIDI 输入统一走 `MIDIEventSource` 协议；真机源 CoreMIDI 直封，模拟源为全链路验收基准**；BLE 丢 noteOff 双保险（velocity=0 转换 + 800ms 超时截断）已实现并单测覆盖。

## 1. 交付物

| 文件 | 职责 |
|---|---|
| `Services/MIDI/MIDIEvent.swift` | 规范化事件模型：noteOn/noteOff/velocity/CC64/channel/timeNanos(mach uptime ns)/isSuspicious |
| `Services/MIDI/MIDIEventSource.swift` | 输入源协议（全 App 唯一消费面）：事件回调 + 连接态回调 + start/stop |
| `Services/MIDI/CoreMIDISource.swift` | 真机源：`MIDIClientCreateWithBlock` + `MIDIInputPortCreateWithBlock`，枚举连接系统全部源（含已配对 BLE MIDI/USB/网络），`msgObjectAdded/Removed` 自动重连枚举；MIDITimeStamp(ticks)→ns 换算 |
| `Services/MIDI/SimulatedMIDIEventSource.swift` | 模拟源：屏幕琴键 press/release、CC64、自动回放音阶（定时派发）、`simulateDisconnect()` 钩子（S11b 验收用） |
| `Services/MIDI/HeldNoteTracker.swift` | 双保险：① Note On velocity=0 → noteOff；② held 音 800ms 无 noteOff → 在 start+800ms 精确补发合成 noteOff 并标 `isSuspicious`（PRD"可疑事件显式标记，禁止静默修正"）；同音重复 noteOn 先补发前一个可疑 noteOff |
| `Services/MIDI/MIDIHub.swift` | @MainActor 中枢：源切换（模拟/真机）、tracker 接线、100ms 泵驱动截断、结构化日志（`[MIDI] 0.532 ch1 noteOn note=60 vel=88`） |
| `Features/Spike/MIDISpikeView.swift` | spike 验收 UI：源切换 Picker、连接态、8 键屏幕琴键、自动回放按钮、事件流列表（可疑事件红色） |

## 2. 验收证据

- **超时截断单测**（`HeldNoteTrackerTests`，7 条全过）：velocity=0 转换；799ms 不截断 / 801ms 截断且截断点严格=start+800ms、标可疑；正常 on/off 不误标；重复 noteOn 补发可疑 noteOff；多音独立截断；CC64 不参与跟踪。
- **模拟源管线单测**（`SimulatedSourcePipelineTests`）：自动回放产出成对 noteOn/noteOff、时间戳单调；CoreMIDI 字节流解析层（noteOn/velocity=0→noteOff/CC64）直测。
- **模拟器实机**：MIDISpikeView 启动显示"已连接：模拟输入"，屏幕琴键/自动回放可用，事件流结构化打印（截图 bisect-c）。真机源模式在模拟器下等待系统 MIDI 设备（无设备，符合预期）。

## 3. 选型说明与 F1（SwiftMIDI 包矛盾）

- PRD M1 写 `orchetect/SwiftMIDI`（MIDIKit）；P1 brief 写 `genedelisa/SwiftMIDI`，并允许"不行则直接封装 CoreMIDI"。
- **实际采用：CoreMIDI 直封**（brief 的 fallback 分支）。理由：① 两包名互相矛盾，本就需裁决；② spike 只需"接收全部输入源事件"，CoreMIDI 直封 ~120 行即可，不引第三方；③ 红线 7（不引入未批准 SPM）下最稳。后续如需自动 endpoint 管理/虚拟端口再评估引入，属增量替换（协议面不变）。
- 已记入 `docs/findings.md` F1。

## 4. 风险与后续

1. **BLE 配对入口未验证**：iOS 上 BLE MIDI 设备需系统级配对后才会作为 CoreMIDI source 出现。S03 向导实装时需实测 V70 配对流程（真机，等用户回家验证项）。若需 App 内配对 UI，走 CoreBluetooth 扫 `03B80E5A-…` MIDI BLE service——已留协议面，不阻塞。
2. **800ms 截断会误伤长音**（延音踏板/长按键）：P1 按 brief 锁定 800ms，事件标可疑不静默；P2 M5 判分时可用"CC64 踩着不算结束 + 可疑事件降权"消化。常量已参数化（`HeldNoteTracker(timeoutNanos:)`）。
3. **断连重连**：真机源目前只有"源列表变化→重新枚举"，会话级断点续录（interruptionRanges）在练习室批次实装。
4. program change/pitch bend 按 PRD"记录但不依赖"——spike 未采集，S24 诊断页实装时补齐解析。

## 5. 结论

M1 Spike B 通过。App 侧 MIDI 输入契约定型：`MIDIEventSource` 协议 + `MIDIEvent` 模型 + `HeldNoteTracker` 双保险；模拟源可支撑 P1 全部验收链路（onboarding 定级/今日/练习室/报告），V70 真机仅在 S03 配对环节需实机确认。
