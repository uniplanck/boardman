import Cocoa

final class BoardManHeaderTabButton: NSButton {
    private var hoverTrackingArea: NSTrackingArea?
    private(set) var isHovering = false
    var hoverDidChange: (() -> Void)?

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        setHovering(true)
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        setHovering(false)
        super.mouseExited(with: event)
    }

    func setHoveringForTesting(_ value: Bool) {
        setHovering(value)
    }

    private func setHovering(_ value: Bool) {
        guard isHovering != value else { return }
        isHovering = value
        hoverDidChange?()
    }
}

final class BoardManHeaderTabBar: NSView {
    let historyButton = BoardManHeaderTabButton(title: "", target: nil, action: nil)
    let snippetsButton = BoardManHeaderTabButton(title: "", target: nil, action: nil)
    let selectionButton = BoardManHeaderTabButton(title: "", target: nil, action: nil)
    let separatorView = NSView(frame: .zero)
    let secondSeparatorView = NSView(frame: .zero)
    private(set) var selectedIndex = BoardManPanelTab.history.rawValue
    var selectionDidChange: ((Int) -> Void)?

    var buttons: [BoardManHeaderTabButton] {
        return [historyButton, snippetsButton, selectionButton]
    }

    var hoveredIndex: Int {
        return buttons.firstIndex(where: { $0.isHovering }) ?? -1
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        layer?.masksToBounds = true
        layer?.shadowOpacity = 0

        for (index, button) in buttons.enumerated() {
            button.tag = index
            button.target = self
            button.action = #selector(tabButtonPressed(_:))
            button.isBordered = false
            button.showsBorderOnlyWhileMouseInside = false
            button.focusRingType = .none
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleProportionallyDown
            if #available(macOS 11.0, *) {
                button.imageHugsTitle = true
            }
            button.alignment = .center
            button.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
            button.wantsLayer = true
            button.layer?.cornerRadius = 11
            button.layer?.masksToBounds = true
            button.layer?.borderWidth = 0
            button.layer?.shadowOpacity = 0
            button.hoverDidChange = { [weak self] in self?.refreshVisualState() }
            addSubview(button)
        }

