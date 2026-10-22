# ADR-0012 — V7 Zf 月度录像相册导入（S17）

- 状态：accepted
- 日期：2026-10-22
- 关联：backlog §7 V7；PRD M8「Zf 月度录像」/「数据生命周期」；S17 spec；依赖 ADR-0010（视频附件与保留规则）。

## 背景与 bottom-up

- S17 真值：从档案 push 进入、无 tab bar、sticky footer；候选行 64×44 缩略图 + 时长/分辨率/大小 + 20×20 行首 checkbox；月份汇总卡（剩余空间 badge + 已选合计）；说明卡与琥珀提示卡。
- 代码侧：只有 `PhotoLibraryWriter`（add-only 写相册），**没有任何相册读取/选片代码**，Info.plist 也没有 `NSPhotoLibraryUsageDescription`。
- 保留规则：`VideoRetentionService` 已有 `isPermanent` 概念（Zf 永不清理），但 `VideoAttachmentStore` 把所有视频都按 `isPermanent: false` 传 —— V7 不修就会把 Zf 归档当普通 take 视频按「每曲 8 条」删掉。
- `Take` 没有 `sourceAssetIdentifier`，重复导入同一相册视频会生成重复条目。

## 决策（用户 2026-10-22 五项口径全拍）

1. **归月：按视频拍摄日期自动归月**。选片后读取 PHAsset `creationDate`；为此新增 `NSPhotoLibraryUsageDescription` 并请求**受限访问**（limited）。
2. **曲目：可选可跳过**。导入时可选挂到某首曲目（`Take.pieceId`），跳过 = 无曲目的纯表演存档，只在档案按月回看与月报出现。
3. **存储：导入前预检**。剩余空间不足则阻止导入并逐条标出超限文件；单文件上限 2GB；导入中可取消；失败/取消回滚已写入的半成品文件与 Take 行。
4. **预览：点缩略图全屏播放**（AVPlayer，只读本机文件；未导入的候选先落临时文件再播）。
5. **iCloud 未下载项：允许自动下载**，显示「正在下载」与进度，可取消。

## 技术形态

- **选片**：SwiftUI `PhotosPicker(selection:matching: .videos, maxSelectionCount: 10)`；每个 item 用 `loadTransferable` 写到临时文件（带 Progress，可取消）。
  - **候选列表口径（2026-10-22 补充，S17 真值要求直接列出候选）**：S17 真值没有「选择视频」按钮，直接列出 4 行候选 → 需要**完整相册读权限**才能枚举最近视频（`PHAsset.fetchAssets(.video, sortBy creationDate desc)`，取最近 30 条）。因此：
    - 用户授权 `.authorized` → 列出最近 30 条视频作为候选（默认只勾选最近一次导入之后的新视频）；
    - 用户只给 `.limited` → **不伪造候选列表**，改为显示「选择视频」按钮走 `PhotosPicker`，列表只含用户所选条目，并如实说明「仅能访问你勾选的照片」；
    - 拒绝权限 → 空态 + 去系统设置。
- **元数据**：`PHAsset.fetchAssets(withLocalIdentifiers:)`（受限访问下只对已选 item 有效）取 `creationDate`、`duration`、`pixelWidth/pixelHeight`；大小取临时文件字节数。**取不到拍摄日期时该条标为「无法读取日期」并禁用勾选**（不猜日期）。
- **落盘**：`Documents/videos/zf/yyyy/MM/<assetIdentifier 短哈希>.mov`，与普通录像 `videos/yyyy/MM/` 分开；复制后校验字节数一致才删临时文件。
- **数据**：新建 `Take(taskType:"zfImport", hasMidi:false, isFreePlay:false, isPassEligible:false, isRecordingSession:false, startedAt: creationDate, videoFileURL, videoDurationSec, pieceId?/title)`；`Take` 新增 `sourceAssetIdentifier: String?` 用于去重（已导入过的候选标「已导入」并禁用）。
- **保留**：`VideoAttachmentStore.enforceRetention` 与任何 LRU 判定把 `taskType == "zfImport"` 视为 `isPermanent: true`（永不淘汰）；设置页文案已有「月度 Zf 录像永不清理」，本次让其真实成立。
- **档案/月报**：Zf take 进档案时间线（按月筛选可用），月报的 `refsVideoCount` 统计 Zf 条数（此前恒 0 的注记更新）。
- **不做**：上传、判分、手型分析、自动转码（原片复制归档，保持 Zf 画质）。

## 红线

- 不上传、不判分、不进课程推进、不触发手型分析。
- 不猜拍摄日期；读不到就禁用并说明。
- 失败必须回滚，不留半成品 Take 或孤立文件。
- 不删相册原片；只复制。
- Zf 归档不受「每曲 8 条」影响。

## 非目标

Zf 视频转码/压缩、云备份、导入后编辑标题、批量跨月导入、从 iCloud 失败后的后台重试队列。
