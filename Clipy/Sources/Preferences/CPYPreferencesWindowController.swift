//
//  CPYPreferencesWindowController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/02/25.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa

final class CPYPreferencesWindowController: NSWindowController {

    // MARK: - Properties
    static let sharedController = CPYPreferencesWindowController(windowNibName: "CPYPreferencesWindowController")
    @IBOutlet private weak var toolBar: NSView!
    // ImageViews
    @IBOutlet private weak var generalImageView: NSImageView!
    @IBOutlet private weak var menuImageView: NSImageView!
    @IBOutlet private weak var typeImageView: NSImageView!
    @IBOutlet private weak var excludeImageView: NSImageView!
    @IBOutlet private weak var shortcutsImageView: NSImageView!
    @IBOutlet private weak var updatesImageView: NSImageView!
    @IBOutlet private weak var betaImageView: NSImageView!
    // Labels
    @IBOutlet private weak var generalTextField: NSTextField!
    @IBOutlet private weak var menuTextField: NSTextField!
    @IBOutlet private weak var typeTextField: NSTextField!
    @IBOutlet private weak var excludeTextField: NSTextField!
    @IBOutlet private weak var shortcutsTextField: NSTextField!
    @IBOutlet private weak var updatesTextField: NSTextField!
    @IBOutlet private weak var betaTextField: NSTextField!
    // Buttons
    @IBOutlet private weak var generalButton: NSButton!
    @IBOutlet private weak var menuButton: NSButton!
    @IBOutlet private weak var typeButton: NSButton!
    @IBOutlet private weak var excludeButton: NSButton!
    @IBOutlet private weak var shortcutsButton: NSButton!
    @IBOutlet private weak var updatesButton: NSButton!
    @IBOutlet private weak var betaButton: NSButton!
    private var toolbarLabels: [NSTextField] {
        return [generalTextField, menuTextField, typeTextField, excludeTextField, shortcutsTextField, updatesTextField, betaTextField]
    }
    private var toolbarImages: [NSImageView] {
        return [generalImageView, menuImageView, typeImageView, excludeImageView, shortcutsImageView, updatesImageView, betaImageView]
    }
    private var toolbarButtons: [NSButton] {
        return [generalButton, menuButton, typeButton, excludeButton, shortcutsButton, updatesButton, betaButton]
    }
    private var settingsGlassBackgroundView: NSVisualEffectView?
    private var toolbarGlassView: NSVisualEffectView?
    private let boardManCategoryTitles = ["General", "History", "Paste", "Privacy", "Shortcuts", "Updates", "Advanced"]
    private let paneTextRewrites = [
        "Input \"⌘ + V\" after menu item selection": "Paste automatically after choosing an item",
        "Send crash report and error log (reflected at the next launch)": "Share crash reports and error logs after relaunch",
        "Max clipboard history size:": "History capacity:",
        "Sort history order by:": "History sort order:",
        "Status Bar icon style:": "Menu bar icon style:",
        "Number of items place inline:": "Items shown before folders:",
        "Number of items place inside a folder:": "Items grouped inside folders:",
        "Number of characters in the menu:": "Row title length:",
        "Place already copied history at the top": "Move repeated history items to the top",
        "Move instead of copying (removes the older one from the list)": "Move the existing item instead of duplicating it",
        "Mark menu items with numbers": "Show quick number keys in rows",
        "Menu items' title starts with 0": "Start quick number keys at 0",
        "Display icons in menu items": "Show type icons in rows",
        "Add key equivalents to numeric keys": "Use number keys as shortcuts",
        "Add a menu item to clear clipboard history": "Show Clear History action",
        "Show alert panel before clear history": "Confirm before clearing history",
        "Show tool tip on a menu item": "Show full text preview on hover",
        "Max length of tool tip string:": "Preview length:",
        "Show Image": "Show image previews",
        "Show color code preview": "Show color previews",
        "Menu": "Board-Man Panel",
        "Main:": "Board-Man Panel:",
        "Clear History:": "Clear History:"
    ]
    // ViewController
    private let viewController = [NSViewController(nibName: "CPYGeneralPreferenceViewController", bundle: nil),
                                  NSViewController(nibName: "CPYMenuPreferenceViewController", bundle: nil),
                                  CPYTypePreferenceViewController(nibName: "CPYTypePreferenceViewController", bundle: nil),
                                  CPYExcludeAppPreferenceViewController(nibName: "CPYExcludeAppPreferenceViewController", bundle: nil),
                                  CPYShortcutsPreferenceViewController(nibName: "CPYShortcutsPreferenceViewController", bundle: nil),
                                  CPYUpdatesPreferenceViewController(nibName: "CPYUpdatesPreferenceViewController", bundle: nil),
                                  CPYBetaPreferenceViewController(nibName: "CPYBetaPreferenceViewController", bundle: nil)]

