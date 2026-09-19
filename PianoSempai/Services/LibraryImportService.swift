import Foundation
import SheetMusicLoader

// 曲库导入服务（library.md 导入契约 + S08b）：可测（baseDir 注入）。
// 规则：
// - 支持 .xml/.musicxml/.mxl/.mscz/.mscx/.mid（真实解析校验，ScoreLoader）与 .pdf（不解析，canFollow=false）；
// - 成功：先解析校验，再拷入沙盒 scores/（PDF → pdfs/），返回 ScoreFile 字段（不静默、不产生假曲目）；
// - 失败：明确错误码（S08b 展示），失败文件绝不入曲库；
// - 红线：PDF 不 OMR、不猜分轨（不在此层，仅落文件）。

enum LibraryImportService {

    // MARK: 错误（S08b 展示契约：code + detail + hint）

    struct ImportError: Error, Equatable {
        enum Code: String, Equatable {
            case unsupportedFormat = "UNSUPPORTED_FORMAT"
            case copyFailed = "COPY_FAILED"
            case parseFailed = "PARSE_FAILED"
            case msczCompat = "MSCZ_COMPAT"
        }

        let code: Code
        let detail: String
        /// S08b「错误详情」卡片第三行提示
        let hint: String
    }

    struct Imported: Equatable {
        /// musicxml / mxl / mscz / mid / pdf
        let kind: String
        /// 沙盒相对路径（scores/… 或 pdfs/…）
        let relativePath: String
        let title: String
        let canFollow: Bool
    }

    // MARK: 类型识别

    static func detectKind(fileExtension ext: String) -> String? {
        switch ext.lowercased() {
        case "xml", "musicxml": return "musicxml"
        case "mxl": return "mxl"
        case "mscz": return "mscz"
        case "mscx": return "mscx"
        case "mid", "midi": return "mid"
        case "pdf": return "pdf"
        default: return nil
        }
    }

    static func isSupported(_ ext: String) -> Bool {
        detectKind(fileExtension: ext) != nil
    }

    // MARK: 导入主流程

    /// - Parameters:
    ///   - sourceURL: 源文件（fileImporter 场景由调用方负责 security scope 的开启/关闭）
    ///   - baseDir: 沙盒 Documents（测试注入临时目录）
    static func importScore(from sourceURL: URL, into baseDir: URL, fileManager: FileManager = .default) -> Result<Imported, ImportError> {
        let ext = sourceURL.pathExtension
        guard let kind = detectKind(fileExtension: ext) else {
            return .failure(ImportError(
                code: .unsupportedFormat,
                detail: "不支持的文件类型：.\(ext)",
                hint: "支持 .xml / .musicxml / .mxl / .mscz / .mscx / .mid；PDF 请放进 PDF 资料库（不能跟弹）。"
            ))
        }

        // PDF：不解析（红线：不做 OMR），直接拷入 pdfs/
        if kind == "pdf" {
            return copyToSandbox(sourceURL, baseDir: baseDir, subdirectory: "pdfs", kind: kind, canFollow: false, fileManager: fileManager)
        }

        // 可跟弹谱：先真实解析校验（失败即失败，不拷贝不入库）
        do {
            _ = try ScoreLoader.loadScore(contentsOf: sourceURL)
        } catch {
            if kind == "mscz" || kind == "mscx" {
                return .failure(ImportError(
                    code: .msczCompat,
                    detail: "MuseScore 工程文件解析失败：\(briefError(error))",
                    hint: "MuseScore 工程文件兼容有限，可在 MuseScore 里导出 .mxl 再试。"
                ))
            }
            return .failure(ImportError(
                code: .parseFailed,
                detail: "解析失败：\(briefError(error))",
                hint: "在 MuseScore 里打开这个文件检查后另存为 .musicxml 再试。"
            ))
        }

        return copyToSandbox(sourceURL, baseDir: baseDir, subdirectory: "scores", kind: kind, canFollow: true, fileManager: fileManager)
    }

    private static func copyToSandbox(_ sourceURL: URL, baseDir: URL, subdirectory: String, kind: String, canFollow: Bool, fileManager: FileManager) -> Result<Imported, ImportError> {
        let dir = baseDir.appendingPathComponent(subdirectory, isDirectory: true)
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return .failure(ImportError(code: .copyFailed, detail: "创建目录失败：\(briefError(error))", hint: "检查沙盒可用空间。"))
        }
        // 重名避免：加时间戳后缀
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        var target = dir.appendingPathComponent("\(baseName).\(ext)")
        var counter = 1
        while fileManager.fileExists(atPath: target.path) {
            target = dir.appendingPathComponent("\(baseName)-\(counter).\(ext)")
            counter += 1
        }
        do {
            try fileManager.copyItem(at: sourceURL, to: target)
        } catch {
            return .failure(ImportError(code: .copyFailed, detail: "拷入沙盒失败：\(briefError(error))", hint: "文件可能被系统占用，稍后再试。"))
        }
        let relative = "\(subdirectory)/\(target.lastPathComponent)"
        return .success(Imported(kind: kind, relativePath: relative, title: baseName, canFollow: canFollow))
    }

    private static func briefError(_ error: Error) -> String {
        let text = String(describing: error)
        return text.count > 120 ? String(text.prefix(120)) + "…" : text
    }
}
