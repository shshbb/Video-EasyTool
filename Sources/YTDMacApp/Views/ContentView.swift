import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum SidebarSection: String, CaseIterable, Identifiable {
    case settings = "全局设置"
    case download = "下载视频"
    case transcode = "视频转码"
    case transcribe = "转录字幕"
    case translate = "翻译字幕"
    case logs = "日志"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .settings: return "gearshape"
        case .download: return "arrow.down.circle"
        case .transcode: return "film.stack"
        case .transcribe: return "waveform"
        case .translate: return "globe"
        case .logs: return "text.justify.left"
        }
    }
}

struct ContentView: View {
    @StateObject private var vm = AppViewModel()
    @State private var selectedSection: SidebarSection? = .settings

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("功能")
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if vm.isRunning {
                        progressView
                    }
                    detailView(for: selectedSection ?? .settings)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(WindowCloseGuard(viewModel: vm))
        .alert("缺少运行环境", isPresented: $vm.showMissingToolAlert) {
            Button("自动安装") {
                vm.installMissingTool()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("缺少工具：\(vm.missingToolName)\n\(vm.missingToolInstallHint)")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            vm.handleAppTermination()
        }
    }

    @ViewBuilder
    private func detailView(for section: SidebarSection) -> some View {
        switch section {
        case .settings:
            settingsView
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
        }
    }

