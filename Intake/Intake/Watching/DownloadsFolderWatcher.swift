import Darwin
import Foundation
import IntakeCore

nonisolated final class DownloadsFolderWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.intake.watcher")
    private let policy = DownloadIgnorePolicy()
    private var descriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var debounce: DispatchWorkItem?
    private var folder: URL?
    private var knownNames: Set<String> = []
    private var pending: [String: FileStabilitySnapshot] = [:]
    private var onStable: ((URL) -> Void)?

    func start(folder: URL, onStableFile: @escaping (URL) -> Void) {
        stop()
        queue.sync {
            self.folder = folder
            self.onStable = onStableFile
            self.knownNames = self.currentRootNames(in: folder)
            self.pending.removeAll()
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

    func stop() {
        queue.sync {
            debounce?.cancel()
            debounce = nil
            source?.cancel()
            source = nil
            pending.removeAll()
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

        for url in items {
            let name = url.lastPathComponent
            present.insert(name)
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDirectory = values?.isDirectory ?? url.hasDirectoryPath
            if policy.shouldIgnore(url: url, kind: .appeared, isDirectory: isDirectory) {
                continue
            }
            if knownNames.contains(name) {
                continue
            }

            let snapshot = FileStabilitySnapshot(
                size: Int64(values?.fileSize ?? 0),
                modificationTime: values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            )
            if pending[name] == snapshot {
                knownNames.insert(name)
                pending.removeValue(forKey: name)
                onStable?(url)
            } else {
                pending[name] = snapshot
                stillPending = true
            }
        }

        knownNames = knownNames.intersection(present)
        pending = pending.filter { present.contains($0.key) }
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
