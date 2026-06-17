// CarbonHotkeyBinder.swift — global hotkeys via Carbon RegisterEventHotKey + a single
// InstallEventHandler dispatching by hotkey id. Stable, needs no accessibility permission.
// Bind on the main thread; the actions fire on the main run loop.

import Foundation
import Carbon.HIToolbox

public final class CarbonHotkeyBinder {

    private var actions: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var handlerRef: EventHandlerRef?
    private let signature: OSType = 0x5A_54_4C_52  // 'ZTLR'

    public init() { installHandler() }

    /// Register a global hotkey. Returns true if registration succeeded (false if the combo
    /// is already taken by another app, e.g. a running Hammerspoon).
    @discardableResult
    public func bind(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> Bool {
        let id = nextID
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        actions[id] = action
        hotKeyRefs[id] = ref
        return true
    }

    public func unbindAll() {
        for (_, ref) in hotKeyRefs { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
        actions.removeAll()
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID), nil,
                                        MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            guard err == noErr else { return err }
            let binder = Unmanaged<CarbonHotkeyBinder>.fromOpaque(userData).takeUnretainedValue()
            binder.actions[hkID.id]?()
            return noErr
        }, 1, &spec, context, &handlerRef)
    }
}
