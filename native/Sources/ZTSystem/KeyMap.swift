// KeyMap.swift — maps config key names / modifier-alias names to Carbon keycodes + modifier
// masks for RegisterEventHotKey. US-ANSI layout (sufficient for v1; layout-aware mapping can
// come later). Modifier names come from config aliases (e.g. mash = ["ctrl","cmd"]).

import Carbon.HIToolbox

public enum KeyMap {

    /// Carbon virtual keycode for a config key string ("h", "0", ",", "return", …), or nil.
    public static func keyCode(for key: String) -> UInt32? {
        if key.count == 1, let code = singleChar[key.lowercased()] { return code }
        return named[key.lowercased()]
    }

    /// Combined Carbon modifier mask for a list of modifier names (cmd/ctrl/alt/shift).
    public static func modifierMask(for names: [String]) -> UInt32 {
        var mask: UInt32 = 0
        for name in names {
            switch name.lowercased() {
            case "cmd", "command": mask |= UInt32(cmdKey)
            case "ctrl", "control": mask |= UInt32(controlKey)
            case "alt", "option", "opt": mask |= UInt32(optionKey)
            case "shift": mask |= UInt32(shiftKey)
            default: break
            }
        }
        return mask
    }

    private static let singleChar: [String: UInt32] = [
        "a": UInt32(kVK_ANSI_A), "b": UInt32(kVK_ANSI_B), "c": UInt32(kVK_ANSI_C),
        "d": UInt32(kVK_ANSI_D), "e": UInt32(kVK_ANSI_E), "f": UInt32(kVK_ANSI_F),
        "g": UInt32(kVK_ANSI_G), "h": UInt32(kVK_ANSI_H), "i": UInt32(kVK_ANSI_I),
        "j": UInt32(kVK_ANSI_J), "k": UInt32(kVK_ANSI_K), "l": UInt32(kVK_ANSI_L),
        "m": UInt32(kVK_ANSI_M), "n": UInt32(kVK_ANSI_N), "o": UInt32(kVK_ANSI_O),
        "p": UInt32(kVK_ANSI_P), "q": UInt32(kVK_ANSI_Q), "r": UInt32(kVK_ANSI_R),
        "s": UInt32(kVK_ANSI_S), "t": UInt32(kVK_ANSI_T), "u": UInt32(kVK_ANSI_U),
        "v": UInt32(kVK_ANSI_V), "w": UInt32(kVK_ANSI_W), "x": UInt32(kVK_ANSI_X),
        "y": UInt32(kVK_ANSI_Y), "z": UInt32(kVK_ANSI_Z),
        "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2),
        "3": UInt32(kVK_ANSI_3), "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5),
        "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7), "8": UInt32(kVK_ANSI_8),
        "9": UInt32(kVK_ANSI_9),
        ",": UInt32(kVK_ANSI_Comma), ".": UInt32(kVK_ANSI_Period), "/": UInt32(kVK_ANSI_Slash),
        ";": UInt32(kVK_ANSI_Semicolon), "'": UInt32(kVK_ANSI_Quote),
        "[": UInt32(kVK_ANSI_LeftBracket), "]": UInt32(kVK_ANSI_RightBracket),
        "-": UInt32(kVK_ANSI_Minus), "=": UInt32(kVK_ANSI_Equal),
        "\\": UInt32(kVK_ANSI_Backslash), "`": UInt32(kVK_ANSI_Grave),
    ]

    private static let named: [String: UInt32] = [
        "return": UInt32(kVK_Return), "enter": UInt32(kVK_Return),
        "space": UInt32(kVK_Space), "tab": UInt32(kVK_Tab),
        "escape": UInt32(kVK_Escape), "esc": UInt32(kVK_Escape),
        "delete": UInt32(kVK_Delete),
        "left": UInt32(kVK_LeftArrow), "right": UInt32(kVK_RightArrow),
        "up": UInt32(kVK_UpArrow), "down": UInt32(kVK_DownArrow),
        "f1": UInt32(kVK_F1), "f2": UInt32(kVK_F2),
    ]
}
