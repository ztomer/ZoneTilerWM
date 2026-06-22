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
    public static func windows(forApp appName: String) -> [(id: CGWindowID, pid: pid_t, title: String, frame: CGRect)] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
        var out: [(CGWindowID, pid_t, String, CGRect)] = []
        for info in infos {
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (info[kCGWindowOwnerName as String] as? String) == appName,
                  let num = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let b = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let rect = CGRect(dictionaryRepresentation: b as CFDictionary) else { continue }
            // Skip tiny utility/shadow windows.
            guard rect.width >= 80, rect.height >= 60 else { continue }
            let pid = pid_t((info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0)
            let title = (info[kCGWindowName as String] as? String) ?? appName
            out.append((num, pid, title, rect))
        }
        return out.map { (id: $0.0, pid: $0.1, title: $0.2, frame: $0.3) }
    }

    /// Capture thumbnails for an app and present the panel anchored to `item` on `edge`. No-op (and
    /// hides any existing panel) if the app has no capturable windows. `onRaise` fires with a window
    /// id when a thumbnail is clicked.
    public func show(appName: String, item: DockItem, edge: DockEdge, thumbWidth: CGFloat,
                     screen: ZTRect, onRaise: @escaping (CGWindowID, pid_t) -> Void) {
        let wins = Self.windows(forApp: appName)
        guard !wins.isEmpty else { hide(); return }
        let thumbs: [WinThumb] = wins.prefix(6).map { w in
            let img = CGWindowListCreateImage(.null, .optionIncludingWindow, w.id, [.boundsIgnoreFraming])
            return WinThumb(id: w.id, pid: w.pid, title: w.title, frame: w.frame, image: img)
        }
        let content = DockPreviewView(appName: appName, thumbs: thumbs, thumbWidth: thumbWidth, onRaise: { [weak self] id, pid in
            onRaise(id, pid); self?.hide()
        })
        let size = content.intrinsicSize()
        let origin = DockPreview.panelOrigin(item: item, size: (w: Double(size.width), h: Double(size.height)),
                                             edge: edge, screen: screen)
        // CG top-left origin → AppKit bottom-left for the window frame.
        let scrH: CGFloat = (NSScreen.screens.first { NSPointInRect(NSPoint(x: origin.x, y: origin.y), $0.frame) }?.frame.height)
            ?? NSScreen.main?.frame.height ?? CGFloat(screen.h)
        let appKitY = scrH - CGFloat(origin.y) - size.height
        let frame = NSRect(x: CGFloat(origin.x), y: appKitY, width: size.width, height: size.height)

        let p = panel ?? makePanel()
        p.setFrame(frame, display: true)
        p.contentView = content
        p.orderFrontRegardless()
        panel = p
    }

    public func hide() { panel?.orderOut(nil) }

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

/// The panel's content: a dark frosted card with the app name + a row of window thumbnails. Dark by
/// design so it reads over ANY wallpaper (the validate-light-and-dark rule); click a thumbnail to
/// raise that window.
final class DockPreviewView: NSView {
    private let appName: String
    private let thumbs: [DockPreviewOverlay.WinThumb]
    private let thumbW: CGFloat
    private let onRaise: (CGWindowID, pid_t) -> Void
    private var cellRects: [(rect: NSRect, id: CGWindowID, pid: pid_t)] = []

    private let pad: CGFloat = 14, titleH: CGFloat = 22, gap: CGFloat = 10, labelH: CGFloat = 16
    private var thumbH: CGFloat { (thumbW * 0.6).rounded() }   // uniform 5:3 cells

    init(appName: String, thumbs: [DockPreviewOverlay.WinThumb], thumbWidth: CGFloat,
         onRaise: @escaping (CGWindowID, pid_t) -> Void) {
        self.appName = appName; self.thumbs = thumbs; self.thumbW = thumbWidth; self.onRaise = onRaise
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    func intrinsicSize() -> NSSize {
        let n = CGFloat(max(1, thumbs.count))
        return NSSize(width: pad * 2 + n * thumbW + (n - 1) * gap,
                      height: pad * 2 + titleH + thumbH + labelH)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Dark frosted card.
        let card = NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16)
        NSColor.black.withAlphaComponent(0.82).setFill(); card.fill()
        NSColor.white.withAlphaComponent(0.10).setStroke(); card.lineWidth = 1; card.stroke()

        (appName as NSString).draw(at: NSPoint(x: pad, y: pad - 2), withAttributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92)])

        cellRects.removeAll()
        let trunc = NSMutableParagraphStyle(); trunc.lineBreakMode = .byTruncatingTail; trunc.alignment = .center
        var x = pad
        let top = pad + titleH
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
            cellRects.append((cell, t.id, t.pid))
            x += thumbW + gap
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let hit = cellRects.first(where: { $0.rect.contains(p) }) { onRaise(hit.id, hit.pid) }
    }

    /// Fit `imageSize` inside `box` preserving aspect, centred.
    private func aspectFit(_ imageSize: CGSize, in box: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return box }
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