    // MARK: - Window Life Cycle
    override func windowDidLoad() {
        super.windowDidLoad()
        configureSettingsWindow()
        if #available(OSX 10.10, *) {
            self.window?.titlebarAppearsTransparent = true
        }
        styleToolbar()
        toolBarItemTapped(generalButton)
        generalButton.sendAction(on: .leftMouseDown)
        menuButton.sendAction(on: .leftMouseDown)
        typeButton.sendAction(on: .leftMouseDown)
        excludeButton.sendAction(on: .leftMouseDown)
        shortcutsButton.sendAction(on: .leftMouseDown)
        updatesButton.sendAction(on: .leftMouseDown)
        betaButton.sendAction(on: .leftMouseDown)
    }

    override func showWindow(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        configureSettingsWindow()
        super.showWindow(sender)
        window?.centerIfNeeded()
        window?.makeKeyAndOrderFront(self)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - IBActions
extension CPYPreferencesWindowController {
    @IBAction private func toolBarItemTapped(_ sender: NSButton) {
        selectedTab(sender.tag)
        switchView(sender.tag)
    }
}

// MARK: - NSWindow Delegate
extension CPYPreferencesWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let viewController = viewController[2] as? CPYTypePreferenceViewController {
            AppEnvironment.current.defaults.set(viewController.storeTypes, forKey: Constants.UserDefaults.storeTypes)
            AppEnvironment.current.defaults.synchronize()
        }
        if let window = window, !window.makeFirstResponder(window) {
            window.endEditing(for: nil)
        }
    }
}

