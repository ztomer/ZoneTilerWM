// SkyLightBorderRenderer.swift — ZTSystem: EXPERIMENTAL, opt-in, last-resort border backend that
// draws the outline as a window created directly on the window server via private SkyLight APIs
// (the JankyBorders technique, reimplemented clean-room — no GPL code). Off by default; overlay is
// the supported renderer. NOTE: this does NOT improve tracking latency — the lag is the
// CGWindowList polling, not the drawing — it only draws above more layers / across spaces. Kept
// purely as a fallback if the public NSWindow overlay ever misbehaves on some setup.
//
// Click-through: like JankyBorders, the window is a filled rect made transparent to the mouse via
// window-server TAGS — SLSSetWindowTags with bits (1<<1)|(1<<9), the SkyLight equivalent of
// NSWindow.ignoresMouseEvents. (The earlier version omitted this and captured clicks.) The tag
// symbol is REQUIRED: if it can't be resolved, init?() fails and the controller falls back to the
// overlay renderer rather than ship a window that eats mouse input.
//
// Every private symbol is resolved with dlsym from SkyLight.framework, so a dropped/renamed
// symbol degrades to the overlay backend instead of failing to link or crashing. SkyLight window
// origins are global top-left (== ZTRect, no flip); the per-window CGContext is bottom-left.

import AppKit
import ZTCore

// ⚠ PRIVATE / EXPERIMENTAL — dlopens SkyLight.framework. Compiled in only under ZT_PRIVATE_APIS
// (build_public.sh / build_dev.sh); a strict-MAS build (build_mas.sh) excludes it and uses the
// public OverlayBorderRenderer.
#if ZT_PRIVATE_APIS
final class SkyLightBorderRenderer: BorderRenderer {
    private typealias MainConnFn      = @convention(c) () -> Int32
    private typealias NewRegionFn     = @convention(c) (UnsafePointer<CGRect>, UnsafeMutablePointer<CFTypeRef?>) -> Int32
    private typealias NewWindowFn     = @convention(c) (Int32, Int32, Float, Float, CFTypeRef?, UnsafeMutablePointer<UInt32>) -> Int32
    private typealias ReleaseWindowFn = @convention(c) (Int32, UInt32) -> Int32
    private typealias SetOpacityFn    = @convention(c) (Int32, UInt32, Bool) -> Int32
    private typealias SetLevelFn      = @convention(c) (Int32, UInt32, Int32) -> Int32
    private typealias SetTagsFn       = @convention(c) (Int32, UInt32, UnsafeMutablePointer<UInt64>, Int32) -> Int32
    private typealias OrderWindowFn   = @convention(c) (Int32, UInt32, Int32, UInt32) -> Int32
    private typealias MoveWindowFn    = @convention(c) (Int32, UInt32, UnsafePointer<CGPoint>) -> Int32
    private typealias SetShapeFn      = @convention(c) (Int32, UInt32, Float, Float, CFTypeRef) -> Int32
    private typealias ContextCreateFn = @convention(c) (Int32, UInt32, CFDictionary?) -> Unmanaged<CGContext>?
    private typealias FlushFn         = @convention(c) (Int32, UInt32, CFTypeRef?) -> Int32

    private let newRegion: NewRegionFn
    private let newWindow: NewWindowFn
    private let releaseWindow: ReleaseWindowFn
    private let setOpacity: SetOpacityFn
    private let setLevel: SetLevelFn
    private let setTags: SetTagsFn
    private let orderWindow: OrderWindowFn
    private let moveWindow: MoveWindowFn
    private let setShape: SetShapeFn
    private let contextCreate: ContextCreateFn
    private let flush: FlushFn

    private let cid: Int32
    private var wid: UInt32 = 0
    private var size: CGSize = .zero      // current window content size; recreate the shape on change