        [separatorView, secondSeparatorView].forEach { separator in
            separator.wantsLayer = true
            separator.layer?.shadowOpacity = 0
            addSubview(separator)
        }
        refreshVisualState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let innerWidth = max(0, bounds.width - 8)
        let segmentWidth = floor(innerWidth / 3)
        for (index, button) in buttons.enumerated() {
            let segmentOriginX = 4 + CGFloat(index) * segmentWidth
            let width = index == buttons.count - 1
                ? max(0, bounds.width - segmentOriginX - 4)
                : segmentWidth
            button.frame = NSIntegralRect(NSRect(
                x: segmentOriginX,
                y: 4,
                width: width,
                height: max(0, bounds.height - 8)
            ))
        }
        separatorView.frame = NSIntegralRect(NSRect(
            x: 4 + segmentWidth,
            y: 10,
            width: 1,
            height: max(0, bounds.height - 20)
        ))
        secondSeparatorView.frame = NSIntegralRect(NSRect(
            x: 4 + segmentWidth * 2,
            y: 10,
            width: 1,
            height: max(0, bounds.height - 20)
        ))
    }

    func configureTab(index: Int, title: String, toolTip: String, image: NSImage?) {
        guard buttons.indices.contains(index) else { return }
        let button = buttons[index]
        button.title = title
        button.toolTip = toolTip
        button.setAccessibilityLabel(toolTip)
        button.image = image
    }

    func setFont(_ font: NSFont) {
        buttons.forEach { $0.font = font }
    }

    func setSelectedIndex(_ index: Int) {
        let normalized = buttons.indices.contains(index) ? index : -1
        guard selectedIndex != normalized else { return }
        selectedIndex = normalized
        refreshVisualState()
    }

    func updateHoveredTab(at point: NSPoint) {
        let hoveredIndex: Int? = bounds.contains(point)
            ? min(buttons.count - 1, max(0, Int((point.x / max(bounds.width, 1)) * CGFloat(buttons.count))))
            : nil
        for (index, button) in buttons.enumerated() {
            button.setHoveringForTesting(index == hoveredIndex)
        }
    }

    func hoverBackgroundRect(forTab index: Int) -> NSRect? {
        guard buttons.indices.contains(index) else { return nil }
        return buttons[index].frame
    }

    func refreshVisualState() {
        let defaults = AppEnvironment.current.defaults
        let style = BoardManUIStyle.allowed(defaults.string(forKey: Constants.UserDefaults.boardManUIStyle))
        let preset = BoardManThemePreset.allowed(defaults.string(forKey: Constants.UserDefaults.boardManThemePreset))
        let depthStyle = style.usesDepth
        let futureGlow = style.usesFutureGlow
        let accent = preset.accentColor

        layer?.backgroundColor = (futureGlow
            ? accent.withAlphaComponent(0.10)
            : NSColor.controlBackgroundColor.withAlphaComponent(depthStyle ? 0.24 : 0.16)).cgColor
        layer?.borderColor = (futureGlow
            ? accent.withAlphaComponent(0.54)
            : NSColor.separatorColor.withAlphaComponent(depthStyle ? 0.92 : 0.82)).cgColor
        layer?.borderWidth = futureGlow ? 1.25 : 1
        layer?.masksToBounds = !depthStyle
        layer?.shadowColor = (futureGlow ? accent : NSColor.black).cgColor
        layer?.shadowOpacity = depthStyle ? (futureGlow ? 0.22 : 0.12) : 0
        layer?.shadowRadius = depthStyle ? (futureGlow ? 14 : 8) : 0
        layer?.shadowOffset = depthStyle ? NSSize(width: 0, height: -2) : .zero
        [separatorView, secondSeparatorView].forEach {
            $0.layer?.backgroundColor = (futureGlow
                ? accent.withAlphaComponent(0.34)
                : NSColor.separatorColor.withAlphaComponent(0.72)).cgColor
        }
        for (index, button) in buttons.enumerated() {
            let isSelected = selectedIndex == index
            let fillColor: NSColor
            if isSelected {
                fillColor = futureGlow
                    ? accent.withAlphaComponent(0.22)
                    : NSColor.labelColor.withAlphaComponent(depthStyle ? 0.18 : 0.14)
            } else if button.isHovering {
                fillColor = futureGlow
                    ? accent.withAlphaComponent(0.11)
                    : NSColor.labelColor.withAlphaComponent(0.07)
            } else {
                fillColor = .clear
            }
            button.layer?.backgroundColor = fillColor.cgColor
            button.layer?.borderColor = (futureGlow && isSelected
                ? accent.withAlphaComponent(0.45)
                : NSColor.clear).cgColor
            button.layer?.borderWidth = futureGlow && isSelected ? 1 : 0
            button.layer?.shadowColor = accent.cgColor
            button.layer?.shadowOpacity = futureGlow && isSelected ? 0.20 : 0
            button.layer?.shadowRadius = futureGlow && isSelected ? 8 : 0
            if #available(macOS 10.14, *) {
                button.contentTintColor = isSelected
                    ? (futureGlow ? accent : .labelColor)
                    : .secondaryLabelColor
            }
        }
    }

    @objc private func tabButtonPressed(_ sender: NSButton) {
        guard buttons.indices.contains(sender.tag) else { return }
        setSelectedIndex(sender.tag)
        selectionDidChange?(sender.tag)
    }
}

