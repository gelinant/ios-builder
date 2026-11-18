import Foundation
import VelaCore

/// The `PlatformFiles` seam over `FileManager` (PORTAGE_IOS.md D5). `filesDir` is Application
/// Support, `cacheDir` is Caches, `noBackupDir` is `Application Support/NoBackup`, excluded from
/// the iCloud and computer backups.
final class FileManagerPlatformFiles: NSObject, PlatformFiles {
    let filesDir: String
    let cacheDir: String
    let noBackupDir: String

    private let fm = FileManager.default

    override init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        var noBackup = support.appendingPathComponent("NoBackup", isDirectory: true)
        for dir in [support, caches, noBackup] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? noBackup.setResourceValues(values)
        filesDir = support.path
        cacheDir = caches.path
        noBackupDir = noBackup.path
        super.init()
    }

    func exists(path: String) -> Bool {
        fm.fileExists(atPath: path)
    }

    func isDirectory(path: String) -> Bool {
        var dir: ObjCBool = false
        return fm.fileExists(atPath: path, isDirectory: &dir) && dir.boolValue
    }

    func size(path: String) -> Int64 {
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              attrs[.type] as? FileAttributeType == .typeRegular else { return 0 }
        return (attrs[.size] as? NSNumber)?.int64Value ?? 0
    }

    func lastModifiedMillis(path: String) -> Int64 {
        guard let date = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date else { return 0 }
        return Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
    }

    func list(path: String) -> [FileEntry]? {
        guard isDirectory(path: path), let names = try? fm.contentsOfDirectory(atPath: path) else { return nil }
        return names.map { name in
            let child = joined(path, name)
            let dir = isDirectory(path: child)
            return FileEntry(
                name: name, path: child, isDirectory: dir, size: dir ? 0 : size(path: child),
                lastModifiedMillis: lastModifiedMillis(path: child))
        }
    }

    func mkdirs(path: String) -> Bool {
        try? fm.createDirectory(atPath: path, withIntermediateDirectories: true)
        return isDirectory(path: path)
    }

    func readBytes(path: String) throws -> KotlinByteArray {
        IosBytes.shared.toByteArray(data: try Data(contentsOf: URL(fileURLWithPath: path)))
    }

    func readText(path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    func writeBytes(path: String, bytes: KotlinByteArray) throws {
        try IosBytes.shared.toData(bytes: bytes).write(to: URL(fileURLWithPath: path))
    }

    func writeText(path: String, text: String) throws {
        try Data(text.utf8).write(to: URL(fileURLWithPath: path))
    }

    /// Temp sibling, `fsync`, then `rename(2)`, which replaces the target atomically on APFS.
    func writeTextAtomic(path: String, text: String) throws {
        let tmp = path + ".tmp"
        try Data(text.utf8).write(to: URL(fileURLWithPath: tmp))
        let fd = open(tmp, O_RDONLY)
        if fd >= 0 {
            fsync(fd)
            close(fd)
        }
        if Darwin.rename(tmp, path) == 0 { return }
        _ = Darwin.remove(path)
        if Darwin.rename(tmp, path) == 0 { return }
        _ = Darwin.remove(tmp)
        throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: path])
    }

    func rename(from: String, to: String) -> Bool {
        Darwin.rename(from, to) == 0
    }

    func delete(path: String) -> Bool {
        Darwin.remove(path) == 0
    }

    func deleteRecursively(path: String) -> Bool {
        if !fm.fileExists(atPath: path) { return true }
        try? fm.removeItem(atPath: path)
        return !fm.fileExists(atPath: path)
    }

    private func joined(_ dir: String, _ name: String) -> String {
        (dir.hasSuffix("/") ? String(dir.dropLast()) : dir) + "/" + name
    }
}
