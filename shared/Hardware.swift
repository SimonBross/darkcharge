// Shared by the darkcharge helper and the DarkCharge app: SMC access, the lid state,
// and the paths and notification names the two use to talk to each other.
// The LED is controlled by SMC key ACLC: 0 = macOS controls it, 1 = off, 3 = green, 4 = amber.

import Foundation
import IOKit

// Bumped whenever the helper changes; the app reinstalls the helper when it differs.
let helperVersion = "13"

let supportDir = "/Library/Application Support/DarkCharge"
// When this file exists the user has turned the feature off; the daemon leaves the LED alone.
let pausedFile = supportDir + "/paused"
// When this file exists the LED is kept off all the time, not just while the screen is dark.
let alwaysFile = supportDir + "/always"
// Written by the running daemon, so the app can tell which version is installed.
let versionFile = supportDir + "/version"

let notifyOff = "com.darkcharge.off"
let notifyOn = "com.darkcharge.on"
// Sent by the app, which can see the screen: notify state 1 when the built-in screen
// is dark (asleep or brightness at zero), 0 when it's lit.
let notifyScreen = "com.darkcharge.screen"
// Carries the mode in its notify state: 1 for always off, 0 for whenever the screen is dark.
let notifyMode = "com.darkcharge.mode"

var alwaysOff: Bool { FileManager.default.fileExists(atPath: alwaysFile) }

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

// MARK: - Lid

// True while the lid is closed (also while the Mac runs closed with an external display).
func lidIsClosed() -> Bool {
    let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard rootDomain != 0 else { return false }
    defer { IOObjectRelease(rootDomain) }
    let state = IORegistryEntryCreateCFProperty(rootDomain, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
    return (state?.takeRetainedValue() as? Bool) ?? false
}
