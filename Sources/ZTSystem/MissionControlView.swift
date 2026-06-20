// MissionControlView.swift — the NSView that DRAWS the Exposé/Mission-Control overlay (window-tile
// badges, close buttons, the per-monitor Spaces strip, wallpapers, the Liquid-Glass bar). Split out
// of MissionControlOverlay.swift, which now owns only the window lifecycle + renderPNG. Same module.

import AppKit
import ZTCore

/// Top-left/flipped container so child frames (wallpaper, glass bar, drawing view) share the same
/// coordinate space as the flipped MissionControlView.
final class FlippedContainerView: NSView {
    override var isFlipped: Bool { true }
}

final class MissionControlView: NSView {
    /// The spaces-bar rect (flipped/top-left coords) for a given position + overlay size. Single
    /// source of truth for the bar geometry — used by both the live glass material and the draw pass.
    static let barThickness: CGFloat = 240
    static func barRect(position: String, size: NSSize) -> NSRect {
        switch position.lowercased() {
        case "left":   return NSRect(x: 0, y: 0, width: barThickness, height: size.height)
        case "right":  return NSRect(x: size.width - barThickness, y: 0, width: barThickness, height: size.height)
        case "bottom": return NSRect(x: 0, y: size.height - barThickness, width: size.width, height: barThickness)
        default:       return NSRect(x: 0, y: 0, width: size.width, height: barThickness)   // "top"
        }
    }

    var hints: [MissionControl.Hint] = []
    var origin: (x: Double, y: Double) = (0, 0)
    private var windowImages: [Int: CGImage] = [:]
    private var wallpaper: NSImage?
    
    // Spaces state
    var spaces: [MissionControlOverlay.SpaceInfo] = []
    private var selectedSpaceIndex: Int = 0
    private var spacesBarPosition: String = "top"
    var groups: [MissionControlOverlay.SpaceGroup] = []   // monitor groupings for the combined strip

    /// Live overlay layers a wallpaper image + a Liquid Glass material behind this view, so it draws
    /// transparently. The QA renderPNG path has neither, so it keeps painting its own backdrop + bar.
    var drawsOwnBackground = true

    /// Keyboard-selected window (arrow / vim nav) — drawn with a highlight ring. nil = none.
    var selectedWindowId: Int? { didSet { if oldValue != selectedWindowId { needsDisplay = true } } }
    /// During "/" search: windows matching the query are bordered and the rest dimmed. nil = no search.
    var matchedWindowIds: Set<Int>? { didSet { if oldValue != matchedWindowIds { needsDisplay = true } } }

    var onJump: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onDismiss: (() -> Void)?
    var onSelectSpace: ((Int) -> Void)?
    var onAddSpace: (() -> Void)?
    var onDeleteSpace: ((Int) -> Void)?
    var onMoveWindowToSpace: ((Int, Int) -> Void)?
    var onRenameSpace: ((Int) -> Void)?

    /// When false (all-monitors strip = monitor targets), the + / × chrome for editing virtual
    /// spaces is hidden — you can only select / drop onto the monitor thumbnails.
    var editableSpaces = true

    // Dragging state
    var draggedWindowId: Int? = nil
    var dragStartPoint: NSPoint = .zero
    var dragCurrentPoint: NSPoint = .zero

    override var isFlipped: Bool { true }   // top-left origin to match CG
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var iconCache: [String: NSImage?] = [:]

    private func appIcon(for name: String) -> NSImage? {
        if name.isEmpty { return nil }
        if let cached = iconCache[name] { return cached }
        let icon = NSWorkspace.shared.runningApplications.first { $0.localizedName == name }?.icon
        iconCache[name] = icon
        return icon
    }

