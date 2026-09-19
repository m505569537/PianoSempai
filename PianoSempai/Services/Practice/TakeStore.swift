import Foundation

// Take 原始事件落盘（红线 4：原始 MIDI 只追加不可变；沙盒布局 data-model §3）。
// 文件格式：JSON Lines（每行一个事件对象），开放可解析（导出包不依赖 App）。
// 目录：Documents/midi/yyyy/MM/take-<uuid>.midi.jsonl

struct RawMIDIEventRecord: Codable, Equatable {
    /// 事件时刻（纳秒，mach uptime 域）
    let t: UInt64
    /// "on" / "off" / "cc64"
    let k: String
    let c: UInt8
    /// noteOn/noteOff 音高；CC64 时为 64
    let n: UInt8
    /// velocity 或 CC 值
    let v: UInt8
    let suspicious: Bool
}

enum TakeStore {

    enum StoreError: Error {
        case directoryCreationFailed
    }

    /// 本 take 的事件文件 URL（不创建内容；落盘由 append 驱动）
    static func makeFileURL(now: Date = Date(), fileManager: FileManager = .default) throws -> URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let cal = Calendar.current
        let dir = docs
            .appendingPathComponent("midi", isDirectory: true)
            .appendingPathComponent(String(cal.component(.year, from: now)), isDirectory: true)
            .appendingPathComponent(String(cal.component(.month, from: now)), isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("take-\(UUID().uuidString).midi.jsonl")
    }

    /// 追加一条事件（FileHandle 逐条写；只追加，永不重写已有内容）
    static func append(_ record: RawMIDIEventRecord, to url: URL, fileManager: FileManager = .default) throws {
        let line = try JSONEncoder().encode(record) + Data("\n".utf8)
        if fileManager.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url)
        }
    }

    /// 读取已落盘事件（报告/导出用；只读）
    static func readEvents(from url: URL) throws -> [RawMIDIEventRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let raw = try Data(contentsOf: url)
        return raw.split(separator: 0x0A).compactMap { line in
            try? JSONDecoder().decode(RawMIDIEventRecord.self, from: line)
        }
    }
}
