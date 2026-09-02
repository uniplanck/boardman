import Cocoa

enum BoardManAppearanceMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var appearance: NSAppearance? {
        switch self {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }

    static func allowed(_ value: String?) -> BoardManAppearanceMode {
        return allCases.first(where: { $0.rawValue == value }) ?? .system
    }
}

enum BoardManUIStyle: String, CaseIterable {
    case defaultStyle = "Default"
    case simple = "Simple"
    case monochrome = "Monochrome"

    static func allowed(_ value: String?) -> BoardManUIStyle {
        return allCases.first(where: { $0.rawValue == value }) ?? .defaultStyle
    }
}

struct BoardManFontChoice: Equatable {
    let rawValue: String

    static let system = BoardManFontChoice(rawValue: "System")
    static let rounded = BoardManFontChoice(rawValue: "Rounded")
    static let serif = BoardManFontChoice(rawValue: "Serif")
    static let monospaced = BoardManFontChoice(rawValue: "Monospaced")
    static let builtIns: [BoardManFontChoice] = [.system, .rounded, .serif, .monospaced]

    static var installedFamilies: [String] {
        let builtInNames = Set(builtIns.map(\.rawValue))
        return NSFontManager.shared.availableFontFamilies
            .filter { !builtInNames.contains($0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func allowed(_ value: String?) -> BoardManFontChoice {
        guard let value, !value.isEmpty else { return .system }
        if let builtIn = builtIns.first(where: { $0.rawValue == value }) {
            return builtIn
        }
        return installedFamilies.contains(value) ? BoardManFontChoice(rawValue: value) : .system
    }

    func font(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        switch rawValue {
        case Self.system.rawValue:
            return base
        case Self.rounded.rawValue, Self.serif.rawValue, Self.monospaced.rawValue:
            let design: NSFontDescriptor.SystemDesign = rawValue == Self.rounded.rawValue
                ? .rounded
                : (rawValue == Self.serif.rawValue ? .serif : .monospaced)
            guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
            return NSFont(descriptor: descriptor, size: size) ?? base
        default:
            let descriptor = NSFontDescriptor(fontAttributes: [
                .family: rawValue,
                .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue]
            ])
            return NSFont(descriptor: descriptor, size: size)
                ?? NSFontManager.shared.convert(base, toFamily: rawValue)
        }
    }
}

enum BoardManThemePreset: String, CaseIterable {
    case defaultPreset = "Default"
    case graphite = "Graphite"
    case ocean = "Ocean"
    case amber = "Amber"
    case rose = "Rose"
    case scarlet = "Scarlet"
    case emerald = "Emerald"
    case violet = "Violet"
    case indigo = "Indigo"

    var title: String {
        return boardManText(rawValue)
    }

    var accentColor: NSColor {
        switch self {
        case .defaultPreset: return NSColor.labelColor.withAlphaComponent(0.70)
        case .graphite: return NSColor(calibratedWhite: 0.52, alpha: 1)
        case .ocean: return .systemTeal
        case .amber: return .systemOrange
        case .rose: return .systemPink
        case .scarlet: return .systemRed
        case .emerald: return .systemGreen
        case .violet: return .systemPurple
        case .indigo: return .systemIndigo
        }
    }

    var tintColor: NSColor {
        switch self {
        case .defaultPreset: return NSColor.controlBackgroundColor.withAlphaComponent(0.10)
        case .graphite: return NSColor.labelColor.withAlphaComponent(0.11)
        case .ocean: return NSColor.systemTeal.withAlphaComponent(0.16)
        case .amber: return NSColor.systemOrange.withAlphaComponent(0.15)
        case .rose: return NSColor.systemPink.withAlphaComponent(0.15)
        case .scarlet: return NSColor.systemRed.withAlphaComponent(0.15)
        case .emerald: return NSColor.systemGreen.withAlphaComponent(0.15)
        case .violet: return NSColor.systemPurple.withAlphaComponent(0.15)
        case .indigo: return NSColor.systemIndigo.withAlphaComponent(0.15)
        }
    }

    var glassMaterial: NSVisualEffectView.Material {
        switch self {
        case .graphite:
            return .hudWindow
        default:
            return .popover
        }
    }

    private func lightenedAlpha(_ alpha: CGFloat) -> CGFloat {
        switch self {
        case .defaultPreset:
            return min(alpha, 0.06)
        default:
            return alpha * 0.56
        }
    }

    func panelTintColor(useLiquidGlass: Bool, lighten: Bool = false) -> NSColor {
        if useLiquidGlass {
            switch self {
            case .defaultPreset: return NSColor.controlBackgroundColor.withAlphaComponent(lighten ? 0.06 : 0.10)
            case .graphite: return NSColor.labelColor.withAlphaComponent(lighten ? 0.08 : 0.15)
            case .ocean: return NSColor.systemTeal.withAlphaComponent(lighten ? 0.08 : 0.15)
            case .amber: return NSColor.systemOrange.withAlphaComponent(lighten ? 0.08 : 0.14)
            case .rose: return NSColor.systemPink.withAlphaComponent(lighten ? 0.08 : 0.14)
            case .scarlet: return NSColor.systemRed.withAlphaComponent(lighten ? 0.08 : 0.14)
            case .emerald: return NSColor.systemGreen.withAlphaComponent(lighten ? 0.08 : 0.14)
            case .violet: return NSColor.systemPurple.withAlphaComponent(lighten ? 0.08 : 0.14)
            case .indigo: return NSColor.systemIndigo.withAlphaComponent(lighten ? 0.08 : 0.14)
            }
        }
        return lighten ? tintColor.withAlphaComponent(lightenedAlpha(tintColor.alphaComponent)) : tintColor
    }

    func surfaceTintColor(useLiquidGlass: Bool, lighten: Bool = false) -> NSColor {
        let alpha: CGFloat = useLiquidGlass ? 0.52 : 0.18
        return tintColor.withAlphaComponent(lighten ? lightenedAlpha(alpha) : alpha)
    }

    func rowFillColor(useLiquidGlass: Bool, lighten: Bool = false) -> NSColor {
        let alpha: CGFloat = useLiquidGlass ? 0.32 : 0.42
        return tintColor.withAlphaComponent(lighten ? lightenedAlpha(alpha) : alpha)
    }

    func rowHoverColor(useLiquidGlass: Bool, lighten: Bool = false) -> NSColor {
        let alpha: CGFloat = useLiquidGlass ? 0.18 : 0.16
        return accentColor.withAlphaComponent(lighten ? lightenedAlpha(alpha) : alpha)
    }

    func rowSelectedColor(useLiquidGlass: Bool, lighten: Bool = false) -> NSColor {
        let alpha: CGFloat = useLiquidGlass ? 0.34 : 0.28
        return accentColor.withAlphaComponent(lighten ? max(0.12, lightenedAlpha(alpha)) : alpha)
    }

    func edgeColor(useLiquidGlass: Bool, lighten: Bool = false) -> NSColor {
        if self == .defaultPreset && !useLiquidGlass {
            return NSColor.separatorColor.withAlphaComponent(lighten ? 0.18 : 0.28)
        }
        let alpha: CGFloat = useLiquidGlass ? 0.28 : 0.10
        return NSColor.white.withAlphaComponent(lighten ? max(0.08, lightenedAlpha(alpha)) : alpha)
    }

    func shadowColor(useLiquidGlass: Bool, lighten: Bool = false) -> NSColor {
        switch self {
        case .graphite:
            let alpha: CGFloat = useLiquidGlass ? 0.36 : 0.16
            return NSColor.black.withAlphaComponent(lighten ? alpha * 0.55 : alpha)
        default:
            let alpha: CGFloat = useLiquidGlass ? 0.24 : 0.14
            return accentColor.withAlphaComponent(lighten ? lightenedAlpha(alpha) : alpha)
        }
    }

    static func allowed(_ value: String?) -> BoardManThemePreset {
        guard let value,
              let preset = BoardManThemePreset.allCases.first(where: { $0.rawValue == value }) else {
            return .defaultPreset
        }
        return preset
    }
}
