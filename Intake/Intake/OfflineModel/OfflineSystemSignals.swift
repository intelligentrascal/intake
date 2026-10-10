import Foundation
import IOKit.ps
import IntakeCore
import Network

/// Reads this Mac for onboarding (SPEC §8.1). Everything is local: sysctl,
/// ProcessInfo and the volume's capacity. Nothing is sent anywhere.
enum MacHardwareProbe {
    static func profile(storageRoot: URL) -> MacHardwareProfile {
        #if arch(arm64)
        let isARM64Build = true
        #else
        let isARM64Build = false
        #endif
        return MacHardwareProfile(
            architecture: MacHardwareProfile.architecture(
                isARM64Build: isARM64Build,
                isTranslated: sysctlInt("sysctl.proc_translated") == 1
            ),
            memoryBytes: ProcessInfo.processInfo.physicalMemory,
            chipName: chipName(),
            freeDiskBytes: freeBytes(near: storageRoot)
        )
    }

    /// `volumeAvailableCapacityForImportantUsage` for the volume holding
    /// Application Support (the models folder may not exist yet).
    static func freeBytes(near url: URL) -> Int64 {
        var probe = url
        let fileManager = FileManager.default
        while !fileManager.fileExists(atPath: probe.path), probe.pathComponents.count > 1 {
            probe.deleteLastPathComponent()
        }
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        guard let values = try? probe.resourceValues(forKeys: keys) else { return 0 }
        if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 {
            return important
        }
        return Int64(values.volumeAvailableCapacity ?? 0)
    }

    /// "M2" / "M4 Max" / "Intel(R) Core(TM) i9-9980HK CPU @ 2.40GHz".
    private static func chipName() -> String? {
        guard var name = sysctlString("machdep.cpu.brand_string") else { return nil }
        if name.hasPrefix("Apple ") {
            name.removeFirst("Apple ".count)
        }
        return name
    }

    private static func sysctlInt(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// Watches the signals the run policy and the downloader need (SPEC §9.1):
/// network path, thermal state, Low Power Mode, power source and memory
/// pressure. Calls `onChange` on the main actor whenever one changes.
final class OfflineSystemSignals {
    private(set) var network: OfflineNetworkStatus = .unmetered
    private(set) var resources: ResourceSignals

    var onChange: (() -> Void)?

    private let pathMonitor = NWPathMonitor()
    private var memorySource: DispatchSourceMemoryPressure?
    private var memoryRelaxTask: Task<Void, Never>?
    private var powerRunLoopSource: CFRunLoopSource?
    private var observers: [NSObjectProtocol] = []

    init(architecture: MacArchitecture) {
        resources = ResourceSignals(
            thermal: Self.thermal(ProcessInfo.processInfo.thermalState),
            memory: .normal,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            power: Self.currentPower(),
            architecture: architecture
        )
    }

    func start() {
        // Built nonisolated: NWPathMonitor calls this on its own queue, and a
        // closure formed here would otherwise inherit main-actor isolation.
        pathMonitor.pathUpdateHandler = Self.pathHandler { [weak self] status in
            Task { @MainActor in
                guard let self, self.network != status else { return }
                self.network = status
                self.onChange?()
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "app.intake.offline-model.network"))

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.update { $0.thermal = Self.thermal(ProcessInfo.processInfo.thermalState) }
            }
        })
        observers.append(center.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.update { $0.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled }
            }
        })

        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let source = self.memorySource else { return }
                let event = source.data
                let level: MemoryPressureLevel = event.contains(.critical) ? .critical
                    : event.contains(.warning) ? .warning : .normal
                self.update { $0.memory = level }
            }
        }
        memorySource = source
        source.resume()

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let loop = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let signals = Unmanaged<OfflineSystemSignals>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                signals.update { $0.power = OfflineSystemSignals.currentPower() }
            }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), loop, .defaultMode)
            powerRunLoopSource = loop
        }
    }

    func stop() {
        pathMonitor.cancel()
        memorySource?.cancel()
        memorySource = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        if let loop = powerRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), loop, .defaultMode)
            powerRunLoopSource = nil
        }
    }

    /// Fresh sample right before an inference (SPEC §9.1).
    func sample() -> ResourceSignals {
        var signals = resources
        signals.thermal = Self.thermal(ProcessInfo.processInfo.thermalState)
        signals.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        signals.power = Self.currentPower()
        return signals
    }

    private func update(_ change: (inout ResourceSignals) -> Void) {
        var next = resources
        change(&next)
        guard next != resources else { return }
        resources = next
        onChange?()
    }

    // MARK: Readers

    nonisolated private static func pathHandler(
        _ deliver: @escaping @Sendable (OfflineNetworkStatus) -> Void
    ) -> @Sendable (NWPath) -> Void {
        { path in deliver(status(path)) }
    }

    nonisolated private static func status(_ path: NWPath) -> OfflineNetworkStatus {
        guard path.status == .satisfied else { return .offline }
        return (path.isExpensive || path.isConstrained) ? .metered : .unmetered
    }

    private static func thermal(_ state: ProcessInfo.ThermalState) -> ThermalLevel {
        switch state {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
    }

    /// AC, or battery with its percentage. Desktops (no battery) count as AC.
    static func currentPower() -> PowerSource {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return .ac }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        guard providing == kIOPSBatteryPowerValue else { return .ac }
        let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
            else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int
            let maximum = description[kIOPSMaxCapacityKey] as? Int
            if let current, let maximum, maximum > 0 {
                return .battery(percent: Int((Double(current) / Double(maximum) * 100).rounded()))
            }
            return .battery(percent: nil)
        }
        return .battery(percent: nil)
    }
}
