import Cocoa

let options: CGWindowListOption = [.excludeDesktopElements]
guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}

let runningApps = NSWorkspace.shared.runningApplications
let pids = Set(runningApps.map { $0.processIdentifier })

for info in infoList {
    let num = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
    let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
    let owner = info[kCGWindowOwnerName as String] as? String ?? ""
    let name = info[kCGWindowName as String] as? String ?? ""
    let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
    let isOnScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false
    
    if layer == 0 {
        let app = runningApps.first { $0.processIdentifier == pid }
        let policy = app?.activationPolicy
        let policyStr = policy.flatMap { p -> String in
            switch p {
            case .regular: return "regular"
            case .accessory: return "accessory"
            case .prohibited: return "prohibited"
            @unknown default: return "unknown"
            }
        } ?? "none"
        
        print("ID: \(num), Owner: \(owner), Name: \(name), OnScreen: \(isOnScreen), Policy: \(policyStr)")
    }
}
