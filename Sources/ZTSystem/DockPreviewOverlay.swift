// DockPreviewOverlay.swift — the floating panel that shows a hovered Dock app's window thumbnails
// (DockDoor-style, clean-room). The controller (agent) decides WHEN to show it; this owns the
// capture + the panel rendering + click-to-raise.
//
// Capture is 0-AX: window list via CGWindowListCopyWindowInfo (owner-name filtered), thumbnails via
// CGWindowListCreateImage — the same path the Exposé overlay uses. Click-to-raise is the only AX
// touch, and it's user-triggered.

import AppKit
import ApplicationServices
import ZTCore

/// What a click on a preview thumbnail does: the body raises; the three traffic lights close /
/// minimize / full-screen that specific window (DockDoor-style).
public enum DockWindowAction { case raise, close, minimize, fullscreen }

/// Perform a window action via AX, matching the app's window by its on-screen FRAME (the only AX
/// touch, and only on an explicit click). Frame-matching — not title — because titles are often blank
/// or duplicated, and a wrong match on `.close` would close the WRONG window. No fallback: an
/// unmatched action (esp. close) is a safe no-op.
public enum DockWindowActions {
    private static let kAXFullScreenButtonAttribute = "AXFullScreenButton"

    public static func perform(pid: pid_t, frame: CGRect, _ action: DockWindowAction) {
        if action == .raise {
            NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateIgnoringOtherApps])
        }
        let app = AXUIElementCreateApplication(pid)
        var winsV: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &winsV) == .success,
              let wins = winsV as? [AXUIElement],
              let w = wins.first(where: { axFrame($0).map { framesMatch($0, frame) } ?? false }) else { return }
        switch action {
        case .raise:
            AXUIElementPerformAction(w, kAXRaiseAction as CFString)
        case .minimize:
            AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        case .close:
            if let btn = attr(w, kAXCloseButtonAttribute) { AXUIElementPerformAction(btn as! AXUIElement, kAXPressAction as CFString) }
        case .fullscreen:
            if let btn = attr(w, kAXFullScreenButtonAttribute) {
                AXUIElementPerformAction(btn as! AXUIElement, kAXPressAction as CFString)
            } else { // older AX: toggle the attribute
                AXUIElementSetAttributeValue(w, "AXFullScreen" as CFString, kCFBooleanTrue)
            }
        }
    }

    private static func axFrame(_ el: AXUIElement) -> CGRect? {
        guard let pv = attr(el, kAXPositionAttribute), let sv = attr(el, kAXSizeAttribute) else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &p); AXValueGetValue(sv as! AXValue, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }
    private static func framesMatch(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 4 && abs(a.minY - b.minY) < 4 && abs(a.width - b.width) < 4 && abs(a.height - b.height) < 4
    }
    private static func attr(_ el: AXUIElement, _ a: String) -> AnyObject? {
        var v: AnyObject?; return AXUIElementCopyAttributeValue(el, a as CFString, &v) == .success ? v : nil
    }
}

public final class DockPreviewOverlay {

    /// One capturable window of the hovered app.
    public struct WinThumb {
        let id: CGWindowID
        let pid: pid_t
        let title: String
        let frame: CGRect
        let image: CGImage?
    }

    private var panel: NSPanel?
    public init() {}

    /// On-screen, normal-layer windows owned by `appName`, front-to-back (0 AX, current Space only).
    /// Resolves the app's PID from its (Dock-title) display name and filters CGWindowList by OWNER PID
    /// — exact — rather than owner NAME, which can differ from the Dock's localized title (so the
    /// feature wouldn't silently do nothing for those apps). Falls back to a name match if unresolved.
    public static func windows(forApp appName: String) -> [(id: CGWindowID, pid: pid_t, title: String, frame: CGRect)] {
        let pid = NSWorkspace.shared.runningApplications.first {
            $0.localizedName == appName || $0.localizedName?.caseInsensitiveCompare(appName) == .orderedSame
        }?.processIdentifier
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
        var out: [(CGWindowID, pid_t, String, CGRect)] = []
        for info in infos {
            let ownerPID = pid_t((info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0)
            let matches = pid != nil ? (ownerPID == pid!) : ((info[kCGWindowOwnerName as String] as? String) == appName)
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0, matches,
                  let num = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let b = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let rect = CGRect(dictionaryRepresentation: b as CFDictionary) else { continue }
            guard rect.width >= 80, rect.height >= 60 else { continue }   // skip tiny utility/shadow windows
            let title = (info[kCGWindowName as String] as? String) ?? appName
            out.append((num, ownerPID, title, rect))
        }
        return out.map { (id: $0.0, pid: $0.1, title: $0.2, frame: $0.3) }
    }

    /// Capture thumbnails for an app and present the panel anchored to `item` on `edge`. No-op (and
    /// hides any existing panel) if the app has no capturable windows. `onRaise` fires with a window
    /// id when a thumbnail is clicked.
    public func show(appName: String, item: DockItem, edge: DockEdge, thumbWidth: CGFloat,
                     screen: ZTRect, onAction: @escaping (pid_t, CGRect, DockWindowAction) -> Void) {
        let wins = Self.windows(forApp: appName)
        guard !wins.isEmpty else { hide(); return }
        let thumbs: [WinThumb] = wins.prefix(6).map { w in
            let img = CGWindowListCreateImage(.null, .optionIncludingWindow, w.id, [.boundsIgnoreFraming])
            return WinThumb(id: w.id, pid: w.pid, title: w.title, frame: w.frame, image: img)
        }
        let content = DockPreviewView(thumbs: thumbs, thumbWidth: thumbWidth,
                                      onAction: { [weak self] pid, frame, action in
            onAction(pid, frame, action); self?.hide()
        })
        let size = content.intrinsicSize()
        let origin = DockPreview.panelOrigin(item: item, size: (w: Double(size.width), h: Double(size.height)),
                                             edge: edge, screen: screen)
        // Top-left CG → bottom-left AppKit via the shared converter (flips by the PRIMARY display
        // height, x unchanged) — the same path every other overlay uses. The old hand-rolled flip
        // hit-tested a top-left point against bottom-left NSScreen frames and broke on right/left
        // docks + multi-monitor.
        let frame = CoordConvert.nsFrame(fromCG: ZTRect(x: origin.x, y: origin.y,
                                                        w: Double(size.width), h: Double(size.height)))
        let p = panel ?? makePanel()
        p.setFrame(frame, display: true)
        p.contentView = content
        p.orderFrontRegardless()
        panel = p
        panelFrame = frame
    }

    /// The shown panel's screen frame (bottom-left global), for the controller's hover hit-test. nil
    /// when hidden.
    public private(set) var panelFrame: NSRect?

    public func hide() { panel?.orderOut(nil); panelFrame = nil }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return p
    }
}

