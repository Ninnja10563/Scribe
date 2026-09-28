import Foundation
import CZlib

public enum ArchiveError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let reason) = self { return "Cannot read DOCX archive: \(reason)" }; return nil }
}
/// Minimal OPC ZIP transport. Stored output; stored/deflated input. Never extracts paths to disk.
public enum ZipArchive {
    public static func encode(_ files: [String: Data]) throws -> Data {
        var output = Data(), central = Data()
        for name in files.keys.sorted() {
            let data = files[name]!, path = Data(name.utf8), offset = output.count
            guard path.count <= 65535, data.count < Int(UInt32.max) else { throw ArchiveError.invalid("entry too large") }
            let crc = checksum(data)
            output.u32(0x04034b50); output.u16(20); output.u16(0x800); output.u16(0)
            output.u16(0); output.u16(33); output.u32(crc)
            output.u32(UInt32(data.count)); output.u32(UInt32(data.count)); output.u16(UInt16(path.count)); output.u16(0)
            output.append(path); output.append(data)
            central.u32(0x02014b50); central.u16(20); central.u16(20); central.u16(0x800); central.u16(0)
            central.u16(0); central.u16(33); central.u32(crc); central.u32(UInt32(data.count)); central.u32(UInt32(data.count))
            central.u16(UInt16(path.count)); central.u16(0); central.u16(0); central.u16(0); central.u16(0)
            central.u32(0); central.u32(UInt32(offset)); central.append(path)
        }
        let offset = output.count
        output.append(central); output.u32(0x06054b50); output.u16(0); output.u16(0)
        output.u16(UInt16(files.count)); output.u16(UInt16(files.count))
        output.u32(UInt32(central.count)); output.u32(UInt32(offset)); output.u16(0)
        return output
    }
    public static func decode(_ data: Data) throws -> [String: Data] {
        guard data.count >= 22, data.count <= 128 * 1024 * 1024 else { throw ArchiveError.invalid("invalid archive size") }
        var end: Int?
        for i in stride(from: data.count - 22, through: max(0, data.count - 65557), by: -1) {
            if try data.read32(i) == 0x06054b50,
               i + 22 + Int(try data.read16(i + 20)) == data.count { end = i; break }
        }
        guard let end else { throw ArchiveError.invalid("missing directory") }
        guard try data.read16(end + 4) == 0, try data.read16(end + 6) == 0 else { throw ArchiveError.invalid("multi-disk archive") }
        let count = Int(try data.read16(end + 10))
        guard count <= 4096 else { throw ArchiveError.invalid("too many entries") }
        var cursor = Int(try data.read32(end + 16)), result: [String: Data] = [:], total = 0
        for _ in 0..<count {
            guard try data.read32(cursor) == 0x02014b50 else { throw ArchiveError.invalid("corrupt directory") }
            let flags = try data.read16(cursor + 8), method = try data.read16(cursor + 10)
            guard flags & 1 == 0, method == 0 || method == 8 else { throw ArchiveError.invalid("encrypted or unsupported entry") }
            let crc = try data.read32(cursor + 16), compressed = Int(try data.read32(cursor + 20))
            let size = Int(try data.read32(cursor + 24)), length = Int(try data.read16(cursor + 28))
            let extra = Int(try data.read16(cursor + 30)), comment = Int(try data.read16(cursor + 32))
            let offset = Int(try data.read32(cursor + 42))
            total += size
            guard total <= 128 * 1024 * 1024 else { throw ArchiveError.invalid("expanded archive exceeds 128 MB") }
            let nameData = try data.slice(cursor + 46, length)
            guard let name = String(data: nameData, encoding: .utf8), !name.hasPrefix("/"),
                  !name.split(separator: "/").contains(".."), result[name] == nil else { throw ArchiveError.invalid("unsafe or duplicate path") }
            guard try data.read32(offset) == 0x04034b50 else { throw ArchiveError.invalid("missing entry header") }
            let start = offset + 30 + Int(try data.read16(offset + 26)) + Int(try data.read16(offset + 28))
            let payload = try data.slice(start, compressed)
            let expanded = method == 0 ? payload : try inflateRaw(payload, size: size)
            guard expanded.count == size, checksum(expanded) == crc else { throw ArchiveError.invalid("checksum mismatch") }
            result[name] = expanded
            cursor += 46 + length + extra + comment
        }
        return result
    }
    private static func checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { UInt32(crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(data.count))) }
    }
    private static func inflateRaw(_ input: Data, size: Int) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw ArchiveError.invalid("decompression initialization failed")
        }
        defer { inflateEnd(&stream) }
        var output = Data(count: max(1, size))
        let status: Int32 = input.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination in
                stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(input.count)
                stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(max(1, size))
                return inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END, stream.total_out == size else { throw ArchiveError.invalid("damaged compressed content") }
        return output.prefix(size)
    }
}
private extension Data {
    mutating func u16(_ n: UInt16) { append(UInt8(n & 255)); append(UInt8(n >> 8)) }
    mutating func u32(_ n: UInt32) { u16(UInt16(n & 65535)); u16(UInt16(n >> 16)) }
    func slice(_ offset: Int, _ length: Int) throws -> Data {
        guard offset >= 0, length >= 0, offset <= count, length <= count - offset else { throw ArchiveError.invalid("truncated data") }
        return subdata(in: offset..<(offset + length))
    }
    func read16(_ offset: Int) throws -> UInt16 {
        let d = try slice(offset, 2); return UInt16(d[0]) | UInt16(d[1]) << 8
    }
    func read32(_ offset: Int) throws -> UInt32 {
        UInt32(try read16(offset)) | UInt32(try read16(offset + 2)) << 16
    }
}