// MARK: - Layout
private extension CPYPreferencesWindowController {
    func configureSettingsWindow() {
        guard let window = window else { return }
        window.title = "Board-Man Settings"
        window.level = .normal
        (window as? NSPanel)?.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.styleMask.insert([.titled, .closable, .miniaturizable])
        window.styleMask.remove(.nonactivatingPanel)
        let useLiquidGlass = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.boardManLiquidGlass)
        window.backgroundColor = useLiquidGlass ? .clear : .windowBackgroundColor
        window.isOpaque = !useLiquidGlass
        window.hasShadow = true
        window.delegate = self

        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = (useLiquidGlass
                ? NSColor.clear
                : NSColor.windowBackgroundColor).cgColor
            contentView.layer?.cornerRadius = useLiquidGlass ? 12 : 0
            contentView.layer?.masksToBounds = useLiquidGlass
            configureSettingsGlassBackground(in: contentView, enabled: useLiquidGlass)
        }
    }

    func makeSettingsGlassSurface(blendingMode: NSVisualEffectView.BlendingMode) -> NSVisualEffectView {
        let glass = NSVisualEffectView(frame: .zero)
        glass.blendingMode = blendingMode
        glass.material = .hudWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 12
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 1
        return glass
    }

    func configureSettingsGlassBackground(in contentView: NSView, enabled: Bool) {
        if settingsGlassBackgroundView == nil {
            let glass = makeSettingsGlassSurface(blendingMode: .behindWindow)
            glass.autoresizingMask = [.width, .height]
            contentView.addSubview(glass, positioned: .below, relativeTo: nil)
            settingsGlassBackgroundView = glass
        }
        settingsGlassBackgroundView?.frame = contentView.bounds
        settingsGlassBackgroundView?.isHidden = !enabled
        settingsGlassBackgroundView?.layer?.backgroundColor = NSColor.black.withAlphaComponent(enabled ? 0.10 : 0).cgColor
        settingsGlassBackgroundView?.layer?.borderColor = NSColor.white.withAlphaComponent(enabled ? 0.16 : 0).cgColor
    }

    func styleToolbar() {
        let useLiquidGlass = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.boardManLiquidGlass)
        if toolbarGlassView == nil {
            let glass = makeSettingsGlassSurface(blendingMode: .withinWindow)
            glass.autoresizingMask = [.width, .height]
            toolBar.addSubview(glass, positioned: .below, relativeTo: nil)
            toolbarGlassView = glass
        }
        toolbarGlassView?.frame = toolBar.bounds
        toolbarGlassView?.isHidden = !useLiquidGlass
        toolbarGlassView?.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(useLiquidGlass ? 0.10 : 0).cgColor
        toolbarGlassView?.layer?.borderColor = NSColor.white.withAlphaComponent(useLiquidGlass ? 0.14 : 0).cgColor
        toolBar.wantsLayer = true
        toolBar.layer?.backgroundColor = (useLiquidGlass
            ? NSColor.clear
            : NSColor.controlBackgroundColor).cgColor
        toolBar.layer?.cornerRadius = useLiquidGlass ? 10 : 0
        toolBar.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(useLiquidGlass ? 0.26 : 0.6).cgColor
        toolBar.layer?.borderWidth = 1
        for (index, label) in toolbarLabels.enumerated() {
            label.stringValue = boardManCategoryTitles[safe: index] ?? label.stringValue
            label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            label.textColor = useLiquidGlass ? NSColor.secondaryLabelColor.withAlphaComponent(0.96) : .secondaryLabelColor
            label.backgroundColor = .clear
            label.drawsBackground = false
        }
        toolbarButtons.forEach { button in
            button.wantsLayer = true
            button.layer?.cornerRadius = useLiquidGlass ? 9 : 7
            button.layer?.backgroundColor = NSColor.clear.cgColor
            button.layer?.borderWidth = 0
        }
        toolbarImages.forEach { imageView in
            imageView.contentTintColor = useLiquidGlass ? NSColor.secondaryLabelColor.withAlphaComponent(0.96) : .secondaryLabelColor
            imageView.image?.isTemplate = true
        }
    }

    func resetImages() {
        let useLiquidGlass = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.boardManLiquidGlass)
        generalImageView.image = boardManSymbol("gearshape", fallback: NSImage(resource: .prefGeneral))
        menuImageView.image = boardManSymbol("list.bullet.rectangle", fallback: NSImage(resource: .prefMenu))
        typeImageView.image = boardManSymbol("doc.on.clipboard", fallback: NSImage(resource: .prefType))
        excludeImageView.image = boardManSymbol("minus.circle", fallback: NSImage(resource: .prefExcluded))
        shortcutsImageView.image = boardManSymbol("keyboard", fallback: NSImage(resource: .prefShortcut))
        updatesImageView.image = boardManSymbol("arrow.triangle.2.circlepath", fallback: NSImage(resource: .prefUpdate))
        betaImageView.image = boardManSymbol("sparkles", fallback: NSImage(resource: .prefBeta))

        let inactiveLabelColor = useLiquidGlass ? NSColor.secondaryLabelColor.withAlphaComponent(0.96) : NSColor(resource: .tabTitle)
        generalTextField.textColor = inactiveLabelColor
        menuTextField.textColor = inactiveLabelColor
        typeTextField.textColor = inactiveLabelColor
        excludeTextField.textColor = inactiveLabelColor
        shortcutsTextField.textColor = inactiveLabelColor
        updatesTextField.textColor = inactiveLabelColor
        betaTextField.textColor = inactiveLabelColor
        toolbarImages.forEach { imageView in
            imageView.contentTintColor = useLiquidGlass ? NSColor.secondaryLabelColor.withAlphaComponent(0.96) : .secondaryLabelColor
            imageView.image?.isTemplate = true
        }
        toolbarButtons.forEach { button in
            button.layer?.backgroundColor = NSColor.clear.cgColor
            button.layer?.borderWidth = 0
        }
    }

    func boardManSymbol(_ name: String, fallback: NSImage) -> NSImage {
        if #available(macOS 11.0, *) {
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? fallback
            image.isTemplate = true
            return image
        }
        return fallback
    }

    func selectedTab(_ index: Int) {
        resetImages()

        switch index {
        case 0:
            generalImageView.image = NSImage(resource: .prefGeneralOn)
            generalTextField.textColor = NSColor.controlAccentColor
            generalImageView.contentTintColor = NSColor.controlAccentColor
        case 1:
            menuImageView.image = NSImage(resource: .prefMenuOn)
            menuTextField.textColor = NSColor.controlAccentColor
            menuImageView.contentTintColor = NSColor.controlAccentColor
        case 2:
            typeImageView.image = NSImage(resource: .prefTypeOn)
            typeTextField.textColor = NSColor.controlAccentColor
            typeImageView.contentTintColor = NSColor.controlAccentColor
        case 3:
            excludeImageView.image = NSImage(resource: .prefExcludedOn)
            excludeTextField.textColor = NSColor.controlAccentColor
            excludeImageView.contentTintColor = NSColor.controlAccentColor
        case 4:
            shortcutsImageView.image = NSImage(resource: .prefShortcutOn)
            shortcutsTextField.textColor = NSColor.controlAccentColor
            shortcutsImageView.contentTintColor = NSColor.controlAccentColor
        case 5:
            updatesImageView.image = NSImage(resource: .prefUpdateOn)
            updatesTextField.textColor = NSColor.controlAccentColor
            updatesImageView.contentTintColor = NSColor.controlAccentColor
        case 6:
            betaImageView.image = NSImage(resource: .prefBetaOn)
            betaTextField.textColor = NSColor.controlAccentColor
            betaImageView.contentTintColor = NSColor.controlAccentColor
        default: break
        }
        let useLiquidGlass = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.boardManLiquidGlass)
        toolbarButtons[safe: index]?.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(useLiquidGlass ? 0.16 : 0.12).cgColor
        toolbarButtons[safe: index]?.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(useLiquidGlass ? 0.30 : 0).cgColor
        toolbarButtons[safe: index]?.layer?.borderWidth = useLiquidGlass ? 1 : 0
    }

    func switchView(_ index: Int) {
        let newView = viewController[index].view
        if index == 0 {
            newView.frame.size = NSSize(width: 1180, height: 650)
        }
        // Remove current views without toolbar
        window?.contentView?.subviews.forEach { view in
            if view != toolBar && (settingsGlassBackgroundView == nil || view !== settingsGlassBackgroundView!) {
                view.removeFromSuperview()
            }
        }
        // Resize view
        let frame = window!.frame
        var newFrame = window!.frameRect(forContentRect: newView.frame)
        newFrame.origin = frame.origin
        newFrame.origin.y += frame.height - newFrame.height - toolBar.frame.height
        newFrame.size.height += toolBar.frame.height
        window?.setFrame(newFrame, display: true)
        stylePreferencePane(newView)
        window?.contentView?.addSubview(newView)
    }

    func stylePreferencePane(_ view: NSView) {
        let useLiquidGlass = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.boardManLiquidGlass)
        view.wantsLayer = true
        view.layer?.backgroundColor = (useLiquidGlass
            ? NSColor.clear
            : NSColor.windowBackgroundColor).cgColor
        view.layer?.cornerRadius = useLiquidGlass ? 12 : 0
        view.layer?.borderColor = NSColor.white.withAlphaComponent(useLiquidGlass ? 0.14 : 0).cgColor
        view.layer?.borderWidth = useLiquidGlass ? 1 : 0
        let paneGlassIdentifier = NSUserInterfaceItemIdentifier("BoardManSettingsPaneGlass")
        view.subviews
            .filter { $0.identifier == paneGlassIdentifier }
            .forEach { $0.removeFromSuperview() }
        if useLiquidGlass {
            let paneGlass = makeSettingsGlassSurface(blendingMode: .withinWindow)
            paneGlass.identifier = paneGlassIdentifier
            paneGlass.frame = view.bounds
            paneGlass.autoresizingMask = [.width, .height]
            paneGlass.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.08).cgColor
            paneGlass.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
            view.addSubview(paneGlass, positioned: .below, relativeTo: nil)
        }
        stylePreferenceSubviews(in: view, depth: 0)
        styleAppearanceSectionIfPresent(in: view, useLiquidGlass: useLiquidGlass)
    }

    func stylePreferenceSubviews(in view: NSView, depth: Int) {
        for subview in view.subviews {
            if let label = subview as? NSTextField {
                if let rewritten = paneTextRewrites[label.stringValue] {
                    label.stringValue = rewritten
                }
                let useLiquidGlass = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.boardManLiquidGlass)
                label.textColor = label.isEnabled
                    ? (useLiquidGlass ? NSColor.labelColor.withAlphaComponent(0.98) : .labelColor)
                    : .tertiaryLabelColor
                label.backgroundColor = .clear
                label.drawsBackground = false
                if label.font?.fontDescriptor.symbolicTraits.contains(.bold) == true {
                    label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
                    label.textColor = useLiquidGlass ? NSColor.labelColor.withAlphaComponent(0.98) : .labelColor
                } else if label.font?.pointSize ?? 0 <= 11 {
                    label.font = NSFont.systemFont(ofSize: max(11, label.font?.pointSize ?? 11), weight: .regular)
                }
            } else if let button = subview as? NSButton {
                let useLiquidGlass = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.boardManLiquidGlass)
                if let rewritten = paneTextRewrites[button.title] {
                    button.title = rewritten
                }
                button.font = NSFont.systemFont(ofSize: 12, weight: .regular)
                button.contentTintColor = button.isEnabled
                    ? (useLiquidGlass ? NSColor.labelColor.withAlphaComponent(0.98) : .labelColor)
                    : .tertiaryLabelColor
            } else if let tableView = subview as? NSTableView {
                let useLiquidGlass = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.boardManLiquidGlass)
                tableView.backgroundColor = useLiquidGlass ? .clear : .controlBackgroundColor
                tableView.gridColor = NSColor.separatorColor.withAlphaComponent(useLiquidGlass ? 0.35 : 1)
            } else if let scrollView = subview as? NSScrollView {
                let useLiquidGlass = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.boardManLiquidGlass)
                scrollView.wantsLayer = true
                scrollView.layer?.backgroundColor = (useLiquidGlass
                    ? NSColor.clear
                    : NSColor.controlBackgroundColor).cgColor
                scrollView.layer?.cornerRadius = useLiquidGlass ? 10 : 7
                scrollView.layer?.borderColor = (useLiquidGlass ? NSColor.white : NSColor.separatorColor).withAlphaComponent(useLiquidGlass ? 0.14 : 1).cgColor
                scrollView.layer?.borderWidth = 1
                scrollView.borderType = .noBorder
                scrollView.drawsBackground = !useLiquidGlass
            }
            stylePreferenceSubviews(in: subview, depth: depth + 1)
        }
    }

    func styleAppearanceSectionIfPresent(in view: NSView, useLiquidGlass: Bool) {
        guard let titleLabel = view.subviews.compactMap({ $0 as? NSTextField }).first(where: { $0.stringValue == "Appearance" }),
              let statusLabel = view.subviews.compactMap({ $0 as? NSTextField }).first(where: { $0.stringValue == "Menu bar icon style:" }),
              let statusControl = view.subviews.compactMap({ $0 as? NSPopUpButton }).first(where: { $0.frame.minY >= 10 && $0.frame.maxY <= 45 }) else {
            return
        }

        let cardIdentifier = NSUserInterfaceItemIdentifier("BoardManAppearancePreferenceCard")
        view.subviews
            .filter { $0.identifier == cardIdentifier }
            .forEach { $0.removeFromSuperview() }

        titleLabel.isHidden = true
        statusLabel.isHidden = true
        statusControl.isHidden = true
        let card = makeAppearancePreferencesScaffold(frame: view.bounds.insetBy(dx: 26, dy: 24), useLiquidGlass: useLiquidGlass)
        card.identifier = cardIdentifier
        view.addSubview(card)
    }

    func makeAppearancePreferencesScaffold(frame: NSRect, useLiquidGlass: Bool) -> NSView {
        let root = NSView(frame: frame)
        BoardManPreferenceUI.prepare(root, color: BoardManPreferenceUI.base, radius: BoardManPreferenceUI.Radius.window, border: BoardManPreferenceUI.borderNormal)

        let isPro = EntitlementGate.currentSnapshot().isProEntitled
        let left = NSView(frame: NSRect(x: 18, y: 18, width: 560, height: frame.height - 36))
        BoardManPreferenceUI.prepare(left, color: BoardManPreferenceUI.window, radius: BoardManPreferenceUI.Radius.panel, border: BoardManPreferenceUI.borderSubtle)
        root.addSubview(left)

        let preview = NSView(frame: NSRect(x: 594, y: 18, width: frame.width - 612, height: frame.height - 36))
        BoardManPreferenceUI.prepare(preview, color: useLiquidGlass ? BoardManPreferenceUI.panel.withAlphaComponent(0.86) : BoardManPreferenceUI.panel, radius: BoardManPreferenceUI.Radius.panel, border: BoardManPreferenceUI.borderSubtle)
        root.addSubview(preview)

        left.addSubview(BoardManPreferenceUI.label("Window Background", size: 16, weight: .semibold).bmPositioned(originX: 18, originY: left.frame.height - 42, width: 240, height: 22))
        addBackgroundModes(to: left, originY: left.frame.height - 126, isPro: isPro)
        addSourcePath(to: left, originY: left.frame.height - 172, isPro: isPro)
        addAdjustmentSection(to: left, originY: left.frame.height - 376, isPro: isPro)
        addShapeSection(to: left, originY: left.frame.height - 505, isPro: isPro)
        addPresetSection(to: left, originY: 18, isPro: isPro)

        preview.addSubview(BoardManPreferenceUI.label("Live Preview", size: 16, weight: .semibold).bmPositioned(originX: 18, originY: preview.frame.height - 42, width: 160, height: 22))
        preview.addSubview(BoardManPreferenceUI.icon("questionmark.circle", size: 14, color: BoardManPreferenceUI.secondaryText).bmPositioned(originX: 122, originY: preview.frame.height - 39, width: 18, height: 18))
        addPreviewScaffold(to: preview, isPro: isPro)
        addProLockedAppearanceControl(to: preview)
        return root
    }

    func addBackgroundModes(to view: NSView, originY: CGFloat, isPro: Bool) {
        let modes = [
            ("photo", "Wallpaper", false),
            ("square.dashed", "Transparent", false),
            ("rectangle.fill", "Solid Color", false),
            ("paintbrush", "Gradient", true),
            ("sparkles", "Blur Glass", true)
        ]
        for (index, mode) in modes.enumerated() {
            let originX = 18 + CGFloat(index) * 104
            let card = appearanceTile(symbol: mode.0, title: mode.1, active: index == 1, locked: mode.2 && !isPro)
            card.frame = NSRect(x: originX, y: originY, width: 86, height: 76)
            view.addSubview(card)
        }
    }

    func addSourcePath(to view: NSView, originY: CGFloat, isPro: Bool) {
        view.addSubview(BoardManPreferenceUI.label("Source", size: 13, weight: .semibold).bmPositioned(originX: 18, originY: originY + 8, width: 70, height: 20))
        let field = NSTextField(string: "/Users/naomac/Pictures/Board-Man Background.jpg")
        field.font = NSFont.systemFont(ofSize: 12)
        field.textColor = isPro ? BoardManPreferenceUI.secondaryText : BoardManPreferenceUI.mutedText
        field.backgroundColor = BoardManPreferenceUI.field
        field.isEnabled = isPro
        field.frame = NSRect(x: 86, y: originY + 4, width: 360, height: 28)
        BoardManPreferenceUI.prepare(field, color: BoardManPreferenceUI.field, radius: BoardManPreferenceUI.Radius.control, border: BoardManPreferenceUI.borderSubtle)
        view.addSubview(field)
        let choose = BoardManPreferenceUI.secondaryButton("Choose...")
        choose.isEnabled = isPro
        choose.frame = NSRect(x: 458, y: originY + 4, width: 78, height: 28)
        view.addSubview(choose)
    }

    func addAdjustmentSection(to view: NSView, originY: CGFloat, isPro: Bool) {
        addSectionDivider(to: view, originY: originY + 154)
        view.addSubview(BoardManPreferenceUI.label("Appearance Adjustments", size: 16, weight: .semibold).bmPositioned(originX: 18, originY: originY + 126, width: 250, height: 22))
        let controls = [
            ("Opacity", "78 %", false), ("Contrast", "12 %", true),
            ("Blur", "28 px", true), ("Noise", "6 %", true),
            ("Tint", "#FF3B30", false), ("Vignette", "22 %", true),
            ("Brightness", "8 %", true), ("Shadow Intensity", "35 %", true),
            ("Saturation", "14 %", true)
        ]
        for (index, control) in controls.enumerated() {
            let column = index % 2
            let row = index / 2
            addSliderRow(to: view, title: control.0, value: control.1, originX: 18 + CGFloat(column) * 280, originY: originY + 94 - CGFloat(row) * 34, locked: control.2 && !isPro)
        }
    }

    func addShapeSection(to view: NSView, originY: CGFloat, isPro: Bool) {
        addSectionDivider(to: view, originY: originY + 86)
        view.addSubview(BoardManPreferenceUI.label("Window Shape & Layout", size: 16, weight: .semibold).bmPositioned(originX: 18, originY: originY + 58, width: 250, height: 22))
        let controls = [
            ("Corner Radius", "16 px", false), ("Inner Spacing", "14 px", true),
            ("Border Thickness", "1.0 px", true), ("Panel Depth", "22 px", true),
            ("Padding", "18 px", true)
        ]
        for (index, control) in controls.enumerated() {
            let column = index % 2
            let row = index / 2
            addSliderRow(to: view, title: control.0, value: control.1, originX: 18 + CGFloat(column) * 280, originY: originY + 26 - CGFloat(row) * 34, locked: control.2 && !isPro)
        }
    }

    func addPresetSection(to view: NSView, originY: CGFloat, isPro: Bool) {
        addSectionDivider(to: view, originY: originY + 116)
        view.addSubview(BoardManPreferenceUI.label("Quick Presets", size: 16, weight: .semibold).bmPositioned(originX: 18, originY: originY + 88, width: 180, height: 22))
        let presets = [
            ("Deep Dark", BoardManPreferenceUI.redSoft, false),
            ("Carbon", NSColor(bmHex: 0x273242), true),
            ("Aurora", NSColor(bmHex: 0x4B2BB8), true),
            ("Sunset", NSColor(bmHex: 0xD75C3C), true),
            ("Ocean", NSColor(bmHex: 0x0F7190), true)
        ]
        for (index, preset) in presets.enumerated() {
            let tile = presetTile(title: preset.0, color: preset.1, active: index == 0, locked: preset.2 && !isPro)
            tile.frame = NSRect(x: 18 + CGFloat(index) * 104, y: originY, width: 86, height: 76)
            view.addSubview(tile)
        }
    }

    func addPreviewScaffold(to view: NSView, isPro: Bool) {
        let canvas = BoardManPreviewCanvasView(frame: NSRect(x: 18, y: 42, width: view.frame.width - 36, height: view.frame.height - 96))
        BoardManPreferenceUI.prepare(canvas, color: BoardManPreferenceUI.card, radius: BoardManPreferenceUI.Radius.panel, border: BoardManPreferenceUI.borderSubtle)
        view.addSubview(canvas)
        let panel = NSView(frame: NSRect(x: 110, y: 92, width: canvas.frame.width - 220, height: canvas.frame.height - 132))
        BoardManPreferenceUI.prepare(panel, color: BoardManPreferenceUI.base.withAlphaComponent(isPro ? 0.82 : 0.70), radius: 16, border: BoardManPreferenceUI.borderNormal)
        canvas.addSubview(panel)
        panel.addSubview(BoardManPreferenceUI.label("Board-Man", size: 14, weight: .bold).bmPositioned(originX: 158, originY: panel.frame.height - 38, width: 140, height: 20))
        let search = BoardManPreferenceUI.label("  Search clipboard history or snippets...", size: 12, color: BoardManPreferenceUI.mutedText)
        BoardManPreferenceUI.prepare(search, color: BoardManPreferenceUI.field, radius: BoardManPreferenceUI.Radius.control, border: BoardManPreferenceUI.borderSubtle)
        panel.addSubview(search.bmPositioned(originX: 20, originY: panel.frame.height - 76, width: panel.frame.width - 40, height: 32))
        let rows = [("Board-Man is the smart clipboard for creators.", "Text"), ("const build = () => 'Ship it!'", "Code"), ("https://board-man.app", "Link")]
        for (index, row) in rows.enumerated() {
            let item = NSView(frame: NSRect(x: 20, y: panel.frame.height - 128 - CGFloat(index) * 58, width: panel.frame.width - 40, height: 44))
            BoardManPreferenceUI.prepare(item, color: BoardManPreferenceUI.card.withAlphaComponent(0.72), radius: BoardManPreferenceUI.Radius.control, border: BoardManPreferenceUI.borderSubtle)
            item.addSubview(BoardManPreferenceUI.label(row.0, size: 12).bmPositioned(originX: 14, originY: 13, width: item.frame.width - 110, height: 18))
            item.addSubview(BoardManPreferenceUI.label(row.1, size: 12, color: BoardManPreferenceUI.secondaryText).bmPositioned(originX: item.frame.width - 72, originY: 13, width: 48, height: 18))
            panel.addSubview(item)
        }
    }

    func addProLockedAppearanceControl(to view: NSView) {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: ["Transparent", "Gradient", "Blur Glass"])
        popup.selectItem(withTitle: "Blur Glass")

        let control = BoardManPreferenceProLockedControlView(
            title: "Advanced Appearance",
            helper: "Gradient, glass, blur, depth, and extra presets are Pro-only.",
            feature: .appearanceAdvanced,
            control: popup,
            upgrade: (target: self, action: #selector(openBoardManProUpgrade))
        )
        control.frame = NSRect(x: 46, y: view.frame.height - 166, width: view.frame.width - 92, height: 96)
        view.addSubview(control)
    }

    @objc func openBoardManProUpgrade() {
        BoardManUpgradeRoute.openProPage()
    }

    func addSliderRow(to view: NSView, title: String, value: String, originX: CGFloat, originY: CGFloat, locked: Bool) {
        view.addSubview(BoardManPreferenceUI.label(title, size: 12, color: locked ? BoardManPreferenceUI.mutedText : BoardManPreferenceUI.primaryText).bmPositioned(originX: originX, originY: originY + 4, width: 112, height: 18))
        if title == "Tint" {
            let swatch = NSView(frame: NSRect(x: originX + 116, y: originY + 2, width: 38, height: 22))
            BoardManPreferenceUI.prepare(swatch, color: BoardManPreferenceUI.red, radius: 5, border: BoardManPreferenceUI.borderNormal)
            view.addSubview(swatch)
        } else {
            let slider = NSSlider(value: locked ? 0.42 : 0.70, minValue: 0, maxValue: 1, target: nil, action: nil)
            slider.isEnabled = !locked
            slider.frame = NSRect(x: originX + 116, y: originY, width: 120, height: 24)
            view.addSubview(slider)
        }
        let pill = BoardManPreferenceUI.label(value, size: 12, color: locked ? BoardManPreferenceUI.mutedText : BoardManPreferenceUI.primaryText)
        pill.alignment = .center
        BoardManPreferenceUI.prepare(pill, color: BoardManPreferenceUI.field, radius: BoardManPreferenceUI.Radius.control, border: BoardManPreferenceUI.borderSubtle)
        view.addSubview(pill.bmPositioned(originX: originX + 244, originY: originY + 1, width: 44, height: 24))
        if locked {
            view.addSubview(BoardManPreferenceUI.proBadge().bmPositioned(originX: originX + 206, originY: originY + 3, width: 30, height: 18))
        }
    }

    func addSectionDivider(to view: NSView, originY: CGFloat) {
        let divider = NSView(frame: NSRect(x: 18, y: originY, width: view.frame.width - 36, height: 1))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = BoardManPreferenceUI.borderSubtle.cgColor
        view.addSubview(divider)
    }

    func appearanceTile(symbol: String, title: String, active: Bool, locked: Bool) -> NSView {
        let tile = NSView()
        BoardManPreferenceUI.prepare(tile, color: BoardManPreferenceUI.card, radius: BoardManPreferenceUI.Radius.card, border: active ? BoardManPreferenceUI.red : BoardManPreferenceUI.borderNormal)
        tile.addSubview(BoardManPreferenceUI.icon(symbol, size: 20, color: locked ? BoardManPreferenceUI.mutedText : BoardManPreferenceUI.red).bmPositioned(originX: 28, originY: 34, width: 30, height: 28))
        tile.addSubview(BoardManPreferenceUI.label(title, size: 11, color: locked ? BoardManPreferenceUI.mutedText : BoardManPreferenceUI.primaryText).bmPositioned(originX: 4, originY: 8, width: 78, height: 16))
        if locked {
            tile.addSubview(BoardManPreferenceUI.lockedBadge().bmPositioned(originX: 58, originY: 46, width: 22, height: 22))
        }
        return tile
    }

    func presetTile(title: String, color: NSColor, active: Bool, locked: Bool) -> NSView {
        let tile = NSView()
        BoardManPreferenceUI.prepare(tile, color: color.withAlphaComponent(0.78), radius: BoardManPreferenceUI.Radius.card, border: active ? BoardManPreferenceUI.red : BoardManPreferenceUI.borderNormal)
        let mini = NSView(frame: NSRect(x: 14, y: 24, width: 58, height: 34))
        BoardManPreferenceUI.prepare(mini, color: BoardManPreferenceUI.card.withAlphaComponent(0.78), radius: 6, border: BoardManPreferenceUI.borderSubtle)
        tile.addSubview(mini)
        tile.addSubview(BoardManPreferenceUI.label(title, size: 11).bmPositioned(originX: 4, originY: 6, width: 78, height: 16))
        if active {
            tile.addSubview(BoardManPreferenceUI.icon("checkmark.circle.fill", size: 15).bmPositioned(originX: 64, originY: 22, width: 18, height: 18))
        } else if locked {
            tile.addSubview(BoardManPreferenceUI.proBadge().bmPositioned(originX: 51, originY: 52, width: 30, height: 18))
        }
        return tile
    }
}