    private func badgeColor(for zone: String?) -> NSColor {
        guard let zone = zone?.lowercased() else {
            return NSColor(red: 0.94, green: 0.94, blue: 0.94, alpha: 0.97) // Pastel Gray
        }
        switch zone {
        case "h", "left":
            return NSColor(red: 0.85, green: 0.92, blue: 0.97, alpha: 0.97) // Pastel Blue
        case "l", "right":
            return NSColor(red: 0.85, green: 0.95, blue: 0.88, alpha: 0.97) // Pastel Green
        case "k", "top":
            return NSColor(red: 0.92, green: 0.88, blue: 0.96, alpha: 0.97) // Pastel Purple
        case "j", "bottom":
            return NSColor(red: 0.98, green: 0.92, blue: 0.85, alpha: 0.97) // Pastel Orange
        case "c", "center":
            return NSColor(red: 1.0, green: 0.95, blue: 0.75, alpha: 0.97)  // Pastel Yellow/Amber
        default:
            let colors = [
                NSColor(red: 0.85, green: 0.92, blue: 0.97, alpha: 0.97),
                NSColor(red: 0.85, green: 0.95, blue: 0.88, alpha: 0.97),
                NSColor(red: 0.92, green: 0.88, blue: 0.96, alpha: 0.97),
                NSColor(red: 0.98, green: 0.92, blue: 0.85, alpha: 0.97),
                NSColor(red: 1.0, green: 0.95, blue: 0.75, alpha: 0.97)
            ]
            let hash = abs(zone.hashValue)
            return colors[hash % colors.count]
        }
    }

