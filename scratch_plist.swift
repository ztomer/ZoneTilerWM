import Cocoa

let url = URL(fileURLWithPath: "/Users/ztomer/Library/Application Support/com.apple.wallpaper/Store/Index.plist")
guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else {
    print("Failed to load plist")
    exit(1)
}

print("Spaces Keys:")
if let spacesDict = dict["Spaces"] as? [String: Any] {
    for (spaceUUID, spaceVal) in spacesDict {
        print("\nSpace UUID: \(spaceUUID)")
        if let spaceValDict = spaceVal as? [String: Any] {
            // Check Default or Displays
            if let defDict = spaceValDict["Default"] as? [String: Any],
               let desktopDict = defDict["Desktop"] as? [String: Any],
               let contentDict = desktopDict["Content"] as? [String: Any],
               let choices = contentDict["Choices"] as? [[String: Any]] {
                for choice in choices {
                    if let files = choice["Files"] as? [[String: Any]] {
                        print("Files: \(files)")
                    }
                    if let provider = choice["Provider"] as? String {
                        print("Provider: \(provider)")
                    }
                    if let configData = choice["Configuration"] as? Data {
                        // Let's decode this data!
                        if let decoded = try? PropertyListSerialization.propertyList(from: configData, options: [], format: nil) {
                            print("Decoded Configuration: \(decoded)")
                        }
                    }
                }
            }
        }
    }
}
