import SwiftData
import SwiftUI

// MARK: - 详情容器（sheet 呈现：‹ 返回 + 居中 serif 标题 = 服务商名）

struct ProviderDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let provider: AIProvider
    let runtime: ProviderChainRuntime

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                FormHeader(
                    title: provider.displayName.isEmpty ? "服务商" : provider.displayName,
                    leadingTitle: "返回",
                    leadingAction: { dismiss() }
                )
                ProviderDetailForm(provider: provider, runtime: runtime, onClose: { dismiss() })
            }
            .background(Color.canvas)
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - S25 服务商详情（点链上任意一行进入；S25 spec「服务商行展开」）

/// 同一个表单复用在两处：链上点行的 sheet，以及添加服务商流程创建后的内嵌页
/// （brief §3：创建后可直接进入详情填 key/模型）。容器负责导航头。
struct ProviderDetailForm: View {
    @Environment(\.modelContext) private var context
    let provider: AIProvider
    let runtime: ProviderChainRuntime
    /// 关闭入口（sheet = dismiss；添加流程内嵌 = dismiss 整个添加 sheet）
    var onClose: () -> Void = {}

    @State private var displayName = ""
    @State private var baseURL = ""
    @State private var enabled = true
    @State private var baseError: String?

    @State private var newModelId = ""
    @State private var modelError: String?

    @State private var revealedUntil: Date?
    @State private var revealTimer: Timer?
    @State private var showReplaceKey = false
    @State private var showDeleteKeyConfirm = false
    @State private var showDeleteProviderConfirm = false
    @State private var validation: KeyValidationOutcome = .idle

    /// 删除后本表单立刻失去读取 provider 的合法性——先置位，body 换成占位再关
    @State private var isDeleted = false

    private var hasKey: Bool { runtime.keyPresence[provider.providerId] ?? false }

    private var isMasked: Bool {
        guard let revealedUntil else { return true }
        return Date() >= revealedUntil
    }