    func set(_ hints: [MissionControl.Hint], screenOrigin: (x: Double, y: Double), wallpaper: NSImage? = nil, spaces: [MissionControlOverlay.SpaceInfo] = [], selectedSpaceIndex: Int = 0, spacesBarPosition: String = "top") {
        self.origin = screenOrigin
        self.wallpaper = wallpaper
        self.windowImages = [:]
        self.spaces = spaces
        self.selectedSpaceIndex = selectedSpaceIndex
        self.spacesBarPosition = spacesBarPosition
        
        var adjustedHints: [MissionControl.Hint] = []
        for h in hints {
            if let image = CGWindowListCreateImage(CGRect.null, .optionIncludingWindow, CGWindowID(h.windowId), []) {
                self.windowImages[h.windowId] = image
                
                let imgW = Double(image.width)
                let imgH = Double(image.height)
                if imgW > 0 && imgH > 0 {
                    // Calculate aspect-fitted bounds in global coordinates
                    let scale = min(h.frame.w / imgW, h.frame.h / imgH)
                    let dw = imgW * scale
                    let dh = imgH * scale
                    let dx = h.frame.x + (h.frame.w - dw) / 2
                    let dy = h.frame.y + (h.frame.h - dh) / 2
                    
                    // Center the badge inside the actual preview rect
                    let hasIcon = self.appIcon(for: h.appName) != nil
                    let bw = min(hasIcon ? 62.0 : 34.0, dw)
                    let bh = min(28.0, dh)
                    let badgeRect = ZTRect(x: dx + (dw - bw) / 2, y: dy + (dh - bh) / 2, w: bw, h: bh)
                    
                    // Position close button at the top-LEFT corner of the preview rect (macOS-native
                    // side), slightly larger than before.
                    let cs = 26.0
                    let inset = 4.0
                    let closeRect = ZTRect(x: dx + inset, y: dy + inset, w: cs, h: cs)
                    
                    adjustedHints.append(MissionControl.Hint(
                        windowId: h.windowId,
                        label: h.label,
                        frame: h.frame,
                        badge: badgeRect,
                        close: closeRect,
                        appName: h.appName,
                        zoneKey: h.zoneKey
                    ))
                } else {
                    adjustedHints.append(h)
                }
            } else {
                adjustedHints.append(h)
            }
        }
        self.hints = adjustedHints

        // Also capture screenshots for any window shown in a strip thumbnail (so every monitor's
        // thumbnail renders real mini-previews, not just the windows in this panel's grid). All are
        // on-screen → capture succeeds. 0 AX (CGWindowList).
        for sp in spaces {
            for win in sp.windows where win.windowId != 0 && windowImages[win.windowId] == nil {
                if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(win.windowId), []) {
                    windowImages[win.windowId] = image
                }
            }
        }
    }

    /// Draw a CGImage upright inside `rect` in this flipped view (file-loaded wallpapers otherwise
    /// render upside-down here).
    private func drawUpright(_ cg: CGImage, in rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }

    func spacesBarGeometry(bounds: NSRect) -> (bar: NSRect, thumbs: [NSRect], closeButtons: [NSRect], plus: NSRect) {
        let pos = spacesBarPosition.lowercased()
        let barRect = Self.barRect(position: pos, size: bounds.size)

        let thumbW: CGFloat = 210, thumbH: CGFloat = 135, plusSize: CGFloat = 135, gap: CGFloat = 20
        let n = spaces.count
        var thumbs: [NSRect] = []
        var closeButtons: [NSRect] = []
        let horizontal = (pos != "left" && pos != "right")

        func appendThumb(_ t: NSRect) {
            thumbs.append(t)
            // Close (×) at the thumbnail's top-left corner.
            closeButtons.append(NSRect(x: t.minX - 6, y: t.minY - 6, width: 24, height: 24))
        }

        // The + button only exists when spaces are editable; otherwise the group is just the thumbs.
        let plusExtent = editableSpaces ? (gap + plusSize) : 0

        // Extra spacing inserted before each monitor group's first thumbnail (combined strip).
        let groupGap: CGFloat = 56
        var groupStart = Set<Int>()
        if !groups.isEmpty { var acc = 0; for g in groups { if acc > 0 { groupStart.insert(acc) }; acc += g.count } }
        let groupExtent = CGFloat(max(0, groups.count - 1)) * groupGap

        let plusRect: NSRect
        if horizontal {
            // Centre the whole [thumb … thumb (+)] group across the bar width (with monitor-group gaps).
            let totalW = CGFloat(n) * thumbW + CGFloat(max(0, n - 1)) * gap + groupExtent + plusExtent
            let y: CGFloat = (pos == "bottom") ? bounds.height - 240 + 40 : 40
            var x = (bounds.width - totalW) / 2
            for i in 0..<n {
                if groupStart.contains(i) { x += groupGap }
                appendThumb(NSRect(x: x, y: y, width: thumbW, height: thumbH))
                x += thumbW + (i < n - 1 || editableSpaces ? gap : 0)
            }
            plusRect = NSRect(x: x, y: y + (thumbH - plusSize) / 2, width: plusSize, height: plusSize)
        } else {
            // Vertical bar: centre the group across the bar height.
            let totalH = CGFloat(n) * thumbH + CGFloat(max(0, n - 1)) * gap + plusExtent
            let x: CGFloat = (pos == "right") ? bounds.width - 240 + 15 : 15
            var y = (bounds.height - totalH) / 2
            for i in 0..<n { appendThumb(NSRect(x: x, y: y, width: thumbW, height: thumbH)); y += thumbH + (i < n - 1 || editableSpaces ? gap : 0) }
            plusRect = NSRect(x: x + (thumbW - plusSize) / 2, y: y, width: plusSize, height: plusSize)
        }

        return (barRect, thumbs, closeButtons, plusRect)
    }


    func local(_ r: ZTRect) -> NSRect {
        NSRect(x: r.x - origin.x, y: r.y - origin.y, width: r.w, height: r.h)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Backdrop is drawn here ONLY for the windowless QA render; the live overlay layers a
        // wallpaper NSImageView + a Liquid Glass NSVisualEffectView behind this (transparent) view.
        if drawsOwnBackground {
            if let wallpaper = self.wallpaper {
                wallpaper.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)
            } else {
                NSColor(white: 0.15, alpha: 1.0).setFill()
                bounds.fill()
            }
        }

        // Draw Spaces Bar
        if !spaces.isEmpty {
            let geom = spacesBarGeometry(bounds: bounds)

            // Flat bar background only in the QA render; live uses the glass material behind the view.
            if drawsOwnBackground {
                NSColor.black.withAlphaComponent(0.45).setFill()
                geom.bar.fill()
            }

            // Hard divider line only in the QA render; the live floating glass panel needs none.
            if drawsOwnBackground {
                let dividerRect: NSRect
                let pos = spacesBarPosition.lowercased()
                if pos == "left" {
                    dividerRect = NSRect(x: geom.bar.width - 1, y: 0, width: 1, height: bounds.height)
                } else if pos == "right" {
                    dividerRect = NSRect(x: geom.bar.minX, y: 0, width: 1, height: bounds.height)
                } else if pos == "bottom" {
                    dividerRect = NSRect(x: 0, y: geom.bar.minY, width: bounds.width, height: 1)
                } else {
                    dividerRect = NSRect(x: 0, y: geom.bar.height - 1, width: bounds.width, height: 1)
                }
                NSColor.white.withAlphaComponent(0.12).setFill()
                dividerRect.fill()
            }

            // Draw a labelled rounded border around each monitor group (combined "all" strip) so it's
            // clear which spaces belong to which monitor.
            if !groups.isEmpty {
                var idx = 0
                for g in groups where g.count > 0 && idx < geom.thumbs.count {
                    let slice = geom.thumbs[idx..<min(idx + g.count, geom.thumbs.count)]
                    var u = slice.first!
                    for r in slice { u = u.union(r) }
                    let box = u.insetBy(dx: -12, dy: -12)
                    let path = NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10)
                    NSColor.white.withAlphaComponent(0.06).setFill(); path.fill()
                    NSColor.white.withAlphaComponent(0.35).setStroke(); path.lineWidth = 1.5; path.stroke()
                    let label = g.name as NSString
                    let la: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                        .foregroundColor: NSColor.white.withAlphaComponent(0.85)
                    ]
                    label.draw(at: NSPoint(x: box.minX + 6, y: box.minY - 16), withAttributes: la)
                    idx += g.count
                }
            }

            // Draw spaces thumbnails
            for i in 0..<spaces.count {
                let thumbRect = geom.thumbs[i]
                
                // Draw thumbnail background — the actual desktop wallpaper, UPRIGHT (#1), clipped to the
                // rounded thumb. space.wallpaper is the real per-monitor wallpaper in all-mode; else the
                // panel's own (so virtual-space thumbs all show the correct current wallpaper, #2).
                let space = spaces[i]
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: thumbRect, xRadius: 4, yRadius: 4).addClip()
                if let wp = space.wallpaper ?? self.wallpaper,
                   let cg = wp.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    drawUpright(cg, in: thumbRect)
                } else {
                    NSColor(white: 0.1, alpha: 0.8).setFill(); thumbRect.fill()
                }
                NSGraphicsContext.restoreGraphicsState()
                
                // Draw selection highlight or border (the current space gets the accent ring)
                if space.isCurrent {
                    NSColor.keyboardFocusIndicatorColor.setStroke()
                    let path = NSBezierPath(roundedRect: thumbRect, xRadius: 4, yRadius: 4)
                    path.lineWidth = 2.0
                    path.stroke()
                } else {
                    NSColor.white.withAlphaComponent(0.2).setStroke()
                    let path = NSBezierPath(roundedRect: thumbRect, xRadius: 4, yRadius: 4)
                    path.lineWidth = 1.0
                    path.stroke()
                }

                // Draw space name centered below the thumbnail
                let name = space.name as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                    .foregroundColor: space.isCurrent ? NSColor.keyboardFocusIndicatorColor : NSColor.secondaryLabelColor
                ]
                let nameSize = name.size(withAttributes: attrs)
                name.draw(at: NSPoint(x: thumbRect.midX - nameSize.width / 2, y: thumbRect.maxY + 4), withAttributes: attrs)
                
                // Draw each window as a real mini-screenshot at its true on-screen position (#3) — a
                // faithful miniature of the desktop, clipped to the thumbnail (replaces the random
                // colored chips). Falls back to a colored box only if a screenshot is unavailable.
                if !space.windows.isEmpty {
                    NSGraphicsContext.saveGraphicsState()
                    NSBezierPath(roundedRect: thumbRect, xRadius: 4, yRadius: 4).addClip()
                    for win in space.windows {
                        let nr = win.normRect
                        let r = NSRect(x: thumbRect.minX + nr.minX * thumbRect.width,
                                       y: thumbRect.minY + nr.minY * thumbRect.height,
                                       width: max(6, nr.width * thumbRect.width),
                                       height: max(6, nr.height * thumbRect.height))
                        let rp = NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2)
                        if let img = windowImages[win.windowId] {
                            NSGraphicsContext.saveGraphicsState()
                            rp.addClip()
                            drawUpright(img, in: r)
                            NSGraphicsContext.restoreGraphicsState()
                        } else {
                            win.badgeColor.withAlphaComponent(0.85).setFill(); rp.fill()
                        }
                        NSColor.black.withAlphaComponent(0.55).setStroke(); rp.lineWidth = 0.75; rp.stroke()
                    }
                    NSGraphicsContext.restoreGraphicsState()
                }
                
                // Draw space delete button (x) (larger) — only when spaces are editable.
                if editableSpaces && spaces.count > 1 {
                    let closeRect = geom.closeButtons[i]
                    let closePath = NSBezierPath(ovalIn: closeRect)
                    NSColor.gray.withAlphaComponent(0.85).setFill()
                    closePath.fill()
                    let xStr = "×" as NSString
                    let xattrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 16, weight: .bold),
                        .foregroundColor: NSColor.white
                    ]
                    let xsz = xStr.size(withAttributes: xattrs)
                    xStr.draw(at: NSPoint(x: closeRect.midX - xsz.width / 2, y: closeRect.midY - xsz.height / 2 - 1), withAttributes: xattrs)
                }
            }
            
            // Draw plus button (larger) — only when spaces are editable (hidden for monitor targets).
            if editableSpaces {
                let plusRect = geom.plus
                let plusPath = NSBezierPath(roundedRect: plusRect, xRadius: 4, yRadius: 4)
                NSColor.white.withAlphaComponent(0.1).setFill()
                plusPath.fill()

                NSColor.white.withAlphaComponent(0.3).setStroke()
                plusPath.lineWidth = 1.0
                plusPath.stroke()

                let plusStr = "+" as NSString
                let pattrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 40, weight: .medium),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.6)
                ]
                let psz = plusStr.size(withAttributes: pattrs)
                plusStr.draw(at: NSPoint(x: plusRect.midX - psz.width / 2, y: plusRect.midY - psz.height / 2), withAttributes: pattrs)
            }
        }

        // Draw grid preview windows
        for h in hints {
            var tf = local(h.frame)
            var b = local(h.badge)
            var c = local(h.close)

            // The PREVIEW rect = the screenshot aspect-fitted inside the tile. The badge, close (×) and
            // selection ring all conform to THIS rect so they hug the screenshot, not the letterboxed
            // tile (prettier + the × stays pinned to the screenshot's top-left corner).
            var pf = tf
            if let image = windowImages[h.windowId], image.width > 0, image.height > 0 {
                let scale = min(tf.width / CGFloat(image.width), tf.height / CGFloat(image.height))
                let dw = CGFloat(image.width) * scale, dh = CGFloat(image.height) * scale
                pf = NSRect(x: tf.minX + (tf.width - dw) / 2, y: tf.minY + (tf.height - dh) / 2, width: dw, height: dh)
            }

            // Apply drag translations
            if draggedWindowId == h.windowId {
                let dx = dragCurrentPoint.x - dragStartPoint.x
                let dy = dragCurrentPoint.y - dragStartPoint.y
                tf = tf.offsetBy(dx: dx, dy: dy); pf = pf.offsetBy(dx: dx, dy: dy)
                b = b.offsetBy(dx: dx, dy: dy); c = c.offsetBy(dx: dx, dy: dy)
            }

            if pf.width > 10 && pf.height > 10 {
                let path = NSBezierPath(roundedRect: pf, xRadius: 8, yRadius: 8)
                // Draw the actual window screenshot, rounded to the preview rect.
                if let image = windowImages[h.windowId] {
                    NSGraphicsContext.saveGraphicsState()
                    path.addClip()
                    NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                        .draw(in: pf, from: .zero, operation: .sourceOver, fraction: 1.0)
                    NSGraphicsContext.restoreGraphicsState()
                } else {
                    NSColor.white.withAlphaComponent(0.08).setFill()
                    path.fill()
                }

                // "/" search: dim non-matches so the matching windows stand out, and border each match.
                if let matches = matchedWindowIds {
                    if matches.contains(h.windowId) {
                        let bord = NSBezierPath(roundedRect: pf.insetBy(dx: -1, dy: -1), xRadius: 9, yRadius: 9)
                        NSColor.controlAccentColor.setStroke(); bord.lineWidth = 2.5; bord.stroke()
                    } else {
                        NSColor.black.withAlphaComponent(0.6).setFill()
                        NSBezierPath(roundedRect: pf, xRadius: 8, yRadius: 8).fill()
                    }
                }

                // Keyboard-selection ring hugging the screenshot (#6) — drawn last so it sits on top.
                if h.windowId == selectedWindowId {
                    let ring = NSBezierPath(roundedRect: pf.insetBy(dx: -2, dy: -2), xRadius: 10, yRadius: 10)
                    NSColor.controlAccentColor.setStroke(); ring.lineWidth = 3.5; ring.stroke()
                }
            }

            // Label badge — pastel color chip + dark border + icon + key.
            let chip = NSBezierPath(roundedRect: b, xRadius: 6, yRadius: 6)
            badgeColor(for: h.zoneKey).setFill(); chip.fill()
            NSColor.black.withAlphaComponent(0.85).setStroke(); chip.lineWidth = 1.5; chip.stroke()

            let label = h.label.uppercased() as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .bold),
                .foregroundColor: NSColor.black,
            ]
            let sz = label.size(withAttributes: attrs)

            if let icon = appIcon(for: h.appName) {
                // Draw icon on the left
                let iconSize: CGFloat = 18.0
                let iconRect = NSRect(
                    x: b.minX + 6,
                    y: b.minY + (b.height - iconSize) / 2,
                    width: iconSize,
                    height: iconSize
                )
                icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)

                // Center the key letter in the remaining space
                let remainingCenterX = (b.minX + 6 + iconSize + 6 + b.maxX) / 2.0
                label.draw(
                    at: NSPoint(x: remainingCenterX - sz.width / 2, y: b.midY - sz.height / 2),
                    withAttributes: attrs
                )
            } else {
                // Center key letter fully
                label.draw(
                    at: NSPoint(x: b.midX - sz.width / 2, y: b.midY - sz.height / 2),
                    withAttributes: attrs
                )
            }

            // Close (×) button — red disc + white cross at the tile's top-right.
            let disc = NSBezierPath(ovalIn: c)
            NSColor.systemRed.withAlphaComponent(0.92).setFill(); disc.fill()
            let x = NSBezierPath(); let pad = c.width * 0.3
            x.move(to: NSPoint(x: c.minX + pad, y: c.minY + pad)); x.line(to: NSPoint(x: c.maxX - pad, y: c.maxY - pad))
            x.move(to: NSPoint(x: c.maxX - pad, y: c.minY + pad)); x.line(to: NSPoint(x: c.minX + pad, y: c.maxY - pad))
            NSColor.white.setStroke(); x.lineWidth = 1.6; x.lineCapStyle = .round; x.stroke()
        }
    }
}
