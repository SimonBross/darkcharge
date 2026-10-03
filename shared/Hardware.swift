// Shared by the darkcharge helper and the DarkCharge app: SMC access, the light sensor,
// and the paths and notification names the two use to talk to each other.
// The LED is controlled by SMC key ACLC: 0 = macOS controls it, 1 = off, 3 = green, 4 = amber.

import Foundation
import IOKit

// Bumped whenever the helper changes; the app reinstalls the helper when it differs.
let helperVersion = "11"

let supportDir = "/Library/Application Support/DarkCharge"
// When this file exists the user has turned the LED back on; the daemon leaves it alone.
let pausedFile = supportDir + "/paused"
// Lux at or below which the room counts as dark. No file means defaultThreshold.
let thresholdFile = supportDir + "/threshold"
// "dark" to hide the LED only when the room is dark; no file means always.
let modeFile = supportDir + "/mode"
// Written by the running daemon, so the app can tell which version is installed.
let versionFile = supportDir + "/version"
let defaultThreshold = 10.0

let notifyOff = "com.darkcharge.off"
let notifyOn = "com.darkcharge.on"
// Carries the threshold in its notify state, in tenths of a lux.
let notifyThreshold = "com.darkcharge.threshold"
// Carries the mode in its notify state: 1 for when dark, 0 for always.
let notifyMode = "com.darkcharge.mode"

func readOnlyWhenDark() -> Bool {
    (try? String(contentsOfFile: modeFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) == "dark"
}

// MARK: - SMC

// SMCKeyData is an 80-byte C struct; we address its fields by offset.
private let structSize = 80
private let offKey = 0, offDataSize = 28, offResult = 40, offCommand = 42, offBytes = 48
private let cmdRead: UInt8 = 5, cmdWrite: UInt8 = 6, cmdKeyInfo: UInt8 = 9
private let selectorHandleYPCEvent: UInt32 = 2

struct SMCError: Error, CustomStringConvertible { let description: String }

final class SMC {
    private var conn: io_connect_t = 0

    init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError(description: "AppleSMC service not found") }
        defer { IOObjectRelease(service) }
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard kr == KERN_SUCCESS else { throw SMCError(description: "IOServiceOpen failed (\(kr))") }
    }

    deinit { IOServiceClose(conn) }

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
                           ? "not privileged, run with sudo" : "SMC call failed (\(kr))")
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

    func read(_ key: String) throws -> [UInt8] {
        let size = try dataSize(key)
        let out = try call(request(key, command: cmdRead, size: size))
        return Array(out[offBytes..<offBytes + Int(size)])
    }

    func write(_ key: String, _ bytes: [UInt8]) throws {
        let size = try dataSize(key)
        guard bytes.count == Int(size) else { throw SMCError(description: "\(key) expects \(size) bytes") }
        var buf = request(key, command: cmdWrite, size: size)
        buf.replaceSubrange(offBytes..<offBytes + bytes.count, with: bytes)
        _ = try call(buf)
    }
}

// MARK: - LED

let ledKey = "ACLC"
let ledSystem: UInt8 = 0x00
let ledOff: UInt8 = 0x01

func setLED(_ value: UInt8) throws {
    let smc = try SMC()
    if try smc.read(ledKey) != [value] {
        try smc.write(ledKey, [value])
    }
}

func describe(_ value: UInt8) -> String {
    switch value {
    case 0x00: return "system"
    case 0x01: return "off"
    case 0x03: return "green"
    case 0x04: return "amber"
    default: return String(format: "0x%02x", value)
    }
}

// MARK: - Light sensor

// Reads the ambient light sensor through the private IOHIDEventSystemClient API,
// the only way to reach it on Apple Silicon. Loaded at runtime so a missing symbol
// just means "no sensor" rather than a crash.
final class LightSensor {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias CopyServicesFn = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias ConformsFn = @convention(c) (AnyObject, UInt32, UInt32) -> Bool
    private typealias CopyEventFn = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloatFn = @convention(c) (AnyObject, Int32) -> Double

    private static let eventTypeAmbientLight: Int64 = 12
    private let copyEvent: CopyEventFn
    private let getFloat: GetFloatFn
    private let client: AnyObject
    private let service: AnyObject

    init?() {
        guard let lib = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let create = dlsym(lib, "IOHIDEventSystemClientCreate"),
              let copyServices = dlsym(lib, "IOHIDEventSystemClientCopyServices"),
              let conforms = dlsym(lib, "IOHIDServiceClientConformsTo"),
              let copyEvent = dlsym(lib, "IOHIDServiceClientCopyEvent"),
              let getFloat = dlsym(lib, "IOHIDEventGetFloatValue"),
              let client = unsafeBitCast(create, to: CreateFn.self)(kCFAllocatorDefault)?.takeRetainedValue(),
              let services = unsafeBitCast(copyServices, to: CopyServicesFn.self)(client)?.takeRetainedValue() as? [AnyObject],
              // Apple vendor usage page 0xFF00, usage 4: ambient light sensor.
              let service = services.first(where: { unsafeBitCast(conforms, to: ConformsFn.self)($0, 0xFF00, 4) })
        else { return nil }
        self.copyEvent = unsafeBitCast(copyEvent, to: CopyEventFn.self)
        self.getFloat = unsafeBitCast(getFloat, to: GetFloatFn.self)
        self.client = client
        self.service = service
    }

    var lux: Double? {
        guard let event = copyEvent(service, Self.eventTypeAmbientLight, 0, 0)?.takeRetainedValue() else { return nil }
        return getFloat(event, Int32(Self.eventTypeAmbientLight << 16))
    }
}
