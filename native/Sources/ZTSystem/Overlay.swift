// Overlay.swift — lightweight on-screen overlays (borderless click-through windows):
// a focus flash and the Pomodoro color bar. Purely visual; validate in a UI round.
//
// Coordinates: ZTRect is top-left CG; NSWindow frames are bottom-left global. CoordConvert
// flips using the primary display height (CGDisplayBounds(main)). A flip bug here is the
// most likely visual regression.

import AppKit
import ZTCore

enum CoordConvert {
    /// Convert a top-left CG rect to a bottom-left global NSRect for NSWindow placement.
    static func nsFrame(fromCG r: ZTRect) -> NSRect {
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        return NSRect(x: r.x, y: primaryHeight - r.y - r.h, width: r.w, height: r.h)
    }
}

private func makeOverlayWindow(_ frame: NSRect, color: NSColor) -> NSWindow {
    let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    w.isOpaque = false
    w.backgroundColor = color
    w.ignoresMouseEvents = true
    w.level = .statusBar
    w.hasShadow = false
    w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    return w
}

/// A brief translucent highlight over a window's frame (focus/tile feedback).
public final class FlashOverlay {
    private var window: NSWindow?
    private var hideWork: DispatchWorkItem?
    public init() {}

    public func flash(_ rect: ZTRect, duration: Double = 0.2,
                      color: NSColor = NSColor(red: 0.5, green: 0.5, blue: 1.0, alpha: 0.3)) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hideWork?.cancel()
            self.window?.orderOut(nil)
            let w = makeOverlayWindow(CoordConvert.nsFrame(fromCG: rect), color: color)
            w.orderFront(nil)
            self.window = w
            let work = DispatchWorkItem { [weak self] in self?.window?.orderOut(nil); self?.window = nil }
            self.hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
        }
    }
}

/// Two thin strips at the top of the main screen: used (left) + remaining (right).
public final class PomodoroBar {
    private var usedWindow: NSWindow?
    private var remainingWindow: NSWindow?
    public init() {}

    public func update(timeLeft: Int, maxTime: Int, heightRatio: Double, alpha: Double,
                       remaining: NSColor, used: NSColor) {
        DispatchQueue.main.async { [weak self] in
            guard let self, maxTime > 0 else { return }
            let full = CGDisplayBounds(CGMainDisplayID())
            let barHeight = max(2.0, 22.0 * heightRatio)   // ~menubar height * ratio
            let ratio = max(0, min(1, Double(timeLeft) / Double(maxTime)))
            let remainingW = full.width * ratio
            let usedW = full.width - remainingW
            // Top edge in CG coords -> NS frames.
            let usedRect = ZTRect(x: full.minX, y: full.minY, w: usedW, h: barHeight)
            let remainingRect = ZTRect(x: full.minX + usedW, y: full.minY, w: remainingW, h: barHeight)
            self.usedWindow = self.place(self.usedWindow, usedRect, used.withAlphaComponent(alpha))
            self.remainingWindow = self.place(self.remainingWindow, remainingRect, remaining.withAlphaComponent(alpha))
        }
    }

    public func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.usedWindow?.orderOut(nil); self?.usedWindow = nil
            self?.remainingWindow?.orderOut(nil); self?.remainingWindow = nil
        }
    }

    private func place(_ existing: NSWindow?, _ rect: ZTRect, _ color: NSColor) -> NSWindow {
        let frame = CoordConvert.nsFrame(fromCG: rect)
        if let w = existing {
            w.setFrame(frame, display: true)
            w.backgroundColor = color
            w.orderFront(nil)
            return w
        }
        let w = makeOverlayWindow(frame, color: color)
        w.orderFront(nil)
        return w
    }
}