private extension NSView {
    func bmPositioned(originX: CGFloat, originY: CGFloat, width: CGFloat, height: CGFloat) -> Self {
        frame = NSRect(x: originX, y: originY, width: width, height: height)
        return self
    }
}

private final class BoardManPreviewCanvasView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGradient(colors: [
            BoardManPreferenceUI.base,
            BoardManPreferenceUI.redSoft,
            NSColor(bmHex: 0x26334A)
        ])?.draw(in: bounds, angle: 25)
    }
}

final class BoardManPreferenceProLockedControlView: NSView {
    private let feature: EntitlementFeature
    private let titleLabel = BoardManPreferenceUI.label("", size: 14, weight: .semibold)
    private let proBadge = BoardManPreferenceUI.proBadge()
    private let helperLabel = BoardManPreferenceUI.label("", size: 12, color: BoardManPreferenceUI.secondaryText)
    private let upgradeButton = BoardManPreferenceUI.primaryButton("Upgrade")
    private let control: NSView
    private var lockView: NSView?

    init(title: String,
         helper: String,
         feature: EntitlementFeature,
         control: NSView,
         upgrade: (target: AnyObject?, action: Selector?)) {
        self.feature = feature
        self.control = control
        super.init(frame: .zero)

        BoardManPreferenceUI.prepare(self, color: BoardManPreferenceUI.redSoft.withAlphaComponent(0.66), radius: BoardManPreferenceUI.Radius.card, border: BoardManPreferenceUI.red.withAlphaComponent(0.45))

        titleLabel.stringValue = title
        addSubview(titleLabel)

        let lock = makeLockView()
        addSubview(lock)
        lockView = lock

        helperLabel.stringValue = helper
        addSubview(helperLabel)

        upgradeButton.target = upgrade.target
        upgradeButton.action = upgrade.action
        upgradeButton.toolTip = "Upgrade to unlock this Pro control."
        addSubview(upgradeButton)

        addSubview(proBadge)
        addSubview(control)
        refresh()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layout() {
        super.layout()
        lockView?.frame = NSRect(x: 16, y: bounds.height - 36, width: 22, height: 22)
        titleLabel.frame = NSRect(x: 48, y: bounds.height - 35, width: 190, height: 22)
        proBadge.frame = NSRect(x: 242, y: bounds.height - 32, width: 34, height: 18)
        helperLabel.frame = NSRect(x: 48, y: bounds.height - 60, width: max(160, bounds.width - 196), height: 20)
        upgradeButton.frame = NSRect(x: bounds.width - 120, y: 31, width: 96, height: 32)
        control.frame = NSRect(x: 48, y: 16, width: max(160, bounds.width - 196), height: 28)
    }

    func refresh() {
        let canUse = EntitlementGate.canUse(feature)
        setEnabled(canUse, in: control)
        control.alphaValue = canUse ? 1 : 0.48
        lockView?.isHidden = canUse
        proBadge.isHidden = canUse
        upgradeButton.isHidden = canUse
        helperLabel.textColor = canUse ? BoardManPreferenceUI.secondaryText : BoardManPreferenceUI.mutedText
        toolTip = canUse ? "Available in your current plan." : "Pro feature. Upgrade to unlock this control."
    }

    private func makeLockView() -> NSView {
        if #available(macOS 11.0, *) {
            return BoardManPreferenceUI.icon("lock.fill", size: 14, color: BoardManPreferenceUI.red)
        }
        return BoardManPreferenceUI.label("Locked", size: 11, weight: .semibold, color: BoardManPreferenceUI.red)
    }

