import Foundation
import NaturalLanguage

@MainActor
final class AppViewModel: ObservableObject {
    @Published var youtubeURL: String = ""
    @Published var selectedVideoPath: String = ""
    @Published var selectedTranscodeInputPath: String = ""
    @Published var selectedTranscodeFormat: String = "mp4"
    @Published var selectedTranscodeCRF: String = "23"
    @Published var selectedSubtitlePath: String = ""
    @Published var settings: AppSettings
    @Published var logs: String = ""
    @Published var isRunning: Bool = false
    @Published var currentTaskTitle: String = ""
    @Published var taskProgress: Double? = nil
    @Published var runningTaskKind: TaskKind? = nil
    @Published var modelStatusText: String = "未检测"
    @Published var showMissingToolAlert: Bool = false
    @Published var missingToolName: String = ""
    @Published var missingToolInstallHint: String = ""

    private let downloader = YouTubeDownloader()
    private let transcoder = VideoTranscoder()
    private let subtitleService = SubtitleService()
    private let localWhisperTranscriber = LocalWhisperTranscriber()
    private let modelDownloader = ModelDownloadService()
    private let settingsStore = SettingsStore()

    private var activeTask: Task<Void, Never>?
    private var activeProcess: Process?
    private var userCancelledTask: Bool = false
    private var cleanupFilesOnCancel: Set<String> = []
    private var cleanupDirectoriesOnCancel: Set<String> = []

    init() {
        self.settings = settingsStore.load()
        normalizeSettingsToRelativePaths()
        ensureAppInternalDirectories()
    }

    func saveSettings() {
        settingsStore.save(settings)
    }

    func cancelCurrentTask() {
        guard isRunning else { return }
        stopOllamaIfNeeded(trigger: "任务终止")
        userCancelledTask = true
        activeTask?.cancel()
        if let process = activeProcess, process.isRunning {
            process.terminate()
        }
        cleanupTaskArtifacts()
        appendRawLog("\n[INFO] 任务终止请求已发送，缓存与临时文件已清理。\n")
    }

    func handleAppTermination() {
        guard isRunning else { return }
        stopOllamaIfNeeded(trigger: "应用退出")
        userCancelledTask = true
        activeTask?.cancel()
        if let process = activeProcess, process.isRunning {
            process.terminate()
        }
    }

    func downloadVideo() {
        guard !youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logs.append("\n请输入 YouTube 链接")
            return
        }

