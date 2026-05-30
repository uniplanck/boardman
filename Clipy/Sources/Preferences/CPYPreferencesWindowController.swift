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
                ? NSColor.windowBackgroundColor.withAlphaComponent(0.78)
                : NSColor.windowBackgroundColor).cgColor
        }
    }

    func styleToolbar() {
        let useLiquidGlass = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.boardManLiquidGlass)
        toolBar.wantsLayer = true
        toolBar.layer?.backgroundColor = (useLiquidGlass
            ? NSColor.controlBackgroundColor.withAlphaComponent(0.62)
            : NSColor.controlBackgroundColor).cgColor
        toolBar.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(useLiquidGlass ? 0.38 : 0.6).cgColor
        toolBar.layer?.borderWidth = 1
        for (index, label) in toolbarLabels.enumerated() {
            label.stringValue = boardManCategoryTitles[safe: index] ?? label.stringValue
            label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.backgroundColor = .clear
            label.drawsBackground = false
        }
        toolbarButtons.forEach { button in
            button.wantsLayer = true
            button.layer?.cornerRadius = 7
            button.layer?.backgroundColor = NSColor.clear.cgColor
        }
        toolbarImages.forEach { imageView in
            imageView.contentTintColor = .secondaryLabelColor
            imageView.image?.isTemplate = true
        }
    }

    func resetImages() {
        generalImageView.image = boardManSymbol("gearshape", fallback: NSImage(resource: .prefGeneral))
        menuImageView.image = boardManSymbol("list.bullet.rectangle", fallback: NSImage(resource: .prefMenu))
        typeImageView.image = boardManSymbol("doc.on.clipboard", fallback: NSImage(resource: .prefType))
        excludeImageView.image = boardManSymbol("minus.circle", fallback: NSImage(resource: .prefExcluded))
        shortcutsImageView.image = boardManSymbol("keyboard", fallback: NSImage(resource: .prefShortcut))
        updatesImageView.image = boardManSymbol("arrow.triangle.2.circlepath", fallback: NSImage(resource: .prefUpdate))
        betaImageView.image = boardManSymbol("sparkles", fallback: NSImage(resource: .prefBeta))

        generalTextField.textColor = NSColor(resource: .tabTitle)
        menuTextField.textColor = NSColor(resource: .tabTitle)
        typeTextField.textColor = NSColor(resource: .tabTitle)
        excludeTextField.textColor = NSColor(resource: .tabTitle)
        shortcutsTextField.textColor = NSColor(resource: .tabTitle)
        updatesTextField.textColor = NSColor(resource: .tabTitle)
        betaTextField.textColor = NSColor(resource: .tabTitle)
        toolbarImages.forEach { imageView in
            imageView.contentTintColor = .secondaryLabelColor
            imageView.image?.isTemplate = true
        }
        toolbarButtons.forEach { button in
            button.layer?.backgroundColor = NSColor.clear.cgColor
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
        toolbarButtons[safe: index]?.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
    }

    func switchView(_ index: Int) {
        let newView = viewController[index].view
        // Remove current views without toolbar
        window?.contentView?.subviews.forEach { view in
            if view != toolBar {
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
            ? NSColor.windowBackgroundColor.withAlphaComponent(0.72)
            : NSColor.windowBackgroundColor).cgColor
        stylePreferenceSubviews(in: view, depth: 0)
    }

    func stylePreferenceSubviews(in view: NSView, depth: Int) {
        for subview in view.subviews {
            if let label = subview as? NSTextField {
                if let rewritten = paneTextRewrites[label.stringValue] {
                    label.stringValue = rewritten
                }
                label.textColor = label.isEnabled ? .labelColor : .tertiaryLabelColor
                label.backgroundColor = .clear
                label.drawsBackground = false
                if label.font?.fontDescriptor.symbolicTraits.contains(.bold) == true {
                    label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
                    label.textColor = .labelColor
                } else if label.font?.pointSize ?? 0 <= 11 {
                    label.font = NSFont.systemFont(ofSize: max(11, label.font?.pointSize ?? 11), weight: .regular)
                }
            } else if let button = subview as? NSButton {
                if let rewritten = paneTextRewrites[button.title] {
                    button.title = rewritten
                }
                button.font = NSFont.systemFont(ofSize: 12, weight: .regular)
                button.contentTintColor = button.isEnabled ? .labelColor : .tertiaryLabelColor
            } else if let tableView = subview as? NSTableView {
                tableView.backgroundColor = .controlBackgroundColor
                tableView.gridColor = .separatorColor
            } else if let scrollView = subview as? NSScrollView {
                scrollView.wantsLayer = true
                scrollView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
                scrollView.layer?.cornerRadius = 7
                scrollView.layer?.borderColor = NSColor.separatorColor.cgColor
                scrollView.layer?.borderWidth = 1
                scrollView.borderType = .noBorder
            }
            stylePreferenceSubviews(in: subview, depth: depth + 1)
        }
    }
}

private extension NSWindow {
    func centerIfNeeded() {
        guard isVisible == false else { return }
        center()
    }
}
