# ADR-0013: 等待模式（弹对才继续，G10）

## 状态
已确认（2026-10-31，用户按推荐口径拍板：独立模式形态、隔离判分链、暂停语义）

## 背景
二轮竞品复查（docs/backlog.md G10）：flowkey / Anything Piano / Synthesia 均有等待模式
（wait mode）——光标停在当前位置，弹对了才前进；学新谱阶段不用赶节拍器，是「第一次摸谱」
最舒服的练法。本产品现有循环体系（LoopService 时钟驱动 + ScoreFollowEngine 小节期望消耗）
全是节奏型练习，缺一个零压力的读谱/摸谱形态。

技术路线现成：`ScoreFollowEngine.consume` 已实现「noteOn 命中当前小节期望 → 消耗并推进」，
等待模式的推进语义与之完全同构——只是把「光标自由走 + 错音不打断」收紧为「光标即进度，
弹错不动」。无需引入 NoteAligner 离线对齐（那是 M5 判分链的事，等待模式不判分）。

## 决策一：形态 = 独立会话模式，不是循环档位
练习室顶栏新增模式胶囊：**循环 / 等待** 二选一（默认循环，不持久化选择）。理由：
- 循环的时钟驱动（count-in、gapSec 停顿、遍数 wrap、提速逻辑）与「无限期等待」语义冲突，
  硬塞进 LoopMode 会污染既有三种模式的判定矩阵与测试。
- 独立模式复用 PracticeSession 的骨架（phase / playedNotes / TakeStore 落盘 / 断连暂停），
  只把推进源从 tick 时钟换成 noteOn 消耗。
- 竞品先例（flowkey/Synthesia）也是循环与等待并行的两个形态。

## 决策二：推进与容错口径
- **期望音多重集消耗**：复用 ScoreFollowEngine 规则——命中当前小节任一期望音即消耗（音序
  不敏感，与跟弹一致）；小节期望耗尽 → 光标到下一小节；终点小节耗尽 → 一遍完成（遍数 +1，
  光标 wrap 回起点）。
- **弹错不动光标**：未命中任何期望音 → 记入 wrongNotes（供会话内反馈），光标原地不动。
  不 toast 打断（区别于循环模式的轻提示，等待模式保持零压力）。
- **进度即光标**：顶栏副行显示「小节 x/y · 第 N 遍」，无速度概念（tempoState 不参与）。
- **忘记音了**：长按光标区回退上一小节（期望音重置为该小节全量）；不用「等 5 秒自动提示」
  ——那会变成假的自动演奏。

## 决策三：判分链完全隔离（对齐录像会话先例）
等待会话 **不产可判分 take、不进任何计数**：
- `Take.isWaitSession = true`（对齐 `isRecordingSession` 先例），分析回写、CourseEngine、
  处方 scoping、连续计数、streak 时长、铺路/矫正五处统一排除。
- 会话仍落盘原始 MIDI 事件（RawMIDIEventRecord 照写），供将来「摸谱热身轨迹」类分析；
  但 `canEvaluate` 恒 false——等待弹奏的时间自由度与判分节奏口径根本冲突，不评。
- 今日练习时长**不计入**（weeklyGoal 有效练习日口径是有 MIDI 且当日累计 ≥10 分钟的正常
  take；等待会话是学谱，不算练琴时长，避免虚高）。
- 理由：判分链是产品最重要的诚实性资产（录像隔离已立先例），等待模式天然污染节奏/速度
  两维，任何「宽容判分」都是造假入口，干脆不评。

## 决策四：计时与节拍器
- **计时照走但单独显示**：会话内 elapsedSec 正常累计（用户可能想知道摸谱花了多久），
  但不汇入今日时长（见决策三）。显示为「本次 N 分钟」而非练习时长。
- **节拍器默认关、可开**：等待模式核心是去节奏压力，但有的用户喜欢保留心跳参考；
  toggleMetronome 照常可用。
- **无 count-in、无 gapSec、无自动收尾**：手动「完成」按钮收尾（生成 waitSession take）；
  targetLoopCount / targetLoopMinutes 两项目标 UI 在等待模式下隐藏。

## 决策五：入口与范围
- 入口只在练习室（PracticeRoomView 模式胶囊），S12 循环设置页不动；等待模式下循环设置
  相关卡片（速度档/目标遍数/循环格）折叠隐藏。
- 范围限定：**只吃已解析 MusicXML 的曲目**（canFollow，与跟弹同前提）；PDF/不可解析诚实
  禁用模式胶囊并说明。分手能力（HandMode）照常生效——等待模式单手摸谱是高频场景。
- 热点区间：支持从 PieceDetail/今日卡「只练错误热点」以等待模式进入（热点 lock 逻辑复用）。

## 边界 / 红线
- 不新增采集；只消费既有 MIDIHub noteOn 流。
- 不写 Piece.status、不触发过关/推进/streak/铺路/矫正（红线 4）。
- canEvaluate 恒 false，禁止任何形式的「等待模式宽容判分」（红线 1 诚实）。
- 不做「自动提示下一音」「键盘点亮引导」——那是瀑布流跟灯，定位红线（docs/competitive-gap.md §5）。

## 分阶段
- Stage A（纯核心、可单测）：WaitModeEngine（推进状态机：期望消耗/错音不动/小节回退/
  wrap 计遍；值语义复用 ScoreFollowState 或平行结构）、Take.isWaitSession 字段与四处
  排除点接线、PracticeSession.wait 分支（tick 不驱动推进、finish 产 waitSession take）。
  测试追加 PracticeCoreTests（推进/回退/wrap/隔离断言）。
- Stage B（视图）：练习室模式胶囊、等待模式顶栏（小节进度/遍数/本次时长）、循环设置卡
  折叠、回退手势、S12 联动隐藏。A 独立验证绿后才派 B。
- 验收：V13 真机项登记到 acceptance（等待模式 5 项：进房切换、弹错不动、小节回退、
  一遍完成遍数、完成按钮收尾不进时长）。

## Grill 日期
2026-10-31