/// The panel's content: a dark frosted card with a row of window thumbnails, each labeled with its
/// WINDOW title (the Dock icon already names the app, so no redundant app-name header — F3). Dark by
/// design so it reads over ANY wallpaper (the validate-light-and-dark rule); click a thumbnail to
/// raise that window.
final class DockPreviewView: NSView {
    private let thumbs: [DockPreviewOverlay.WinThumb]
    private let thumbW: CGFloat
    private let onAction: (pid_t, CGRect, DockWindowAction) -> Void
    private struct Hit { let rect: NSRect; let pid: pid_t; let frame: CGRect; let action: DockWindowAction }
    private var hits: [Hit] = []

    private let pad: CGFloat = 14, gap: CGFloat = 10, labelH: CGFloat = 16
    private let dotR: CGFloat = 5.5   // traffic-light radius
    private var thumbH: CGFloat { (thumbW * 0.6).rounded() }   // uniform 5:3 cells

    init(thumbs: [DockPreviewOverlay.WinThumb], thumbWidth: CGFloat,
         onAction: @escaping (pid_t, CGRect, DockWindowAction) -> Void) {
        self.thumbs = thumbs; self.thumbW = thumbWidth; self.onAction = onAction
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    func intrinsicSize() -> NSSize {
        let n = CGFloat(max(1, thumbs.count))
        return NSSize(width: pad * 2 + n * thumbW + (n - 1) * gap,
                      height: pad * 2 + thumbH + labelH)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Dark frosted card.
        let card = NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16)
        NSColor.black.withAlphaComponent(0.82).setFill(); card.fill()
        NSColor.white.withAlphaComponent(0.10).setStroke(); card.lineWidth = 1; card.stroke()

        hits.removeAll()
        let trunc = NSMutableParagraphStyle(); trunc.lineBreakMode = .byTruncatingTail; trunc.alignment = .center
        var x = pad
        let top = pad
        for t in thumbs {
            let cell = NSRect(x: x, y: top, width: thumbW, height: thumbH)
            NSColor.white.withAlphaComponent(0.06).setFill()
            NSBezierPath(roundedRect: cell, xRadius: 8, yRadius: 8).fill()
            if let img = t.image { drawUpright(img, in: aspectFit(CGSize(width: img.width, height: img.height), in: cell.insetBy(dx: 4, dy: 4))) }
            NSColor.white.withAlphaComponent(0.12).setStroke()
            let border = NSBezierPath(roundedRect: cell, xRadius: 8, yRadius: 8); border.lineWidth = 1; border.stroke()
            (t.title as NSString).draw(in: NSRect(x: x, y: top + thumbH, width: thumbW, height: labelH), withAttributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.white.withAlphaComponent(0.6), .paragraphStyle: trunc])

            // Per-window traffic lights (top-left), each a clickable action. Added to `hits` BEFORE the
            // cell-body raise hit so a click on a light wins over a raise.
            let lights: [(NSColor, DockWindowAction)] = [
                (ZTPalette.trafficClose, .close),
                (ZTPalette.trafficMinimize, .minimize),
                (ZTPalette.trafficFullscreen, .fullscreen)]
            for (i, light) in lights.enumerated() {
                let cx = cell.minX + 12 + CGFloat(i) * 17, cy = cell.minY + 12
                let dot = NSRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2)
                light.0.setFill(); NSBezierPath(ovalIn: dot).fill()
                hits.append(Hit(rect: dot.insetBy(dx: -3, dy: -3), pid: t.pid, frame: t.frame, action: light.1))
            }
            hits.append(Hit(rect: cell, pid: t.pid, frame: t.frame, action: .raise))
            x += thumbW + gap
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let hit = hits.first(where: { $0.rect.contains(p) }) { onAction(hit.pid, hit.frame, hit.action) }
    }

    /// Fit `imageSize` inside `box` preserving aspect, centred.
    private func aspectFit(_ imageSize: CGSize, in box: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0, box.width > 0, box.height > 0 else { return box }
        let s = min(box.width / imageSize.width, box.height / imageSize.height)
        let w = imageSize.width * s, h = imageSize.height * s
        return NSRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
    }

    /// Draw a CG (bottom-up) image upright in this flipped (top-left) view.
    private func drawUpright(_ cg: CGImage, in rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }
}
