import SwiftData
import SwiftUI

// MARK: - S25 添加服务商流程（预设入口 / OpenAI 兼容自定义 → 直接进入详情填 Key 与模型）

struct AddProviderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let runtime: ProviderChainRuntime
    /// 新服务商的 sortOrder（父视图给「当前最大值 + 1」）
    let sortOrder: Int
    /// 已存在的 providerId（预设去重：同一预设只能有一个入口）
    let existingIds: Set<String>

    @State private var created: AIProvider?
    @State private var showCustomForm = false
    @State private var customName = ""
    @State private var customBaseURL = ""
    @State private var customError: String?
    @State private var duplicateHint: String?

    var body: some View {
        NavigationStack {
            Group {
                if let created {
                    createdStage(created)
                } else if showCustomForm {
                    customStage
                } else {
                    presetStage
                }
            }
            .background(Color.canvas)
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: ① 选预设

    private var presetStage: some View {
        VStack(spacing: 0) {
            FormHeader(title: "添加服务商", leadingTitle: "取消", leadingAction: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("选一个预设入口，或填你自己的 OpenAI 兼容地址。模型 id 创建后在这个服务商里配置——不写死在 App 里。")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                        .padding(.top, 8)
                    ForEach(ProviderPreset.allCases) { preset in
                        presetRow(preset)
                    }
                    if let duplicateHint {
                        Text(duplicateHint)
                            .font(.labelSm)
                            .foregroundStyle(Color.danger)
                            .padding(.top, 10)
                    }
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func presetRow(_ preset: ProviderPreset) -> some View {
        Button {
            if preset.isCustom {
                showCustomForm = true
            } else {
                createFromPreset(preset)
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.displayName)
                        .font(.titleMd)
                        .foregroundStyle(Color.textPrimary)
                    Text(preset.defaultBaseURL ?? "填入 OpenAI 兼容入口（https://…）")
                        .font(.labelMono(11))
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.horizontal, 14)
            .frame(height: 62)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
    }

    // MARK: ② OpenAI 兼容自定义（baseURL 自填 + 同等校验）

    private var customStage: some View {
        VStack(spacing: 0) {
            FormHeader(title: "自定义服务商", leadingTitle: "返回", leadingAction: { showCustomForm = false })
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("任何 OpenAI 兼容的 /chat/completions 入口都可以接进来。")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                        .padding(.top, 8)
                    Text("显示名")
                        .font(.labelMd)
                        .foregroundStyle(Color.textBody)
                        .padding(.top, 6)
                    styledField("例如：我的网关", text: $customName)
                    Text("baseURL")
                        .font(.labelMd)
                        .foregroundStyle(Color.textBody)
                        .padding(.top, 6)
                    styledField("https://", text: $customBaseURL)
                    if let customError {
                        Text(customError)
                            .font(.labelSm)
                            .foregroundStyle(Color.danger)
                    }
                    Button("创建并配置") { createCustom() }
                        .buttonStyle(PrimaryButtonStyle(cornerRadius: 8))
                        .padding(.top, 8)
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: ③ 创建后直接进入详情（brief §3）

    private func createdStage(_ provider: AIProvider) -> some View {
        VStack(spacing: 0) {
            FormHeader(
                title: provider.displayName.isEmpty ? "服务商" : provider.displayName,
                leadingTitle: "完成",
                leadingAction: { dismiss() }
            )
            ProviderDetailForm(provider: provider, runtime: runtime, onClose: { dismiss() })
        }
    }

    // MARK: 创建

    private func createFromPreset(_ preset: ProviderPreset) {
        guard !existingIds.contains(preset.rawValue) else {
            duplicateHint = "「\(preset.displayName)」已经在链路里（每个预设只能有一个入口）。"
            return
        }
        let result = ProviderChainLogic.makeProvider(
            preset: preset,
            displayName: preset.displayName,
            baseURL: preset.defaultBaseURL ?? "",
            sortOrder: sortOrder
        )
        guard case .success(let provider) = result else { return }
        context.insert(provider)
        try? context.save()
        runtime.refreshKeys([provider.providerId])
        created = provider
    }

    private func createCustom() {
        let result = ProviderChainLogic.makeProvider(
            preset: .custom,
            displayName: customName,
            baseURL: customBaseURL,
            sortOrder: sortOrder
        )
        switch result {
        case .failure(let error):
            customError = error.message
        case .success(let provider):
            customError = nil
            context.insert(provider)
            try? context.save()
            runtime.refreshKeys([provider.providerId])
            created = provider
        }
    }

    private func styledField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.bodyMd)
            .foregroundStyle(Color.textPrimary)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.done)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color.canvas, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.borderInput, lineWidth: 1))
    }
}

#Preview {
    AddProviderSheet(runtime: ProviderChainRuntime(), sortOrder: 0, existingIds: [])
        .modelContainer(for: AIProvider.self)
        .preferredColorScheme(.dark)
}
