import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum SidebarSection: CaseIterable, Identifiable {
    case download
    case transcode
    case transcribe
    case translate
    case logs
    case settings

    var id: Self { self }

    var icon: String {
        switch self {
        case .download: return "arrow.down.circle"
        case .transcode: return "film.stack"
        case .transcribe: return "waveform"
        case .translate: return "globe"
        case .logs: return "text.justify.left"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @StateObject private var vm = AppViewModel()
    @State private var selectedSection: SidebarSection? = .download

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selectedSection) { section in
                Label(sidebarTitle(for: section), systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle(ui("功能", "Sections"))
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if vm.isRunning {
                        progressView
                    }
                    detailView(for: selectedSection ?? .download)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(WindowCloseGuard(viewModel: vm))
        .alert(ui("缺少运行环境", "Missing Dependency"), isPresented: $vm.showMissingToolAlert) {
            Button(ui("自动安装", "Install")) {
                vm.installMissingTool()
            }
            Button(ui("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text("\(ui("缺少工具", "Missing tool")): \(vm.missingToolName)\n\(vm.missingToolInstallHint)")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            vm.handleAppTermination()
        }
    }

    @ViewBuilder
    private func detailView(for section: SidebarSection) -> some View {
        switch section {
        case .download:
            downloadView
        case .transcode:
            transcodeView
        case .transcribe:
            transcribeView
        case .translate:
            translateView
        case .logs:
            logsView
        case .settings:
            settingsView
        }
    }

    private var settingsView: some View {
        GroupBox(ui("全局设置", "Global Settings")) {
            VStack(alignment: .leading, spacing: 10) {
                formRow(ui("显示语言", "Display Language")) {
                    Picker("", selection: $vm.settings.displayLanguage) {
                        ForEach(DisplayLanguage.allCases) { language in
                            Text(language.rawValue).tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                formRow(ui("全局目录", "Global Directory")) {
                    Text(vm.settings.globalOutputDirectory)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                formRow(ui("解析后路径", "Resolved Path")) {
                    Text(vm.resolvedDisplayPath(for: vm.settings.globalOutputDirectory))
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Divider()

                HStack(spacing: 10) {
                    Button(ui("选择全局目录", "Choose Global Directory")) {
                        if let directory = pickDirectory(baseDirectory: vm.appInternalRootPath()) {
                            _ = vm.setRelativeDirectory(from: directory, target: \.globalOutputDirectory)
                        }
                    }
                    .frame(width: 140)
                    .disabled(vm.isRunning)

                    Spacer()

                    Button(ui("全局覆盖功能目录", "Apply to All Tasks")) {
                        vm.applyGlobalOutputDirectoryToAll()
                    }
                    .frame(width: 140)
                    .disabled(vm.isRunning)

                    Spacer()

                    Button(ui("保存设置", "Save Settings")) {
                        vm.saveSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(width: 140)
                    .disabled(vm.isRunning)
                }
            }
            .padding(8)
        }
    }

    private var downloadView: some View {
        GroupBox(ui("下载视频", "Download Video")) {
            VStack(alignment: .leading, spacing: 10) {
                formRow(ui("下载目录", "Download Directory")) {
                    HStack {
                        Text(vm.settings.downloadOutputDirectory)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Button(ui("选择目录", "Choose Directory")) {
                            if let directory = pickDirectory(baseDirectory: vm.appInternalRootPath()) {
                                _ = vm.rememberCommonOutputDirectory(from: directory)
                            }
                        }
                    }
                }

                TextField("YouTube URL", text: $vm.youtubeURL)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button(ui("下载到输出目录", "Download")) {
                        vm.downloadVideo()
                    }
                    .disabled(vm.isRunning)

                    Button(ui("终止任务", "Stop Task")) {
                        vm.cancelCurrentTask()
                    }
                    .disabled(vm.runningTaskKind != .downloadVideo)

                    Text(vm.selectedVideoPath.isEmpty ? ui("未选择视频", "No video selected") : vm.selectedVideoPath)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(8)
        }
    }

    private var transcribeView: some View {
        GroupBox(ui("转录字幕", "Transcribe Subtitle")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Text(ui("转录模型", "Transcription Model"))
                        .frame(width: 120, alignment: .leading)

                    Picker("Transcription Model", selection: $vm.settings.transcriptionModel) {
                        ForEach(TranscriptionModel.allCases) { model in
                            Text(model.label).tag(model)
                        }
                    }
                    .pickerStyle(.menu)

                    Button(ui("下载", "Download")) {
                        vm.downloadTranscriptionModel()
                    }
                    .disabled(vm.isRunning)

                    Button(ui("检测下载", "Check Download")) {
                        vm.checkTranscriptionModelDownloaded()
                    }
                    .disabled(vm.isRunning)

                    Button(ui("终止任务", "Stop Task")) {
                        vm.cancelCurrentTask()
                    }
                    .disabled(vm.runningTaskKind != .downloadModel && vm.runningTaskKind != .checkModel)
                }

                formRow(ui("模型路径", "Model Path")) {
                    Text(vm.localModelPath(for: vm.settings.transcriptionModel))
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                GroupBox(ui("模型状态", "Model Status")) {
                    Text(vm.modelStatusText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                }

                HStack {
                    Spacer()
                    Button(ui("删除模型", "Delete Model")) {
                        vm.deleteTranscriptionModel()
                    }
                    .disabled(vm.isRunning)
                }

                formRow(ui("转录目录", "Transcription Directory")) {
                    HStack {
                        Text(vm.settings.transcribeOutputDirectory)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Button(ui("选择目录", "Choose Directory")) {
                            if let directory = pickDirectory(baseDirectory: vm.appInternalRootPath()) {
                                _ = vm.setRelativeDirectory(from: directory, target: \.transcribeOutputDirectory)
                            }
                        }
                    }
                }

                Divider()

                HStack {
                    Button(ui("手动选择视频", "Choose Video")) {
                        if let path = pickFile(extensions: ["mp4", "mkv", "mov", "m4v", "webm"]) {
                            vm.selectedVideoPath = path
                        }
                    }

                    Text(vm.selectedVideoPath.isEmpty ? ui("未选择视频", "No video selected") : vm.selectedVideoPath)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack {
                    Button(ui("执行转录", "Run Transcription")) {
                        vm.transcribeVideo()
                    }
                    .disabled(vm.isRunning)

                    Button(ui("终止任务", "Stop Task")) {
                        vm.cancelCurrentTask()
                    }
                    .disabled(vm.runningTaskKind != .transcribeVideo)

                    Text(vm.selectedSubtitlePath.isEmpty ? ui("未生成字幕", "No subtitle generated") : vm.selectedSubtitlePath)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(8)
        }
    }

    private var transcodeView: some View {
        GroupBox(ui("视频转码", "Video Transcode")) {
            VStack(alignment: .leading, spacing: 10) {
                formRow(ui("输出目录", "Output Directory")) {
                    HStack {
                        Text(vm.settings.transcodeOutputDirectory)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Button(ui("选择目录", "Choose Directory")) {
                            if let directory = pickDirectory(baseDirectory: vm.appInternalRootPath()) {
                                _ = vm.setRelativeDirectory(from: directory, target: \.transcodeOutputDirectory)
                            }
                        }
                    }
                }

                HStack {
                    Button(ui("选择输入视频", "Choose Input Video")) {
                        if let path = pickFile(extensions: ["mp4", "mkv", "mov", "m4v", "webm", "avi"]) {
                            vm.selectedTranscodeInputPath = path
                        }
                    }

                    Text(vm.selectedTranscodeInputPath.isEmpty ? ui("未选择视频", "No video selected") : vm.selectedTranscodeInputPath)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack {
                    Text(ui("输出格式", "Output Format"))
                        .frame(width: 120, alignment: .leading)
                    Picker("Format", selection: $vm.selectedTranscodeFormat) {
                        Text("mp4").tag("mp4")
                        Text("mkv").tag("mkv")
                        Text("mov").tag("mov")
                        Text("webm").tag("webm")
                    }
                    .pickerStyle(.segmented)
                }

                formRow("CRF (0-51)") {
                    TextField("23", text: $vm.selectedTranscodeCRF)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 120)
                }

                HStack {
                    Button(ui("执行转码", "Run Transcode")) {
                        vm.transcodeVideo()
                    }
                    .disabled(vm.isRunning)

                    Button(ui("终止任务", "Stop Task")) {
                        vm.cancelCurrentTask()
                    }
                    .disabled(vm.runningTaskKind != .transcodeVideo)
                }
            }
            .padding(8)
        }
    }

    private var translateView: some View {
        GroupBox(ui("翻译字幕", "Translate Subtitle")) {
            VStack(alignment: .leading, spacing: 10) {
                formRow(ui("翻译目录", "Translation Directory")) {
                    HStack {
                        Text(vm.settings.translateOutputDirectory)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Button(ui("选择目录", "Choose Directory")) {
                            if let directory = pickDirectory(baseDirectory: vm.appInternalRootPath()) {
                                _ = vm.rememberCommonOutputDirectory(from: directory)
                            }
                        }
                    }
                }

                formRow(ui("翻译引擎", "Translation Backend")) {
                    Picker("Provider", selection: $vm.settings.provider) {
                        ForEach(TranslationProvider.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                formRow(ui("翻译模式", "Translation Mode")) {
                    Picker("Mode", selection: $vm.settings.translationMode) {
                        ForEach(TranslationMode.allCases) { mode in
                            Text(modeLabel(mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                formRow(ui("目标语言", "Target Language")) {
                    Picker("Target Language", selection: $vm.settings.targetLanguage) {
                        ForEach(TargetLanguage.allCases) { language in
                            Text(language.rawValue).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if vm.settings.provider == .openAICompatible {
                    formRow("API Base URL") {
                        TextField("https://api.openai.com", text: $vm.settings.openAIBaseURL)
                            .textFieldStyle(.roundedBorder)
                    }

                    formRow("API Key") {
                        SecureInputField(placeholder: "sk-...", text: $vm.settings.openAIAPIKey)
                            .frame(maxWidth: .infinity)
                    }

                    formRow(ui("翻译模型", "Translation Model")) {
                        TextField("gpt-4o-mini", text: $vm.settings.translationModel)
                            .textFieldStyle(.roundedBorder)
                    }
                } else {
                    formRow("Ollama URL") {
                        TextField("http://127.0.0.1:11434", text: $vm.settings.ollamaBaseURL)
                            .textFieldStyle(.roundedBorder)
                    }
                    formRow(ui("Ollama 模型", "Ollama Model")) {
                        TextField("qwen2.5:7b", text: $vm.settings.ollamaModel)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Divider()

                HStack {
                    Button(ui("手动选择字幕", "Choose Subtitle")) {
                        if let path = pickFile(extensions: ["srt"]) {
                            vm.selectedSubtitlePath = path
                        }
                    }

                    Text(vm.selectedSubtitlePath.isEmpty ? ui("未选择字幕", "No subtitle selected") : vm.selectedSubtitlePath)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack {
                    Button(ui("执行翻译并生成双语字幕", "Translate and Export Bilingual SRT")) {
                        vm.translateSubtitle()
                    }
                    .disabled(vm.isRunning)

                    Button(ui("终止任务", "Stop Task")) {
                        vm.cancelCurrentTask()
                    }
                    .disabled(vm.runningTaskKind != .translateSubtitle)
                }
            }
            .padding(8)
        }
    }

    private var logsView: some View {
        GroupBox(ui("日志", "Logs")) {
            LogTextView(text: vm.logs.isEmpty ? ui("等待执行", "Waiting") : vm.logs)
            .frame(minHeight: 360)
        }
    }

    private var progressView: some View {
        GroupBox(ui("任务进度", "Task Progress")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(vm.currentTaskTitle.isEmpty ? ui("处理中", "Processing") : vm.currentTaskTitle)
                    .font(.headline)

                if let progress = vm.taskProgress {
                    ProgressView(value: progress)
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                    Text(ui("正在执行，请查看日志输出...", "Running, see logs for details..."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()
                    Button(ui("终止当前任务", "Stop Current Task")) {
                        vm.cancelCurrentTask()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func formRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .frame(width: 120, alignment: .leading)
            content()
        }
    }

    private func ui(_ zh: String, _ en: String) -> String {
        vm.settings.displayLanguage == .english ? en : zh
    }

    private func sidebarTitle(for section: SidebarSection) -> String {
        switch section {
        case .download: return ui("下载视频", "Download")
        case .transcode: return ui("视频转码", "Transcode")
        case .transcribe: return ui("转录字幕", "Transcribe")
        case .translate: return ui("翻译字幕", "Translate")
        case .logs: return ui("日志", "Logs")
        case .settings: return ui("全局设置", "Settings")
        }
    }

    private func modeLabel(_ mode: TranslationMode) -> String {
        switch mode {
        case .fast: return ui("极速", "Fast")
        case .balanced: return ui("标准", "Balanced")
        case .quality: return ui("高质量", "Quality")
        }
    }

    private func pickDirectory(baseDirectory: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: baseDirectory)
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    private func pickFile(extensions: [String]) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = extensions.compactMap { ext in
            UTType(filenameExtension: ext)
        }
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
