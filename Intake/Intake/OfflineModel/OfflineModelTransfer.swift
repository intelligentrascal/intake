import Foundation

/// One HTTP transfer of a model file into its `.partial` file, resumable with
/// `Range: bytes=<n>-`.
///
/// A plain data task streaming to disk, not a background download task: the
/// partial file is ours, so it survives quit, sleep and Cancel (kept 24 h),
/// and resumes from its byte count on any network. All callbacks arrive on a
/// private serial queue; the caller hops to the main actor.
nonisolated final class OfflineModelTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Outcome: Equatable, Sendable {
        case finished(totalBytes: Int64)
        case httpStatus(Int)
        case networkLost(receivedBytes: Int64)
        case diskFull(shortBytes: Int64)
        case cancelled
    }

    private let sourceURL: URL
    private let destination: URL
    private let startByte: Int64
    private let expectedTotal: Int64
    private let onProgress: @Sendable (Int64) -> Void
    private let onComplete: @Sendable (Outcome) -> Void

    private let lock = NSLock()
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var handle: FileHandle?
    private var received: Int64
    private var lastProgressReport = Date.distantPast
    private var finalOutcome: Outcome?

    init(
        sourceURL: URL,
        destination: URL,
        startByte: Int64,
        expectedTotal: Int64,
        onProgress: @escaping @Sendable (Int64) -> Void,
        onComplete: @escaping @Sendable (Outcome) -> Void
    ) {
        self.sourceURL = sourceURL
        self.destination = destination
        self.startByte = startByte
        self.expectedTotal = expectedTotal
        self.onProgress = onProgress
        self.onComplete = onComplete
        received = startByte
    }

    func start() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        var request = URLRequest(url: sourceURL)
        if startByte > 0 {
            request.setValue("bytes=\(startByte)-", forHTTPHeaderField: "Range")
        }
        let task = session.dataTask(with: request)
        lock.withLock {
            self.session = session
            self.task = task
        }
        task.resume()
    }

    /// Stops the transfer; the partial file stays on disk.
    func cancel() {
        let task = lock.withLock { () -> URLSessionDataTask? in
            if finalOutcome == nil { finalOutcome = .cancelled }
            return self.task
        }
        task?.cancel()
    }

    // MARK: URLSessionDataDelegate

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // Hugging Face redirects to its CDN: keep the Range header.
        var redirected = request
        if startByte > 0 {
            redirected.setValue("bytes=\(startByte)-", forHTTPHeaderField: "Range")
        }
        completionHandler(redirected)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 206 where startByte > 0, 200:
            do {
                let fileManager = FileManager.default
                if !fileManager.fileExists(atPath: destination.path) {
                    _ = fileManager.createFile(atPath: destination.path, contents: nil)
                }
                let handle = try FileHandle(forWritingTo: destination)
                // 200 means the server ignored the range: start the file over.
                let offset: UInt64 = status == 206 ? UInt64(startByte) : 0
                try handle.truncate(atOffset: offset)
                try handle.seek(toOffset: offset)
                lock.withLock {
                    self.handle = handle
                    self.received = Int64(offset)
                }
                completionHandler(.allow)
            } catch {
                record(.diskFull(shortBytes: max(expectedTotal - startByte, 0)))
                completionHandler(.cancel)
            }
        case 416:
            // Range past the end: the partial is already complete, or junk.
            let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
            if size == expectedTotal {
                record(.finished(totalBytes: size))
            } else {
                try? FileManager.default.removeItem(at: destination)
                record(.networkLost(receivedBytes: 0))
            }
            completionHandler(.cancel)
        default:
            record(.httpStatus(status))
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let (handle, total) = lock.withLock { (self.handle, self.received) }
        guard let handle else { return }
        do {
            try handle.write(contentsOf: data)
        } catch {
            record(.diskFull(shortBytes: max(expectedTotal - total, Int64(data.count))))
            dataTask.cancel()
            return
        }
        let now = Date()
        let report: Int64? = lock.withLock {
            received += Int64(data.count)
            guard now.timeIntervalSince(lastProgressReport) >= 0.25 else { return nil }
            lastProgressReport = now
            return received
        }
        if let report { onProgress(report) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (handle, total, recorded) = lock.withLock { (self.handle, self.received, self.finalOutcome) }
        try? handle?.synchronize()
        try? handle?.close()
        let outcome: Outcome
        if let recorded {
            outcome = recorded
        } else if error != nil {
            outcome = .networkLost(receivedBytes: total)
        } else {
            outcome = .finished(totalBytes: total)
        }
        lock.withLock {
            self.handle = nil
            self.task = nil
        }
        session.finishTasksAndInvalidate()
        onProgress(total)
        onComplete(outcome)
    }

    private func record(_ outcome: Outcome) {
        lock.withLock {
            if finalOutcome == nil { finalOutcome = outcome }
        }
    }
}
