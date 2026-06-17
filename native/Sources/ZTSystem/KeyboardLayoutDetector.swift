// KeyboardLayoutDetector.swift — best-effort detection of the active keyboard layout via Text
// Input Source Services, mapped to one of ZTCore's presets (qwerty/dvorak/colemak). Exotic
// layouts fall back to qwerty; the user can always override in settings.

import Foundation
import Carbon

public enum KeyboardLayoutDetector {

    /// Raw input-source id, e.g. "com.apple.keylayout.Dvorak" (nil if unavailable).
    public static func currentInputSourceID() -> String? {
        guard let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    /// The preset name matching the active layout; defaults to "qwerty".
    public static func current() -> String {
        let id = (currentInputSourceID() ?? "").lowercased()
        if id.contains("dvorak") { return "dvorak" }
        if id.contains("colemak") { return "colemak" }
        return "qwerty"
    }
}
