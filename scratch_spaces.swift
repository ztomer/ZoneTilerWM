import Cocoa

let url = URL(fileURLWithPath: "/Users/ztomer/Library/Preferences/com.apple.spaces.plist")
guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else {
    print("Failed to load spaces plist")
    exit(1)
}

print(dict)
