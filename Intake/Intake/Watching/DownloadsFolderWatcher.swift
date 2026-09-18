import Darwin
import Foundation
import IntakeCore

nonisolated final class DownloadsFolderWatcher: @unchecked Sendable {
    /// Minimum unchanged dwell before a non-zero file is considered stable.
    static let minimumStableDwell: TimeInterval = 2.0

    private let queue = DispatchQueue(label: "app.intake.watcher")
    private var policy = DownloadIgnorePolicy()
    private var descriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var debounce: DispatchWorkItem?
    private var folder: URL?
    private var knownNames: Set<String> = []
    private var pending: [String: FileStabilitySnapshot] = [:]
    private var pendingSince: [String: Date] = [:]
    private var onStable: ((URL) -> Void)?

    func start(
        folder: URL,
        ignorePolicy: DownloadIgnorePolicy = DownloadIgnorePolicy(),
        onStableFile: @escaping (URL) -> Void
    ) {
        stop()
        queue.sync {
            self.folder = folder
            self.policy = ignorePolicy
            self.onStable = onStableFile
            self.knownNames = self.currentRootNames(in: folder)
            self.pending.removeAll()
            self.pendingSince.removeAll()
            let fd = open(folder.path, O_EVTONLY)
            guard fd >= 0 else { return }
            self.descriptor = fd
            let src = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .rename, .delete, .link],
                queue: self.queue
            )
            src.setEventHandler { [weak self] in
                self?.scheduleScan()
            }
            src.setCancelHandler { [weak self] in
                guard let self else { return }
                if self.descriptor >= 0 {
                    close(self.descriptor)
                    self.descriptor = -1
                }
            }
            self.source = src
            src.resume()
        }
    }

    func updateIgnorePolicy(_ ignorePolicy: DownloadIgnorePolicy) {
        queue.async {
            self.policy = ignorePolicy
        }
    }

    /// After rename-on-stable, mark the new root name known so the watcher
    /// does not treat the rename as a brand-new download.
    func acknowledgeRootFile(named name: String) {
        queue.async {
            self.knownNames.insert(name)
            self.pending.removeValue(forKey: name)
            self.pendingSince.removeValue(forKey: name)
        }
    }

    func stop() {
        queue.sync {
            debounce?.cancel()
            debounce = nil
            source?.cancel()
            source = nil
            pending.removeAll()
            pendingSince.removeAll()
            onStable = nil
            folder = nil
        }
    }

    private func scheduleScan() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.scanForStableNewFiles()
        }
        debounce = work
        queue.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func scanForStableNewFiles() {
        guard let folder else { return }
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ]
        let items = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: []
        )) ?? []

        var present: Set<String> = []
        var stillPending = false
        let now = Date()
        var snapshots: [DownloadFileSnapshot] = []

        for url in items {
            let name = url.lastPathComponent
            present.insert(name)
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDirectory = values?.isDirectory ?? url.hasDirectoryPath
            if isDirectory {
                continue
            }
            if policy.shouldIgnore(url: url, kind: .appeared, isDirectory: false) {
                continue
            }
            snapshots.append(
                DownloadFileSnapshot(
                    url: url,
                    size: Int64(values?.fileSize ?? 0)
                )
            )
        }

        // Prefer the full download: drop empty collision twins so they cannot be organized later.
        let removedNames = Set(
            EmptyFullSiblingDedupe.removeEmptySiblings(
                among: snapshots
            ).map(\.lastPathComponent)
        )
        if !removedNames.isEmpty {
            pending = pending.filter { !removedNames.contains($0.key) }
            pendingSince = pendingSince.filter { !removedNames.contains($0.key) }
            knownNames.subtract(removedNames)
            present.subtract(removedNames)
        }

        for url in items {
            let name = url.lastPathComponent
            if removedNames.contains(name) {
                continue
            }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDirectory = values?.isDirectory ?? url.hasDirectoryPath
            if policy.shouldIgnore(url: url, kind: .appeared, isDirectory: isDirectory) {
                continue
            }
            if knownNames.contains(name) {
                continue
            }
            guard FileManager.default.fileExists(atPath: url.path) else {
                continue
            }

            let snapshot = FileStabilitySnapshot(
                size: Int64(values?.fileSize ?? 0),
                modificationTime: values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            )

            // Never stabilize a zero-byte placeholder — browsers often create the
            // final name empty, then write. Renaming that empty file races the writer.
            if snapshot.size <= 0 {
                pending[name] = snapshot
                if pendingSince[name] == nil {
                    pendingSince[name] = now
                }
                stillPending = true
                continue
            }

            if pending[name] == snapshot {
                let since = pendingSince[name] ?? now
                if now.timeIntervalSince(since) >= Self.minimumStableDwell {
                    knownNames.insert(name)
                    pending.removeValue(forKey: name)
                    pendingSince.removeValue(forKey: name)
                    onStable?(url)
                } else {
                    stillPending = true
                }
            } else {
                pending[name] = snapshot
                pendingSince[name] = now
                stillPending = true
            }
        }

        knownNames = knownNames.intersection(present)
        pending = pending.filter { present.contains($0.key) }
        pendingSince = pendingSince.filter { present.contains($0.key) }
        if stillPending {
            scheduleScan()
        }
    }

    private func currentRootNames(in folder: URL) -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return Set(names)
    }
}

struct FileStabilitySnapshot: Equatable, Sendable {
    var size: Int64
    var modificationTime: TimeInterval
}
