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
        case .download: return "arrow.down.circle.fill"
        case .transcode: return "film.stack.fill"
        case .transcribe: return "waveform.badge.mic"
        case .translate: return "globe"
        case .logs: return "text.justify.left"
        case .settings: return "slider.horizontal.3"
        }
    }
}

struct ContentView: View {
    @StateObject private var vm = AppViewModel()
    @State private var selectedSection: SidebarSection? = .download

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            NavigationSplitView {
                sidebar
            } detail: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if vm.isRunning {
                            progressView
                        }
                        detailView(for: selectedSection ?? .download)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(Color.clear)
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

    private var sidebar: some View {
        List(SidebarSection.allCases, selection: $selectedSection) { section in
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selectedSection == section ? Color.white : Color.accentColor)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(selectedSection == section ? Color.accentColor : Color.accentColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(sidebarTitle(for: section))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(sidebarSubtitle(for: section))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .tag(section)
        }
        .listStyle(.sidebar)
        .navigationTitle(ui("Video Easy Tool", "Video Easy Tool"))
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
        VStack(alignment: .leading, spacing: 18) {
            pageHeader(
                title: ui("全局设置", "Global Settings"),
                subtitle: ui("管理界面语言与默认输出目录。", "Manage interface language and default output locations."),
                symbol: "slider.horizontal.3"
            )

            card {
                VStack(alignment: .leading, spacing: 14) {
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
                        pathLabel(vm.settings.globalOutputDirectory)
                    }

                    formRow(ui("解析后路径", "Resolved Path")) {
                        pathLabel(vm.resolvedDisplayPath(for: vm.settings.globalOutputDirectory), compact: true)
                    }

                    Divider()

                    HStack(spacing: 12) {
                        Button(ui("选择全局目录", "Choose Global Directory")) {
                            if let directory = pickDirectory(baseDirectory: vm.appInternalRootPath()) {
                                _ = vm.setRelativeDirectory(from: directory, target: \.globalOutputDirectory)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(vm.isRunning)

                        Spacer(minLength: 0)

                        Button(ui("全局覆盖功能目录", "Apply to All Tasks")) {
                            vm.applyGlobalOutputDirectoryToAll()
                        }
                        .buttonStyle(.bordered)
                        .disabled(vm.isRunning)

                        Button(ui("保存设置", "Save Settings")) {
                            vm.saveSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.isRunning)
                    }
                }
            }
        }
    }

    private var downloadView: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageHeader(
                title: ui("下载视频", "Download Video"),
                subtitle: ui("输入 YouTube 链接并直接保存到目标目录。", "Paste a YouTube link and save it directly to your target folder."),
                symbol: "arrow.down.circle.fill"
            )

            card {
                VStack(alignment: .leading, spacing: 14) {
                    formRow(ui("下载目录", "Download Directory")) {
                        HStack(spacing: 10) {
                            pathLabel(vm.settings.downloadOutputDirectory)
                            Button(ui("选择目录", "Choose Directory")) {
                                if let directory = pickDirectory(baseDirectory: vm.appInternalRootPath()) {
                                    _ = vm.rememberCommonOutputDirectory(from: directory)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    formRow(ui("视频链接", "Video URL")) {
                        TextField("https://www.youtube.com/watch?v=...", text: $vm.youtubeURL)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack(spacing: 12) {
                        Button(ui("下载到输出目录", "Download")) {
                            vm.downloadVideo()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.isRunning)

                        Button(ui("终止任务", "Stop Task")) {
                            vm.cancelCurrentTask()
                        }
                        .buttonStyle(.bordered)
                        .disabled(vm.runningTaskKind != .downloadVideo)

                        Spacer(minLength: 0)
                        statusPill(
                            title: ui("当前文件", "Current File"),
                            value: vm.selectedVideoPath.isEmpty ? ui("未生成", "None") : URL(fileURLWithPath: vm.selectedVideoPath).lastPathComponent
                        )
                    }
                }
            }

            logCard(title: ui("下载日志", "Download Logs"), minHeight: 220)
        }
    }

    private var transcribeView: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageHeader(
                title: ui("转录字幕", "Transcribe Subtitle"),
                subtitle: ui("使用本地 Whisper 模型把视频转成字幕文件。", "Use local Whisper models to turn video into subtitle files."),
                symbol: "waveform.badge.mic"
            )

            card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 10) {
                        Text(ui("转录模型", "Transcription Model"))
                            .frame(width: 120, alignment: .leading)

                        Picker("Transcription Model", selection: $vm.settings.transcriptionModel) {
                            ForEach(TranscriptionModel.allCases) { model in
                                Text(model.label).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 220)

                        Button(ui("下载", "Download")) {
                            vm.downloadTranscriptionModel()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.isRunning)

                        Button(ui("检测下载", "Check Download")) {
                            vm.checkTranscriptionModelDownloaded()
                        }
                        .buttonStyle(.bordered)
                        .disabled(vm.isRunning)

                        Button(ui("终止任务", "Stop Task")) {
                            vm.cancelCurrentTask()
                        }
                        .buttonStyle(.bordered)
                        .disabled(vm.runningTaskKind != .downloadModel && vm.runningTaskKind != .checkModel)
                    }

                    formRow(ui("模型路径", "Model Path")) {
                        pathLabel(vm.localModelPath(for: vm.settings.transcriptionModel), compact: true)
                    }

                    formRow(ui("模型状态", "Model Status")) {
                        statusPill(title: ui("状态", "Status"), value: vm.modelStatusText)
                    }

                    HStack {
                        Spacer()
                        Button(ui("删除模型", "Delete Model")) {
                            vm.deleteTranscriptionModel()
                        }
                        .buttonStyle(.bordered)
                        .disabled(vm.isRunning)
                    }

                    formRow(ui("转录目录", "Transcription Directory")) {
                        HStack(spacing: 10) {
                            pathLabel(vm.settings.transcribeOutputDirectory)
                            Button(ui("选择目录", "Choose Directory")) {
                                if let directory = pickDirectory(baseDirectory: vm.appInternalRootPath()) {
                                    _ = vm.setRelativeDirectory(from: directory, target: \.transcribeOutputDirectory)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Button(ui("手动选择视频", "Choose Video")) {
                            if let path = pickFile(extensions: ["mp4", "mkv", "mov", "m4v", "webm"]) {
                                vm.selectedVideoPath = path
                            }
                        }
                        .buttonStyle(.bordered)

                        Spacer(minLength: 0)
                        statusPill(
                            title: ui("视频", "Video"),
                            value: vm.selectedVideoPath.isEmpty ? ui("未选择", "None") : URL(fileURLWithPath: vm.selectedVideoPath).lastPathComponent
                        )
                    }

                    HStack(spacing: 12) {
                        Button(ui("执行转录", "Run Transcription")) {
                            vm.transcribeVideo()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.isRunning)

                        Button(ui("终止任务", "Stop Task")) {
                            vm.cancelCurrentTask()
                        }
                        .buttonStyle(.bordered)
                        .disabled(vm.runningTaskKind != .transcribeVideo)

                        Spacer(minLength: 0)
                        statusPill(
                            title: ui("字幕输出", "Subtitle Output"),
                            value: vm.selectedSubtitlePath.isEmpty ? ui("未生成", "None") : URL(fileURLWithPath: vm.selectedSubtitlePath).lastPathComponent
                        )
                    }
                }
            }
        }
    }

    private var transcodeView: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageHeader(
                title: ui("视频转码", "Video Transcode"),
                subtitle: ui("调整格式和压缩强度，导出更适合分发的视频文件。", "Choose a format and compression level for a distribution-ready video file."),
                symbol: "film.stack.fill"
            )

            card {
                VStack(alignment: .leading, spacing: 14) {
                    formRow(ui("输出目录", "Output Directory")) {
                        HStack(spacing: 10) {
                            pathLabel(vm.settings.transcodeOutputDirectory)
                            Button(ui("选择目录", "Choose Directory")) {
                                if let directory = pickDirectory(baseDirectory: vm.appInternalRootPath()) {
                                    _ = vm.setRelativeDirectory(from: directory, target: \.transcodeOutputDirectory)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    HStack(spacing: 12) {
                        Button(ui("选择输入视频", "Choose Input Video")) {
                            if let path = pickFile(extensions: ["mp4", "mkv", "mov", "m4v", "webm", "avi"]) {
                                vm.selectedTranscodeInputPath = path
                            }
                        }
                        .buttonStyle(.bordered)

                        Spacer(minLength: 0)
                        statusPill(
                            title: ui("输入文件", "Input File"),
                            value: vm.selectedTranscodeInputPath.isEmpty ? ui("未选择", "None") : URL(fileURLWithPath: vm.selectedTranscodeInputPath).lastPathComponent
                        )
                    }

                    formRow(ui("输出格式", "Output Format")) {
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
                            .frame(maxWidth: 140)
                    }

                    HStack(spacing: 12) {
                        Button(ui("执行转码", "Run Transcode")) {
                            vm.transcodeVideo()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.isRunning)

                        Button(ui("终止任务", "Stop Task")) {
                            vm.cancelCurrentTask()
                        }
                        .buttonStyle(.bordered)
                        .disabled(vm.runningTaskKind != .transcodeVideo)
                    }
                }
            }
        }
    }

    private var translateView: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageHeader(
                title: ui("翻译字幕", "Translate Subtitle"),
                subtitle: ui("在在线接口和 Ollama 之间切换，并导出双语字幕。", "Switch between online APIs and Ollama, then export bilingual subtitles."),
                symbol: "globe"
            )

            card {
                VStack(alignment: .leading, spacing: 14) {
                    formRow(ui("翻译目录", "Translation Directory")) {
                        HStack(spacing: 10) {
                            pathLabel(vm.settings.translateOutputDirectory)
                            Button(ui("选择目录", "Choose Directory")) {
                                if let directory = pickDirectory(baseDirectory: vm.appInternalRootPath()) {
                                    _ = vm.rememberCommonOutputDirectory(from: directory)
                                }
                            }
                            .buttonStyle(.bordered)
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
                }
            }

            card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Button(ui("手动选择字幕", "Choose Subtitle")) {
                            if let path = pickFile(extensions: ["srt"]) {
                                vm.selectedSubtitlePath = path
                            }
                        }
                        .buttonStyle(.bordered)

                        Spacer(minLength: 0)
                        statusPill(
                            title: ui("字幕文件", "Subtitle File"),
                            value: vm.selectedSubtitlePath.isEmpty ? ui("未选择", "None") : URL(fileURLWithPath: vm.selectedSubtitlePath).lastPathComponent
                        )
                    }

                    HStack(spacing: 12) {
                        Button(ui("执行翻译并生成双语字幕", "Translate and Export Bilingual SRT")) {
                            vm.translateSubtitle()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.isRunning)

                        Button(ui("终止任务", "Stop Task")) {
                            vm.cancelCurrentTask()
                        }
                        .buttonStyle(.bordered)
                        .disabled(vm.runningTaskKind != .translateSubtitle)
                    }
                }
            }
        }
    }

    private var logsView: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageHeader(
                title: ui("运行日志", "Runtime Logs"),
                subtitle: ui("查看任务输出、错误信息和依赖检测结果。", "Inspect task output, errors, and dependency checks in one place."),
                symbol: "text.justify.left"
            )

            logCard(title: ui("全部日志", "All Logs"), minHeight: 480)
        }
    }

