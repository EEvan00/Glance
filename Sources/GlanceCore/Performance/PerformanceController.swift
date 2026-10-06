import AppKit
import Combine
import Darwin

struct PerformanceSnapshot: Equatable {
    let cpuPercent: Double?
    let usedMemory: UInt64
    let totalMemory: UInt64
    let pressure: Pressure?
    enum Pressure: Int { case normal = 1, warning = 2, critical = 4 }
    var memoryPercent: Double { totalMemory > 0 ? Double(usedMemory) / Double(totalMemory) * 100 : 0 }
}

enum PerformanceSampler {
    static func cpuTicks() -> [UInt32]? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
    }

    static func cpuPercent(previous: [UInt32], current: [UInt32]) -> Double? {
        guard previous.count == 4, current.count == 4 else { return nil }
        let delta = zip(current, previous).map { UInt64($0 &- $1) }
        let total = delta.reduce(0, +)
        guard total > 0 else { return nil }
        return Double(total - delta[Int(CPU_STATE_IDLE)]) / Double(total) * 100
    }

    static func memory() -> (used: UInt64, total: UInt64, pressure: PerformanceSnapshot.Pressure?)? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
        let resident = UInt64(info.active_count) + UInt64(info.inactive_count) + UInt64(info.wire_count) + UInt64(info.compressor_page_count)
        let cached = UInt64(info.external_page_count) + UInt64(info.purgeable_count)
        let total = ProcessInfo.processInfo.physicalMemory
        let used = usedMemory(residentPages: resident, cachedPages: cached, pageSize: UInt64(pageSize), total: total)
        var level: Int32 = 0
        var length = MemoryLayout<Int32>.size
        let pressure = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &length, nil, 0) == 0
            ? PerformanceSnapshot.Pressure(rawValue: Int(level)) : nil
        return (used, total, pressure)
    }

    static func usedMemory(residentPages: UInt64, cachedPages: UInt64, pageSize: UInt64, total: UInt64) -> UInt64 {
        let pages = residentPages > cachedPages ? residentPages - cachedPages : 0
        let (bytes, overflow) = pages.multipliedReportingOverflow(by: pageSize)
        return overflow ? total : min(bytes, total)
    }
}

@MainActor
final class PerformanceController: ObservableObject {
    @Published private(set) var snapshot: PerformanceSnapshot?
    @Published private(set) var isUnavailable = false
    private var previousTicks: [UInt32]?
    private var task: Task<Void, Never>?

    func setVisible(_ visible: Bool) {
        task?.cancel(); task = nil
        previousTicks = nil
        guard visible else { return }
        snapshot = nil
        sample()
        task = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard !Task.isCancelled else { return }
                self?.sample()
            }
        }
    }

    private func sample() {
        let ticks = PerformanceSampler.cpuTicks()
        let cpu = previousTicks.flatMap { old in ticks.flatMap { PerformanceSampler.cpuPercent(previous: old, current: $0) } }
        previousTicks = ticks
        guard let memory = PerformanceSampler.memory() else { snapshot = nil; isUnavailable = true; return }
        snapshot = PerformanceSnapshot(cpuPercent: cpu, usedMemory: memory.used, totalMemory: memory.total, pressure: memory.pressure)
        isUnavailable = ticks == nil
    }

    deinit { task?.cancel() }

    func openActivityMonitor() { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")) }
}