        runTask(kind: .downloadVideo, startMessage: "开始下载视频") {
            let cacheDir = try self.createTaskCacheDirectory(prefix: "download")
            self.registerCleanupDirectory(cacheDir)

            let result = try await self.downloader.download(
                url: self.youtubeURL,
                outputDirectory: self.resolveAppPath(self.settings.downloadOutputDirectory),
                tempDirectory: cacheDir,
                onOutput: { chunk in
                    Task { @MainActor in
                        self.appendRawLog(chunk)
                    }
                },
                onProgress: { progress in
                    Task { @MainActor in
                        self.taskProgress = progress
                    }
                },
                onProcessStart: { process in
                    Task { @MainActor in
                        self.activeProcess = process
                    }
                }
            )

            self.selectedVideoPath = result.videoPath
            if self.selectedTranscodeInputPath.isEmpty {
                self.selectedTranscodeInputPath = result.videoPath
            }
            self.taskProgress = 1
            await self.log("下载完成: \(result.videoPath)")
        }
    }

    func transcodeVideo() {
        guard !selectedTranscodeInputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logs.append("\n请先选择要转码的视频文件")
            return
        }
        guard let crf = Int(selectedTranscodeCRF), (0...51).contains(crf) else {
            logs.append("\nCRF 请输入 0-51 之间的整数")
            return
        }

        runTask(kind: .transcodeVideo, startMessage: "开始视频转码") {
            let inputURL = URL(fileURLWithPath: self.selectedTranscodeInputPath)
            let baseName = inputURL.deletingPathExtension().lastPathComponent
            let outputPath = "\(self.resolveAppPath(self.settings.transcodeOutputDirectory))/\(baseName)_transcoded.\(self.selectedTranscodeFormat)"
            self.registerCleanupFile(outputPath)

            try await self.transcoder.transcode(
                inputPath: self.selectedTranscodeInputPath,
                outputPath: outputPath,
                format: self.selectedTranscodeFormat,
                crf: crf,
                onOutput: { chunk in
                    Task { @MainActor in
                        self.appendRawLog(chunk)
                    }
                },
                onProgress: { progress in
                    Task { @MainActor in
                        self.taskProgress = progress
                    }
                },
                onProcessStart: { process in
                    Task { @MainActor in
                        self.activeProcess = process
                    }
                }
            )

            self.unregisterCleanupFile(outputPath)
            self.taskProgress = 1
            await self.log("转码完成: \(outputPath)")
        }
    }

    func transcribeVideo() {
        guard !selectedVideoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logs.append("\n请先选择视频文件")
            return
        }

        runTask(kind: .transcribeVideo, startMessage: "开始转录字幕") {
            let modelPath = self.localModelPath(for: self.settings.transcriptionModel)
            guard FileManager.default.fileExists(atPath: modelPath) else {
                throw AppError.ioFailed("未检测到本地模型，请先下载: \(self.settings.transcriptionModel.label)")
            }

            let baseName = URL(fileURLWithPath: self.selectedVideoPath).deletingPathExtension().lastPathComponent
            let outputPath = "\(self.resolveAppPath(self.settings.transcribeOutputDirectory))/\(baseName)_original.srt"
            self.registerCleanupFile(outputPath)

            try await self.localWhisperTranscriber.transcribe(
                videoPath: self.selectedVideoPath,
                modelPath: modelPath,
                outputSRTPath: outputPath,
                onOutput: { chunk in
                    Task { @MainActor in
                        self.appendRawLog(chunk)
                    }
                },
                onProgress: { progress in
                    Task { @MainActor in
                        self.taskProgress = progress
                    }
                },
                onProcessStart: { process in
                    Task { @MainActor in
                        self.activeProcess = process
                    }
                }
            )

            // Post-process local Whisper SRT to remove duplicated zero-duration/near-duplicate cues.
            let rawCues = try self.subtitleService.parseSRT(path: outputPath)
            let cleaned = self.subtitleService.cleanTranscriptionCues(rawCues)
            try self.subtitleService.writeSRT(cues: cleaned.cleaned, to: outputPath)

            self.selectedSubtitlePath = outputPath
            self.taskProgress = 1
            self.unregisterCleanupFile(outputPath)
            if cleaned.removedCount > 0 {
                await self.log("转录清洗: 已移除重复/异常片段 \(cleaned.removedCount) 条")
            }
            await self.log("转录完成: \(outputPath)")
        }
    }

    func translateSubtitle() {
        guard !selectedSubtitlePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logs.append("\n请先选择字幕文件")
            return
        }

        runTask(kind: .translateSubtitle, startMessage: "开始翻译字幕") {
            await MainActor.run {
                self.taskProgress = 0
            }

            let cues = try self.subtitleService.parseSRT(path: self.selectedSubtitlePath)

            let client = try OpenAICompatibleClient(baseURL: self.settings.openAIBaseURL, apiKey: self.settings.openAIAPIKey)
            let translator = try self.makeTranslator(settings: self.settings, client: client)
            let texts = cues.map(\.text)
            // For Ollama, use segmented sending (5 cues per request)
            // so cancellation/exit can still stop by not issuing subsequent requests.
            let batchSize = (self.settings.provider == .ollama)
                ? 5
                : self.translationBatchSize(
                    provider: self.settings.provider,
                    mode: self.settings.translationMode,
                    model: self.settings.translationModel
                )
            let totalBatches = max(1, Int(ceil(Double(texts.count) / Double(batchSize))))
            var translated: [String] = []
            await self.log("翻译批次规划: \(totalBatches) 批，每批最多 \(batchSize) 条")

            for batchIndex in 0..<totalBatches {
                let start = batchIndex * batchSize
                let end = min(start + batchSize, texts.count)
                let batch = Array(texts[start..<end])
                let part = try await translator.translateBatch(batch, targetLanguage: self.settings.targetLanguage.code)
                let repaired = try await self.repairLanguageDriftIfNeeded(
                    sourceBatch: batch,
                    translatedBatch: part,
                    targetLanguageCode: self.settings.targetLanguage.code,
                    translator: translator,
                    batchIndex: batchIndex + 1,
                    totalBatches: totalBatches
                )
                translated.append(contentsOf: repaired)

                let ratio = Double(batchIndex + 1) / Double(totalBatches)
                await MainActor.run {
                    self.taskProgress = ratio * 0.95
                }
                await self.log("翻译进度: \(batchIndex + 1)/\(totalBatches)")
            }

            let bilingual = try self.subtitleService.buildBilingualCues(original: cues, translatedTexts: translated)
            let sourceName = URL(fileURLWithPath: self.selectedSubtitlePath).deletingPathExtension().lastPathComponent
            let outputPath = "\(self.resolveAppPath(self.settings.translateOutputDirectory))/\(sourceName)_bilingual.srt"
            self.registerCleanupFile(outputPath)
            try self.subtitleService.writeSRT(cues: bilingual, to: outputPath)
            self.unregisterCleanupFile(outputPath)

            await MainActor.run {
                self.taskProgress = 1
            }
            await self.log("双语字幕已生成: \(outputPath)")
        }
    }

    func downloadTranscriptionModel() {
        runTask(kind: .downloadModel, startMessage: "开始下载转录模型: \(settings.transcriptionModel.label)") {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: self.modelStorageDirectory()),
                withIntermediateDirectories: true,
                attributes: nil
            )

            let model = self.settings.transcriptionModel
            let destination = URL(fileURLWithPath: self.localModelPath(for: model))
            var lastLogTime = Date.distantPast

            try await self.modelDownloader.download(
                from: model.downloadURL,
                to: destination,
                progressHandler: { progress, downloaded, total, speed in
                    Task { @MainActor in
                        self.taskProgress = progress
                        let now = Date()
                        guard now.timeIntervalSince(lastLogTime) >= 0.7 else { return }
                        lastLogTime = now

                        let downloadedStr = Self.formatBytes(downloaded)
                        let totalStr = total.map { Self.formatBytes($0) } ?? "unknown"
                        let speedStr = Self.formatBytes(Int64(speed))
                        if let progress {
                            let percent = Int(progress * 100)
                            await self.log("模型下载: \(percent)% \(downloadedStr)/\(totalStr) 速度 \(speedStr)/s")
                        } else {
                            await self.log("模型下载: \(downloadedStr)/\(totalStr) 速度 \(speedStr)/s")
                        }
                    }
                }
            )

            await MainActor.run {
                self.taskProgress = 1
                self.modelStatusText = "下载完成：\(self.settings.transcriptionModel.label)"
            }
            await self.log("模型下载完成: \(destination.path)")
        }
    }

    func checkTranscriptionModelDownloaded() {
        runTask(kind: .checkModel, startMessage: "检测转录模型可用性: \(settings.transcriptionModel.label)") {
            await MainActor.run {
                self.taskProgress = 0.2
            }
            let path = self.localModelPath(for: self.settings.transcriptionModel)
            if FileManager.default.fileExists(atPath: path) {
                let attr = try FileManager.default.attributesOfItem(atPath: path)
                let size = (attr[.size] as? NSNumber)?.int64Value ?? 0
                if size > 1_000_000 {
                    await MainActor.run {
                        self.modelStatusText = "可用：\(self.settings.transcriptionModel.label)（\(size / 1024 / 1024) MB）"
                    }
                    await self.log("检测成功: 本地模型可用 (\(path), \(size / 1024 / 1024) MB)")
                } else {
                    await MainActor.run {
                        self.modelStatusText = "异常：模型文件过小，可能下载不完整"
                    }
                    await self.log("检测失败: 模型文件过小，可能下载不完整 (\(path))")
                }
            } else {
                await MainActor.run {
                    self.modelStatusText = "未下载：\(self.settings.transcriptionModel.label)"
                }
                await self.log("检测失败: 本地未找到模型文件 (\(path))")
            }
            await MainActor.run {
                self.taskProgress = 1
            }
        }
    }

    func deleteTranscriptionModel() {
        runTask(kind: .deleteModel, startMessage: "删除转录模型: \(settings.transcriptionModel.label)") {
            await MainActor.run {
                self.taskProgress = 0.3
            }
            let path = self.localModelPath(for: self.settings.transcriptionModel)
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
                await MainActor.run {
                    self.modelStatusText = "已删除：\(self.settings.transcriptionModel.label)"
                }
                await self.log("已删除模型文件: \(path)")
            } else {
                await MainActor.run {
                    self.modelStatusText = "未下载：\(self.settings.transcriptionModel.label)"
                }
                await self.log("模型文件不存在，无需删除: \(path)")
            }
            await MainActor.run {
                self.taskProgress = 1
            }
        }
    }

    func applyGlobalOutputDirectoryToAll() {
        settings.downloadOutputDirectory = settings.globalOutputDirectory
        settings.transcodeOutputDirectory = settings.globalOutputDirectory
        settings.transcribeOutputDirectory = settings.globalOutputDirectory
        settings.translateOutputDirectory = settings.globalOutputDirectory
        saveSettings()
    }

    func installMissingTool() {
        let tool = missingToolName
        guard !tool.isEmpty else { return }
        guard let package = packageName(forTool: tool) else {
            appendRawLog("\n[WARN] 未知工具 \(tool)，请手动安装。\n")
            return
        }

        runTask(kind: .installDependency, startMessage: "安装依赖: \(package)") {
            _ = try await ProcessRunner.run(
                "brew",
                args: ["install", package],
                onOutput: { chunk in
                    Task { @MainActor in
                        self.appendRawLog(chunk)
                    }
                },
                onProcessStart: { process in
                    Task { @MainActor in
                        self.activeProcess = process
                    }
                }
            )
            await self.log("依赖安装完成: \(package)")
        }
    }

    func localModelPath(for model: TranscriptionModel) -> String {
        "\(modelStorageDirectory())/\(model.rawValue)"
    }

    func appInternalRootPath() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/YTDMacApp")
            .path
    }

    func resolvedDisplayPath(for relativePath: String) -> String {
        resolveAppPath(relativePath)
    }

    @discardableResult
    func setRelativeDirectory(from absolutePath: String, target: WritableKeyPath<AppSettings, String>) -> Bool {
        let root = appInternalRootPath()
        if absolutePath.hasPrefix(root) {
            var relative = String(absolutePath.dropFirst(root.count))
            if relative.hasPrefix("/") {
                relative.removeFirst()
            }
            settings[keyPath: target] = relative.isEmpty ? "." : relative
        } else {
            // User-selected external path is kept as absolute.
            settings[keyPath: target] = absolutePath
        }
        saveSettings()
        return true
    }

    @discardableResult
    func rememberCommonOutputDirectory(from absolutePath: String) -> Bool {
        let ok1 = setRelativeDirectory(from: absolutePath, target: \.downloadOutputDirectory)
        let ok2 = setRelativeDirectory(from: absolutePath, target: \.transcodeOutputDirectory)
        let ok3 = setRelativeDirectory(from: absolutePath, target: \.translateOutputDirectory)
        let ok4 = setRelativeDirectory(from: absolutePath, target: \.globalOutputDirectory)
        saveSettings()
        return ok1 && ok2 && ok3 && ok4
    }

    private func modelStorageDirectory() -> String {
        resolveAppPath("models/whisper")
    }

    private func cacheStorageDirectory() -> String {
        resolveAppPath("cache")
    }

    private func createTaskCacheDirectory(prefix: String) throws -> String {
        let base = cacheStorageDirectory()
        let fm = FileManager.default
        try fm.createDirectory(atPath: base, withIntermediateDirectories: true)
        let dir = "\(base)/\(prefix)-\(UUID().uuidString)"
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func resolveAppPath(_ relativePath: String) -> String {
        let root = appInternalRootPath()
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "." {
            return root
        }
        if trimmed.hasPrefix("/") {
            return trimmed
        }
        let cleaned = trimmed
        return "\(root)/\(cleaned)"
    }

    private func normalizeSettingsToRelativePaths() {
        let root = appInternalRootPath()
        settings.globalOutputDirectory = normalizeToRelative(settings.globalOutputDirectory, fallback: AppSettings.default.globalOutputDirectory, root: root)
        settings.downloadOutputDirectory = normalizeToRelative(settings.downloadOutputDirectory, fallback: AppSettings.default.downloadOutputDirectory, root: root)
        settings.transcodeOutputDirectory = normalizeToRelative(settings.transcodeOutputDirectory, fallback: AppSettings.default.transcodeOutputDirectory, root: root)
        settings.transcribeOutputDirectory = normalizeToRelative(settings.transcribeOutputDirectory, fallback: AppSettings.default.transcribeOutputDirectory, root: root)
        settings.translateOutputDirectory = normalizeToRelative(settings.translateOutputDirectory, fallback: AppSettings.default.translateOutputDirectory, root: root)
    }

    private func normalizeToRelative(_ value: String, fallback: String, root: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        if trimmed.hasPrefix("/") {
            guard trimmed.hasPrefix(root) else { return trimmed }
            var relative = String(trimmed.dropFirst(root.count))
            if relative.hasPrefix("/") {
                relative.removeFirst()
            }
            return relative.isEmpty ? "." : relative
        }
        return trimmed
    }

    private func ensureAppInternalDirectories() {
        let fm = FileManager.default
        for rel in [
            settings.globalOutputDirectory,
            settings.downloadOutputDirectory,
            settings.transcodeOutputDirectory,
            settings.transcribeOutputDirectory,
            settings.translateOutputDirectory,
            "models/whisper",
            "cache"
        ] {
            let abs = resolveAppPath(rel)
            try? fm.createDirectory(atPath: abs, withIntermediateDirectories: true)
        }
    }

    private func registerCleanupFile(_ path: String) {
        cleanupFilesOnCancel.insert(path)
    }

    private func unregisterCleanupFile(_ path: String) {
        cleanupFilesOnCancel.remove(path)
    }

    private func registerCleanupDirectory(_ path: String) {
        cleanupDirectoriesOnCancel.insert(path)
    }

    private func cleanupTaskArtifacts() {
        let fm = FileManager.default

        for file in cleanupFilesOnCancel {
            if fm.fileExists(atPath: file) {
                try? fm.removeItem(atPath: file)
            }
        }
        for directory in cleanupDirectoriesOnCancel {
            if fm.fileExists(atPath: directory) {
                try? fm.removeItem(atPath: directory)
            }
        }

        cleanupFilesOnCancel.removeAll()
        cleanupDirectoriesOnCancel.removeAll()
    }

    private func runTask(kind: TaskKind, startMessage: String, work: @escaping () async throws -> Void) {
        guard !isRunning else { return }

        isRunning = true
        runningTaskKind = kind
        userCancelledTask = false
        currentTaskTitle = startMessage
        taskProgress = nil
        activeProcess = nil
        cleanupFilesOnCancel.removeAll()
        cleanupDirectoriesOnCancel.removeAll()

        activeTask = Task {
            do {
                await log(startMessage)
                try await work()
            } catch {
                if userCancelledTask || error is CancellationError {
                    cleanupTaskArtifacts()
                    await log("任务已终止，已清理缓存和临时文件")
                } else if case let AppError.toolNotFound(tool) = error {
                    await log("失败: 未找到工具: \(tool)")
                    await MainActor.run {
                        self.missingToolName = tool
                        self.missingToolInstallHint = self.installHint(forTool: tool)
                        self.showMissingToolAlert = true
                    }
                } else {
                    await log("失败: \(error.localizedDescription)")
                }
            }

            await MainActor.run {
                self.isRunning = false
                self.runningTaskKind = nil
                self.currentTaskTitle = ""
                self.taskProgress = nil
                self.activeTask = nil
                self.activeProcess = nil
                self.userCancelledTask = false
                self.saveSettings()
            }
        }
    }

    private func makeTranslator(settings: AppSettings, client: OpenAICompatibleClient) throws -> TranslationService {
        switch settings.provider {
        case .openAICompatible:
            return OpenAICompatibleTranslator(client: client, model: settings.translationModel)
        case .ollama:
            return try OllamaTranslator(baseURL: settings.ollamaBaseURL, model: settings.ollamaModel)
        }
    }

    private func translationBatchSize(provider: TranslationProvider, mode: TranslationMode, model: String) -> Int {
        let isQwenMT = model.lowercased().contains("qwen-mt")
        switch (provider, mode) {
        case (.ollama, .fast): return 1
        case (.ollama, .balanced): return 2
        case (.ollama, .quality): return 4
        case (.openAICompatible, .fast): return isQwenMT ? 5 : 8
        case (.openAICompatible, .balanced): return isQwenMT ? 5 : 12
        case (.openAICompatible, .quality): return isQwenMT ? 5 : 20
        }
    }

    private func repairLanguageDriftIfNeeded(
        sourceBatch: [String],
        translatedBatch: [String],
        targetLanguageCode: String,
        translator: TranslationService,
        batchIndex: Int,
        totalBatches: Int
    ) async throws -> [String] {
        guard sourceBatch.count == translatedBatch.count else {
            return translatedBatch
        }

        guard isLanguageMismatch(text: translatedBatch.joined(separator: " "), targetLanguageCode: targetLanguageCode) else {
            return translatedBatch
        }

        await log("检测到语言漂移，整批重译：批次 \(batchIndex)/\(totalBatches)")
        var latest = translatedBatch
        for _ in 0..<2 {
            let retried = try await translator.translateBatch(sourceBatch, targetLanguage: targetLanguageCode)
            if retried.count == sourceBatch.count {
                latest = retried
                if !isLanguageMismatch(text: retried.joined(separator: " "), targetLanguageCode: targetLanguageCode) {
                    return retried
                }
            }
        }

        await log("警告：该批次重译后仍可能偏离目标语言，已保留最后结果")
        return latest
    }

    private func isLanguageMismatch(text: String, targetLanguageCode: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { return false }

        // Script-first heuristics to avoid false positives on short subtitles.
        let cjkRatio = ratio(in: trimmed, for: { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) || // CJK Unified
            (0x3400...0x4DBF).contains(scalar.value) || // CJK Extension A
            (0x3040...0x30FF).contains(scalar.value) || // Japanese kana
            (0xAC00...0xD7AF).contains(scalar.value)    // Korean hangul
        })
        let latinRatio = ratio(in: trimmed, for: { scalar in
            (0x0041...0x005A).contains(scalar.value) || (0x0061...0x007A).contains(scalar.value)
        })

        let target = normalizedLanguageCode(targetLanguageCode)
        if target == "zh", cjkRatio >= 0.25 { return false }
        if target == "ja", cjkRatio >= 0.20 { return false }
        if target == "ko", cjkRatio >= 0.20 { return false }
        if target == "en", latinRatio >= 0.45 { return false }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        let hyps = recognizer.languageHypotheses(withMaximum: 2)
        guard let (dominantLang, confidence) = hyps.max(by: { $0.value < $1.value }) else { return false }
        guard confidence >= 0.85 else { return false }

        let got = normalizedLanguageCode(dominantLang.rawValue)

        // Chinese variants are considered compatible.
        if target == "zh", got == "zh" { return false }
        return target != got
    }

    private func normalizedLanguageCode(_ code: String) -> String {
        let lower = code.lowercased()
        if lower.hasPrefix("zh") { return "zh" }
        if lower.hasPrefix("en") { return "en" }
        if lower.hasPrefix("ja") { return "ja" }
        if lower.hasPrefix("ko") { return "ko" }
        if lower.hasPrefix("fr") { return "fr" }
        if lower.hasPrefix("de") { return "de" }
        if lower.hasPrefix("es") { return "es" }
        if lower.hasPrefix("vi") { return "vi" }
        return lower
    }

    private func ratio(in text: String, for predicate: (UnicodeScalar) -> Bool) -> Double {
        let scalars = text.unicodeScalars.filter { !$0.properties.isWhitespace }
        guard !scalars.isEmpty else { return 0 }
        let matched = scalars.filter(predicate).count
        return Double(matched) / Double(scalars.count)
    }

    private func log(_ text: String) async {
        await MainActor.run {
            let timestamp = Self.timestampString()
            let line = "[\(timestamp)] \(text)"
            if self.logs.isEmpty {
                self.logs = line
            } else {
                self.logs += "\n\(line)"
            }
        }
    }

    private func appendRawLog(_ text: String) {
        let normalized = text.replacingOccurrences(of: "\r", with: "\n")
        if logs.isEmpty {
            logs = normalized
        } else {
            logs += normalized
        }
    }

    private static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.includesCount = true
        return formatter.string(fromByteCount: bytes)
    }

    private func packageName(forTool tool: String) -> String? {
        switch tool {
        case "whisper-cli":
            return "whisper-cpp"
        case "yt-dlp":
            return "yt-dlp"
        case "ffmpeg":
            return "ffmpeg"
        case "ffprobe":
            return "ffmpeg"
        default:
            return nil
        }
    }

    private func installHint(forTool tool: String) -> String {
        if let package = packageName(forTool: tool) {
            return "建议执行: brew install \(package)"
        }
        return "请手动安装缺失工具: \(tool)"
    }

    private func stopOllamaIfNeeded(trigger: String) {
        guard runningTaskKind == .translateSubtitle, settings.provider == .ollama else { return }
        let model = settings.ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return }

        Task {
            await self.log("\(trigger)：尝试停止 Ollama 模型 \(model)")
            do {
                _ = try await ProcessRunner.run("ollama", args: ["stop", model])
                await self.log("已停止 Ollama 模型: \(model)")
            } catch {
                await self.log("停止 Ollama 模型失败: \(error.localizedDescription)")
            }
        }
    }
}
