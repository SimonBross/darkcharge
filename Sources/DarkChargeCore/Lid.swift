import Foundation
import IOKit

public enum Lid {
    // True while the lid is closed (also while the Mac runs closed with an external display).
    public static var isClosed: Bool {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != 0 else { return false }
        defer { IOObjectRelease(rootDomain) }
        let state = IORegistryEntryCreateCFProperty(rootDomain, "AppleClamshellState" as CFString,
                                                    kCFAllocatorDefault, 0)
        return (state?.takeRetainedValue() as? Bool) ?? false
    }
}
