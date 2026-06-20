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
import ZTCore

#if ZT_PRIVATE_APIS
// ⚠️ PRIVATE / EXPERIMENTAL — `_AXUIElementGetWindow` is an undocumented AX SPI (the standard
// yabai-style way to map an AX window element to its CGWindowID). NOT App-Store-safe; compiled in
// only under ZT_PRIVATE_APIS (set by build_public.sh / build_dev.sh). The public fallback below
// (match by pid + frame) is used otherwise — see `AXWindowSystem.windowID(of:pid:)`.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement,
                                   _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError
#endif

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

public final class AXWindowSystem: WindowSystem {

    private let screenProvider: ScreenProvider
    public init(screenProvider: ScreenProvider) { self.screenProvider = screenProvider }

    /// Per-pid memo of "does this app have AXEnhancedUserInterface on?". SentinelOne hooks and
    /// analyzes every AX call, so the read below is itself a real cost; the flag is set by the
    /// app at launch and stable for its process lifetime, so we read it at most once per app and
    /// reuse it on every subsequent move. Native-AX apps (cached false) then make ZERO extra AX
    /// calls around a move; Firefox/Zen-class apps (cached true) keep the exact toggle. Keyed by
    /// pid, so a relaunched app gets a fresh read.
    private var enhancedUICache: [pid_t: Bool] = [:]

    private func appUsesEnhancedUI(_ appElem: AXUIElement, pid: pid_t) -> Bool {
        if let cached = enhancedUICache[pid] { return cached }
        var v: CFTypeRef?
        let on = AXUIElementCopyAttributeValue(appElem, Self.kAXEnhancedUserInterface, &v) == .success
            && (v as? Bool == true)
        enhancedUICache[pid] = on
        return on
    }

    /// Set a window's frame with the AXEnhancedUserInterface dance (Firefox/Zen quirk): toggle it
    /// off around the set, restore after — but only when the app actually has it on, and reading
    /// that state at most once per app (see `enhancedUICache`).
    private func setFrameWithEnhancedToggle(_ window: AXUIElement, app: AXUIElement, pid: pid_t, rect: CGRect) {
        let wasEnhanced = appUsesEnhancedUI(app, pid: pid)
        if wasEnhanced { AXUIElementSetAttributeValue(app, Self.kAXEnhancedUserInterface, kCFBooleanFalse) }
        Self.setFrame(window, rect)
        if wasEnhanced { AXUIElementSetAttributeValue(app, Self.kAXEnhancedUserInterface, kCFBooleanTrue) }
    }

    // MARK: - WindowSystem (live AX)

