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
    let separatorView = NSView(frame: .zero)
    private(set) var selectedIndex = BoardManPanelTab.history.rawValue
    var selectionDidChange: ((Int) -> Void)?

    var buttons: [BoardManHeaderTabButton] {
        return [historyButton, snippetsButton]
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

        separatorView.wantsLayer = true
        separatorView.layer?.shadowOpacity = 0
        addSubview(separatorView)
        refreshVisualState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let halfWidth = floor(bounds.width / 2)
        historyButton.frame = NSIntegralRect(NSRect(
            x: 4,
            y: 4,
            width: max(0, halfWidth - 6),
            height: max(0, bounds.height - 8)
        ))
        snippetsButton.frame = NSIntegralRect(NSRect(
            x: halfWidth + 2,
            y: 4,
            width: max(0, bounds.width - halfWidth - 6),
            height: max(0, bounds.height - 8)
        ))
        separatorView.frame = NSIntegralRect(NSRect(
            x: halfWidth,
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
        let hoveredIndex: Int? = bounds.contains(point) ? (point.x < bounds.midX ? 0 : 1) : nil
        for (index, button) in buttons.enumerated() {
            button.setHoveringForTesting(index == hoveredIndex)
        }
    }

    func hoverBackgroundRect(forTab index: Int) -> NSRect? {
        guard buttons.indices.contains(index) else { return nil }
        return buttons[index].frame
    }

    func refreshVisualState() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.16).cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.82).cgColor
        separatorView.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.72).cgColor
        for (index, button) in buttons.enumerated() {
            let isSelected = selectedIndex == index
            let fillColor: NSColor
            if isSelected {
                fillColor = NSColor.labelColor.withAlphaComponent(0.14)
            } else if button.isHovering {
                fillColor = NSColor.labelColor.withAlphaComponent(0.07)
            } else {
                fillColor = .clear
            }
            button.layer?.backgroundColor = fillColor.cgColor
            button.layer?.borderColor = NSColor.clear.cgColor
            button.layer?.shadowOpacity = 0
            if #available(macOS 10.14, *) {
                button.contentTintColor = isSelected ? .labelColor : .secondaryLabelColor
            }
        }
    }

    @objc private func tabButtonPressed(_ sender: NSButton) {
        guard buttons.indices.contains(sender.tag) else { return }
        setSelectedIndex(sender.tag)
        selectionDidChange?(sender.tag)
    }
}
