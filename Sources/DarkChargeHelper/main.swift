// DarkChargeHelper: the root LaunchDaemon that turns the MagSafe charging LED off while
// the DarkCharge app asks for it. The app registers it with SMAppService; launchd starts
// it as `DarkChargeHelper daemon`. `status` prints the LED state, for troubleshooting.

import DarkChargeCore
import Foundation

let usage = """
    usage: DarkChargeHelper <command>
      status   show the current LED state
      daemon   run the helper (started by launchd)
    """

switch CommandLine.arguments.dropFirst().first {
case "status":
    do {
        print(MagSafeLED.describe(try MagSafeLED.read(using: SMC())))
    } catch {
        FileHandle.standardError.write(Data("DarkChargeHelper: \(error)\n".utf8))
        exit(1)
    }
case "daemon":
    guard getuid() == 0 else {
        FileHandle.standardError.write(Data("DarkChargeHelper: the daemon must run as root\n".utf8))
        exit(1)
    }
    Helper().run()
default:
    print(usage)
    exit(1)
}