    var body: some View {
        Group {
            if isDeleted {
                Color.clear
            } else {
                form
            }
        }
        .onAppear {
            displayName = provider.displayName
            baseURL = provider.baseURL
            enabled = provider.enabled
            runtime.refreshKeys([provider.providerId])
        }
        .onDisappear { revealTimer?.invalidate() }
        .sheet(isPresented: $showReplaceKey) {
            ReplaceKeySheet(provider: provider, runtime: runtime) { outcome in
                validation = outcome
            }
        }
        .confirmationDialog(
            "从钥匙串删除「\(provider.displayName)」的 Key？删除后该商不再参与提问，直到重新设置。",
            isPresented: $showDeleteKeyConfirm,
            titleVisibility: .visible
        ) {
            Button("取消", role: .cancel) {}
            Button("删除 Key", role: .destructive) {
                try? runtime.deleteKey(providerId: provider.providerId)
                validation = .idle
            }
        }
        .confirmationDialog(
            "删除「\(provider.displayName)」？它的 Key 与全部配置都会删除，不可恢复。",
            isPresented: $showDeleteProviderConfirm,
            titleVisibility: .visible
        ) {
            // 取消在前 = 默认焦点（S25 spec：二次确认默认焦点取消）
            Button("取消", role: .cancel) {}
            Button("删除服务商与 Key", role: .destructive) { deleteProvider() }
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                identityCard.padding(.top, 12)
                modelsCard.padding(.top, 12)
                keyCard.padding(.top, 12)
                validationRow.padding(.top, 8)
                dangerZone.padding(.top, 24)
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 20)
        }
        .background(Color.canvas)
    }

    // MARK: 服务商身份（显示名 / baseURL / enabled）

    private var identityCard: some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("服务商")
                    .font(.titleMd)
                    .foregroundStyle(Color.textPrimary)
                fieldLabel("显示名")
                styledField("服务商显示名", text: $displayName)
                    .onChange(of: displayName) { _, new in
                        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return } // 空值不写，保留上一个合法显示名
                        provider.displayName = trimmed
                        save()
                    }
                fieldLabel("入口 baseURL（OpenAI 兼容）")
                styledField("https://", text: $baseURL)
                    .onChange(of: baseURL) { _, new in
                        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let error = ProviderChainLogic.validateBaseURL(trimmed) {
                            baseError = error // 不写非法值：模型侧永远拿到上一个合法入口
                            return
                        }
                        baseError = nil
                        provider.baseURL = trimmed
                        save()
                    }
                if let baseError {
                    Text(baseError)
                        .font(.labelSm)
                        .foregroundStyle(Color.danger)
                }
                Toggle(isOn: $enabled) {
                    Text("参与提问")
                        .font(.bodyMd)
                        .foregroundStyle(Color.textPrimary)
                    Text("停用后仍保留配置，但不参与链路")
                        .font(.labelSm)
                        .foregroundStyle(Color.textMuted)
                }
                .tint(Color.amber)
                .onChange(of: enabled) { _, new in
                    provider.enabled = new
                    save()
                }
            }
        }
    }

    // MARK: 模型列表（可多个，按顺序尝试）

    private var modelsCard: some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("模型（按顺序尝试，任一调通即用）")
                    .font(.titleMd)
                    .foregroundStyle(Color.textPrimary)
                if provider.modelIds.isEmpty {
                    Text("还没有模型。填一个模型 id（控制台里的完整模型名），可加多个。")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                }
                ForEach(provider.modelIds, id: \.self) { modelId in
                    HStack(spacing: 10) {
                        Text(modelId)
                            .font(.labelMono(12))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button { removeModel(modelId) } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.danger)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
                HStack(spacing: 10) {
                    styledField("添加模型 id", text: $newModelId)
                        .onSubmit(addModel)
                    Button("添加") { addModel() }
                        .font(.labelMd)
                        .foregroundStyle(Color.amber)
                        .disabled(newModelId.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let modelError {
                    Text(modelError)
                        .font(.labelSm)
                        .foregroundStyle(Color.danger)
                }
            }
        }
    }

    private func addModel() {
        guard let updated = ProviderChainLogic.addModel(newModelId, to: provider.modelIds) else {
            let trimmed = newModelId.trimmingCharacters(in: .whitespacesAndNewlines)
            modelError = trimmed.isEmpty ? "模型 id 不能为空" : "这个模型 id 已经在列表里"
            return
        }
        modelError = nil
        provider.modelIds = updated
        newModelId = ""
        save()
    }

    private func removeModel(_ modelId: String) {
        provider.modelIds.removeAll { $0 == modelId }
        save()
    }

    // MARK: API Key（Keychain；掩码末 4 位，眼睛显隐 30s 回掩码）

    private var keyCard: some View {
        NocturneCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("API Key")
                    .font(.titleMd)
                    .foregroundStyle(Color.textPrimary)
                if hasKey {
                    HStack(spacing: 10) {
                        Text(runtime.maskedKey(providerId: provider.providerId, visible: !isMasked) ?? "")
                            .font(.labelMono(13))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Spacer()
                        Button { revealKey() } label: {
                            Image(systemName: isMasked ? "eye" : "eye.slash")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.textBody)
                        }
                        .buttonStyle(.plain)
                        Button { showDeleteKeyConfirm = true } label: {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.danger)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Text("还没有 Key。Key 只写入 iOS 钥匙串，不进入备份、导出包与日志。")
                        .font(.bodySm)
                        .foregroundStyle(Color.textMuted)
                }
                Button(hasKey ? "替换 Key" : "设置 Key") { showReplaceKey = true }
                    .font(.bodyMd)
                    .foregroundStyle(Color.amber)
                Text("保存即用这个 Key 和首个模型发一条最小请求校验（不阻塞保存）。")
                    .font(.labelSm)
                    .foregroundStyle(Color.textMuted)
            }
        }
    }

    /// 眼睛：显态 30s 自动回掩码（S25 spec）
    private func revealKey() {
        guard hasKey else { return }
        revealedUntil = Date().addingTimeInterval(30)
        revealTimer?.invalidate()
        revealTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { _ in
            Task { @MainActor in revealedUntil = nil }
        }
    }

    // MARK: 校验结果行

    @ViewBuilder
    private var validationRow: some View {
        switch validation {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("正在用这个 Key 发一条最小请求…")
                    .font(.bodySm)
                    .foregroundStyle(Color.textMuted)
            }
        case .success(let providerModel):
            resultRow(color: Color.success, icon: "checkmark.circle.fill", text: "校验通过：\(providerModel)")
        case .failed(let reason):
            resultRow(color: Color.danger, icon: "xmark.octagon.fill", text: "校验失败：\(reason)")
        case .skipped(let reason):
            resultRow(color: Color.amber, icon: "exclamationmark.circle", text: reason)
        }
    }

    private func resultRow(color: Color, icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
            Text(text)
                .font(.bodySm)
                .foregroundStyle(color)
        }
    }

    // MARK: 危险区

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("删除服务商会同时删除它的钥匙串条目，并把它从链路移除。")
                .font(.labelSm)
                .foregroundStyle(Color.textMuted)
            Button("删除这个服务商") { showDeleteProviderConfirm = true }
                .font(.bodyMd)
                .foregroundStyle(Color.danger)
        }
    }

    private func deleteProvider() {
        isDeleted = true
        try? runtime.deleteKey(providerId: provider.providerId)
        context.delete(provider)
        try? context.save()
        onClose()
    }

    private func save() {
        try? context.save()
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.labelMd)
            .foregroundStyle(Color.textBody)
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

