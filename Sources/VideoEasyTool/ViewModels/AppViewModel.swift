import CryptoKit
import Foundation
import NaturalLanguage

@MainActor
final class AppViewModel: ObservableObject {
    @Published var youtubeURL: String = ""
    @Published var selectedVideoPath: String = ""
    @Published var selectedTranscodeInputPath: String = ""
    @Published var selectedTranscodeFormat: String = "mp4"
    @Published var selectedTranscodeCRF: String = "23"
    @Published var selectedClipStartTime: String = ""
    @Published var selectedClipEndTime: String = ""
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
    @Published var showPlaylistChoiceAlert: Bool = false
    @Published var translationPromptTokens: Int = 0
    @Published var translationCompletionTokens: Int = 0
    @Published var translationTotalTokens: Int = 0
    @Published var showCacheResultAlert: Bool = false
    @Published var cacheResultTitle: String = ""
    @Published var cacheResultMessage: String = ""

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
    private var pendingPlaylistDownloadURL: String?
    private var rawLogCarryover: String = ""

    init() {
        self.settings = settingsStore.load()
        normalizeSettingsToRelativePaths()
        ensureAppInternalDirectories()
        if settings.customTranslationBatchSize <= 0 {
            settings.customTranslationBatchSize = recommendedTranslationBatchSize(
                provider: settings.provider,
                mode: settings.translationMode,
                model: settings.translationModel
            )
        }
        self.modelStatusText = self.ui("未检测", "Not checked")
    }

    func saveSettings() {
        settingsStore.save(settings)
    }

    var shouldWarnBeforeClosingWindow: Bool {
        if isRunning { return true }
        if let activeProcess, activeProcess.isRunning { return true }
        if activeTask != nil { return true }
        return false
    }

    func cancelCurrentTask() {
        guard isRunning else { return }
        stopOllamaIfNeeded(trigger: self.ui("任务终止", "Task stopped"))
        userCancelledTask = true
        activeTask?.cancel()
        if let process = activeProcess, process.isRunning {
            ProcessRunner.terminateProcessTree(process)
        }
        currentTaskTitle = ""
        taskProgress = nil
        cleanupTaskArtifacts()
        appendRawLog("\n[INFO] \(self.ui("任务终止请求已发送，缓存与临时文件已清理。", "Stop request sent. Cache and temporary files were cleaned."))\n")
    }

    func handleAppTermination() {
        guard isRunning else { return }
        stopOllamaIfNeeded(trigger: self.ui("应用退出", "App exit"))
        userCancelledTask = true
        activeTask?.cancel()
        if let process = activeProcess, process.isRunning {
            ProcessRunner.terminateProcessTree(process)
        }
        currentTaskTitle = ""
        taskProgress = nil
    }

    func downloadVideo() {
        let trimmedURL = youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            appendRawLog(self.ui("请输入 YouTube 或哔哩哔哩链接", "Please enter a YouTube or Bilibili URL") + "\n")
            return
        }

        if shouldConfirmPlaylistChoice(for: trimmedURL) {
            pendingPlaylistDownloadURL = trimmedURL
            showPlaylistChoiceAlert = true
            return
        }