final class BoardManPinnedSectionToggleButton: NSButton {
    static let preferredHeight: CGFloat = 24
    static let leadingAlignmentInset: CGFloat = 6
    static let trailingAlignmentInset: CGFloat = 6
    static let sectionHeaderToFirstRowSpacing: CGFloat = 6
    static let contentLeadingInset: CGFloat = 7
    static let dividerTrailingInset: CGFloat = 8
    static let imageTitleSpacer = "  "

    private let dividerLayer = CALayer()
    private var hoverTrackingArea: NSTrackingArea?
    private var accentColor: NSColor = .controlAccentColor
    private(set) var isSectionCollapsed = false
    private(set) var pinnedItemCount = 0
    private(set) var isHovering = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setButtonType(.momentaryPushIn)
        isBordered = false
        focusRingType = .none
        alignment = .left
        imagePosition = .imageLeading
        imageScaling = .scaleProportionallyDown
        font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 0
        layer?.masksToBounds = true
        dividerLayer.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.30).cgColor
        layer?.addSublayer(dividerLayer)
        identifier = NSUserInterfaceItemIdentifier("BoardManPinnedSectionToggle")
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let scale = max(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2, 1)
        let lineHeight = 1 / scale
        let lineX: CGFloat = min(bounds.width, 74)
        dividerLayer.frame = NSRect(
            x: lineX,
            y: floor(bounds.midY * scale) / scale,
            width: max(0, bounds.maxX - lineX - Self.dividerTrailingInset),
            height: lineHeight
        )
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        refreshAppearance()
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        refreshAppearance()
        super.mouseExited(with: event)
    }

    func configure(itemCount: Int, collapsed: Bool, accentColor: NSColor) {
        pinnedItemCount = max(0, itemCount)
        isSectionCollapsed = collapsed
        self.accentColor = accentColor
        title = "\(Self.imageTitleSpacer)PIN \(pinnedItemCount)"
        state = collapsed ? .on : .off
        toolTip = boardManText(collapsed ? "Show pinned items" : "Hide pinned items")
        setAccessibilityLabel(toolTip ?? boardManText("Pin"))
        setAccessibilityValue(collapsed ? boardManText("Collapsed") : boardManText("Expanded"))
        if #available(macOS 11.0, *) {
            image = Self.paddedDisclosureImage(
                systemName: collapsed ? "chevron.right" : "chevron.down",
                accessibilityDescription: toolTip
            )
        } else {
            image = nil
            title = "   \(collapsed ? "▸" : "⌄")  PIN  \(pinnedItemCount)"
        }
        refreshAppearance()
    }

    @available(macOS 11.0, *)
    private static func paddedDisclosureImage(
        systemName: String,
        accessibilityDescription: String?
    ) -> NSImage? {
        guard let source = NSImage(
            systemSymbolName: systemName,
            accessibilityDescription: accessibilityDescription
        ) else { return nil }
        let sourceSize = source.size
        let image = NSImage(
            size: NSSize(width: sourceSize.width + contentLeadingInset, height: sourceSize.height),
            flipped: false
        ) { _ in
            source.draw(
                in: NSRect(
                    x: contentLeadingInset,
                    y: 0,
                    width: sourceSize.width,
                    height: sourceSize.height
                )
            )
            return true
        }
        image.isTemplate = true
        return image
    }

    private func refreshAppearance() {
        layer?.backgroundColor = (isSectionCollapsed
            ? accentColor.withAlphaComponent(isHovering ? 0.10 : 0.055)
            : NSColor.labelColor.withAlphaComponent(isHovering ? 0.045 : 0)).cgColor
        layer?.borderWidth = 0
        dividerLayer.backgroundColor = (isSectionCollapsed
            ? accentColor.withAlphaComponent(0.32)
            : NSColor.separatorColor.withAlphaComponent(isHovering ? 0.44 : 0.30)).cgColor
        if #available(macOS 10.14, *) {
            contentTintColor = isSectionCollapsed ? accentColor : .secondaryLabelColor
        }
        needsLayout = true
        needsDisplay = true
    }
}
