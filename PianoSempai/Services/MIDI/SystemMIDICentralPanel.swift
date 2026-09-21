import CoreAudioKit
import SwiftUI
import UIKit

// MARK: - 系统蓝牙 MIDI 中心面板（GarageBand 同款）

/// 包装 CABTMIDICentralViewController：iOS 上唯一能让蓝牙 MIDI 连接
/// 生成系统级 CoreMIDI 源的官方入口。
///
/// 关键机制（2026-09-21 真机实证）：
/// - App 用私有 CBCentralManager 连上 MIDI 服务，系统 MIDI 守护进程不参与、
///   不会创建 CoreMIDI 源（实测连接保持 6s，MIDIGetNumberOfSources 始终为 0）。
/// - 只有本面板（或 GarageBand 等 App 经同一路径）建立的连接才会注册全局源；
///   源出现后 CoreMIDISource 的 onSourcesChanged / onConnectionChanged 自动驱动 UI。
struct SystemMIDICentralPanel: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CABTMIDICentralViewController {
        CABTMIDICentralViewController(style: .grouped)
    }

    func updateUIViewController(_ uiViewController: CABTMIDICentralViewController, context: Context) {}
}