    public func focusedWindow() -> LiveWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let axWin = focusedAXWindow(pid: app.processIdentifier) else { return nil }
        let cg = Self.frame(of: axWin)
        let wid = windowID(of: axWin, pid: app.processIdentifier) ?? 0
        let uuid = screenProvider.screen(containing: (x: Double(cg.midX), y: Double(cg.midY)))?.uuid
        return LiveWindow(id: Int(wid), appName: app.localizedName ?? "",
                          frame: ZTRect(x: cg.origin.x, y: cg.origin.y, w: cg.size.width, h: cg.size.height),
                          screenUUID: uuid, pid: Int(app.processIdentifier))
    }

    public func windows(onScreen uuid: String) -> [LiveWindow] {
        Self.onScreenWindows().filter { $0.layer == 0 }.compactMap { w in
            let center = (x: Double(w.bounds.midX), y: Double(w.bounds.midY))
            guard let s = screenProvider.screen(containing: center), s.uuid == uuid else { return nil }
            return LiveWindow(id: Int(w.windowID), appName: w.ownerName,
                              frame: ZTRect(x: w.bounds.origin.x, y: w.bounds.origin.y,
                                            w: w.bounds.size.width, h: w.bounds.size.height),
                              screenUUID: uuid, pid: Int(w.pid))
        }
    }

    /// All standard (layer-0) on-screen windows, front-to-back (CGWindowList z-order). Unlike
    /// windows(onScreen:), this does NOT filter by which display the window's center is on — used by
    /// focus-follows-mouse, which hit-tests the cursor point against the global front-to-back order
    /// (filtering by center wrongly drops a window under the cursor whose centre is on another
    /// display, so FFM would focus the window beneath it). 0 AX (CGWindowList).
    public func allWindows() -> [LiveWindow] {
        Self.onScreenWindows().filter { $0.layer == 0 }.map { w in
            LiveWindow(id: Int(w.windowID), appName: w.ownerName,
                       frame: ZTRect(x: w.bounds.origin.x, y: w.bounds.origin.y,
                                     w: w.bounds.size.width, h: w.bounds.size.height),
                       screenUUID: nil, pid: Int(w.pid))
        }
    }

    @discardableResult
    public func moveFocusedWindow(to rect: ZTRect) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let axWin = focusedAXWindow(pid: app.processIdentifier) else { return false }
        let appElem = AXUIElementCreateApplication(app.processIdentifier)
        setFrameWithEnhancedToggle(axWin, app: appElem, pid: app.processIdentifier,
                                   rect: CGRect(x: rect.x, y: rect.y, width: rect.w, height: rect.h))
        return true
    }

    @discardableResult
    public func move(windowId: Int, to rect: ZTRect) -> Bool {
        guard let r = resolveWindow(windowId: windowId) else { return false }
        setFrameWithEnhancedToggle(r.window, app: r.app, pid: r.pid,
                                   rect: CGRect(x: rect.x, y: rect.y, width: rect.w, height: rect.h))
        return true
    }

    @discardableResult
    public func focus(windowId: Int) -> Bool {
        guard let r = resolveWindow(windowId: windowId) else { return false }
        let app = NSRunningApplication(processIdentifier: r.pid)
        // A hidden app (Cmd-H — e.g. Notion / Notion Calendar, both Electron) does NOT come back
        // on activate() alone: it takes focus but its windows stay hidden until you click the Dock
        // icon. unhide() FIRST, then raise the specific window. Mirrors AppController.launchOrFocus.
        app?.unhide()
        AXUIElementPerformAction(r.window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(r.window, kAXMainAttribute as CFString, kCFBooleanTrue)
        app?.activate(options: [.activateAllWindows])
        return true
    }

    @discardableResult
    public func setMinimized(_ minimized: Bool, windowId: Int) -> Bool {
        guard let r = resolveWindow(windowId: windowId) else { return false }
        let value: CFBoolean = minimized ? kCFBooleanTrue : kCFBooleanFalse
        return AXUIElementSetAttributeValue(r.window, kAXMinimizedAttribute as CFString, value) == .success
    }

    /// Close a window by pressing its AX close button (the exposé × button). Returns false if the
    /// window or its close button can't be resolved.
    @discardableResult
    public func closeWindow(windowId: Int) -> Bool {
        guard let r = resolveWindow(windowId: windowId) else { return false }
        var btnRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(r.window, kAXCloseButtonAttribute as CFString, &btnRef) == .success,
              let btn = btnRef, CFGetTypeID(btn) == AXUIElementGetTypeID() else { return false }
        return AXUIElementPerformAction(btn as! AXUIElement, kAXPressAction as CFString) == .success
    }

    /// Resolve a CGWindowID to its AX window + owning app element via _AXUIElementGetWindow.
    private func resolveWindow(windowId: Int) -> (window: AXUIElement, app: AXUIElement, pid: pid_t)? {
        let target = CGWindowID(windowId)
        guard let pid = Self.onScreenWindows().first(where: { $0.windowID == target })?.pid else { return nil }
        let appElem = AXUIElementCreateApplication(pid)
        var winsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElem, kAXWindowsAttribute as CFString, &winsRef) == .success,
              let wins = winsRef as? [AXUIElement] else { return nil }
        for w in wins {
            if windowID(of: w, pid: pid) == target { return (w, appElem, pid) }
        }
        return nil
    }

    /// AX window → CGWindowID. Uses the private SPI when compiled in (ZT_PRIVATE_APIS), else matches
    /// by pid + frame against the CGWindowList (public, MAS-safe). When an app has multiple windows of
    /// the same size at the same spot the frame match is ambiguous; we break the tie by **z-order** —
    /// `onScreenWindows()` is front-to-back, and the focused window is the frontmost of its app, so the
    /// first match is the right one. (Title would be a second signal but `kCGWindowName` is usually
    /// empty without screen-recording permission, so it's not reliable here.)
    private func windowID(of axWin: AXUIElement, pid: pid_t) -> CGWindowID? {
        #if ZT_PRIVATE_APIS
        var wid: CGWindowID = 0
        return _AXUIElementGetWindow(axWin, &wid) == .success ? wid : nil
        #else
        let f = Self.frame(of: axWin)
        let matches = Self.onScreenWindows().filter {
            $0.pid == pid
                && abs($0.bounds.origin.x - f.origin.x) < 2 && abs($0.bounds.origin.y - f.origin.y) < 2
                && abs($0.bounds.size.width - f.size.width) < 2 && abs($0.bounds.size.height - f.size.height) < 2
        }
        if matches.count > 1 {
            FileHandle.standardError.write(Data("zt-agent[ax]: windowID match ambiguous (\(matches.count) same-pid/same-frame windows) — using frontmost\n".utf8))
        }
        return matches.first?.windowID   // front-to-back order → frontmost (= focused) wins the tie
        #endif
    }

    private func focusedAXWindow(pid: pid_t) -> AXUIElement? {
        let appElem = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElem, kAXFocusedWindowAttribute as CFString, &ref) == .success,
              let w = ref, CFGetTypeID(w) == AXUIElementGetTypeID() else { return nil }
        return (w as! AXUIElement)
    }

    // MARK: - Static helpers (used by zt-axspike + the instance methods above)

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
                CGRectMakeWithDictionaryRepresentation(boundsDict as CFDictionary, &bounds)
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
