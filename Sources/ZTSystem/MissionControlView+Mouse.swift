// MissionControlView+Mouse.swift — mouse interaction for the Exposé overlay view (click a window to
// jump, click × to close, drag a window onto the Spaces strip to move it). Split out for file size;
// the touched members were made internal so this extension can reach them. Same module.

import AppKit
import ZTCore

extension MissionControlView {
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)   // local flipped (top-left)
        
        // 1. Check if spaces bar hit
        if !spaces.isEmpty {
            let geom = spacesBarGeometry(bounds: bounds)
            if geom.bar.contains(p) {
                // Check space close buttons (x) if count > 1 (only when spaces are editable)
                if editableSpaces && spaces.count > 1 {
                    for i in 0..<spaces.count {
                        if geom.closeButtons[i].contains(p) {
                            onDeleteSpace?(i)
                            return
                        }
                    }
                }

                // Check space thumbnails — single-click switches, double-click renames.
                for i in 0..<spaces.count {
                    if geom.thumbs[i].contains(p) {
                        if event.clickCount >= 2 { onRenameSpace?(i) } else { onSelectSpace?(i) }
                        return
                    }
                }

                // Check plus button (only when spaces are editable)
                if editableSpaces && geom.plus.contains(p) {
                    onAddSpace?()
                    return
                }
                
                // clicked spaces bar empty space, do nothing
                return
            }
        }
        
        // 2. Check window close button (×)
        let cx = Double(p.x) + origin.x
        let cy = Double(p.y) + origin.y
        if let id = MissionControl.closeHit(at: cx, cy, in: hints) {
            onClose?(id)
            return
        }
        
        // 3. Check window grid preview click to start dragging
        for h in hints {
            let tf = local(h.frame)
            if tf.contains(p) {
                draggedWindowId = h.windowId
                dragStartPoint = p
                dragCurrentPoint = p
                needsDisplay = true
                return
            }
        }
        
        // Clicked empty grid space, dismiss
        onDismiss?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard draggedWindowId != nil else { return }
        let p = convert(event.locationInWindow, from: nil)
        dragCurrentPoint = p
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let wid = draggedWindowId else { return }
        let p = convert(event.locationInWindow, from: nil)
        
        let dx = p.x - dragStartPoint.x
        let dy = p.y - dragStartPoint.y
        let distance = sqrt(dx*dx + dy*dy)
        
        if distance > 5.0 {
            // Drop over the strip → move to the closest thumbnail (a virtual space in "active" mode,
            // or a monitor target in "all" mode — the controller's callback interprets the index).
            if !spaces.isEmpty {
                let geom = spacesBarGeometry(bounds: bounds)
                if geom.bar.contains(p) {
                    var closestIdx = 0
                    var minDist = CGFloat.infinity
                    for i in 0..<spaces.count {
                        let center = NSPoint(x: geom.thumbs[i].midX, y: geom.thumbs[i].midY)
                        let dist = sqrt(pow(center.x - p.x, 2) + pow(center.y - p.y, 2))
                        if dist < minDist { minDist = dist; closestIdx = i }
                    }
                    onMoveWindowToSpace?(wid, closestIdx)
                }
            }
        } else {
            // Regular click/tap on the preview window to jump
            onJump?(wid)
        }
        
        draggedWindowId = nil
        needsDisplay = true
    }
}