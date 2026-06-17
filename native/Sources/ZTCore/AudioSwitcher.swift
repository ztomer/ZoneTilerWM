// AudioSwitcher.swift — pure device-cycle logic from audio_switcher.lua. Given the
// configured device-name list and the current default device's name, picks the next device
// name to switch to. Enumerating devices, setting the default, and the Shortcut trigger are
// the CoreAudio / system boundary.

public enum AudioSwitcher {

    /// The next configured device name to cycle to, or nil if fewer than two are configured.
    /// Mirrors audio_switcher.toggle: if the current device isn't in the list (or is last),
    /// wrap to the first; otherwise advance by one.
    public static func nextDevice(configured: [String], currentName: String?) -> String? {
        guard configured.count >= 2 else { return nil }
        // 1-based index of the current device in the configured list, or -1.
        var currentIndex = -1
        if let name = currentName {
            for (i, deviceName) in configured.enumerated() where deviceName == name {
                currentIndex = i + 1
                break
            }
        }
        let nextIndex: Int
        if currentIndex == -1 || currentIndex == configured.count {
            nextIndex = 1
        } else {
            nextIndex = currentIndex + 1
        }
        return configured[nextIndex - 1]
    }
}