    private var progressView: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ui("任务进度", "Task Progress"))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(vm.currentTaskTitle.isEmpty ? ui("处理中", "Processing") : vm.currentTaskTitle)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                    }

                    Spacer(minLength: 0)

                    Button(ui("终止当前任务", "Stop Current Task")) {
                        vm.cancelCurrentTask()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }

                if let progress = vm.taskProgress {
                    ProgressView(value: progress)
                        .controlSize(.large)
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.large)
                    Text(ui("正在执行，请查看日志输出...", "Running, see logs for details..."))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func pageHeader(title: String, subtitle: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 58, height: 58)
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: Color.black.opacity(0.05), radius: 18, x: 0, y: 10)
        )
    }

    private func logCard(title: String, minHeight: CGFloat) -> some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                LogTextView(text: vm.logs.isEmpty ? ui("等待执行", "Waiting") : vm.logs)
                    .frame(minHeight: minHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func statusPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
    }

    private func pathLabel(_ text: String, compact: Bool = false) -> some View {
        Text(text)
            .font(.system(size: compact ? 11 : 12, weight: .medium, design: .monospaced))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 12)
            .padding(.vertical, compact ? 8 : 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.045))
            )
    }

    @ViewBuilder
    private func formRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(width: 132, alignment: .leading)
                .padding(.top, 10)
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

    private func sidebarSubtitle(for section: SidebarSection) -> String {
        switch section {
        case .download: return ui("抓取与保存视频", "Fetch and save videos")
        case .transcode: return ui("转换格式与压缩", "Convert format and bitrate")
        case .transcribe: return ui("本地 Whisper 转录", "Local Whisper transcription")
        case .translate: return ui("双语字幕导出", "Bilingual subtitle export")
        case .logs: return ui("查看实时输出", "Inspect runtime output")
        case .settings: return ui("语言与目录偏好", "Language and path preferences")
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
