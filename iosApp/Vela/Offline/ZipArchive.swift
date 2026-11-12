import Foundation

/// The central-directory subset needed by Vela's release ZIPs. Entries are streamed by ZipInflate.c,
/// so a state pack is never held uncompressed in memory.
struct ZipArchive {
    struct Entry {
        let name: String
        let method: Int
        let crc32: UInt32
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let dataOffset: UInt64
    }

    enum ZipError: Error {
        case truncated, unsupported, corrupt, unsafeName, tooLarge, inflate(Int32)
    }

    private let path: String
    private let data: Data
    let entries: [Entry]

    init(url: URL) throws {
        path = url.path
        data = try Data(contentsOf: url, options: .mappedIfSafe)
        entries = try Self.readEntries(data)
    }

    func firstDatabase() throws -> Entry {
        guard let entry = entries.first(where: {
            !$0.name.hasSuffix("/") && $0.name.lowercased().hasSuffix(".db")
        }) else { throw ZipError.corrupt }
        return entry
    }

    func extract(_ entry: Entry, to output: URL) throws {
        guard entry.uncompressedSize <= 4 * 1024 * 1024 * 1024 else { throw ZipError.tooLarge }
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let result = VelaInflateZipEntry(
            path, entry.dataOffset, entry.compressedSize, entry.uncompressedSize,
            entry.crc32, Int32(entry.method), output.path)
        guard result == 0 else { throw ZipError.inflate(result) }
    }

    private static func readEntries(_ data: Data) throws -> [Entry] {
        guard data.count >= 22 else { throw ZipError.truncated }
        let firstEOCD = max(0, data.count - 22 - 65_535)
        var eocd: Int?
        var at = data.count - 22
        while at >= firstEOCD {
            if try u32(data, at) == 0x0605_4B50 {
                eocd = at
                break
            }
            at -= 1
        }
        guard let eocd else { throw ZipError.corrupt }
        let count = Int(try u16(data, eocd + 10))
        let centralSize = Int(try u32(data, eocd + 12))
        var cursor = Int(try u32(data, eocd + 16))
        guard cursor >= 0, centralSize >= 0, cursor + centralSize <= data.count else {
            throw ZipError.truncated
        }
        var out: [Entry] = []
        out.reserveCapacity(count)
        for _ in 0..<count {
            guard try u32(data, cursor) == 0x0201_4B50 else { throw ZipError.corrupt }
            let method = Int(try u16(data, cursor + 10))
            let crc = try u32(data, cursor + 16)
            let compressed = UInt64(try u32(data, cursor + 20))
            let uncompressed = UInt64(try u32(data, cursor + 24))
            let nameLength = Int(try u16(data, cursor + 28))
            let extraLength = Int(try u16(data, cursor + 30))
            let commentLength = Int(try u16(data, cursor + 32))
            let local = Int(try u32(data, cursor + 42))
            let recordLength = 46 + nameLength + extraLength + commentLength
            guard compressed != UInt64(UInt32.max), uncompressed != UInt64(UInt32.max),
                  cursor + recordLength <= data.count else { throw ZipError.unsupported }
            let nameData = data.subdata(in: cursor + 46..<cursor + 46 + nameLength)
            guard let name = String(data: nameData, encoding: .utf8) else { throw ZipError.corrupt }
            let components = name.split(separator: "/", omittingEmptySubsequences: false)
            guard !name.hasPrefix("/"), !name.contains("\\"), !components.contains("..") else {
                throw ZipError.unsafeName
            }
            guard try u32(data, local) == 0x0403_4B50, local + 30 <= data.count else {
                throw ZipError.corrupt
            }
            let localName = Int(try u16(data, local + 26))
            let localExtra = Int(try u16(data, local + 28))
            let dataOffset = local + 30 + localName + localExtra
            guard dataOffset >= 0, UInt64(dataOffset) + compressed <= UInt64(data.count) else {
                throw ZipError.truncated
            }
            out.append(Entry(
                name: name, method: method, crc32: crc, compressedSize: compressed,
                uncompressedSize: uncompressed, dataOffset: UInt64(dataOffset)))
            cursor += recordLength
        }
        return out
    }

    private static func u16(_ data: Data, _ at: Int) throws -> UInt16 {
        guard at >= 0, at + 2 <= data.count else { throw ZipError.truncated }
        return UInt16(data[at]) | UInt16(data[at + 1]) << 8
    }

    private static func u32(_ data: Data, _ at: Int) throws -> UInt32 {
        guard at >= 0, at + 4 <= data.count else { throw ZipError.truncated }
        return UInt32(data[at]) | UInt32(data[at + 1]) << 8
            | UInt32(data[at + 2]) << 16 | UInt32(data[at + 3]) << 24
    }
}
