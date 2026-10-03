// Access to the System Management Controller, which drives the MagSafe LED.
// Reading works for any user; writing needs root, so only the helper writes.

import IOKit

public struct SMCError: Error, CustomStringConvertible {
    public let description: String
}

// SMCKeyData is an 80-byte C struct; we address its fields by offset.
private let structSize = 80
private let offKey = 0, offDataSize = 28, offResult = 40, offCommand = 42, offBytes = 48
private let cmdRead: UInt8 = 5, cmdWrite: UInt8 = 6, cmdKeyInfo: UInt8 = 9
private let selectorHandleYPCEvent: UInt32 = 2

public final class SMC {
    private var conn: io_connect_t = 0

    public init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError(description: "AppleSMC service not found") }
        defer { IOObjectRelease(service) }
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard kr == KERN_SUCCESS else { throw SMCError(description: "IOServiceOpen failed (\(kr))") }
    }

    deinit { IOServiceClose(conn) }

    public func read(_ key: String) throws -> [UInt8] {
        let size = try dataSize(key)
        let out = try call(request(key, command: cmdRead, size: size))
        return Array(out[offBytes..<offBytes + Int(size)])
    }

    public func write(_ key: String, _ bytes: [UInt8]) throws {
        let size = try dataSize(key)
        guard bytes.count == Int(size) else { throw SMCError(description: "\(key) expects \(size) bytes") }
        var buf = request(key, command: cmdWrite, size: size)
        buf.replaceSubrange(offBytes..<offBytes + bytes.count, with: bytes)
        _ = try call(buf)
    }

    private static func fourCC(_ s: String) -> UInt32 {
        s.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }

    private func call(_ input: [UInt8]) throws -> [UInt8] {
        var output = [UInt8](repeating: 0, count: structSize)
        var outSize = structSize
        let kr = input.withUnsafeBytes { inp in
            output.withUnsafeMutableBytes { out in
                IOConnectCallStructMethod(conn, selectorHandleYPCEvent,
                                          inp.baseAddress, structSize, out.baseAddress, &outSize)
            }
        }
        guard kr == KERN_SUCCESS else {
            throw SMCError(description: kr == kIOReturnNotPrivileged
                           ? "not privileged, must run as root" : "SMC call failed (\(kr))")
        }
        guard output[offResult] == 0 else { throw SMCError(description: "SMC returned error \(output[offResult])") }
        return output
    }

    private func request(_ key: String, command: UInt8, size: UInt32 = 0) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: structSize)
        buf.withUnsafeMutableBytes { p in
            p.storeBytes(of: SMC.fourCC(key), toByteOffset: offKey, as: UInt32.self)
            p.storeBytes(of: size, toByteOffset: offDataSize, as: UInt32.self)
        }
        buf[offCommand] = command
        return buf
    }

    private func dataSize(_ key: String) throws -> UInt32 {
        let out = try call(request(key, command: cmdKeyInfo))
        return out.withUnsafeBytes { $0.load(fromByteOffset: offDataSize, as: UInt32.self) }
    }
}

// MARK: - MagSafe LED

// SMC key ACLC: 0 = macOS controls the LED, 1 = off, 3 = green, 4 = amber.
public enum MagSafeLED {
    static let key = "ACLC"
    public static let system: UInt8 = 0x00
    public static let off: UInt8 = 0x01

    public static func read(using smc: SMC) throws -> UInt8 {
        try smc.read(key).first ?? system
    }

    public static func isOff(using smc: SMC) -> Bool {
        (try? read(using: smc)) == off
    }

    // Writes only when the value differs, to keep SMC traffic down. Needs root.
    public static func set(_ value: UInt8) throws {
        let smc = try SMC()
        if try read(using: smc) != value {
            try smc.write(key, [value])
        }
    }

    public static func describe(_ value: UInt8) -> String {
        switch value {
        case 0x00: return "system"
        case 0x01: return "off"
        case 0x03: return "green"
        case 0x04: return "amber"
        default: return String(value, radix: 16)
        }
    }
}
