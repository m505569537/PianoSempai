import SwiftData
import SwiftUI

// MARK: - S25 火山方舟 API Key（Keychain 存储、掩码、替换/删除；测试消息 P3 开放）

struct APIKeySettingsView: View {
    @State private var store: APIKeyStore = KeychainAPIKeyStore()
    @State private var currentKey: String?
    @State private var revealUntil: Date?
    @State private var showReplaceSheet = false
    @State private var replaceText = ""
    @State private var showDeleteConfirm = false
    @State private var revealTimer: Timer?

    private var isMasked: Bool {
        guard let revealUntil else { return true }
        return Date() >= revealUntil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    statusCard.padding(.top, 12)
                    keyCard.padding(.top, 12)
                    modelCard.padding(.top, 12)

                    Button {
                        // P3 开放（brief：发测试消息按钮显示"P3 开放"）
                    } label: {
                        HStack {
                            Text("发一条测试消息")
                            Spacer()
                            Text("P3 开放")
                                .font(.labelSm)
                                .foregroundStyle(Color.textMuted)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                    }
                    .buttonStyle(SecondaryButtonStyle(isEnabled: false, cornerRadius: 8))
                    .disabled(true)
                    .padding(.top, 16)

                    NocturneCard {
                        Text("练琴数据只在你主动提问时组装发送；视频必须经过裁切确认；Key 永不进入导出包，也不会出现在日志里。")
                            .font(.bodySm)
                            .leading(19, fontSize: 12)
                            .foregroundStyle(Color.textBody)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }
            .background(Color.canvas)
            .navigationTitle("AI 助教 · 火山方舟")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismissView() }
                        .foregroundStyle(Color.amber)
                }
            }
            .sheet(isPresented: $showReplaceSheet) {
                replaceSheet
            }
            .confirmationDialog("从钥匙串删除这个 Key？删除后 AI 助教不可用，直到重新设置。", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    try? store.delete()
                    refreshKey()
                }
                Button("取消", role: .cancel) {}
            }
            .onAppear(perform: refreshKey)
            .onDisappear { revealTimer?.invalidate() }
        }
        .preferredColorScheme(.dark)
    }

    @Environment(\.dismiss) private var dismiss
    private func dismissView() { dismiss() }

    private func refreshKey() {
        currentKey = store.read()
    }

    private var statusCard: some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: store.hasKey ? "checkmark.circle" : "exclamationmark.circle")
                        .foregroundStyle(store.hasKey ? Color.success : Color.amber)
                    Text(store.hasKey ? "Key 已设置" : "还没有 Key")
                        .font(.titleMd)
                        .foregroundStyle(Color.textPrimary)
                }
                Text("Key 保存在 iOS 钥匙串，本应用没有服务器。")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
            }
        }
    }

    private var keyCard: some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("API Key")
                    .font(.titleMd)
                    .foregroundStyle(Color.textPrimary)
                if let key = currentKey {
                    HStack(spacing: 10) {
                        Text(APIKeyMasking.mask(key, visible: !isMasked))
                            .font(.labelMono(13))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Spacer()
                        Button {
                            // 眼睛：显态 30s 自动回掩码
                            revealUntil = Date().addingTimeInterval(30)
                            revealTimer?.invalidate()
                            revealTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { _ in
                                Task { @MainActor in refreshKey() }
                            }
                        } label: {
                            Image(systemName: isMasked ? "eye" : "eye.slash")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.textBody)
                        }
                        .buttonStyle(.plain)
                        Button {
                            showDeleteConfirm = true
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.danger)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Text("粘贴你的火山方舟 Key（只在钥匙串里，本应用没有服务器）")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                }
                HStack(spacing: 12) {
                    Button("替换") { showReplaceSheet = true }
                        .font(.bodyMd)
                        .foregroundStyle(Color.amber)
                    if store.hasKey {
                        Button("从钥匙串删除") { showDeleteConfirm = true }
                            .font(.bodyMd)
                            .foregroundStyle(Color.danger)
                    }
                    Spacer()
                }
            }
        }
    }

    private var modelCard: some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("模型配置")
                    .font(.titleMd)
                    .foregroundStyle(Color.textPrimary)
                configRow("服务商", "火山方舟")
                configRow("入口", "ark.cn-beijing.volces.com")
                configRow("文字/数据", "doubao-seed-2.0-pro")
                configRow("视频帧", "豆包视觉理解")
                Text("模型版本可在此更新（不写死在 App，P3 接入）")
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
            }
        }
    }

    private func configRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.labelMd).foregroundStyle(Color.textBody)
            Spacer()
            Text(value).font(.bodySm).foregroundStyle(Color.textPrimary)
        }
    }

    private var replaceSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("替换 API Key")
                .font(.headlineSm)
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 20)
                .padding(.top, 20)
            Text("Key 只写入 iOS 钥匙串。保存前请确认来自火山方舟控制台。")
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
                .padding(.horizontal, 20)
                .padding(.top, 4)
            SecureField("粘贴 Key", text: $replaceText)
                .font(.labelMono(13))
                .foregroundStyle(Color.textPrimary)
                .padding(10)
                .background(Color.card, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.borderInput, lineWidth: 1))
                .padding(.horizontal, 20)
                .padding(.top, 12)
            HStack(spacing: 12) {
                Button("取消") {
                    replaceText = ""
                    showReplaceSheet = false
                }
                .buttonStyle(GhostButtonStyle())
                Button("保存到钥匙串") {
                    guard !replaceText.isEmpty else { return }
                    try? store.save(replaceText)
                    replaceText = ""
                    refreshKey()
                    showReplaceSheet = false
                }
                .buttonStyle(PrimaryButtonStyle(isEnabled: !replaceText.isEmpty, cornerRadius: 8))
                .disabled(replaceText.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Color.cardElevated)
        .preferredColorScheme(.dark)
        .presentationDetents([.height(280)])
    }
}
