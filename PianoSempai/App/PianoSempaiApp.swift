import SwiftUI

@main
struct PianoSempaiApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // UI 恒为 Nocturne 深色，不随系统外观（brief §1）
                .preferredColorScheme(.dark)
        }
    }
}
