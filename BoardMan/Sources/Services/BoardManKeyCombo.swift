//
//  BoardManKeyCombo.swift
//  Board-Man
//
//  Board-Man owned shortcut value type. It stores explicit virtual key codes
//  and modifier flags so the app does not need an external shortcut model.
//

import AppKit
import Carbon

enum Key {
    case letterV

    fileprivate var qwertyKeyCode: Int {
        switch self {
        case .letterV: return Int(kVK_ANSI_V)
        }
    }
}

final class KeyCombo: NSObject, NSCopying, NSCoding {
    let QWERTYKeyCode: Int
    let modifiers: Int
    let doubledModifiers: Bool

    var currentKeyCode: CGKeyCode { CGKeyCode(max(0, QWERTYKeyCode)) }

    var keyEquivalentModifierMask: NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if modifiers & Int(cmdKey) != 0 { result.insert(.command) }
        if modifiers & Int(optionKey) != 0 { result.insert(.option) }
        if modifiers & Int(controlKey) != 0 { result.insert(.control) }
        if modifiers & Int(shiftKey) != 0 { result.insert(.shift) }
        return result
    }

    var keyEquivalentModifierMaskString: String {
        let flags = keyEquivalentModifierMask
        var value = ""
        if flags.contains(.control) { value += "⌃" }
        if flags.contains(.option) { value += "⌥" }
        if flags.contains(.shift) { value += "⇧" }
        if flags.contains(.command) { value += "⌘" }
        return value
    }

    var keyEquivalent: String {
        guard !doubledModifiers else { return "" }
        return Self.displayStrings[QWERTYKeyCode] ?? "Key \(QWERTYKeyCode)"
    }

    var characters: String { keyEquivalent }

    init?(QWERTYKeyCode: Int, carbonModifiers: Int) {
        guard (0...127).contains(QWERTYKeyCode) else { return nil }
        self.QWERTYKeyCode = QWERTYKeyCode
        self.modifiers = carbonModifiers
        self.doubledModifiers = false
        super.init()
    }

    init?(QWERTYKeyCode: Int, cocoaModifiers: NSEvent.ModifierFlags) {
        guard (0...127).contains(QWERTYKeyCode) else { return nil }
        self.QWERTYKeyCode = QWERTYKeyCode
        self.modifiers = Self.carbonModifiers(from: cocoaModifiers)
        self.doubledModifiers = false
        super.init()
    }

    init(key: Key, cocoaModifiers: NSEvent.ModifierFlags) {
        self.QWERTYKeyCode = key.qwertyKeyCode
        self.modifiers = Self.carbonModifiers(from: cocoaModifiers)
        self.doubledModifiers = false
        super.init()
    }

    init?(doubledCocoaModifiers modifiers: NSEvent.ModifierFlags) {
        let carbon = Self.carbonModifiers(from: modifiers)
        guard [Int(cmdKey), Int(optionKey), Int(controlKey), Int(shiftKey)].contains(carbon) else { return nil }
        self.QWERTYKeyCode = 0
        self.modifiers = carbon
        self.doubledModifiers = true
        super.init()
    }

    required init?(coder decoder: NSCoder) {
        doubledModifiers = decoder.decodeBool(forKey: "doubledModifiers")
        modifiers = decoder.decodeInteger(forKey: "modifiers")
        if doubledModifiers {
            QWERTYKeyCode = 0
            super.init()
            return
        }
        if decoder.containsValue(forKey: "QWERTYKeyCode") {
            QWERTYKeyCode = decoder.decodeInteger(forKey: "QWERTYKeyCode")
        } else if decoder.containsValue(forKey: "keyCode") {
            QWERTYKeyCode = decoder.decodeInteger(forKey: "keyCode")
        } else if let keyName = decoder.decodeObject(forKey: "key") as? String,
                  let keyCode = Self.legacyKeyCodes[keyName] {
            QWERTYKeyCode = keyCode
        } else {
            return nil
        }
        guard (0...127).contains(QWERTYKeyCode) else { return nil }
        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(QWERTYKeyCode, forKey: "QWERTYKeyCode")
        coder.encode(modifiers, forKey: "modifiers")
        coder.encode(doubledModifiers, forKey: "doubledModifiers")
    }

    func copy(with zone: NSZone? = nil) -> Any {
        if doubledModifiers {
            return KeyCombo(doubledCocoaModifiers: keyEquivalentModifierMask) as Any
        }
        return KeyCombo(QWERTYKeyCode: QWERTYKeyCode, carbonModifiers: modifiers) as Any
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? KeyCombo else { return false }
        return QWERTYKeyCode == other.QWERTYKeyCode
            && modifiers == other.modifiers
            && doubledModifiers == other.doubledModifiers
    }

    override var hash: Int {
        QWERTYKeyCode ^ modifiers ^ (doubledModifiers ? 1 : 0)
    }

    func archive() -> Data {
        NSKeyedArchiver.archivedData(withRootObject: self)
    }

    static func registerLegacyArchiveMappings() {
        NSKeyedUnarchiver.setClass(KeyCombo.self, forClassName: "Magnet.KeyCombo")
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var result = 0
        if flags.contains(.command) { result |= Int(cmdKey) }
        if flags.contains(.option) { result |= Int(optionKey) }
        if flags.contains(.control) { result |= Int(controlKey) }
        if flags.contains(.shift) { result |= Int(shiftKey) }
        return result
    }

    private static let legacyKeyCodes: [String: Int] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "one": 18, "two": 19, "three": 20, "four": 21,
        "six": 22, "five": 23, "equal": 24, "nine": 25, "seven": 26, "minus": 27,
        "eight": 28, "zero": 29, "rightBracket": 30, "o": 31, "u": 32,
        "leftBracket": 33, "i": 34, "p": 35, "return": 36, "l": 37, "j": 38,
        "quote": 39, "k": 40, "semicolon": 41, "backslash": 42, "comma": 43,
        "slash": 44, "n": 45, "m": 46, "period": 47, "tab": 48, "space": 49,
        "grave": 50, "delete": 51, "escape": 53, "f1": 122, "f2": 120,
        "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111, "leftArrow": 123,
        "rightArrow": 124, "downArrow": 125, "upArrow": 126
    ]

    private static let displayStrings: [Int: String] = [
        0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",
        12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",
        22:"6",23:"5",24:"=",25:"9",26:"7",27:"-",28:"8",29:"0",30:"]",31:"O",
        32:"U",33:"[",34:"I",35:"P",36:"↩",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",
        43:",",44:"/",45:"N",46:"M",47:".",48:"⇥",49:"Space",50:"`",51:"⌫",53:"Esc",
        96:"F5",97:"F6",98:"F7",99:"F3",100:"F8",101:"F9",103:"F11",109:"F10",
        111:"F12",118:"F4",120:"F2",122:"F1",123:"←",124:"→",125:"↓",126:"↑"
    ]
}
