import SwiftData
import SwiftUI

@MainActor
struct FontSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(FontTheme.self) private var theme
    @Environment(LockService.self) private var lockService
    let note: Note?

    @State private var role: TextRole = .body
    @State private var usesNoteOverride = false
    @State private var localOverride = NoteFontOverride()
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    previewCard

                    if note != nil {
                        Toggle(isOn: $usesNoteOverride) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("仅此备忘录")
                                    .font(.subheadline.weight(.semibold))
                                Text("开启后，字号与字体只覆盖当前备忘录，回退到全局设置。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(LumenTheme.accent)
                        .onChange(of: usesNoteOverride) { _, enabled in
                            if enabled {
                                localOverride = theme.makeOverride()
                                note?.fontOverride = localOverride
                            } else {
                                note?.fontOverride = nil
                            }
                            try? modelContext.save()
                        }
                    }

                    sizePanel
                    familyPanel
                    weightPanel
                    dynamicTypePanel
                    securityPanel
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            .scrollContentBackground(.hidden)
            .background(LumenBackground())
            .navigationTitle("字体与字号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("备忘录 Aa 123")
                .font(previewFont(for: .title))
                .foregroundStyle(.primary)
            Text("液态玻璃只属于工具栏，正文永远是一张安静的纸。\nThe quick brown fox jumps over the lazy dog.")
                .font(previewFont(for: .body))
                .foregroundStyle(.primary)
                .lineSpacing(theme.lineSpacing)
            Text("辅助文本 · 12–32pt · 实时预览")
                .font(previewFont(for: .caption))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TagChip(name: "当前字体")
                Text(activeFamily.displayName)
                    .font(previewFont(for: .caption))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(activeSize)) pt")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentSurface(radius: 24, padding: 20)
    }

    private var sizePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassSectionHeader(title: "字号", subtitle: "12–32pt，步长 1pt；标题、正文、辅助文本独立设置。")
            Picker("文本角色", selection: $role) {
                ForEach(TextRole.allCases, id: \.self) { item in
                    Text(item.displayName).tag(item)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                Button {
                    setSize(activeSize - 1)
                } label: {
                    Image(systemName: "textformat.size.smaller")
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.bordered)
                .disabled(activeSize <= 12)

                Slider(value: sizeBinding, in: 12...32, step: 1)
                    .tint(LumenTheme.accent)

                Button {
                    setSize(activeSize + 1)
                } label: {
                    Image(systemName: "textformat.size.larger")
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.bordered)
                .disabled(activeSize >= 32)

                Text("\(Int(activeSize))")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .frame(width: 32, alignment: .trailing)
            }

            Text("当前：\(role.displayName) \(Int(activeSize))pt")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .glassPanel(cornerRadius: 24)
    }

    private var familyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader(title: "字体", subtitle: "六种字体族；每项使用自身字形渲染。")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(FontFamily.allCases) { family in
                    Button {
                        setFamily(family)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(family.displayName)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                if activeFamily == family {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(LumenTheme.accent)
                                }
                            }
                            Text("备忘录 Aa 123")
                                .font(theme.sampleFont(for: family))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(family.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(13)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(activeFamily == family ? LumenTheme.accent.opacity(0.10) : Color(uiColor: .secondarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(activeFamily == family ? LumenTheme.accent.opacity(0.7) : Color(uiColor: .separator).opacity(0.4), lineWidth: activeFamily == family ? 1.2 : 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var weightPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader(title: "字重", subtitle: "PingFang SC 提供细 / 常规 / 中粗 / 粗四档。")
            Picker("字重", selection: weightBinding) {
                ForEach(FontWeightChoice.allCases) { weight in
                    Text(weight.displayName).tag(weight)
                }
            }
            .pickerStyle(.segmented)
        }
        .contentSurface(radius: 20, padding: 16)
    }

    private var dynamicTypePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: dynamicTypeBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("跟随系统动态字体")
                        .font(.subheadline.weight(.semibold))
                    Text("开启时手动字号作为基准，再叠加 Dynamic Type 缩放；关闭时严格使用手动字号。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(LumenTheme.accent)
            HStack {
                Button("恢复全局默认") {
                    if usesNoteOverride {
                        localOverride = theme.makeOverride()
                        note?.fontOverride = localOverride
                    } else {
                        theme.reset()
                    }
                    try? modelContext.save()
                }
                .font(.footnote.weight(.semibold))
                Spacer()
            }
        }
        .contentSurface(radius: 20, padding: 16)
    }

    private var securityPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader(title: "锁定", subtitle: "锁定的正文以 AES-GCM 加密；退到后台会立即重锁。")
            Picker("自动重锁", selection: Binding(
                get: { lockService.autoLockSeconds },
                set: { lockService.autoLockSeconds = $0 }
            )) {
                Text("30 秒").tag(30.0)
                Text("1 分钟").tag(60.0)
                Text("5 分钟").tag(300.0)
                Text("不自动").tag(0.0)
            }
            .pickerStyle(.segmented)
        }
        .contentSurface(radius: 20, padding: 16)
    }

    private func previewFont(for role: TextRole) -> Font {
        theme.font(for: role, override: usesNoteOverride ? localOverride : note?.fontOverride)
    }

    private var activeFamily: FontFamily {
        usesNoteOverride ? (localOverride.family ?? theme.family) : (note?.fontOverride?.family ?? theme.family)
    }

    private var activeWeight: FontWeightChoice {
        usesNoteOverride ? (localOverride.weight ?? theme.weight) : (note?.fontOverride?.weight ?? theme.weight)
    }

    private var activeSize: Double {
        if usesNoteOverride {
            switch role {
            case .title: return localOverride.titleSize ?? theme.titleSize
            case .body: return localOverride.bodySize ?? theme.bodySize
            case .caption: return localOverride.captionSize ?? theme.captionSize
            }
        }
        switch role {
        case .title: return theme.titleSize
        case .body: return theme.bodySize
        case .caption: return theme.captionSize
        }
    }

    private var sizeBinding: Binding<Double> {
        Binding(
            get: { activeSize },
            set: { setSize($0) }
        )
    }

    private var weightBinding: Binding<FontWeightChoice> {
        Binding(
            get: { activeWeight },
            set: { setWeight($0) }
        )
    }

    private var dynamicTypeBinding: Binding<Bool> {
        Binding(
            get: {
                usesNoteOverride ? (localOverride.followDynamicType ?? theme.followDynamicType) : (note?.fontOverride?.followDynamicType ?? theme.followDynamicType)
            },
            set: { value in
                if usesNoteOverride {
                    localOverride.followDynamicType = value
                    note?.fontOverride = localOverride
                } else {
                    theme.followDynamicType = value
                }
                try? modelContext.save()
            }
        )
    }

    private func setSize(_ value: Double) {
        let clamped = min(32, max(12, value.rounded()))
        if usesNoteOverride {
            switch role {
            case .title: localOverride.titleSize = clamped
            case .body: localOverride.bodySize = clamped
            case .caption: localOverride.captionSize = clamped
            }
            note?.fontOverride = localOverride
        } else {
            switch role {
            case .title: theme.titleSize = clamped
            case .body: theme.bodySize = clamped
            case .caption: theme.captionSize = clamped
            }
        }
        try? modelContext.save()
    }

    private func setFamily(_ family: FontFamily) {
        if usesNoteOverride {
            localOverride.family = family
            note?.fontOverride = localOverride
        } else {
            theme.family = family
        }
        try? modelContext.save()
    }

    private func setWeight(_ weight: FontWeightChoice) {
        if usesNoteOverride {
            localOverride.weight = weight
            note?.fontOverride = localOverride
        } else {
            theme.weight = weight
        }
        try? modelContext.save()
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let noteOverride = note?.fontOverride {
            localOverride = noteOverride
            usesNoteOverride = true
        } else {
            localOverride = theme.makeOverride()
        }
    }
}
