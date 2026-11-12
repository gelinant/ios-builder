import Darwin
import Foundation

/// Validates a finished body beside its target, then swaps it in without exposing a partial file.
struct RegionDownloadInstaller {
    private let fm = FileManager.default

    func install(kind: String, temporary: URL, target: URL,
                 expectedBytes: Int64, httpStatus: Int?) -> String? {
        if let httpStatus, !(200..<300).contains(httpStatus) { return "http" }
        let bytes = (try? fm.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.int64Value ?? 0
        if expectedBytes > 0 && bytes != expectedBytes { return "length" }
        do {
            switch kind {
            case "pack":
                let archive = try ZipArchive(url: temporary)
                let unpacked = URL(fileURLWithPath: target.path + ".install")
                try? fm.removeItem(at: unpacked)
                try archive.extract(try archive.firstDatabase(), to: unpacked)
                guard try validMagic(unpacked, count: 16, text: "SQLite format 3") else { return "format" }
                try replace(unpacked, with: target)
                try? fm.removeItem(at: temporary)
            case "pack-delta":
                let archive = try ZipArchive(url: temporary)
                let unpacked = URL(fileURLWithPath: target.path + ".install")
                try? fm.removeItem(at: unpacked)
                try archive.extract(try archive.firstDatabase(), to: unpacked)
                guard try validMagic(unpacked, count: 16, text: "SQLite format 3") else { return "format" }
                try replace(unpacked, with: target)
                try? fm.removeItem(at: temporary)
            case "places", "basemap":
                guard bytes > 127, try validMagic(temporary, count: 7, text: "PMTiles") else {
                    return "format"
                }
                try replace(temporary, with: target)
            case "patch":
                guard bytes > 16, try validMagic(temporary, count: 8, text: "VELAPTCH") else {
                    return "format"
                }
                try replace(temporary, with: target)
            case "glyphs":
                try installGlyphs(temporary: temporary, target: target)
            default:
                return "kind"
            }
            return nil
        } catch {
            return "format"
        }
    }

    private func installGlyphs(temporary: URL, target: URL) throws {
        let archive = try ZipArchive(url: temporary)
        let staging = URL(fileURLWithPath: target.path + ".new", isDirectory: true)
        let old = URL(fileURLWithPath: target.path + ".old", isDirectory: true)
        if !fm.fileExists(atPath: target.path), fm.fileExists(atPath: old.path) {
            try fm.moveItem(at: old, to: target)
        }
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        for entry in archive.entries where entry.name.hasSuffix(".pbf") {
            let parts = entry.name.split(separator: "/").filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }
            let stack = String(parts[parts.count - 2])
            let range = String(parts[parts.count - 1])
            guard stack != ".", stack != "..", range != ".", range != ".." else { continue }
            let output = staging.appendingPathComponent(stack, isDirectory: true)
                .appendingPathComponent(range)
            try archive.extract(entry, to: output)
        }
        let required = staging.appendingPathComponent("Noto Sans Regular/0-255.pbf")
        guard fm.fileExists(atPath: required.path) else { throw ZipArchive.ZipError.corrupt }
        try? fm.removeItem(at: old)
        if fm.fileExists(atPath: target.path) {
            try fm.moveItem(at: target, to: old)
        }
        do {
            try fm.moveItem(at: staging, to: target)
            try? fm.removeItem(at: old)
            try? fm.removeItem(at: temporary)
        } catch {
            if fm.fileExists(atPath: old.path) {
                try? fm.moveItem(at: old, to: target)
            }
            throw error
        }
    }

    private func validMagic(_ url: URL, count: Int, text: String) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: count) ?? Data()
        return data.count >= count && String(data: data.prefix(text.utf8.count), encoding: .utf8) == text
    }

    /// rename(2) replaces the destination on APFS. The completed body is on the same volume.
    private func replace(_ source: URL, with target: URL) throws {
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if Darwin.rename(source.path, target.path) != 0 {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