    private var settingsView: some View {
        GroupBox("全局设置") {
            VStack(alignment: .leading, spacing: 10) {
                formRow("全局目录") {
                    Text(vm.settings.globalOutputDirectory)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                formRow("解析后路径") {
                    Text(vm.resolvedDisplayPath(for: vm.settings.globalOutputDirectory))
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Divider()

                HStack(spacing: 10) {
                    Button("选择全局目录") {
                        if let directory = pickDirectory(baseDirectory: vm.appInternalRootPath()) {
                            _ = vm.setRelativeDirectory(from: directory, target: \.globalOutputDirectory)
                        }
                    }
                    .frame(width: 140)
                    .disabled(vm.isRunning)

                    Spacer()

                    Button("全局覆盖功能目录") {
                        vm.applyGlobalOutputDirectoryToAll()
                    }
                    .frame(width: 140)
                    .disabled(vm.isRunning)

                    Spacer()

                    Button("保存设置") {
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
        GroupBox("下载视频") {
            VStack(alignment: .leading, spacing: 10) {
                formRow("下载目录") {
                    HStack {
                        Text(vm.settings.downloadOutputDirectory)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Button("选择目录") {
                            if let directory = pickDirectory(baseDirectory: vm.appInternalRootPath()) {
                                _ = vm.rememberCommonOutputDirectory(from: directory)
                            }
                        }
                    }
                }

                TextField("YouTube URL", text: $vm.youtubeURL)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("下载到输出目录") {
                        vm.downloadVideo()
                    }
                    .disabled(vm.isRunning)

                    Button("终止任务") {
                        vm.cancelCurrentTask()
                    }
                    .disabled(vm.runningTaskKind != .downloadVideo)

                    Text(vm.selectedVideoPath.isEmpty ? "未选择视频" : vm.selectedVideoPath)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(8)
        }
    }

    private var transcribeView: some View {
        GroupBox("转录字幕") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Text("转录模型")
                        .frame(width: 120, alignment: .leading)

                    Picker("Transcription Model", selection: $vm.settings.transcriptionModel) {
                        ForEach(TranscriptionModel.allCases) { model in
                            Text(model.label).tag(model)
                        }
                    }
                    .pickerStyle(.menu)

                    Button("下载") {
                        vm.downloadTranscriptionModel()
                    }
                    .disabled(vm.isRunning)

                    Button("检测下载") {
                        vm.checkTranscriptionModelDownloaded()
                    }
                    .disabled(vm.isRunning)

                    Button("终止任务") {
                        vm.cancelCurrentTask()
                    }
                    .disabled(vm.runningTaskKind != .downloadModel && vm.runningTaskKind != .checkModel)
                }

                formRow("模型路径") {
                    Text(vm.localModelPath(for: vm.settings.transcriptionModel))
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                GroupBox("模型状态") {
                    Text(vm.modelStatusText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                }

                HStack {
                    Spacer()
                    Button("删除模型") {
                        vm.deleteTranscriptionModel()
                    }
                    .disabled(vm.isRunning)
                }

                formRow("转录目录") {
                    HStack {
                        Text(vm.settings.transcribeOutputDirectory)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Button("选择目录") {
                            if let directory = pickDirectory(baseDirectory: vm.appInternalRootPath()) {
                                _ = vm.setRelativeDirectory(from: directory, target: \.transcribeOutputDirectory)
                            }
                        }
                    }
                }

                Divider()

                HStack {
                    Button("手动选择视频") {
                        if let path = pickFile(extensions: ["mp4", "mkv", "mov", "m4v", "webm"]) {
                            vm.selectedVideoPath = path
                        }
                    }

                    Text(vm.selectedVideoPath.isEmpty ? "未选择视频" : vm.selectedVideoPath)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack {
                    Button("执行转录") {
                        vm.transcribeVideo()
                    }
                    .disabled(vm.isRunning)

                    Button("终止任务") {
                        vm.cancelCurrentTask()
                    }
                    .disabled(vm.runningTaskKind != .transcribeVideo)

                    Text(vm.selectedSubtitlePath.isEmpty ? "未生成字幕" : vm.selectedSubtitlePath)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(8)
        }
    }

    private var transcodeView: some View {
        GroupBox("视频转码") {
            VStack(alignment: .leading, spacing: 10) {
                formRow("输出目录") {
                    HStack {
                        Text(vm.settings.transcodeOutputDirectory)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Button("选择目录") {
                            if let directory = pickDirectory(baseDirectory: vm.appInternalRootPath()) {
                                _ = vm.setRelativeDirectory(from: directory, target: \.transcodeOutputDirectory)
                            }
                        }
                    }
                }

                HStack {
                    Button("选择输入视频") {
                        if let path = pickFile(extensions: ["mp4", "mkv", "mov", "m4v", "webm", "avi"]) {
                            vm.selectedTranscodeInputPath = path
                        }
                    }

                    Text(vm.selectedTranscodeInputPath.isEmpty ? "未选择视频" : vm.selectedTranscodeInputPath)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack {
                    Text("输出格式")
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
                    Button("执行转码") {
                        vm.transcodeVideo()
                    }
                    .disabled(vm.isRunning)

                    Button("终止任务") {
                        vm.cancelCurrentTask()
                    }
                    .disabled(vm.runningTaskKind != .transcodeVideo)
                }
            }
            .padding(8)
        }
    }

    private var translateView: some View {
        GroupBox("翻译字幕") {
            VStack(alignment: .leading, spacing: 10) {
                formRow("翻译目录") {
                    HStack {
                        Text(vm.settings.translateOutputDirectory)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Button("选择目录") {
                            if let directory = pickDirectory(baseDirectory: vm.appInternalRootPath()) {
                                _ = vm.rememberCommonOutputDirectory(from: directory)
                            }
                        }
                    }
                }

                formRow("翻译引擎") {
                    Picker("Provider", selection: $vm.settings.provider) {
                        ForEach(TranslationProvider.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                formRow("翻译模式") {
                    Picker("Mode", selection: $vm.settings.translationMode) {
                        ForEach(TranslationMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                formRow("目标语言") {
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
                        TextField("sk-...", text: $vm.settings.openAIAPIKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    formRow("翻译模型") {
                        TextField("gpt-4o-mini", text: $vm.settings.translationModel)
                            .textFieldStyle(.roundedBorder)
                    }
                } else {
                    formRow("Ollama URL") {
                        TextField("http://127.0.0.1:11434", text: $vm.settings.ollamaBaseURL)
                            .textFieldStyle(.roundedBorder)
                    }
                    formRow("Ollama 模型") {
                        TextField("qwen2.5:7b", text: $vm.settings.ollamaModel)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Divider()

                HStack {
                    Button("手动选择字幕") {
                        if let path = pickFile(extensions: ["srt"]) {
                            vm.selectedSubtitlePath = path
                        }
                    }

                    Text(vm.selectedSubtitlePath.isEmpty ? "未选择字幕" : vm.selectedSubtitlePath)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack {
                    Button("执行翻译并生成双语字幕") {
                        vm.translateSubtitle()
                    }
                    .disabled(vm.isRunning)

                    Button("终止任务") {
                        vm.cancelCurrentTask()
                    }
                    .disabled(vm.runningTaskKind != .translateSubtitle)
                }
            }
            .padding(8)
        }
    }

    private var logsView: some View {
        GroupBox("日志") {
            LogTextView(text: vm.logs.isEmpty ? "等待执行" : vm.logs)
            .frame(minHeight: 360)
        }
    }

    private var progressView: some View {
        GroupBox("任务进度") {
            VStack(alignment: .leading, spacing: 8) {
                Text(vm.currentTaskTitle.isEmpty ? "处理中" : vm.currentTaskTitle)
                    .font(.headline)

                if let progress = vm.taskProgress {
                    ProgressView(value: progress)
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                    Text("正在执行，请查看日志输出...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()
                    Button("终止当前任务") {
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
