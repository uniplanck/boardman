import Foundation

enum BoardManHistoryUsageFilter: String, CaseIterable {
    case all = "All"
    case unused = "Unused"
    case used = "Used"

    static func allowed(_ value: String?) -> BoardManHistoryUsageFilter {
        return allCases.first(where: { $0.rawValue == value }) ?? .all
    }

    var symbolName: String {
        switch self {
        case .all: return "square.stack.3d.up"
        case .unused: return "circle"
        case .used: return "checkmark.circle.fill"
        }
    }

    var toolTip: String {
        switch self {
        case .all: return "All — show every clipboard history item (default)."
        case .unused: return "Unused — show unpasted items. While selected, Command+V pastes the next unused item in copy order."
        case .used: return "Used — show items pasted at least once."
        }
    }

    func includes(_ item: BoardManHistoryItem) -> Bool {
        switch self {
        case .all: return true
        case .unused: return item.pasteCount == 0
        case .used: return item.pasteCount > 0
        }
    }
}

enum BoardManPinLabelStyle: String, CaseIterable {
    case off = "OFF"
    case compact = "P"
    case full = "PIN"

    static func allowed(_ value: String?) -> BoardManPinLabelStyle {
        return allCases.first(where: { $0.rawValue.caseInsensitiveCompare(value ?? "") == .orderedSame }) ?? .full
    }

    var badgeTitle: String { self == .off ? "" : rawValue }
}

enum BoardManInlineImagePosition: String, CaseIterable {
    case left = "Left"
    case right = "Right"

    static func allowed(_ value: String?) -> BoardManInlineImagePosition {
        return allCases.first(where: { $0.rawValue.caseInsensitiveCompare(value ?? "") == .orderedSame }) ?? .right
    }
}
