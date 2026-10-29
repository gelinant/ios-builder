// Files, logs and small process counters shared by the spike.
import Darwin
import Foundation

enum SpikeFiles {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func write(_ name: String, _ text: String = "") {
        let url = documents.appendingPathComponent(name)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    static func writeJSON(_ name: String, _ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? data.write(to: documents.appendingPathComponent(name))
    }
}

func log(_ message: String) {
    print("TERRAIN \(Date().timeIntervalSince1970) \(message)")
    fflush(stdout)
}

/// CPU time of the process, used for a per-frame cost that does not need a profiler.
func processCPUSeconds() -> Double {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
    let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
    let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
    return user + system
}

/// Resident footprint of the process in bytes. Used to bound the memory cost of the three meshes.
func processFootprintBytes() -> Int {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return 0 }
    return Int(info.phys_footprint)
}
