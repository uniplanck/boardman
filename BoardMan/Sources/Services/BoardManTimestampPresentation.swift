//
//  BoardManTimestampPresentation.swift
//  Board-Man
//
//  Timestamp display and relative-time formatting.
//

import Foundation

enum BoardManRelativeNumberStyle: String, CaseIterable {
    case single
    case twoDigits

    static func allowed(_ value: String?) -> BoardManRelativeNumberStyle {
        return allCases.first(where: { $0.rawValue == value }) ?? .single
    }

    var title: String { self == .twoDigits ? "00" : "0" }

    func text(_ value: Int) -> String {
        return self == .twoDigits && value < 100 ? String(format: "%02d", value) : "\(value)"
    }
}

enum BoardManRelativeUnitStyle: String, CaseIterable {
    case symbol
    case full
    case localized

    static func allowed(_ value: String?) -> BoardManRelativeUnitStyle {
        return allCases.first(where: { $0.rawValue == value }) ?? .symbol
    }

    func title(language: BoardManLanguage) -> String {
        switch self {
        case .symbol: return "m / h / d"
        case .full: return "min / hour / day"
        case .localized:
            switch language.resolved {
            case .japanese: return "分 / 時間 / 日"
            case .simplifiedChinese: return "分钟 / 小时 / 天"
            case .korean: return "분 / 시간 / 일"
            case .system, .english: return "min / hour / day"
            }
        }
    }
}

enum BoardManRelativeSuffixStyle: String, CaseIterable {
    case none
    case ago
    case localized

    static func allowed(_ value: String?) -> BoardManRelativeSuffixStyle {
        return allCases.first(where: { $0.rawValue == value }) ?? .none
    }

    func title(language: BoardManLanguage) -> String {
        switch self {
        case .none: return boardManText("None")
        case .ago: return "ago"
        case .localized:
            let token: String
            switch language.resolved {
            case .japanese, .simplifiedChinese: token = "前"
            case .korean: token = "전"
            case .system, .english: token = "ago"
            }
            return "\(boardManText("Localized")): \(token)"
        }
    }
}

enum BoardManRelativeNowStyle: String, CaseIterable {
    case now
    case localized

    static func allowed(_ value: String?) -> BoardManRelativeNowStyle {
        return allCases.first(where: { $0.rawValue == value }) ?? .localized
    }

    func title(language: BoardManLanguage) -> String {
        switch self {
        case .now: return "now"
        case .localized:
            return "\(boardManText("Localized")): \(text(language: language))"
        }
    }

    func text(language: BoardManLanguage) -> String {
        switch self {
        case .now:
            return "now"
        case .localized:
            switch language.resolved {
            case .japanese: return "今"
            case .simplifiedChinese: return "现在"
            case .korean: return "지금"
            case .system, .english: return "now"
            }
        }
    }
}

struct BoardManRelativeTimestampStyle: Equatable {
    let number: BoardManRelativeNumberStyle
    let unit: BoardManRelativeUnitStyle
    let suffix: BoardManRelativeSuffixStyle
    let now: BoardManRelativeNowStyle

    static func current(defaults: UserDefaults = AppEnvironment.current.defaults) -> BoardManRelativeTimestampStyle {
        return BoardManRelativeTimestampStyle(
            number: .allowed(defaults.string(forKey: Constants.UserDefaults.boardManRelativeNumberStyle)),
            unit: .allowed(defaults.string(forKey: Constants.UserDefaults.boardManRelativeUnitStyle)),
            suffix: .allowed(defaults.string(forKey: Constants.UserDefaults.boardManRelativeSuffixStyle)),
            now: .allowed(defaults.string(forKey: Constants.UserDefaults.boardManRelativeNowStyle))
        )
    }