    private func setEnabled(_ enabled: Bool, in view: NSView) {
        if let control = view as? NSControl {
            control.isEnabled = enabled
        }
        view.subviews.forEach { setEnabled(enabled, in: $0) }
    }
}

private extension NSWindow {
    func centerIfNeeded() {
        guard isVisible == false else { return }
        center()
    }
}

enum BoardManPreferenceUI {
    static let base = NSColor(bmHex: 0x0E0F11)
    static let window = NSColor(bmHex: 0x151619)
    static let panel = NSColor(bmHex: 0x1C1D20)
    static let card = NSColor(bmHex: 0x202226)
    static let field = NSColor(bmHex: 0x141518)
    static let borderSubtle = NSColor(bmHex: 0x2B2D31)
    static let borderNormal = NSColor(bmHex: 0x3A3D42)
    static let activeBorder = NSColor(bmHex: 0xFF4B4B)
    static let primaryText = NSColor(bmHex: 0xF2F2F3)
    static let secondaryText = NSColor(bmHex: 0xB7B8BC)
    static let mutedText = NSColor(bmHex: 0x777A80)
    static let red = NSColor(bmHex: 0xFF4B4B)
    static let redDeep = NSColor(bmHex: 0xB91F2B)
    static let redSoft = NSColor(bmHex: 0x3A1518)