    init?() {
        guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else { return nil }
        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            guard let p = dlsym(h, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        guard let mainConn = sym("SLSMainConnectionID", MainConnFn.self),
              let nr = sym("CGSNewRegionWithRect", NewRegionFn.self),
              let nw = sym("SLSNewWindow", NewWindowFn.self),
              let rw = sym("SLSReleaseWindow", ReleaseWindowFn.self),
              let so = sym("SLSSetWindowOpacity", SetOpacityFn.self),
              let sl = sym("SLSSetWindowLevel", SetLevelFn.self),
              let st = sym("SLSSetWindowTags", SetTagsFn.self),       // required: the click-through tag
              let ow = sym("SLSOrderWindow", OrderWindowFn.self),
              let mw = sym("SLSMoveWindow", MoveWindowFn.self),
              let ss = sym("SLSSetWindowShape", SetShapeFn.self),
              let cc = sym("SLWindowContextCreate", ContextCreateFn.self),
              let fl = sym("SLSFlushWindowContentRegion", FlushFn.self)
        else { return nil }
        newRegion = nr; newWindow = nw; releaseWindow = rw; setOpacity = so; setLevel = sl
        setTags = st; orderWindow = ow; moveWindow = mw; setShape = ss; contextCreate = cc; flush = fl
        cid = mainConn()
        guard cid != 0 else { return nil }
    }

    deinit { if wid != 0 { _ = releaseWindow(cid, wid) } }

    func render(frame: ZTRect?, style: BorderStyle) {
        guard let frame else { if wid != 0 { _ = orderWindow(cid, wid, 0, 0) }; return }   // 0 = order out
        let pad = style.width + max(style.inset, 0) + 2
        let outer = CGRect(x: frame.x - pad, y: frame.y - pad, w0: frame.w + 2 * pad, h0: frame.h + 2 * pad)
        if wid == 0 || outer.size != size {
            if !ensureWindow(size: outer.size) { return }
        }
        var origin = CGPoint(x: outer.origin.x, y: outer.origin.y)   // global top-left, no flip
        _ = moveWindow(cid, wid, &origin)
        draw(contentSize: outer.size, windowFrame: frame, pad: pad, style: style)
        _ = orderWindow(cid, wid, 1, 0)   // 1 = order above, relative to all
    }

    private func ensureWindow(size newSize: CGSize) -> Bool {
        var region: CFTypeRef?
        var rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
        guard newRegion(&rect, &region) == 0, let region else { return false }
        if wid == 0 {
            var newID: UInt32 = 0
            guard newWindow(cid, 2, 0, 0, region, &newID) == 0, newID != 0 else { return false }   // 2 = buffered
            wid = newID
            _ = setOpacity(cid, wid, false)
            _ = setLevel(cid, wid, Int32(CGWindowLevelForKey(.floatingWindow)))
            // Click-through: ignore-for-events tags (the SkyLight ignoresMouseEvents equivalent).
            var tags: UInt64 = (1 << 1) | (1 << 9)
            _ = setTags(cid, wid, &tags, 0x40)
        } else {
            _ = setShape(cid, wid, 0, 0, region)   // resize the existing window's shape
        }
        size = newSize
        return true
    }

    /// Draw the rounded-rect stroke into the window's CG context (bottom-left origin).
    private func draw(contentSize: CGSize, windowFrame frame: ZTRect, pad: Double, style: BorderStyle) {
        guard let ctx = contextCreate(cid, wid, nil)?.takeRetainedValue() else { return }
        ctx.clear(CGRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height))
        let r = CGRect(x: pad - style.inset, y: pad - style.inset,
                       w0: frame.w + 2 * style.inset, h0: frame.h + 2 * style.inset)
            .insetBy(dx: style.width / 2, dy: style.width / 2)
        let path = CGPath(roundedRect: r, cornerWidth: style.cornerRadius, cornerHeight: style.cornerRadius, transform: nil)
        ctx.setLineWidth(style.width)
        ctx.setStrokeColor(borderNSColor(style.color).cgColor)
        ctx.addPath(path)
        ctx.strokePath()
        ctx.flush()
        _ = flush(cid, wid, nil)
    }
}

private extension CGRect {
    /// Avoid the `w`/`h` shorthand clash with ZTRect by naming the size args.
    init(x: Double, y: Double, w0: Double, h0: Double) { self.init(x: x, y: y, width: w0, height: h0) }
}
#endif
