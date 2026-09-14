import SwiftUI
import AVFoundation

struct HistoryEvaluationSettingsView: View {
    @State private var audio = true
    var body: some View {
        VStack {
            Picker("experience.nav.history", selection: $audio) {
                Text("experience.audio.title").tag(true)
                Text("experience.history.text").tag(false)
            }.pickerStyle(.segmented).padding()
            if audio { EvaluationLibraryView() }
            else { VoiceInputTab(initialSubtab: .stats, showsSubtabs: false) }
        }
    }
}

struct PrivacyStorageSettingsView: View {
    @ObservedObject private var store = InputMethodSettingsStore.shared
    var body: some View {
        Form {
            AudioRetentionSection()
            Section("experience.privacy.learning") {
                Toggle("experience.privacy.recordCandidates", isOn: Binding(
                    get: { store.settings.recordsCandidateUsage },
                    set: { store.setCandidateUsageRecording($0) }))
                Text("experience.privacy.learningHint").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                NavigationLink("experience.privacy.other") { DataOtherSettingsTab() }
                NavigationLink("experience.onboarding.restart") { OnboardingView() }
            }
        }.formStyle(.grouped)
    }
}

struct InputChoiceSection: View {
    @ObservedObject private var store = InputMethodSettingsStore.shared
    var body: some View {
        Section {
            Picker("experience.input.scheme", selection: Binding(get: { store.settings.schema }, set: { store.setSchema($0) })) {
                ForEach(IMESchema.allCases, id: \.self) { schema in
                    Text(NSLocalizedString(schema.displayNameKey, comment: "")).tag(schema)
                }
            }.pickerStyle(.segmented)
            Picker("experience.input.ranking", selection: Binding(get: { store.settings.enableUserDict }, set: { store.setUserDictEnabled($0) })) {
                Text("experience.input.fixed").tag(false)
                Text("experience.input.dynamic").tag(true)
            }.pickerStyle(.segmented)
            Text("experience.input.rankingHint").font(.caption).foregroundStyle(.secondary)
        } header: { Text("experience.input.title") }
    }
}