        startDownload(url: trimmedURL, allowPlaylist: false)
    }

    func downloadOnlyCurrentVideo() {
        let url = pendingPlaylistDownloadURL ?? youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingPlaylistDownloadURL = nil
        showPlaylistChoiceAlert = false
        guard !url.isEmpty else { return }
        startDownload(url: url, allowPlaylist: false)
    }

    func downloadEntirePlaylist() {
        let url = pendingPlaylistDownloadURL ?? youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingPlaylistDownloadURL = nil
        showPlaylistChoiceAlert = false
        guard !url.isEmpty else { return }
        startDownload(url: url, allowPlaylist: true)
    }

    private func startDownload(url: String, allowPlaylist: Bool) {
        youtubeURL = url

        runTask(kind: .downloadVideo, startMessage: self.ui("开始下载视频", "Starting video download")) {
            let cacheDir = try self.createTaskCacheDirectory(prefix: "download")
            self.registerCleanupDirectory(cacheDir)

            let result = try await self.downloader.download(
                url: url,
                outputDirectory: self.resolveAppPath(self.settings.downloadOutputDirectory),
                allowPlaylist: allowPlaylist,
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
            await self.log("\(self.ui("下载完成", "Download completed")): \(result.videoPath)")
        }
    }

    private func shouldConfirmPlaylistChoice(for urlString: String) -> Bool {
        guard let components = URLComponents(string: urlString),
              let queryItems = components.queryItems else {
            return false
        }
        return queryItems.contains { $0.name.caseInsensitiveCompare("list") == .orderedSame && !($0.value?.isEmpty ?? true) }
    }

    func transcodeVideo() {
        guard !selectedTranscodeInputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appendRawLog(self.ui("请先选择要转码的视频文件", "Please choose a video file to transcode") + "\n")
            return
        }
        guard let crf = Int(selectedTranscodeCRF), (0...51).contains(crf) else {
            appendRawLog(self.ui("CRF 请输入 0-51 之间的整数", "Please enter an integer between 0 and 51 for CRF") + "\n")
            return
        }
        let clipStart = selectedClipStartTime.trimmingCharacters(in: .whitespacesAndNewlines)
        let clipEnd = selectedClipEndTime.trimmingCharacters(in: .whitespacesAndNewlines)
        let startSeconds = try? parseEditTime(clipStart)
        let endSeconds = try? parseEditTime(clipEnd)

        if !clipStart.isEmpty && startSeconds == nil {
            appendRawLog(self.ui("开始时间格式无效，请使用 HH:MM:SS 或 MM:SS", "Invalid start time. Use HH:MM:SS or MM:SS") + "\n")
            return
        }
        if !clipEnd.isEmpty && endSeconds == nil {
            appendRawLog(self.ui("结束时间格式无效，请使用 HH:MM:SS 或 MM:SS", "Invalid end time. Use HH:MM:SS or MM:SS") + "\n")
            return
        }
        if let startSeconds, let endSeconds, endSeconds <= startSeconds {
            appendRawLog(self.ui("结束时间必须大于开始时间", "End time must be greater than start time") + "\n")
            return
        }

        let isClipEdit = startSeconds != nil || endSeconds != nil
        runTask(kind: .transcodeVideo, startMessage: isClipEdit ? self.ui("开始视频编辑", "Starting video edit") : self.ui("开始视频转码", "Starting video transcode")) {
            let inputURL = URL(fileURLWithPath: self.selectedTranscodeInputPath)
            let baseName = inputURL.deletingPathExtension().lastPathComponent
            let suffix = isClipEdit ? "_edited" : "_transcoded"
            let outputPath = "\(self.resolveAppPath(self.settings.transcodeOutputDirectory))/\(baseName)\(suffix).\(self.selectedTranscodeFormat)"
            self.registerCleanupFile(outputPath)

            try await self.transcoder.transcode(
                inputPath: self.selectedTranscodeInputPath,
                outputPath: outputPath,
                format: self.selectedTranscodeFormat,
                crf: crf,
                clipStartTime: startSeconds,
                clipEndTime: endSeconds,
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
            await self.log("\(isClipEdit ? self.ui("视频编辑完成", "Video edit completed") : self.ui("转码完成", "Transcode completed")): \(outputPath)")
        }
    }

    private func parseEditTime(_ value: String) throws -> TimeInterval {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        let parts = trimmed.split(separator: ":").map(String.init)
        guard (2...3).contains(parts.count) else {
            throw AppError.parseFailed("invalid time")
        }

        let secondsPart = parts.last ?? "0"
        guard let seconds = Double(secondsPart) else {
            throw AppError.parseFailed("invalid time")
        }

        if parts.count == 2 {
            guard let minutes = Double(parts[0]) else {
                throw AppError.parseFailed("invalid time")
            }
            return minutes * 60 + seconds
        }

        guard let hours = Double(parts[0]), let minutes = Double(parts[1]) else {
            throw AppError.parseFailed("invalid time")
        }
        return hours * 3600 + minutes * 60 + seconds
    }

    func transcribeVideo() {
        guard !selectedVideoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appendRawLog(self.ui("请先选择视频文件", "Please choose a video file first") + "\n")
            return
        }

        runTask(kind: .transcribeVideo, startMessage: self.ui("开始转录字幕", "Starting subtitle transcription")) {
            let modelPath = self.localModelPath(for: self.settings.transcriptionModel)
            guard FileManager.default.fileExists(atPath: modelPath) else {
                throw AppError.ioFailed("\(self.ui("未检测到本地模型，请先下载", "Local model not found, please download it first")): \(self.settings.transcriptionModel.label)")
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
                await self.log("\(self.ui("转录清洗", "Transcription cleanup")): \(self.ui("已移除重复/异常片段", "Removed duplicate/invalid segments")) \(cleaned.removedCount) \(self.ui("条", "items"))")
            }
            await self.log("\(self.ui("转录完成", "Transcription completed")): \(outputPath)")
        }
    }

    func translateSubtitle() {
        guard !selectedSubtitlePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appendRawLog(self.ui("请先选择字幕文件", "Please choose a subtitle file first") + "\n")
            return
        }

        runTask(kind: .translateSubtitle, startMessage: self.ui("开始翻译字幕", "Starting subtitle translation")) {
            await MainActor.run {
                self.taskProgress = 0
                self.translationPromptTokens = 0
                self.translationCompletionTokens = 0
                self.translationTotalTokens = 0
            }

            let subtitlePath = self.selectedSubtitlePath
            let cues = try self.subtitleService.parseSRT(path: subtitlePath)
            let sourceDigest = try self.subtitleDigest(for: subtitlePath)
            let batchSize = self.effectiveTranslationBatchSize()
            let sessionPath = self.translationSessionPath(
                sourceSubtitlePath: subtitlePath,
                targetLanguageCode: self.settings.targetLanguage.code,
                provider: self.settings.provider,
                modelIdentifier: self.translationSessionModelIdentifier(settings: self.settings),
                mode: self.settings.translationMode
            )
            var resumeSession = self.loadTranslationResumeSession(from: sessionPath)
            let canResume = self.canResumeTranslation(
                session: resumeSession,
                sourceSubtitlePath: subtitlePath,
                sourceDigest: sourceDigest,
                targetLanguageCode: self.settings.targetLanguage.code,
                provider: self.settings.provider,
                modelIdentifier: self.translationSessionModelIdentifier(settings: self.settings),
                mode: self.settings.translationMode,
                totalCueCount: cues.count,
                batchSize: batchSize
            )

            let client = try OpenAICompatibleClient(baseURL: self.settings.openAIBaseURL, apiKey: self.settings.openAIAPIKey)
            let translator = try self.makeTranslator(settings: self.settings, client: client)
            let texts = cues.map(\.text)
            let totalBatches = max(1, Int(ceil(Double(texts.count) / Double(batchSize))))
            var translated: [String] = canResume ? (resumeSession?.translatedTexts ?? []) : []
            let resumeBatchIndex = canResume ? min(resumeSession?.completedBatchCount ?? 0, totalBatches) : 0

            if canResume, resumeBatchIndex > 0 {
                await self.log("\(self.ui("检测到未完成翻译，已自动续翻", "Detected unfinished translation and resumed automatically")): \(resumeBatchIndex + 1)/\(totalBatches)")
                await MainActor.run {
                    self.taskProgress = totalBatches > 0 ? (Double(resumeBatchIndex) / Double(totalBatches)) * 0.95 : 0
                }
            } else {
                resumeSession = TranslationResumeSession(
                    sourceSubtitlePath: subtitlePath,
                    sourceDigest: sourceDigest,
                    targetLanguageCode: self.settings.targetLanguage.code,
                    providerRawValue: self.settings.provider.rawValue,
                    modelIdentifier: self.translationSessionModelIdentifier(settings: self.settings),
                    modeRawValue: self.settings.translationMode.rawValue,
                    translatedTexts: [],
                    completedBatchCount: 0,
                    totalCueCount: cues.count,
                    batchSize: batchSize,
                    updatedAt: Date()
                )
                try self.saveTranslationResumeSession(resumeSession!, to: sessionPath)
            }

            await self.log("\(self.ui("翻译批次规划", "Translation batching")): \(totalBatches) \(self.ui("批，每批最多", "batches, up to")) \(batchSize) \(self.ui("条", "items"))")

            for batchIndex in resumeBatchIndex..<totalBatches {
                let start = batchIndex * batchSize
                let end = min(start + batchSize, texts.count)
                let batch = Array(texts[start..<end])
                let contextHint = self.translationContextHint(from: texts, startIndex: start)
                let part = try await translator.translateBatch(
                    batch,
                    targetLanguage: self.settings.targetLanguage.code,
                    contextHint: contextHint
                )
                let repaired = try await self.repairLanguageDriftIfNeeded(
                    sourceBatch: batch,
                    translatedBatch: part,
                    targetLanguageCode: self.settings.targetLanguage.code,
                    translator: translator,
                    contextHint: contextHint,
                    batchIndex: batchIndex + 1,
                    totalBatches: totalBatches
                )
                translated.append(contentsOf: repaired)
                if var session = resumeSession {
                    session.translatedTexts = translated
                    session.completedBatchCount = batchIndex + 1
                    session.updatedAt = Date()
                    resumeSession = session
                    try self.saveTranslationResumeSession(session, to: sessionPath)
                }

                let ratio = Double(batchIndex + 1) / Double(totalBatches)
                await MainActor.run {
                    self.taskProgress = ratio * 0.95
                }
                await self.log("\(self.ui("翻译进度", "Translation progress")): \(batchIndex + 1)/\(totalBatches)")
                if self.settings.provider == .openAICompatible {
                    await self.log(
                        "\(self.ui("Token 用量", "Token usage")): \(self.translationTokenUsageText)"
                    )
                }
            }

            let bilingual = try self.subtitleService.buildBilingualCues(original: cues, translatedTexts: translated)
            let sourceName = URL(fileURLWithPath: self.selectedSubtitlePath).deletingPathExtension().lastPathComponent
            let outputPath = "\(self.resolveAppPath(self.settings.translateOutputDirectory))/\(sourceName)_bilingual.srt"
            self.registerCleanupFile(outputPath)
            try self.subtitleService.writeSRT(cues: bilingual, to: outputPath)
            self.unregisterCleanupFile(outputPath)
            self.removeTranslationResumeSession(at: sessionPath)

            await MainActor.run {
                self.taskProgress = 1
            }
            await self.log("\(self.ui("双语字幕已生成", "Bilingual subtitle generated")): \(outputPath)")
            await self.log(self.ui("翻译断点缓存已清理", "Translation resume cache cleared"))
        }
    }

    func downloadTranscriptionModel() {
        runTask(kind: .downloadModel, startMessage: "\(self.ui("开始下载转录模型", "Starting model download")): \(settings.transcriptionModel.label)") {
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
                            await self.log("\(self.ui("模型下载", "Model download")): \(percent)% \(downloadedStr)/\(totalStr) \(self.ui("速度", "speed")) \(speedStr)/s")
                        } else {
                            await self.log("\(self.ui("模型下载", "Model download")): \(downloadedStr)/\(totalStr) \(self.ui("速度", "speed")) \(speedStr)/s")
                        }
                    }
                }
            )

            await MainActor.run {
                self.taskProgress = 1
                self.modelStatusText = "\(self.ui("下载完成", "Download completed")): \(self.settings.transcriptionModel.label)"
            }
            await self.log("\(self.ui("模型下载完成", "Model download completed")): \(destination.path)")
        }
    }

    func checkTranscriptionModelDownloaded() {
        runTask(kind: .checkModel, startMessage: "\(self.ui("检测转录模型可用性", "Checking model availability")): \(settings.transcriptionModel.label)") {
            await MainActor.run {
                self.taskProgress = 0.2
            }
            let path = self.localModelPath(for: self.settings.transcriptionModel)
            if FileManager.default.fileExists(atPath: path) {
                let attr = try FileManager.default.attributesOfItem(atPath: path)
                let size = (attr[.size] as? NSNumber)?.int64Value ?? 0
                if size > 1_000_000 {
                    await MainActor.run {
                        self.modelStatusText = "\(self.ui("可用", "Available")): \(self.settings.transcriptionModel.label) (\(size / 1024 / 1024) MB)"
                    }
                    await self.log("\(self.ui("检测成功", "Check succeeded")): \(self.ui("本地模型可用", "Local model is available")) (\(path), \(size / 1024 / 1024) MB)")
                } else {
                    await MainActor.run {
                        self.modelStatusText = self.ui("异常：模型文件过小，可能下载不完整", "Warning: model file is too small and may be incomplete")
                    }
                    await self.log("\(self.ui("检测失败", "Check failed")): \(self.ui("模型文件过小，可能下载不完整", "Model file is too small and may be incomplete")) (\(path))")
                }
            } else {
                await MainActor.run {
                    self.modelStatusText = "\(self.ui("未下载", "Not downloaded")): \(self.settings.transcriptionModel.label)"
                }
                await self.log("\(self.ui("检测失败", "Check failed")): \(self.ui("本地未找到模型文件", "Local model file not found")) (\(path))")
            }
            await MainActor.run {
                self.taskProgress = 1
            }
        }
    }

    func deleteTranscriptionModel() {
        runTask(kind: .deleteModel, startMessage: "\(self.ui("删除转录模型", "Deleting model")): \(settings.transcriptionModel.label)") {
            await MainActor.run {
                self.taskProgress = 0.3
            }
            let path = self.localModelPath(for: self.settings.transcriptionModel)
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
                await MainActor.run {
                    self.modelStatusText = "\(self.ui("已删除", "Deleted")): \(self.settings.transcriptionModel.label)"
                }
                await self.log("\(self.ui("已删除模型文件", "Deleted model file")): \(path)")
            } else {
                await MainActor.run {
                    self.modelStatusText = "\(self.ui("未下载", "Not downloaded")): \(self.settings.transcriptionModel.label)"
                }
                await self.log("\(self.ui("模型文件不存在，无需删除", "Model file does not exist, no need to delete")): \(path)")
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
            appendRawLog("\n[WARN] \(self.ui("未知工具", "Unknown tool")) \(tool)，\(self.ui("请手动安装。", "please install it manually."))\n")
            return
        }

        runTask(kind: .installDependency, startMessage: "\(self.ui("安装依赖", "Installing dependency")): \(package)") {
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
            await self.log("\(self.ui("依赖安装完成", "Dependency installed")): \(package)")
        }
    }

    func localModelPath(for model: TranscriptionModel) -> String {
        "\(modelStorageDirectory())/\(model.rawValue)"
    }

    func appInternalRootPath() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VideoEasyTool")
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

    func clearAppCache() {
        let cachePath = cacheStorageDirectory()
        let fm = FileManager.default

        do {
            if fm.fileExists(atPath: cachePath) {
                try fm.removeItem(atPath: cachePath)
            }
            try fm.createDirectory(atPath: cachePath, withIntermediateDirectories: true)
            appendRawLog("[INFO] \(self.ui("缓存已清理", "Cache cleared")): \(cachePath)\n")
            cacheResultTitle = self.ui("缓存已清理", "Cache Cleared")
            cacheResultMessage = self.ui("应用缓存已清理完成。", "The app cache has been cleared.")
            showCacheResultAlert = true
        } catch {
            appendRawLog("[WARN] \(self.ui("清理缓存失败", "Failed to clear cache")): \(localizedErrorMessage(error))\n")
            cacheResultTitle = self.ui("清理缓存失败", "Cache Clear Failed")
            cacheResultMessage = localizedErrorMessage(error)
            showCacheResultAlert = true
        }
    }

    private func modelStorageDirectory() -> String {
        resolveAppPath("models/whisper")
    }

    private func cacheStorageDirectory() -> String {
        resolveAppPath("cache")
    }

    private func translationSessionStorageDirectory() -> String {
        resolveAppPath("cache/translation-sessions")
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
            "cache",
            "cache/translation-sessions"
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
                    await log(self.ui("任务已终止，已清理缓存和临时文件", "Task stopped. Cache and temporary files were cleaned"))
                } else if case let AppError.toolNotFound(tool) = error {
                    await log("\(self.ui("失败", "Failed")): \(self.ui("未找到工具", "Tool not found")): \(tool)")
                    await MainActor.run {
                        self.missingToolName = tool
                        self.missingToolInstallHint = self.installHint(forTool: tool)
                        self.showMissingToolAlert = true
                    }
                } else {
                    await log("\(self.ui("失败", "Failed")): \(self.localizedErrorMessage(error))")
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
            return OpenAICompatibleTranslator(
                client: client,
                model: settings.translationModel,
                temperature: settings.translationTemperature,
                onUsage: { usage in
                    Task { @MainActor in
                        self.translationPromptTokens += usage.promptTokens
                        self.translationCompletionTokens += usage.completionTokens
                        self.translationTotalTokens += usage.totalTokens
                    }
                }
            )
        case .ollama:
            let resolvedMode = resolvedOllamaWorkMode(settings: settings)
            return try OllamaTranslator(
                baseURL: settings.ollamaBaseURL,
                model: settings.ollamaModel,
                temperature: settings.translationTemperature,
                workMode: resolvedMode
            )
        }
    }

    private func recommendedTranslationBatchSize(provider: TranslationProvider, mode: TranslationMode, model: String) -> Int {
        if provider == .ollama {
            return 5
        }
        switch (provider, mode) {
        case (.openAICompatible, _): return 10
        case (.ollama, _): return 5
        }
    }

    func effectiveTranslationBatchSize() -> Int {
        if settings.useCustomTranslationBatchSize {
            return max(1, settings.customTranslationBatchSize)
        }
        return recommendedTranslationBatchSize(
            provider: settings.provider,
            mode: settings.translationMode,
            model: settings.translationModel
        )
    }

    func resetTranslationAdvancedSettings() {
        settings.translationTemperature = 0.1
        settings.useCustomTranslationBatchSize = false
        settings.ollamaWorkMode = .automatic
        settings.customTranslationBatchSize = recommendedTranslationBatchSize(
            provider: settings.provider,
            mode: settings.translationMode,
            model: settings.translationModel
        )
    }

    private func repairLanguageDriftIfNeeded(
        sourceBatch: [String],
        translatedBatch: [String],
        targetLanguageCode: String,
        translator: TranslationService,
        contextHint: [String],
        batchIndex: Int,
        totalBatches: Int
    ) async throws -> [String] {
        guard sourceBatch.count == translatedBatch.count else {
            return translatedBatch
        }

        let mismatchCount = translatedBatch.filter { isLanguageMismatch(text: $0, targetLanguageCode: targetLanguageCode) }.count
        guard mismatchCount > 0 else {
            return translatedBatch
        }

        await log("\(self.ui("检测到语言漂移，整批重译", "Language drift detected, retranslating batch")): \(batchIndex)/\(totalBatches) (\(mismatchCount) \(self.ui("条疑似偏离目标语言", "items may be off-target")))")
        var latest = translatedBatch
        for _ in 0..<2 {
            let retried = try await translator.translateBatch(
                sourceBatch,
                targetLanguage: targetLanguageCode,
                contextHint: contextHint
            )
            if retried.count == sourceBatch.count {
                latest = retried
                let retriedMismatchCount = retried.filter { isLanguageMismatch(text: $0, targetLanguageCode: targetLanguageCode) }.count
                if retriedMismatchCount == 0 {
                    return retried
                }
            }
        }

        await log(self.ui("警告：该批次重译后仍可能偏离目标语言，已保留最后结果", "Warning: this batch may still deviate from the target language after retry; keeping the latest result"))
        return latest
    }

    private func translationContextHint(from texts: [String], startIndex: Int) -> [String] {
        guard startIndex > 0 else { return [] }
        let contextStart = max(0, startIndex - 2)
        return Array(texts[contextStart..<startIndex])
    }

    func resolvedOllamaWorkMode(settings: AppSettings? = nil) -> OllamaResolvedWorkMode {
        let current = settings ?? self.settings
        return OllamaModelRules.resolve(modelName: current.ollamaModel, userPreference: current.ollamaWorkMode)
    }

    func ollamaWorkModeLabel() -> String {
        switch resolvedOllamaWorkMode() {
        case .structuredJSON:
            return ui("批量 JSON", "Structured JSON")
        case .singleText:
            return ui("单条文本", "Single Text")
        case .unsupported:
            return ui("不支持", "Unsupported")
        }
    }

    func ollamaModelCategoryLabel() -> String {
        guard let rule = OllamaModelRules.matchedRule(for: settings.ollamaModel) else {
            return ui("未识别", "Unclassified")
        }

        switch rule.category {
        case .generalChat:
            return ui("通用聊天", "General Chat")
        case .translation:
            return ui("翻译专用", "Translation")
        case .embedding:
            return ui("Embedding", "Embedding")
        case .vision:
            return ui("视觉", "Vision")
        }
    }

    func ollamaMatchedKeywordsLabel() -> String {
        let keywords = OllamaModelRules.matchedKeywords(for: settings.ollamaModel)
        guard !keywords.isEmpty else {
            return ui("无", "None")
        }
        return keywords.joined(separator: ", ")
    }

    func ollamaModelRuleDescription() -> String {
        guard let rule = OllamaModelRules.matchedRule(for: settings.ollamaModel) else {
            return ui("未命中预设规则，默认使用批量 JSON 模式。", "No preset rule matched. Using structured batch mode by default.")
        }

        switch rule.mode {
        case .structuredJSON:
            return ui("识别为通用聊天模型，默认走批量 JSON 翻译。", "Detected as a general chat model. Structured batch translation is used by default.")
        case .singleText:
            return ui("识别为专用翻译模型，默认走单条文本翻译。", "Detected as a dedicated translation model. Single-text translation is used by default.")
        case .unsupported(let reason):
            return ui("识别为不适合字幕翻译的模型：", "Detected as a model that is not suitable for subtitle translation: ") + reason
        }
    }

    private func subtitleDigest(for path: String) throws -> String {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func translationSessionModelIdentifier(settings: AppSettings) -> String {
        switch settings.provider {
        case .openAICompatible:
            return "openai:\(settings.translationModel)"
        case .ollama:
            return "ollama:\(settings.ollamaModel)#\(ollamaSessionModeKey(for: settings))"
        }
    }

    private func ollamaSessionModeKey(for settings: AppSettings) -> String {
        switch resolvedOllamaWorkMode(settings: settings) {
        case .structuredJSON:
            return "structured-json"
        case .singleText:
            return "single-text"
        case .unsupported:
            return "unsupported"
        }
    }

    private func translationSessionPath(
        sourceSubtitlePath: String,
        targetLanguageCode: String,
        provider: TranslationProvider,
        modelIdentifier: String,
        mode: TranslationMode
    ) -> String {
        let key = [
            sourceSubtitlePath,
            targetLanguageCode,
            provider.rawValue,
            modelIdentifier,
            mode.rawValue
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return "\(translationSessionStorageDirectory())/\(digest).json"
    }

    private func loadTranslationResumeSession(from path: String) -> TranslationResumeSession? {
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        return try? JSONDecoder().decode(TranslationResumeSession.self, from: data)
    }

    private func saveTranslationResumeSession(_ session: TranslationResumeSession, to path: String) throws {
        let dir = translationSessionStorageDirectory()
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(session)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private func removeTranslationResumeSession(at path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    private func canResumeTranslation(
        session: TranslationResumeSession?,
        sourceSubtitlePath: String,
        sourceDigest: String,
        targetLanguageCode: String,
        provider: TranslationProvider,
        modelIdentifier: String,
        mode: TranslationMode,
        totalCueCount: Int,
        batchSize: Int
    ) -> Bool {
        guard let session else { return false }
        guard session.sourceSubtitlePath == sourceSubtitlePath else { return false }
        guard session.sourceDigest == sourceDigest else { return false }
        guard session.targetLanguageCode == targetLanguageCode else { return false }
        guard session.providerRawValue == provider.rawValue else { return false }
        guard session.modelIdentifier == modelIdentifier else { return false }
        guard session.modeRawValue == mode.rawValue else { return false }
        guard session.totalCueCount == totalCueCount else { return false }
        guard session.batchSize == batchSize else { return false }
        guard !session.translatedTexts.isEmpty else { return false }
        guard session.translatedTexts.count <= totalCueCount else { return false }
        return true
    }

    var translationTokenUsageText: String {
        "\(self.ui("总计", "Total")) \(translationTotalTokens) · \(self.ui("输入", "Input")) \(translationPromptTokens) · \(self.ui("输出", "Output")) \(translationCompletionTokens)"
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
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let combined = rawLogCarryover + normalized
        let parts = combined.components(separatedBy: "\n")
        let endsWithNewline = combined.hasSuffix("\n")
        let completeLines = endsWithNewline ? parts : Array(parts.dropLast())
        rawLogCarryover = endsWithNewline ? "" : (parts.last ?? "")

        for line in completeLines {
            appendTimestampedLine(line)
        }
    }

    private func appendTimestampedLine(_ line: String) {
        let entry: String
        if line.isEmpty {
            entry = ""
        } else {
            entry = "[\(Self.timestampString())] \(line)"
        }

        if logs.isEmpty {
            logs = entry
        } else {
            logs += "\n\(entry)"
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
            return self.ui("建议执行", "Suggested command") + ": brew install \(package)"
        }
        return "\(self.ui("请手动安装缺失工具", "Please install the missing tool manually")): \(tool)"
    }

    private func stopOllamaIfNeeded(trigger: String) {
        guard runningTaskKind == .translateSubtitle, settings.provider == .ollama else { return }
        let model = settings.ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return }

        Task {
            await self.log("\(trigger): \(self.ui("尝试停止 Ollama 模型", "Trying to stop Ollama model")) \(model)")
            do {
                _ = try await ProcessRunner.run("ollama", args: ["stop", model])
                await self.log("\(self.ui("已停止 Ollama 模型", "Stopped Ollama model")): \(model)")
            } catch {
                await self.log("\(self.ui("停止 Ollama 模型失败", "Failed to stop Ollama model")): \(localizedErrorMessage(error))")
            }
        }
    }

    func ui(_ zh: String, _ en: String) -> String {
        settings.displayLanguage == .english ? en : zh
    }

    func localizedErrorMessage(_ error: Error) -> String {
        guard settings.displayLanguage == .english else {
            return error.localizedDescription
        }

        if let appError = error as? AppError {
            switch appError {
            case .toolNotFound(let tool):
                return "Tool not found: \(tool)"
            case .processFailed(let detail):
                return "Process failed: \(detail)"
            case .invalidResponse(let detail):
                return "Invalid response: \(detail)"
            case .parseFailed(let detail):
                return "Parse failed: \(detail)"
            case .ioFailed(let detail):
                return "I/O failed: \(detail)"
            }
        }

        return error.localizedDescription
    }
}