    enum Radius {
        static let window: CGFloat = 18
        static let panel: CGFloat = 12
        static let card: CGFloat = 10
        static let control: CGFloat = 7
    }

    static func prepare(_ view: NSView, color: NSColor = panel, radius: CGFloat = Radius.panel, border: NSColor = borderSubtle) {
        view.wantsLayer = true
        view.layer?.backgroundColor = color.cgColor
        view.layer?.cornerRadius = radius
        view.layer?.borderWidth = 1
        view.layer?.borderColor = border.cgColor
    }

    static func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = primaryText) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }

    static func icon(_ symbolName: String, size: CGFloat = 20, color: NSColor = red) -> NSImageView {
        let imageView = NSImageView()
        if #available(macOS 11.0, *) {
            imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        }
        imageView.image?.isTemplate = true
        imageView.contentTintColor = color
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        return imageView
    }

    static func primaryButton(_ title: String) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        button.contentTintColor = .white
        button.wantsLayer = true
        button.layer?.backgroundColor = Self.red.withAlphaComponent(0.88).cgColor
        button.layer?.cornerRadius = Radius.control
        button.layer?.borderWidth = 1
        button.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        return button
    }

    static func secondaryButton(_ title: String) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        button.contentTintColor = primaryText
        button.wantsLayer = true
        button.layer?.backgroundColor = Self.card.cgColor
        button.layer?.cornerRadius = Radius.control
        button.layer?.borderWidth = 1
        button.layer?.borderColor = Self.borderNormal.cgColor
        return button
    }

    static func proBadge() -> NSTextField {
        let badge = label("PRO", size: 10, weight: .bold, color: .white)
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.backgroundColor = Self.red.withAlphaComponent(0.88).cgColor
        badge.layer?.cornerRadius = 4
        return badge
    }

    static func lockedBadge() -> NSView {
        let wrap = NSView()
        prepare(wrap, color: Self.field, radius: Radius.control, border: Self.borderSubtle)
        let lock = icon("lock.fill", size: 12, color: Self.mutedText)
        wrap.addSubview(lock)
        lock.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            lock.centerXAnchor.constraint(equalTo: wrap.centerXAnchor),
            lock.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            wrap.widthAnchor.constraint(equalToConstant: 28),
            wrap.heightAnchor.constraint(equalToConstant: 28)
        ])
        return wrap
    }
}

extension NSColor {
    convenience init(bmHex hex: UInt32, alpha: CGFloat = 1.0) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xff) / 255.0,
            green: CGFloat((hex >> 8) & 0xff) / 255.0,
            blue: CGFloat(hex & 0xff) / 255.0,
            alpha: alpha
        )
    }
}
