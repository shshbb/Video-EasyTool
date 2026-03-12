import Foundation

final class ModelDownloadService {
    typealias ProgressHandler = (_ progress: Double?, _ downloadedBytes: Int64, _ totalBytes: Int64?, _ speedBytesPerSec: Double) -> Void

    func download(
        from url: URL,
        to destination: URL,
        progressHandler: @escaping ProgressHandler
    ) async throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("model-download-\(UUID().uuidString).tmp")

        let downloader = StreamingDownloader(tempURL: tempURL, progressHandler: progressHandler)

        let downloadedTemp = try await downloader.start(url: url)

        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: downloadedTemp)
        } else {
            try FileManager.default.moveItem(at: downloadedTemp, to: destination)
        }
    }
}

private final class StreamingDownloader: NSObject, URLSessionDataDelegate {
    private let tempURL: URL
    private let progressHandler: ModelDownloadService.ProgressHandler

    private var fileHandle: FileHandle?
    private var expectedBytes: Int64?
    private var downloadedBytes: Int64 = 0
    private var startTime = Date()

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<URL, Error>?

    init(tempURL: URL, progressHandler: @escaping ModelDownloadService.ProgressHandler) {
        self.tempURL = tempURL
        self.progressHandler = progressHandler
        super.init()
    }

    func start(url: URL) async throws -> URL {
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: tempURL)
        startTime = Date()

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                self.continuation = continuation
                let configuration = URLSessionConfiguration.default
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                self.session = session
                let task = session.dataTask(with: url)
                self.task = task
                task.resume()
            }
        }, onCancel: {
            self.task?.cancel()
        })
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
        if response.expectedContentLength > 0 {
            expectedBytes = response.expectedContentLength
        } else {
            expectedBytes = nil
        }
        return .allow
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try fileHandle?.write(contentsOf: data)
            downloadedBytes += Int64(data.count)
            let elapsed = Date().timeIntervalSince(startTime)
            let speed = elapsed > 0 ? Double(downloadedBytes) / elapsed : 0
            let progress: Double?
            if let total = expectedBytes, total > 0 {
                progress = min(max(Double(downloadedBytes) / Double(total), 0), 1)
            } else {
                progress = nil
            }
            progressHandler(progress, downloadedBytes, expectedBytes, speed)
        } catch {
            finish(error: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(error: error)
        } else {
            finishSuccess()
        }
    }

    private func finishSuccess() {
        do {
            try fileHandle?.close()
        } catch {
            finish(error: error)
            return
        }

        continuation?.resume(returning: tempURL)
        cleanupAfterFinish()
    }

    private func finish(error: Error) {
        try? fileHandle?.close()
        continuation?.resume(throwing: error)
        try? FileManager.default.removeItem(at: tempURL)
        cleanupAfterFinish()
    }

    private func cleanupAfterFinish() {
        continuation = nil
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }
}
