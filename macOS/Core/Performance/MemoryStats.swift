import Foundation
import Darwin

struct MemoryStats: Sendable, Hashable {
    let total: Int64
    let free: Int64
    let active: Int64
    let inactive: Int64
    let wired: Int64
    let compressed: Int64
    let appMemory: Int64
    let pageSize: Int

    /// macOS "Memory Used" — matches Activity Monitor and vm_stat's notion of
    /// in-use RAM. `total - free` overcounts wildly because macOS keeps almost
    /// nothing truly "free": inactive pages are old app data that's reclaimable
    /// on demand, not used. `wired + compressed + active` is what's actually
    /// holding live state.
    var used: Int64 { wired + compressed + active }
    var pressurePercent: Double {
        guard total > 0 else { return 0 }
        return Double(used) / Double(total) * 100
    }
}

actor MemoryService {

    func snapshot() -> MemoryStats {
        Self.read()
    }

    private nonisolated static func read() -> MemoryStats {
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        let pageSize = Int(sysconf(Int32(_SC_PAGESIZE)))

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return MemoryStats(total: total, free: 0, active: 0, inactive: 0, wired: 0, compressed: 0, appMemory: 0, pageSize: pageSize)
        }

        let p = Int64(pageSize)
        return MemoryStats(
            total: total,
            free: Int64(stats.free_count) * p,
            active: Int64(stats.active_count) * p,
            inactive: Int64(stats.inactive_count) * p,
            wired: Int64(stats.wire_count) * p,
            compressed: Int64(stats.compressor_page_count) * p,
            appMemory: Int64(stats.internal_page_count) * p,
            pageSize: pageSize
        )
    }
}
