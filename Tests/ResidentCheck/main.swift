import Foundation
import ApplicationServices

let args = CommandLine.arguments
let service = ResidentService(app: URL(fileURLWithPath: args[1]), dataDirectory: URL(fileURLWithPath: args[2]))
let config = service.configuration
precondition(config["KeepAlive"] as? Bool == true)
precondition(config["AbandonProcessGroup"] as? Bool == true, "Stopping the helper must preserve the app for saving")
precondition(config["ThrottleInterval"] as? Int == 5)
precondition(config["StartInterval"] == nil && config["UserName"] == nil)
precondition(config["ProgramArguments"] as? [String] == [args[1] + "/Contents/MacOS/MacToysWatchdog", "--app", args[1], "--data", args[2]])
try PropertyListSerialization.data(fromPropertyList: config, format: .xml, options: 0).write(to: URL(fileURLWithPath: args[3]))

// Real AXObserver construction/removal, serialized on its delivery run loop.
// It subscribes only to this test process; no input events are generated.
let observer = AXFocusObserver()
var last: UInt64 = 0
for _ in 0..<200 {
    let current = observer.bind(pid: getpid()) { _, _ in }
    precondition(current > last)
    observer.observe(AXUIElementCreateApplication(getpid()), generation: current)
    observer.stop()
    observer.observe(AXUIElementCreateApplication(getpid()), generation: current)
    precondition(observer.generation > current)
    last = observer.generation
    RunLoop.main.run(until: Date().addingTimeInterval(0.001))
}
print("Resident configuration and 200 AX observer lifecycle cycles passed")
