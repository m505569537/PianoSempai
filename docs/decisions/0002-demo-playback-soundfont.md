# 0002: 整曲示范/试听 app 内合成（内置音源决策反转）

## 状态
已实施（2026-09-22）。这是对 PRD §明确不做「不做内置音源/发声」的**正式反转**，
不是静默修订。麦克风音频识别的禁令保持不变。

## 背景
用户反馈两个紧急问题：
1. 节拍器没有声音。
2. 只能跟练，不能直接播放整首，不知道原曲啥感觉，弹完也没法对照对错。

原设计把示范声寄托在「MIDI 回传 V70 琴内出声」上（PRD §M4 Q2=A）。该路径在实际使用中
不可靠/不可得，用户在跟练前听不到原曲。经对 swift-sheet-music（pin 2a3a6f7）的
BOTTOM-UP 实证，包内已具备完整的 app 内播放能力，无需自研音频系统。

## 决策

### 一、音源：随包 MuseScore General（SF2，MIT）
- 文件 `PianoSempai/Resources/SoundFonts/MuseScore_General.sf2`，215,614,036 字节（约 206MB）。
- MIT 授权。署名义务：Frank Wen（FluidR3 GM 基础）、Michael Cowgill（GeneralUser GS 修正）、
  S. Christian Collins 等及 MuseScore 社区。授权全文随包
  `MuseScore_General_License.md`，并在 设置 → 关于 → 示范音源署名（B11）可达。
- 单文件全 GM：per-program 查找返回 nil，统一走 defaultGMSoundfontURL。
- 体积取舍：本 app 自用、不上 App Store，对体积不敏感，故暂不抽取钢琴单 preset；
  抽取（Polyphone）有丢失 modulator 导致近无声的风险，留到确有瘦身需求时再做（P2）。

### 二、合成后端：SwiftySynth（纯 Swift，MIT）优于 AUMIDISynth
- 注入 `SwiftySynthBackend`（swift-sheet-music 的 SheetMusicAudioSwiftySynth；底层 SwiftySynth
  是 MeltySynth 的纯 Swift 移植）。
- 理由一：修掉 AUMIDISynth 的抢音问题——钢琴尾音长，最怕同通道复音被吃掉。
- 理由二：免疫 AUMIDISynth 在 nil/坏音源下的 EXC_BAD_ACCESS（不可 catch、破坏进程级
  CoreAudio 状态，包文档记录 1.7.0 上约 118 人遇到）。
- 新引入的传递依赖 SwiftySynth 为 MIT、纯 Swift、无网络，符合 P1-BRIEF §工程红线 #7 的意图。

### 三、复用 PlaybackEngine，不自研
- `DemoPlaybackService` 包装包内 `PlaybackEngine`（SheetMusicAudioApple），
  @MainActor @Observable，视图以 @State 持有（非 @StateObject——包 README 示例过时，照抄编译不过）。
- 音频会话策略 `.mixUntilPlay`：prepare 只取 mixing 会话，用户首次真正播放才独占。
  避免默认 `.exclusiveOnPrepare` 在「打开曲目详情页」时就切走用户正在放的音频。

### 四、Take 回放保真实墙钟时序
- `TakePlaybackService` 走「take 原始事件 → MidiTakeParser → TakeMidiBuilder → SMF →
  SwiftySynthBackend」直连，不用 PlaybackEngine。
- 关键：不能走 MidiImporter（带 BarSegmenter + MeasureQuantizer），那会把演奏量化到记谱
  网格、抹平时序误差，就听不出自己弹得多不准。
- TakeMidiBuilder 把整曲跨度对齐到整数拍反推恒定 tempo，使每个 tick 与录音逐毫秒对应；
  不依赖 take 是否弹得稳。事件按 tick 升序、同 tick noteOff 先于 noteOn（MidiWriter 硬 precondition）。

## 入口
- PieceDetailView「试听全曲」（PracticeRoute.demo，复用单一 fullScreenCover，不叠 cover）。
- PracticeRoomView 第五张控制卡「示范」；光标仲裁第三来源；▶/■ 主动作语义不变。
- TakeReportView：错音行 contextMenu「只听这小节期望音」+「只听我弹的」。
- 设置 → 关于 → 示范音源署名。

## 硬性安全约束
- BundledSoundfontResolver 只回答有无音源，不静默降级。
- DemoPlaybackService 在音源 URL 为 nil 时**绝不**调 engine.prepare（EXC_BAD_ACCESS 防线）；
  availability == .unavailable 时所有入口安全 no-op。
- 宿主必须在视图 onDisappear 显式 teardown()（deinit 到不了 @MainActor 的 teardown；
  stop() 只是 pause，IO 线程与 render-notify 块仍存活，释放会竞争致 EXC_BAD_ACCESS）。
- PracticeRoomView 补齐 onDisappear（节拍器 + 示范同时收尾）——这是独立于本功能也存在的
  生命周期缺陷，一并修复。

## 构建注意
Xcode 26 对包内宏（swift-wirelet 的 WireletMacros，SheetMusicAudioCore 内部使用）做启用/指纹
校验，命令行构建会报 "Macro must be enabled before it can be used"。本地 pin 固定、源码已审查，
命令行构建/测试加 `-skipMacroValidation`；在 Xcode GUI 内通过信任提示即可。此与是否直接依赖
Wirelet 无关（回退直连后错误依旧）。

## 验证
- Stage A：TakeMidiBuilderTests（9）+ DemoPlaybackTests（7），0 失败。
- App target 模拟器 build：BUILD SUCCEEDED，0 错误。
- 音频本身无法在模拟器验证（尤其静音开关行为），需真机听验：
  节拍器在静音模式下出声；试听全曲光标跟踪/进度/停止；take 回放保原始时序。

## 涉及文件
新增服务：BundledSoundfontResolver / DemoPlaybackService / TakeMidiBuilder / TakePlaybackService。
新增视图：SoundFontAttributionSheet（曾新增 DemoPlaybackSheet，同日按用户决定移除——示范入口只保留练习室内联）。
改动：project.yml、PracticeRoomView（节拍器/BPM 同步给示范）、TakeReportView、SettingsView；
PieceDetailView 一度加的「试听全曲」入口已随 DemoPlaybackSheet 一并移除；
PRD 三处反转措辞；本 ADR。
