import Cocoa

let options: CGWindowListOption = [.excludeDesktopElements]
guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    print("Failed to get window info list")
    exit(1)
}

print("Found \(infoList.count) windows:")
for info in infoList {
    let num = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
    let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
    let owner = info[kCGWindowOwnerName as String] as? String ?? ""
    let name = info[kCGWindowName as String] as? String ?? ""
    let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
    let isOnScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false
    
    // Only print normal windows (layer 0)
    if layer == 0 {
        print("ID: \(num), PID: \(pid), Owner: \(owner), Name: \(name), IsOnScreen: \(isOnScreen)")
    }
}
