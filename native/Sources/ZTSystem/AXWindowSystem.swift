// AXWindowSystem.swift — macOS Accessibility / CoreGraphics window control.
// Phase 0 of the system-adapter layer: window enumeration + z-order (CGWindowList) and
// moving another app's window (AXUIElement), replicating the Hammerspoon quirks from
// modules/window_actions.lua — notably the AXEnhancedUserInterface toggle that lets
// Firefox/Zen-class (non-native-AX) apps accept frame changes — plus the AppleScript /
// System-Events fallback.
//
// Coordinates are top-left CG/AX space throughout (matching CGWindowList, CGDisplayBounds,
// and the AX kAXPosition/kAXSize attributes).

import Foundation
import AppKit
import ApplicationServices

public struct OnScreenWindow {
    public let windowID: CGWindowID
    public let pid: pid_t
    public let ownerName: String
    public let bounds: CGRect   // top-left CG coords
    public let layer: Int
    public let zOrder: Int      // front-to-back index (0 == frontmost)
}

public struct AXMoveError: Error, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

public enum AXWindowSystem {

    /// Whether this process may use the Accessibility API. Pass prompt=true to surface the
    /// system permission dialog on first use.
    public static func isTrusted(prompt: Bool = false) -> Bool {
        // Key string is "AXTrustedCheckOptionPrompt"; use the literal to avoid Unmanaged juggling.
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// On-screen windows in front-to-back order. Does NOT require Accessibility permission.
    public static func onScreenWindows() -> [OnScreenWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var result: [OnScreenWindow] = []
        for (i, info) in infoList.enumerated() {
            guard let num = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            else { continue }
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            var bounds = CGRect.zero
            if let boundsDict = info[kCGWindowBounds as String] as? NSDictionary {
                CGRectMakeWithDictionaryRepresentation(boundsDict as! CFDictionary, &bounds)
            }
            result.append(OnScreenWindow(windowID: num, pid: pid, ownerName: owner,
                                         bounds: bounds, layer: layer, zOrder: i))
        }
        return result
    }

    public struct MoveResult {
        public let appName: String
        public let before: CGRect
        public let after: CGRect
        public let usedEnhancedUIToggle: Bool
        public let wasEnhancedUI: Bool
    }

    /// Moves the front window of the first regular running app whose name contains `needle`
    /// (case-insensitive) to `rect`. Mirrors window_actions.apply_frame: optional
    /// AXEnhancedUserInterface toggle around the set, position-then-size, no animation.
    public static func moveFrontWindow(ofAppMatching needle: String,
                                       to rect: CGRect,
                                       toggleEnhancedUI: Bool) -> Result<MoveResult, AXMoveError> {
        guard let app = matchingApp(needle) else {
            return .failure(AXMoveError("no running regular app matching '\(needle)'"))
        }
        let appElem = AXUIElementCreateApplication(app.processIdentifier)

        var windowsRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appElem, kAXWindowsAttribute as CFString, &windowsRef)
        guard err == .success, let windows = windowsRef as? [AXUIElement], let win = windows.first else {
            return .failure(AXMoveError("could not read AX windows (AXError \(err.rawValue)); "
                + "accessibility trusted? \(isTrusted())"))
        }

        let before = frame(of: win)

        var wasEnhanced = false
        if toggleEnhancedUI {
            var v: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElem, kAXEnhancedUserInterface, &v) == .success,
               let b = v as? Bool { wasEnhanced = b }
            if wasEnhanced {
                AXUIElementSetAttributeValue(appElem, kAXEnhancedUserInterface, kCFBooleanFalse)
            }
        }

        setFrame(win, rect)

        if toggleEnhancedUI && wasEnhanced {
            AXUIElementSetAttributeValue(appElem, kAXEnhancedUserInterface, kCFBooleanTrue)
        }

        let after = frame(of: win)
        return .success(MoveResult(appName: app.localizedName ?? needle, before: before, after: after,
                                   usedEnhancedUIToggle: toggleEnhancedUI, wasEnhancedUI: wasEnhanced))
    }

    /// AppleScript / System-Events fallback (window_actions.apply_frame_applescript): used on
    /// machines where the AX path is hooked/blocked. Moves "window 1" of the process.
    public static func moveFrontWindowViaAppleScript(ofAppMatching needle: String,
                                                     to rect: CGRect) -> Result<MoveResult, AXMoveError> {
        guard let app = matchingApp(needle), let name = app.localizedName else {
            return .failure(AXMoveError("no running regular app matching '\(needle)'"))
        }
        let x = Int(rect.origin.x), y = Int(rect.origin.y)
        let w = Int(rect.size.width), h = Int(rect.size.height)
        let escaped = name.replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "\(escaped)"
            activate
        end tell
        tell application "System Events"
            tell process "\(escaped)"
                set position of window 1 to {\(x), \(y)}
                set size of window 1 to {\(w), \(h)}
            end tell
        end tell
        """
        var errorInfo: NSDictionary?
        let script = NSAppleScript(source: source)
        script?.executeAndReturnError(&errorInfo)
        if let e = errorInfo {
            return .failure(AXMoveError("AppleScript error: \(e)"))
        }
        return .success(MoveResult(appName: name, before: .zero, after: rect,
                                   usedEnhancedUIToggle: false, wasEnhancedUI: false))
    }

    // MARK: - Internals

    private static let kAXEnhancedUserInterface = "AXEnhancedUserInterface" as CFString

    private static func matchingApp(_ needle: String) -> NSRunningApplication? {
        let n = needle.lowercased()
        return NSWorkspace.shared.runningApplications.first {
            $0.activationPolicy == .regular && ($0.localizedName ?? "").lowercased().contains(n)
        }
    }

    static func setFrame(_ window: AXUIElement, _ rect: CGRect) {
        // Position first, then size (some apps clamp otherwise). No animation in raw AX.
        var pos = rect.origin
        if let posVal = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
        }
        var size = rect.size
        if let sizeVal = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
        }
    }

    static func frame(of window: AXUIElement) -> CGRect {
        var pos = CGPoint.zero
        var size = CGSize.zero
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
           let p = posRef, CFGetTypeID(p) == AXValueGetTypeID() {
            AXValueGetValue((p as! AXValue), .cgPoint, &pos)
        }
        if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let s = sizeRef, CFGetTypeID(s) == AXValueGetTypeID() {
            AXValueGetValue((s as! AXValue), .cgSize, &size)
        }
        return CGRect(origin: pos, size: size)
    }
}
