//
//  BoardManSelectionCapturePreview.swift
//  Board-Man
//
//  Non-activating two-second HUD shown after Selection Memory captures text.
//

import AppKit

enum BoardManSelectionCapturePreviewPosition: String, CaseIterable {
    case center
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    static func allowed(_ rawValue: String?) -> Self {
        Self(rawValue: rawValue ?? "") ?? .center
    }

    var title: String {
        switch self {
        case .center: return boardManText("Center")
        case .topLeft: return boardManText("Top Left")
        case .topRight: return boardManText("Top Right")
        case .bottomLeft: return boardManText("Bottom Left")
        case .bottomRight: return boardManText("Bottom Right")
        }
    }
}

enum BoardManSelectionCapturePreviewStyle: String, CaseIterable {
    case glass
    case pill
    case card

    static func allowed(_ rawValue: String?) -> Self {
        Self(rawValue: rawValue ?? "") ?? .glass
    }

    var title: String {
        switch self {
        case .glass: return boardManText("Glass")
        case .pill: return boardManText("Pill")
        case .card: return boardManText("Card")
        }
    }
}

@MainActor
final class BoardManSelectionCapturePreviewController {
    static let shared = BoardManSelectionCapturePreviewController()
    static let displayDuration: TimeInterval = 2.0

    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    func show(sourceApplicationName: String = "") {
        let defaults = AppEnvironment.current.defaults
        guard defaults.bool(forKey: Constants.UserDefaults.boardManSelectionCapturePreviewEnabled) else { return }

        hideWorkItem?.cancel()
        let style = BoardManSelectionCapturePreviewStyle.allowed(
            defaults.string(forKey: Constants.UserDefaults.boardManSelectionCapturePreviewStyle)
        )
        let position = BoardManSelectionCapturePreviewPosition.allowed(
            defaults.string(forKey: Constants.UserDefaults.boardManSelectionCapturePreviewPosition)
        )
        let panel = makePanel(style: style, sourceApplicationName: sourceApplicationName)
        positionPanel(panel, position: position)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }

        let workItem = DispatchWorkItem { [weak self, weak panel] in
            guard let self, let panel else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
            self.hideWorkItem = nil
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.displayDuration, execute: workItem)
    }

    private func makePanel(
        style: BoardManSelectionCapturePreviewStyle,
        sourceApplicationName: String
    ) -> NSPanel {
        panel?.orderOut(nil)
        let size: NSSize
        switch style {
        case .glass: size = NSSize(width: 220, height: 64)
        case .pill: size = NSSize(width: 180, height: 46)
        case .card: size = NSSize(width: 250, height: 78)
        }
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.blendingMode = .behindWindow
        effect.material = style == .pill ? .hudWindow : .popover
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = style == .pill ? size.height / 2 : 16
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        panel.contentView = effect

        let symbolSize: CGFloat = style == .pill ? 18 : 22
        let icon = NSImageView(frame: NSRect(
            x: style == .pill ? 18 : 20,
            y: floor((size.height - symbolSize) / 2),
            width: symbolSize,
            height: symbolSize
        ))
        icon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        icon.contentTintColor = .systemGreen
        effect.addSubview(icon)

        let title = NSTextField(labelWithString: boardManText("Copied"))
        title.font = NSFont.systemFont(ofSize: style == .pill ? 13 : 14, weight: .semibold)
        title.textColor = .labelColor
        title.frame = NSRect(
            x: icon.frame.maxX + 10,
            y: style == .card ? 39 : floor((size.height - 20) / 2),
            width: size.width - icon.frame.maxX - 24,
            height: 20
        )
        effect.addSubview(title)

        if style == .card {
            let detailText = sourceApplicationName.isEmpty
                ? boardManText("Selection Clipboard")
                : sourceApplicationName
            let detail = NSTextField(labelWithString: detailText)
            detail.font = NSFont.systemFont(ofSize: 10.5)
            detail.textColor = .secondaryLabelColor
            detail.lineBreakMode = .byTruncatingTail
            detail.frame = NSRect(x: title.frame.minX, y: 19, width: title.frame.width, height: 16)
            effect.addSubview(detail)
        }

        self.panel = panel
        return panel
    }

    private func positionPanel(_ panel: NSPanel, position: BoardManSelectionCapturePreviewPosition) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            panel.center()
            return
        }
        let inset: CGFloat = 24
        let origin: NSPoint
        switch position {
        case .center:
            origin = NSPoint(x: visible.midX - panel.frame.width / 2, y: visible.midY - panel.frame.height / 2)
        case .topLeft:
            origin = NSPoint(x: visible.minX + inset, y: visible.maxY - panel.frame.height - inset)
        case .topRight:
            origin = NSPoint(x: visible.maxX - panel.frame.width - inset, y: visible.maxY - panel.frame.height - inset)
        case .bottomLeft:
            origin = NSPoint(x: visible.minX + inset, y: visible.minY + inset)
        case .bottomRight:
            origin = NSPoint(x: visible.maxX - panel.frame.width - inset, y: visible.minY + inset)
        }
        panel.setFrameOrigin(origin)
    }
}
