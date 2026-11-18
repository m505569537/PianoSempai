# App Store 发布流程

本文件记录**实际跑通过**的上传链路（2026-11-17 首次成功），以及两个会让人卡住的坑。

## 前置

| 项 | 值 |
|---|---|
| Team ID | `4P68RDUY3F`（付费团队，支持 App Store 分发） |
| Bundle ID | `com.eeexu.pianosempai` |
| App Store Connect App | ID `6832824382`，SKU `xuuu_pianosempai`，主语言 zh-Hans |
| API Key | Key ID `AMX58ZXG4Q`，私钥 `~/.appstoreconnect/private_keys/AuthKey_AMX58ZXG4Q.p8` |
| Issuer ID | 账号级 UUID，见 App Store Connect → 用户和访问 → 集成 → App Store Connect API 页顶 |

> **Issuer ID 不是 Key ID**。只给 Key ID 会得到 `401 auth issue`，看起来像权限问题，其实是凭据缺一项。

## 一条龙命令

```bash
# 1) Release 归档（必须带克隆缓存，否则会重新拉 23MB 依赖，弱网下 RCE 失败）
xcodebuild -project PianoSempai.xcodeproj -scheme PianoSempai \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/PianoSempai.xcarchive -allowProvisioningUpdates \
  -clonedSourcePackagesDirPath build/device/SourcePackages \
  -disableAutomaticPackageResolution archive

# 2) 导出 App Store 包（method 在 Xcode 15+ 叫 app-store-connect）
#    ExportOptions.plist 见下
xcodebuild -exportArchive -archivePath build/PianoSempai.xcarchive \
  -exportOptionsPlist /tmp/ExportOptions.plist -exportPath build/export \
  -allowProvisioningUpdates

# 3) 校验 + 上传
xcrun altool --validate-app -f build/export/PianoSempai.ipa -t ios \
  --apiKey AMX58ZXG4Q --apiIssuer <ISSUER_UUID>
xcrun altool --upload-app -f build/export/PianoSempai.ipa -t ios \
  --apiKey AMX58ZXG4Q --apiIssuer <ISSUER_UUID>
```

`ExportOptions.plist`：

```xml
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>4P68RDUY3F</string>
  <key>uploadSymbols</key><true/>
  <key>destination</key><string>export</string>
</dict>
```

## 坑一：本地没有分发证书也能分发

`security find-identity -p codesigning` 只列出 `Apple Development`，看不到任何 `Apple Distribution`——
但导出的 IPA 确实带 `Apple Distribution: haoshun xu (4P68RDUY3F)` 签名。
原因是 Xcode 用**云签名**：私钥托管在 Apple 侧，本地无需分发证书与私钥。
所以「没有分发证书」不代表不能上传，别在这里停下。

## 坑二：版本号必须与 App Store Connect 的版本记录一致

上传只校验**构建号**（`CFBundleVersion`）不重复，但 **App 版本记录（`CFBundleShortVersionString`）
必须在 ASC 里存在对应行**，否则构建传上去了也挂不到版本上。

2026-11-17 的实例：ASC 里版本记录是 `1.0`，而工程 `MARKETING_VERSION = 1.0.0`，
构建的 `preReleaseVersion` 就是 `1.0.0` → 无法 attach（2026-11-09 那次 build 1 至今闲置就是这个原因）。

两种修法，**优先改 ASC 以对齐代码**（避免重新上传 173MB）：

```http
PATCH /v1/appStoreVersions/{versionId}
{"data":{"type":"appStoreVersions","id":"{versionId}","attributes":{"versionString":"1.0.0"}}}
```

改完再挂构建：

```http
PATCH /v1/appStoreVersions/{versionId}/relationships/build
{"data":{"type":"builds","id":"{buildId}"}}
```

（返回 204 空 body 属正常成功。）构建处理完成后 `processingState` 才会从 `PROCESSING` 变 `VALID`，
端到端约 5 分钟。

## 三条通道别混：内测 / 外测 / 上架

同一次上传的构建，在三个通道里的要求完全不同。**内测不需要任何元数据**，
截图和描述是「上架」才要的——2026-11-17 曾因为只查 App Store 那条线，
把「外部测试已提交」误判成「提交没登记」，实际是查错了对象。

| 通道 | 需要什么 | 查询对象 |
|---|---|---|
| 内部测试（Internal） | 构建处理完即可，无需审核、无需元数据 | `buildBetaDetail.internalBuildState` |
| 外部测试（External） | Beta App Review + Beta 描述 + **隐私政策网址** + 反馈邮箱 | `buildBetaDetail.externalBuildState`、`betaAppLocalizations` |
| App Store 上架 | 完整元数据 + 截图 + 正式审核 | `appStoreVersions.appStoreState` |

当前实测（2026-11-18）：

- 构建 `1.0.0 (2)`：`internalBuildState = IN_BETA_TESTING`（**内测可直接装**）、
  `externalBuildState = IN_BETA_REVIEW`（外测审核中）
- 内部组 `xuuu`（100 人上限，自动通知 `autoNotifyEnabled = true`）
- 外部组 `redbook`（公开链接可用）
- Beta 描述 ✓、反馈邮箱 `505569537@qq.com` ✓、What to Test「更新一些东西」（较随意）
- 隐私政策网址已于 2026-11-18 填入 `https://m505569537.github.io/pianosempai-privacy/`

### 填 Beta 本地化字段

```http
PATCH /v1/betaAppLocalizations/{locId}
{"data":{"type":"betaAppLocalizations","id":"{locId}","attributes":{"privacyPolicyUrl":"https://..."}}}
```

`locId` 从 `GET /v1/apps/{appId}/betaAppLocalizations` 取（zh-Hans 那条）。

### 内测装机步骤

1. App Store 装 **TestFlight**
2. 用开发者账号同一 Apple ID 登录
3. 列表里选 PianoSempai → 安装

## 上架前还缺什么（查询用）

```http
GET /v1/appStoreVersions/{versionId}/appStoreVersionLocalizations
GET /v1/appStoreVersionLocalizations/{locId}/appScreenshotSets
```

2026-11-17 实测：`description` / `keywords` / `supportUrl` / `marketingUrl` / 截图集**全空**。
这些必须由产品方提供内容，不能代填（支持网址、隐私政策属于对外承诺）。

完整提交清单：

- [ ] 描述、关键词、推广文本（zh-Hans）
- [ ] 支持网址 + 隐私政策网址（**必填**）
- [ ] 截图：6.9"/6.7" 与 6.5" 至少各一组（iPhone 专用 app）
- [ ] 年龄分级问卷
- [ ] App 隐私问卷（本 app 不收集数据，但必须声明）
- [ ] 价格与销售范围
- [ ] 出口合规（`ITSAppUsesNonExemptEncryption` 已在 Info.plist 置 false）
- [ ] 构建已挂到版本且 `VALID`

## 体积说明

内置 `MuseScore_General.sf2`（209MB）→ IPA 约 173MB，包体 231MB。
低于蜂窝下载 200MB 门槛，可提交；如需瘦身，把 `PianoSempai/Resources/SoundFonts/*.sf2`
排除出 app target（缺文件时示范播放自动安全禁用，见 ADR-0002）。
许可为 MIT，`MuseScore_General_License.md` 随包，设置页可达署名。