// MARK: - 替换 / 设置 Key（SecureField sheet；先存 Keychain 再发最小校验）

struct ReplaceKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    let provider: AIProvider
    let runtime: ProviderChainRuntime
    /// 保存后的校验结果回传（详情表单行内展示）
    var onSaved: (KeyValidationOutcome) -> Void = { _ in }

    @State private var keyText = ""
    @State private var checking = false

    private var title: String {
        let name = provider.displayName.isEmpty ? provider.providerId : provider.displayName
        return "\(name) 的 API Key"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headlineSm)
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 20)
                .padding(.top, 20)
            Text("Key 只写入 iOS 钥匙串，不进入备份、导出包与日志。保存后会自动发一条最小请求校验。")
                .font(.bodySm)
                .foregroundStyle(Color.textMuted)
                .padding(.horizontal, 20)
                .padding(.top, 4)
            SecureField("粘贴 Key", text: $keyText)
                .font(.labelMono(13))
                .foregroundStyle(Color.textPrimary)
                .padding(10)
                .background(Color.card, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.borderInput, lineWidth: 1))
                .padding(.horizontal, 20)
                .padding(.top, 12)
            if checking {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("校验中…")
                        .font(.labelSm)
                        .foregroundStyle(Color.textMuted)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }
            HStack(spacing: 12) {
                Button("取消") {
                    keyText = ""
                    dismiss()
                }
                .buttonStyle(GhostButtonStyle())
                Button("保存到钥匙串") { save() }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: !keyText.isEmpty, cornerRadius: 8))
                    .disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Color.cardElevated)
        .preferredColorScheme(.dark)
        .presentationDetents([.height(310)])
    }

    private func save() {
        let key = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        keyText = ""
        do {
            // 先存（校验不阻塞保存），再发最小请求
            try runtime.saveKey(key, providerId: provider.providerId)
        } catch {
            onSaved(.failed("钥匙串写入失败：\(error.localizedDescription)"))
            dismiss()
            return
        }
        checking = true
        Task { @MainActor in
            let outcome = await runtime.validate(provider)
            checking = false
            onSaved(outcome)
            dismiss()
        }
    }
}

// MARK: - 导航头（S25 spec：‹ 返回 + 居中 serif 标题）

/// 详情 / 添加流程共用的页头（navigationBarHidden + 自绘，才能把标题排成 serif 居中）
struct FormHeader: View {
    let title: String
    let leadingTitle: String
    let leadingAction: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.headlineSm)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            HStack {
                Button { leadingAction() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .medium))
                        Text(leadingTitle)
                            .font(.bodyMd)
                    }
                    .foregroundStyle(Color.amber)
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
        .background(Color.canvas)
    }
}

#Preview {
    ProviderDetailSheet(
        provider: AIProvider(
            providerId: "bailian",
            displayName: "百炼",
            baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            modelIds: ["qwen3-vl-plus"],
            enabled: true,
            sortOrder: 0
        ),
        runtime: ProviderChainRuntime()
    )
    .modelContainer(for: AIProvider.self)
    .preferredColorScheme(.dark)
}