    func text(seconds: Int, language: BoardManLanguage) -> String {
        let safeSeconds = max(0, seconds)
        guard safeSeconds >= 60 else { return now.text(language: language) }
        let value: Int
        let unitToken: String
        if safeSeconds < 3_600 {
            value = safeSeconds / 60
            unitToken = unitText(
                symbol: "m", full: "min", localizedJapanese: "分",
                localizedChinese: "分钟", localizedKorean: "분", language: language
            )
        } else if safeSeconds < 86_400 {
            value = safeSeconds / 3_600
            unitToken = unitText(
                symbol: "h", full: "hour", localizedJapanese: "時間",
                localizedChinese: "小时", localizedKorean: "시간", language: language
            )
        } else {
            value = safeSeconds / 86_400
            unitToken = unitText(
                symbol: "d", full: "day", localizedJapanese: "日",
                localizedChinese: "天", localizedKorean: "일", language: language
            )
        }
        let numberText = number.text(value)
        let unitSpacer = unit == .symbol
            || (unit == .localized && [.japanese, .simplifiedChinese].contains(language.resolved)) ? "" : " "
        let suffixText: String
        switch suffix {
        case .none:
            suffixText = ""
        case .ago:
            suffixText = " ago"
        case .localized:
            switch language.resolved {
            case .japanese, .simplifiedChinese: suffixText = "前"
            case .korean: suffixText = " 전"
            case .system, .english: suffixText = " ago"
            }
        }
        return "\(numberText)\(unitSpacer)\(unitToken)\(suffixText)"
    }

    private func unitText(
        symbol: String,
        full: String,
        localizedJapanese: String,
        localizedChinese: String,
        localizedKorean: String,
        language: BoardManLanguage
    ) -> String {
        switch unit {
        case .symbol: return symbol
        case .full: return full
        case .localized:
            switch language.resolved {
            case .japanese: return localizedJapanese
            case .simplifiedChinese: return localizedChinese
            case .korean: return localizedKorean
            case .system, .english: return full
            }
        }
    }
}

enum BoardManTimestampPosition: String, CaseIterable {
    case hidden = "Hidden"
    case below = "Below"
    case left = "Left"
    case right = "Right"

    static func allowed(_ value: String?) -> BoardManTimestampPosition {
        return allCases.first(where: { $0.rawValue.lowercased() == value?.lowercased() }) ?? .below
    }
}

enum BoardManTimestampPresentation {
    private static let formatterLock = NSLock()
    private static var formatters: [String: DateFormatter] = [:]

    static func clampedShortcutDelay(_ value: TimeInterval) -> TimeInterval {
        return min(60, max(0, value))
    }

    static func allowedFormat(_ value: String?) -> String {
        let allowed = [
            "relative", "HH:mm", "HH:mm:ss", "h:mm a", "h:mm:ss a",
            "MMM d HH:mm", "yyyy/MM/dd HH:mm", "none"
        ]
        guard let value, allowed.contains(value) else { return "none" }
        return value
    }

    static func text(
        for updateTime: Int,
        format: String,
        relativeStyle: BoardManRelativeTimestampStyle = .current(),
        now: Date = Date(),
        locale: Locale = .current
    ) -> String {
        guard format != "none" else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(updateTime))
        if format == "relative" {
            let seconds = max(0, Int(now.timeIntervalSince(date)))
            let language = BoardManLanguage.allowed(
                AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManLanguage)
            ).resolved
            return relativeStyle.text(seconds: seconds, language: language)
        }

        let cacheKey = "\(locale.identifier)|\(format)"
        formatterLock.lock()
        defer { formatterLock.unlock() }
        let formatter: DateFormatter
        if let cached = formatters[cacheKey] {
            formatter = cached
        } else {
            let created = DateFormatter()
            created.locale = locale
            created.dateFormat = format
            formatters[cacheKey] = created
            formatter = created
        }
        return formatter.string(from: date)
    }

    static func menuTitle(for value: String?) -> String {
        switch allowedFormat(value) {
        case "relative": return "Relative"
        case "HH:mm": return "24-hour"
        case "HH:mm:ss": return "24-hour + seconds"
        case "h:mm a": return "12-hour"
        case "h:mm:ss a": return "12-hour + seconds"
        case "MMM d HH:mm", "yyyy/MM/dd HH:mm": return "Date + time"
        default: return "Hidden"
        }
    }

    static func format(forMenuTitle title: String?) -> String {
        switch title {
        case "Relative": return "relative"
        case "24-hour": return "HH:mm"
        case "24-hour + seconds": return "HH:mm:ss"
        case "12-hour": return "h:mm a"
        case "12-hour + seconds": return "h:mm:ss a"
        case "Date + time": return "MMM d HH:mm"
        default: return "none"
        }
    }
}