struct SpeechModelSettingsView: View {
    @AppStorage("preferredSpeechModel") private var selectedModel = SpeechModelVariant.preferred.rawValue
    @State private var error: String?
    @State private var ready = false
    @State private var checking = false
    @ObservedObject private var downloader = ModelDownloader.shared
    @ObservedObject private var voice = VoiceInputService.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("experience.voice.model", selection: $selectedModel) {
                ForEach(SpeechModelVariant.allCases, id: \.rawValue) { variant in
                    Text("\(variant.displayName) · \(ByteCountFormatter.string(fromByteCount: variant.expectedByteSize, countStyle: .file))")
                        .tag(variant.rawValue)
                }
            }.disabled(downloader.isDownloading || voice.isRecording || checking)
            Text("experience.onboarding.voiceHint").font(.caption).foregroundStyle(.secondary)
            if downloader.isDownloading {
                ProgressView(value: downloader.downloadProgress)
                Text(downloader.downloadStatus).font(.caption)
                Button("experience.download.cancel", role: .cancel) { downloader.cancelDownload() }
            } else {
                Button("experience.model.downloadVerify") { downloadOrVerify() }
                    .disabled(checking || voice.isRecording)
            }
            if checking { ProgressView() }
            if ready { Label("experience.model.ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .onChange(of: selectedModel) { _, _ in ready = false }
    }

    private func downloadOrVerify() {
        guard let variant = SpeechModelVariant(rawValue: selectedModel) else { return }
        checking = true
        ready = false
        error = nil
        Task {
            defer { checking = false }
            do {
                if !SpeechModelLocator.isInstalled(variant) {
                    try await downloader.downloadModel(baseURL: variant.officialDownloadURL) { _, _, _ in }
                }
                ready = await SpeechTranscriptionModel.shared.preload()
                UserPreferences.shared.isModelDownloaded = ready
                if !ready { error = NSLocalizedString("experience.model.failed", comment: "") }
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct AITriggerSection: View {
    @ObservedObject private var preferences = InputExperiencePreferences.shared
    var body: some View {
        Section {
            Picker("experience.ai.trigger", selection: $preferences.aiTrigger) {
                ForEach(VoiceAITrigger.allCases) { trigger in
                    Text(NSLocalizedString(trigger.titleKey, comment: "")).tag(trigger)
                }
            }.pickerStyle(.segmented)
            Text("experience.ai.hint").font(.caption).foregroundStyle(.secondary)
            if preferences.aiTrigger != .off {
                NavigationLink("experience.ai.services") { AIServiceManagementView() }
                NavigationLink("experience.ai.binding") { AIScenarioMappingView() }
                Toggle("experience.ai.context", isOn: $preferences.allowReferenceContext)
                Text("experience.ai.privacy").font(.caption).foregroundStyle(.secondary)
            }
        } header: { Text("experience.ai.title") }
    }
}

struct AudioRetentionSection: View {
    @ObservedObject private var preferences = InputExperiencePreferences.shared
    @ObservedObject private var archive = VoiceEvaluationArchive.shared
    @State private var confirmClear = false
    var body: some View {
        Section {
            Toggle("experience.audio.save", isOn: $preferences.retainAudio)
            Text("experience.audio.privacy").font(.caption).foregroundStyle(.secondary)
            if preferences.retainAudio {
                Picker("experience.audio.policy", selection: $preferences.retention) {
                    ForEach(AudioRetentionPolicy.allCases) { policy in
                        Text(NSLocalizedString(policy.titleKey, comment: "")).tag(policy)
                    }
                }
                Text("experience.audio.limitHint").font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent("experience.audio.usage") {
                Text("\(archive.records.count) · \(ByteCountFormatter.string(fromByteCount: archive.records.reduce(0) { $0 + $1.audioBytes }, countStyle: .file))")
            }
            Button("experience.audio.clear", role: .destructive) { confirmClear = true }
                .disabled(archive.records.isEmpty)
            if let error = archive.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
        } header: { Text("experience.audio.title") }
        .task { await archive.refresh() }
        .onChange(of: preferences.retention) { _, _ in Task { await archive.trim() } }
        .confirmationDialog("experience.audio.clearConfirm", isPresented: $confirmClear) {
            Button("experience.audio.clear", role: .destructive) { Task { await archive.clear() } }
        }
    }
}

struct AITextProcessingView: View {
    @ObservedObject private var preferences = UserPreferences.shared
    @ObservedObject private var workflow = InputExperiencePreferences.shared
    @ObservedObject private var context = ContextProfileManager.shared
    @State private var testText = ""
    @State private var testResult = ""
    @State private var testing = false
    var body: some View {
        Form {
            AITriggerSection()
            if workflow.aiTrigger != .off {
                Section("experience.ai.prompt") {
                    TextEditor(text: $preferences.aiSystemPrompt).frame(minHeight: 130)
                    Toggle("experience.ai.rules", isOn: $context.enablePowerMode)
                    NavigationLink("experience.ai.editRules") { ContextProfileEditorView() }
                    Text("experience.ai.rulesHint").font(.caption).foregroundStyle(.secondary)
                    Toggle("experience.ai.rewrite", isOn: $preferences.enableAIContextualRewrite)
                }
                Section("experience.ai.test") {
                    TextField("experience.ai.testPlaceholder", text: $testText, axis: .vertical)
                    Button("experience.ai.runTest") { runTest() }
                        .disabled(testing || testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if testing { ProgressView() }
                    if !testResult.isEmpty { Text(testResult).textSelection(.enabled) }
                }
            }
        }.formStyle(.grouped)
    }

    private func runTest() {
        guard let config = VoiceAIConfiguration.resolve() else {
            testResult = NSLocalizedString("experience.ai.unconfigured", comment: ""); return
        }
        testing = true
        let input = testText
        Task {
            defer { testing = false }
            do {
                let start = Date()
                let output = try await config.optimize(input)
                testResult = "\(config.profile.name) · \(config.model) · \(String(format: "%.2f s", Date().timeIntervalSince(start)))\n\(output)"
            } catch { testResult = error.localizedDescription }
        }
    }
}

struct EvaluationLibraryView: View {
    @ObservedObject private var archive = VoiceEvaluationArchive.shared
    @State private var selected: UUID?
    var body: some View {
        VStack(alignment: .leading) {
            Text("experience.evaluation.hint").font(.caption).foregroundStyle(.secondary).padding()
            HStack(spacing: 0) {
                List(archive.records, selection: $selected) { record in
                    VStack(alignment: .leading) {
                        Text(record.date, style: .date)
                        Text(record.rawText.isEmpty ? NSLocalizedString("experience.evaluation.emptyText", comment: "") : record.rawText)
                            .lineLimit(2).font(.caption).foregroundStyle(.secondary)
                    }.tag(record.id)
                }.frame(minWidth: 170, idealWidth: 220, maxWidth: 260)
                Divider()
                if let record = archive.records.first(where: { $0.id == selected }) {
                    EvaluationDetailView(record: record).id(record.id)
                } else {
                    ContentUnavailableView("experience.evaluation.select", systemImage: "waveform")
                }
            }
            if let error = archive.errorMessage { Text(error).foregroundStyle(.red).padding() }
        }.task { await archive.refresh() }
    }
}

private struct EvaluationDetailView: View {
    let record: VoiceEvaluationRecord
    @State private var reference = ""
    @State private var player: AVAudioPlayer?
    @State private var confirmDelete = false
    @State private var errorRate: Double?
    @State private var evaluating = false
    var body: some View {
        Form {
            Section {
                Text(record.date, style: .time)
                Text("\(record.model) · \(record.language) · \(String(format: "%.1f s", record.duration))")
                    .font(.caption).foregroundStyle(.secondary)
                Button("experience.evaluation.play") {
                    do {
                        player = try AVAudioPlayer(contentsOf: VoiceEvaluationArchive.shared.audioURL(record))
                        player?.play()
                    } catch { VoiceEvaluationArchive.shared.errorMessage = error.localizedDescription }
                }
                Button("experience.evaluation.stop") { player?.stop() }
            }
            Section("experience.evaluation.raw") { Text(record.rawText).textSelection(.enabled) }
            Section("experience.evaluation.corrected") { Text(record.correctedText).textSelection(.enabled) }
            Section("experience.evaluation.final") { Text(record.finalText).textSelection(.enabled) }
            Section("experience.evaluation.reference") {
                TextEditor(text: $reference).frame(minHeight: 90)
                Button("experience.evaluation.saveReference") {
                    var updated = record
                    updated.referenceText = reference
                    evaluating = true
                    let raw = record.rawText
                    let expected = reference
                    Task {
                        await VoiceEvaluationArchive.shared.update(updated)
                        errorRate = await Task.detached(priority: .utility) {
                            VoiceEvaluationMetrics.characterErrorRate(recognized: raw, reference: expected)
                        }.value
                        evaluating = false
                    }
                }
                .disabled(evaluating)
                if evaluating { ProgressView() }
                if let rate = errorRate {
                    Text("CER: \(rate.formatted(.percent.precision(.fractionLength(1))))")
                        .monospacedDigit()
                }
            }
            Button("experience.evaluation.delete", role: .destructive) { confirmDelete = true }
        }.formStyle(.grouped)
        .onAppear { reference = record.referenceText }
        .onChange(of: reference) { _, _ in errorRate = nil }
        .onDisappear { player?.stop() }
        .confirmationDialog("experience.evaluation.deleteConfirm", isPresented: $confirmDelete) {
            Button("experience.evaluation.delete", role: .destructive) {
                player?.stop()
                Task { await VoiceEvaluationArchive.shared.remove(record.id) }
            }
        }
    }
}
