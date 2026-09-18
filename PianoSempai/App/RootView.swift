import SwiftUI

/// M0 验收：空白 app 启动为 canvas（#1C1917）底色全屏。
struct RootView: View {
    var body: some View {
        Color.canvas
            .ignoresSafeArea()
    }
}

#Preview {
    RootView()
}
