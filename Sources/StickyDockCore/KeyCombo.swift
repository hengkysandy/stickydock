import Foundation

/// A key and its modifiers, as a plain value.
///
/// Deliberately free of Carbon and AppKit so the formatting and the round trip
/// through settings can be tested. The modifier bits are Carbon's, because that
/// is what `RegisterEventHotKey` wants, but they are written out here rather
/// than imported so this file stays portable.
public struct KeyCombo: Codable, Equatable, Sendable {
    public static let control: UInt32 = 4096
    public static let option: UInt32  = 2048
    public static let shift: UInt32   = 512
    public static let command: UInt32 = 256

    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// A shortcut with no modifier would swallow ordinary typing everywhere on
    /// the machine, so it is not something the recorder should ever accept.
    public var hasModifier: Bool { modifiers != 0 }

    /// How the shortcut reads in a menu, in the usual macOS order.
    public var display: String {
        var out = ""
        if modifiers & Self.control != 0 { out += "⌃" }
        if modifiers & Self.option  != 0 { out += "⌥" }
        if modifiers & Self.shift   != 0 { out += "⇧" }
        if modifiers & Self.command != 0 { out += "⌘" }
        return out + (Self.keyName(keyCode) ?? "Key \(keyCode)")
    }

    /// Virtual key codes are a fixed table on macOS, so this is a lookup rather
    /// than anything clever. Only the keys worth binding are listed; anything
    /// else falls back to its number.
    public static func keyName(_ code: UInt32) -> String? { names[code] }

    private static let names: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C",
        9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[",
        34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}
