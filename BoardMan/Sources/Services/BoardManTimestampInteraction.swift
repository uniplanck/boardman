//
//  BoardManTimestampInteraction.swift
//  Board-Man
//
//  Timestamp interaction mode and persisted shortcut configuration.
//

import Foundation

enum BoardManTimestampInteraction: String, CaseIterable {
    case click
    case longPress
    case clickMask
    case longPressMask
    case none

    static func allowed(_ value: String?) -> BoardManTimestampInteraction {
        return allCases.first(where: { $0.rawValue == value }) ?? .click
    }

    var title: String {
        switch self {
        case .click: return boardManText("Click: Run Shortcut Below")
        case .longPress: return boardManText("Long Press: Run Shortcut Below")
        case .clickMask: return boardManText("Click: Hide / Show Content")
        case .longPressMask: return boardManText("Long Press: Hide / Show Content")
        case .none: return boardManText("Do Nothing")
        }
    }

    var runsShortcutOnClick: Bool { self == .click }
    var runsShortcutOnLongPress: Bool { self == .longPress }
    var togglesMaskOnClick: Bool { self == .clickMask }
    var togglesMaskOnLongPress: Bool { self == .longPressMask }
}

enum BoardManTimestampShortcutStore {
    static var defaultKeyCombo: KeyCombo {
        return KeyCombo(key: .letterV, cocoaModifiers: .command)
    }

    static func keyCombo(defaults: UserDefaults = AppEnvironment.current.defaults) -> KeyCombo {
        return defaults.archiveDataForKey(
            KeyCombo.self,
            key: Constants.UserDefaults.boardManTimestampShortcut
        ) ?? defaultKeyCombo
    }

    static func save(_ keyCombo: KeyCombo, defaults: UserDefaults = AppEnvironment.current.defaults) {
        defaults.setArchiveData(keyCombo, forKey: Constants.UserDefaults.boardManTimestampShortcut)
        defaults.synchronize()
    }
}
