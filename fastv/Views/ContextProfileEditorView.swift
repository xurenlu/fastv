//
//  ContextProfileEditorView.swift
//  fastv
//
//  Power Mode 编辑界面：列表展示所有 ContextProfile，行内编辑名称 / 匹配规则 /
//  prompt 模板 / 可选绑定的 AI Profile。
//

import SwiftUI

struct ContextProfileEditorView: View {
    @ObservedObject private var manager = ContextProfileManager.shared
    @ObservedObject private var preferences = UserPreferences.shared
    @State private var selectedId: UUID?
    @State private var showAddSheet = false
    @State private var showResetConfirm = false

    var body: some View {
        HSplitView {
            // 左：列表
            VStack(spacing: 0) {
                List(selection: $selectedId) {
                    ForEach(manager.profiles) { profile in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name)
                                    .font(.system(size: 13, weight: .medium))
                                Text("\(profile.matchRules.count) " + NSLocalizedString("context.profile.rules.suffix", comment: ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if profile.isBuiltIn {
                                Text(NSLocalizedString("context.profile.builtin.tag", comment: ""))
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 4)
                        .tag(profile.id)
                    }
                }
                .listStyle(.sidebar)
                .frame(minWidth: 220, maxWidth: 280)

                Divider()

                HStack(spacing: 8) {
                    Button {
                        addBlankProfile()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                        Text(NSLocalizedString("context.profile.add", comment: ""))
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    Button {
                        showResetConfirm = true
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                        Text(NSLocalizedString("context.profile.reset.builtins", comment: ""))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
                .padding(8)
            }

            // 右：详情
            if let selectedId = selectedId,
               let binding = profileBinding(for: selectedId) {
                ContextProfileDetailView(profile: binding, onDelete: {
                    deleteProfile(selectedId)
                })
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.left")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text(NSLocalizedString("context.profile.select.hint", comment: ""))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert(NSLocalizedString("context.profile.reset.confirm.title", comment: ""), isPresented: $showResetConfirm) {
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("context.profile.reset.confirm.action", comment: ""), role: .destructive) {
                manager.resetBuiltInsToDefault()
            }
        } message: {
            Text(NSLocalizedString("context.profile.reset.confirm.message", comment: ""))
        }
        .onAppear {
            if selectedId == nil { selectedId = manager.profiles.first?.id }
        }
    }

    // MARK: - 操作

    private func profileBinding(for id: UUID) -> Binding<ContextProfile>? {
        guard let idx = manager.profiles.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { manager.profiles[idx] },
            set: { manager.update($0) }
        )
    }

    private func addBlankProfile() {
        let newOne = ContextProfile(
            name: NSLocalizedString("context.profile.new.name", comment: ""),
            matchRules: [],
            promptTemplate: "",
            isBuiltIn: false
        )
        manager.add(newOne)
        selectedId = newOne.id
    }

    private func deleteProfile(_ id: UUID) {
        guard let p = manager.profiles.first(where: { $0.id == id }) else { return }
        manager.remove(p)
        selectedId = manager.profiles.first?.id
    }
}

// MARK: - 详情面板

private struct ContextProfileDetailView: View {
    @Binding var profile: ContextProfile
    let onDelete: () -> Void

    @State private var newRuleType: NewRuleType = .bundleId
    @State private var newRuleValue: String = ""

    enum NewRuleType: String, CaseIterable, Identifiable {
        case bundleId, urlPattern, appNameContains
        var id: String { rawValue }
        var displayKey: String {
            switch self {
            case .bundleId: return "context.profile.rule.bundle.id"
            case .urlPattern: return "context.profile.rule.url.pattern"
            case .appNameContains: return "context.profile.rule.app.name"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 名称
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("context.profile.field.name", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("", text: $profile.name)
                        .textFieldStyle(.roundedBorder)
                        .disabled(profile.isBuiltIn)
                }

                // 匹配规则
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("context.profile.field.rules", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if profile.matchRules.isEmpty {
                        Text(NSLocalizedString("context.profile.rules.empty", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(Array(profile.matchRules.enumerated()), id: \.offset) { idx, rule in
                            HStack(spacing: 8) {
                                Text(ruleLabel(rule))
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15))
                                    .clipShape(Capsule())
                                Text(ruleValue(rule))
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button {
                                    profile.matchRules.remove(at: idx)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // 新增规则
                    HStack(spacing: 8) {
                        Picker("", selection: $newRuleType) {
                            ForEach(NewRuleType.allCases) { t in
                                Text(NSLocalizedString(t.displayKey, comment: ""))
                                    .tag(t)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()

                        TextField(NSLocalizedString("context.profile.rule.placeholder", comment: ""), text: $newRuleValue)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            addRule()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(newRuleValue.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                // Prompt 模板
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(NSLocalizedString("context.profile.field.template", comment: ""))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(NSLocalizedString("context.profile.field.template.hint", comment: ""))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    TextEditor(text: $profile.promptTemplate)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 220)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                }

                // 操作
                HStack {
                    Spacer()
                    if !profile.isBuiltIn {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Text(NSLocalizedString("delete", comment: ""))
                        }
                    }
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
    }

    private func addRule() {
        let value = newRuleValue.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        let rule: MatchRule
        switch newRuleType {
        case .bundleId: rule = .bundleId(value)
        case .urlPattern: rule = .urlPattern(value)
        case .appNameContains: rule = .appNameContains(value)
        }
        profile.matchRules.append(rule)
        newRuleValue = ""
    }

    private func ruleLabel(_ rule: MatchRule) -> String {
        switch rule {
        case .bundleId: return "Bundle ID"
        case .urlPattern: return "URL"
        case .appNameContains: return "App Name"
        }
    }

    private func ruleValue(_ rule: MatchRule) -> String {
        switch rule {
        case .bundleId(let v), .urlPattern(let v), .appNameContains(let v): return v
        }
    }
}
