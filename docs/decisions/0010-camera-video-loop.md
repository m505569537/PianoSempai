# ADR-0010 — 相机录像闭环（V1 机位校准 + V2 视频回看）

- 状态：accepted
- 日期：2026-10-22
- 关联：backlog §7 V1/V2；PRD M6（机位校准）/ M8（视频作为 take 可选附件）。本 ADR **只覆盖采集与回看**，发送（V3）与 Zf 相册导入（V7）留待下一批。

## 背景（bottom-up 实证，2026-10-22）

- 相机/视频代码为零：全仓无 `AVCaptureSession` / `AVAsset` / `AVAssetExportSession` / `PhotosPicker` / `PHAsset`；`Take` 模型无任何视频字段；`AppSettings` 无视频设置。
- 已有的底座比预想多：`Info.plist` 已有 `NSCameraUsageDescription` / `NSMicrophoneUsageDescription`；`ExportService.VideoRetentionService` 已有 LRU 纯函数（`.lru(keepPerSource:)` / `.never` + 单测）；设置页已有「视频保留（每曲最近 8 条 / 不自动清理）」与「存储占用」真实计算。
- 发现真缺口：视频保留规则 UI 只是 `@State`（`SettingsView.swift` RetentionRuleSheet），选完不落库、退页即丢 —— 本批必须修，否则「规则在设置页可见可改」是假的。
- 设计真值 S15/S16 都画了 MediaPipe 21 点骨架与手型观察卡（S16 卡②「这一段的观察」3 条带置信度）——那是 PRD M6/P4 能力，本批不含。

## 决策（用户 2026-10-22 五项口径，全部按推荐拍板）

1. **范围**：本批打通 V1 采集 + V2 回看闭环（校准 → 录 → 存 → 看）；V3 裁切发送、V7 Zf 导入留到下一批。
2. **不含手型 / MediaPipe**：S15 只做真实相机预览 + 静态取景框 + 提示卡 + 免责卡 + 双按钮；**骨架层、检测 chips（「键盘完整可见」「指尖略出框」）、S16 卡②手型观察一律不渲染**（无数据源，禁止造假），登记 backlog V8 blocked。
3. **录像会话 = 练习会话**：录像照常判分（进分析链、出报告），但 `isPassEligible = false`，不参与过关判定；streak 口径（有效练习 = 有 MIDI 且当日 ≥10 分钟）不变。理由：侧拍位看不到谱面，判定口径与正常练习不一致。
4. **数据归属**：复用 `Take` 实体挂视频附件；Zf 月度录像下一批同样走 `Take`（`taskType="zfImport"`、`hasMidi=false`）。
5. **入口**：练习室顶栏。

## 技术形态

- **采集**：`AVCaptureSession` + `AVCaptureMovieFileOutput`（不自管 AVAssetWriter 编码）；1080p / 30fps / H.264 + 现场音轨。选 H.264 是为了下一批 V3 可直接上传，不必转码。预览用 `AVCaptureVideoPreviewLayer` 经 `UIViewRepresentable` 包一层（不做自绘假预览）。
- **权限**：`AVCaptureDevice.requestAccess(for: .video / .audio)`；拒绝时诚实提示（相机权限被关 → 去系统设置），且**不阻塞**继续纯 MIDI 练习。
- **配对**：录像与练习会话同起同停。锚点 = `Take.startedAt`；`Take` 记录视频起录偏移（通常 0）。任一路失败只落已有的一半：视频无 MIDI → `hasMidi=false`；MIDI 无视频 → 无附件。
- **文件**：`Documents/videos/yyyy/MM/take-<takeId>.mov`（与 `TakeStore` 的 `midi/yyyy/MM/` 平行），`Take` 只存相对路径。
- **保留**：接 `VideoRetentionService`，按 `pieceId` 分组、`keepPerSource = 8`；无 `pieceId` 的 take 自成一组；Zf 永留留给 V7。规则持久化到 `AppSettings.videoRetentionMode`（`"lru8"` / `"never"`，默认 `lru8`），执行时机 = 每次保存视频后；被淘汰的 take 清 `videoFileURL` 并删文件。
- **相册写回**：保存成功后 add-only 写一份进系统相册（新增 `NSPhotoLibraryAddUsageDescription`），失败或被拒静默跳过、不打断保存（PRD 299 已定）。
- **回看（S16）**：`AVPlayer` + scrubber + 时码；入口 = 档案 take 行视频角标 + 报告页；「重新校准」→ S15；「问 Neko」本批隐藏（视频上传链路未做，不留死按钮）。

## 红线

- 手型不进门禁；本批不产出手型结论。
- 不造假：骨架、检测 chips、观察卡、服务商名一律不画。
- 视频不上传、不出端；本批无网络调用。
- 不改过关判定逻辑；`isPassEligible=false` 由录像会话显式设置，普通会话不变。
- 每曲 8 条上限默认开启；淘汰只删视频文件，不删 take / MIDI / 报告。

## 非目标

V3 视频裁切与上传、V7 Zf 相册导入、MediaPipe 手型检测、双视频并排、云端备份、实时角标、录像中看谱面光标。
