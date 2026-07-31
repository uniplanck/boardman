//
//  HotKeyService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/11/19.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import Cocoa
import Carbon
import Magnet
import RealmSwift

final class HotKeyService: NSObject {

    // MARK: - Properties
    static var defaultKeyCombos: [String: Any] = {
        // MainMenu:    ⌘ + Option + V
        // HistoryMenu: ⌘ + Control + V
        // SnippetMenu: ⌘ + Shift + B
        return [Constants.Menu.clip: ["keyCode": 9, "modifiers": Int(cmdKey) | Int(optionKey)],
                Constants.Menu.history: ["keyCode": 9, "modifiers": Int(cmdKey) | Int(controlKey)],
                Constants.Menu.snippet: ["keyCode": 11, "modifiers": Int(cmdKey) | Int(shiftKey)]]
    }()

    fileprivate(set) var mainKeyCombo: KeyCombo?
    fileprivate(set) var historyKeyCombo: KeyCombo?
    fileprivate(set) var snippetKeyCombo: KeyCombo?
    fileprivate(set) var clearHistoryKeyCombo: KeyCombo?
    fileprivate(set) var quickModeKeyCombo: KeyCombo?
    private var globalMainHotKeyEventTap: CFMachPort?
    private var globalMainHotKeyRunLoopSource: CFRunLoopSource?
    private var globalMainHotKeyMonitor: Any?
    private var globalMainHotKeyActivationObserver: NSObjectProtocol?
    private var didRequestListenEventAccess = false
    private var mainCarbonHotKeyRegistered = false
    private var lastMainHotKeyInvocation: CFAbsoluteTime = 0

    static let mainHotKeyInvocationDebounce: TimeInterval = 0.75

    static func shouldAcceptMainHotKeyInvocation(now: CFAbsoluteTime, last: CFAbsoluteTime) -> Bool {
        return last == 0 || now - last > mainHotKeyInvocationDebounce
    }

    deinit {
        if let monitor = globalMainHotKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let observer = globalMainHotKeyActivationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let source = globalMainHotKeyRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = globalMainHotKeyEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
    }

}

// MARK: - Actions
extension HotKeyService {
    @objc func popupMainMenu() {
        let now = CFAbsoluteTimeGetCurrent()
        guard Self.shouldAcceptMainHotKeyInvocation(now: now, last: lastMainHotKeyInvocation) else { return }
        lastMainHotKeyInvocation = now
        AppEnvironment.current.menuManager.popUpMenu(.main)
    }

    @objc func popupHistoryMenu() {
        AppEnvironment.current.menuManager.popUpMenu(.history)
    }

    @objc func popUpSnippetMenu() {
        AppEnvironment.current.menuManager.popUpMenu(.snippet)
    }

    @objc func popUpClearHistoryAlert() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        appDelegate.clearAllHistory()
    }

    @objc func popupQuickMode() {
        AppEnvironment.current.menuManager.showBoardManQuickPanel()
    }
}

// MARK: - Setup
extension HotKeyService {
    func setupDefaultHotKeys() {
        // Migration new framework
        if !AppEnvironment.current.defaults.bool(forKey: Constants.HotKey.migrateNewKeyCombo) {
            migrationKeyCombos()
            AppEnvironment.current.defaults.set(true, forKey: Constants.HotKey.migrateNewKeyCombo)
            AppEnvironment.current.defaults.synchronize()
        }
        migrateLegacyMainShortcutIfNeeded()
        // Snippet hotkey
        setupSnippetHotKeys()

        // Main menu. A missing/corrupt archive must not leave Board-Man unreachable.
        let mainKeyCombo = savedKeyCombo(forKey: Constants.HotKey.mainKeyCombo) ?? restoreDefaultMainKeyCombo()
        change(with: .main, keyCombo: mainKeyCombo)
        // History menu
        change(with: .history, keyCombo: savedKeyCombo(forKey: Constants.HotKey.historyKeyCombo))
        // Snippet menu
        change(with: .snippet, keyCombo: savedKeyCombo(forKey: Constants.HotKey.snippetKeyCombo))
        // Clear History
        changeClearHistoryKeyCombo(savedKeyCombo(forKey: Constants.HotKey.clearHistoryKeyCombo))
        // Quick Mode
        changeQuickModeKeyCombo(savedKeyCombo(forKey: Constants.HotKey.quickModeKeyCombo))
    }

    func change(with type: MenuType, keyCombo: KeyCombo?) {
        switch type {
        case .main:
            mainKeyCombo = keyCombo
        case .history:
            historyKeyCombo = keyCombo
        case .snippet:
            snippetKeyCombo = keyCombo
        }
        let registered = register(with: type, keyCombo: keyCombo)
        if type == .main {
            mainCarbonHotKeyRegistered = registered
            setupGlobalMainHotKeyFallback()
        }
    }

    func changeClearHistoryKeyCombo(_ keyCombo: KeyCombo?) {
        clearHistoryKeyCombo = keyCombo
        AppEnvironment.current.defaults.set(keyCombo?.archive(), forKey: Constants.HotKey.clearHistoryKeyCombo)
        AppEnvironment.current.defaults.synchronize()
        // Reset hotkey
        HotKeyCenter.shared.unregisterHotKey(with: "ClearHistory")
        // Register new hotkey
        guard let keyCombo = keyCombo else { return }
        let hotkey = HotKey(identifier: "ClearHistory", keyCombo: keyCombo, target: self, action: #selector(HotKeyService.popUpClearHistoryAlert))
        hotkey.register()
    }

    func changeQuickModeKeyCombo(_ keyCombo: KeyCombo?) {
        quickModeKeyCombo = keyCombo
        AppEnvironment.current.defaults.set(keyCombo?.archive(), forKey: Constants.HotKey.quickModeKeyCombo)
        AppEnvironment.current.defaults.synchronize()
        HotKeyCenter.shared.unregisterHotKey(with: "QuickMode")
        guard let keyCombo else { return }
        let hotkey = HotKey(
            identifier: "QuickMode",
            keyCombo: keyCombo,
            target: self,
            action: #selector(HotKeyService.popupQuickMode)
        )
        hotkey.register()
    }

    private func savedKeyCombo(forKey key: String) -> KeyCombo? {
        guard let data = AppEnvironment.current.defaults.object(forKey: key) as? Data else { return nil }
        guard let keyCombo = NSKeyedUnarchiver.unarchiveObject(with: data) as? KeyCombo else { return nil }
        return keyCombo
    }

    private func restoreDefaultMainKeyCombo() -> KeyCombo? {
        guard let keyCombo = KeyCombo(
            QWERTYKeyCode: 9,
            carbonModifiers: Int(cmdKey) | Int(optionKey)
        ) else {
            return nil
        }
        AppEnvironment.current.defaults.set(keyCombo.archive(), forKey: Constants.HotKey.mainKeyCombo)
        AppEnvironment.current.defaults.synchronize()
        NSLog("Board-Man main hotkey archive missing or invalid; restored default Command-Option-V")
        return keyCombo
    }
}

// MARK: - Global Main HotKey Fallback
private extension HotKeyService {
    func setupGlobalMainHotKeyFallback() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        guard mainKeyCombo != nil, !mainCarbonHotKeyRegistered else {
            stopGlobalMainHotKeyFallback()
            return
        }
        if globalMainHotKeyMonitor == nil {
            globalMainHotKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return }
                if let tap = self.globalMainHotKeyEventTap, CGEvent.tapIsEnabled(tap: tap) {
                    return
                }
                guard self.shouldHandleGlobalMainHotKey(event) else { return }
                DispatchQueue.main.async { [weak self] in
                    self?.invokeGlobalMainHotKeyFallback()
                }
            }
        }
        if globalMainHotKeyActivationObserver == nil {
            globalMainHotKeyActivationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.setupGlobalMainHotKeyEventTapIfPossible()
            }
        }
        setupGlobalMainHotKeyEventTapIfPossible()
    }

    func stopGlobalMainHotKeyFallback() {
        if let monitor = globalMainHotKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalMainHotKeyMonitor = nil
        }
        if let observer = globalMainHotKeyActivationObserver {
            NotificationCenter.default.removeObserver(observer)
            globalMainHotKeyActivationObserver = nil
        }
        if let source = globalMainHotKeyRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            globalMainHotKeyRunLoopSource = nil
        }
        if let tap = globalMainHotKeyEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            globalMainHotKeyEventTap = nil
        }
    }

    func setupGlobalMainHotKeyEventTapIfPossible() {
        guard !mainCarbonHotKeyRegistered, globalMainHotKeyEventTap == nil else { return }

        if #available(macOS 10.15, *) {
            guard CGPreflightListenEventAccess() else {
                if !didRequestListenEventAccess {
                    didRequestListenEventAccess = true
                    let granted = CGRequestListenEventAccess()
                    NSLog("Board-Man Input Monitoring request granted=%@", granted.description)
                }
                return
            }
        }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: Self.globalMainHotKeyEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            NSLog("Board-Man global hotkey event tap creation failed")
            return
        }

        globalMainHotKeyEventTap = tap
        globalMainHotKeyRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("Board-Man global hotkey event tap started")
    }

    static let globalMainHotKeyEventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }

        let service = Unmanaged<HotKeyService>.fromOpaque(refcon).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = service.globalMainHotKeyEventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown, service.shouldHandleGlobalMainHotKey(event) else {
            return Unmanaged.passUnretained(event)
        }

        DispatchQueue.main.async { [weak service] in
            service?.invokeGlobalMainHotKeyFallback()
        }
        return Unmanaged.passUnretained(event)
    }

    func invokeGlobalMainHotKeyFallback() {
        popupMainMenu()
        setupGlobalMainHotKeyEventTapIfPossible()
    }

    func shouldHandleGlobalMainHotKey(_ event: NSEvent) -> Bool {
        guard !event.isARepeat else { return false }
        guard let keyCombo = mainKeyCombo,
              !keyCombo.doubledModifiers else {
            return false
        }

        guard Int(event.keyCode) == Int(keyCombo.currentKeyCode) else { return false }

        var modifiers = 0
        let flags = event.modifierFlags
        if flags.contains(.command) { modifiers |= cmdKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        return modifiers == keyCombo.modifiers
    }

    func shouldHandleGlobalMainHotKey(_ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return false }
        guard let keyCombo = mainKeyCombo,
              !keyCombo.doubledModifiers else {
            return false
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == Int(keyCombo.currentKeyCode) else { return false }

        var modifiers = 0
        let flags = event.flags
        if flags.contains(.maskCommand) { modifiers |= cmdKey }
        if flags.contains(.maskAlternate) { modifiers |= optionKey }
        if flags.contains(.maskControl) { modifiers |= controlKey }
        if flags.contains(.maskShift) { modifiers |= shiftKey }
        return modifiers == keyCombo.modifiers
    }
}

// MARK: - Register
private extension HotKeyService {
    @discardableResult
    func register(with type: MenuType, keyCombo: KeyCombo?) -> Bool {
        save(with: type, keyCombo: keyCombo)
        // Reset hotkey
        HotKeyCenter.shared.unregisterHotKey(with: type.rawValue)
        // Register new hotkey
        guard let keyCombo = keyCombo else { return false }
        let hotKey = HotKey(identifier: type.rawValue, keyCombo: keyCombo, target: self, action: type.hotKeySelector)
        let registered = hotKey.register()
        if type == .main {
            NSLog("Board-Man main hotkey Carbon registration=%@ fallback=%@", registered.description, (!registered).description)
        }
        return registered
    }

    func save(with type: MenuType, keyCombo: KeyCombo?) {
        AppEnvironment.current.defaults.set(keyCombo?.archive(), forKey: type.userDefaultsKey)
        AppEnvironment.current.defaults.synchronize()
    }
}

// MARK: - Migration
private extension HotKeyService {
    /**
     *  Migration for changing the storage with v1.1.0
     *  Changed framework, PTHotKey to Magnet
     */
    func migrationKeyCombos() {
        guard let keyCombos = AppEnvironment.current.defaults.object(forKey: Constants.UserDefaults.hotKeys) as? [String: Any] else { return }

        // Main menu
        if let (keyCode, modifiers) = parse(with: keyCombos, forKey: Constants.Menu.clip) {
            if let keyCombo = KeyCombo(QWERTYKeyCode: keyCode, carbonModifiers: modifiers) {
                AppEnvironment.current.defaults.set(keyCombo.archive(), forKey: Constants.HotKey.mainKeyCombo)
            }
        }
        // History menu
        if let (keyCode, modifiers) = parse(with: keyCombos, forKey: Constants.Menu.history) {
            if let keyCombo = KeyCombo(QWERTYKeyCode: keyCode, carbonModifiers: modifiers) {
                AppEnvironment.current.defaults.set(keyCombo.archive(), forKey: Constants.HotKey.historyKeyCombo)
            }
        }
        // Snippet menu
        if let (keyCode, modifiers) = parse(with: keyCombos, forKey: Constants.Menu.snippet) {
            if let keyCombo = KeyCombo(QWERTYKeyCode: keyCode, carbonModifiers: modifiers) {
                AppEnvironment.current.defaults.set(keyCombo.archive(), forKey: Constants.HotKey.snippetKeyCombo)
            }
        }
    }

    func parse(with keyCombos: [String: Any], forKey key: String) -> (Int, Int)? {
        guard let combos = keyCombos[key] as? [String: Any] else { return nil }
        guard let keyCode = combos["keyCode"] as? Int, let modifiers = combos["modifiers"] as? Int else { return nil }
        return (keyCode, modifiers)
    }

    func migrateLegacyMainShortcutIfNeeded() {
        let defaults = AppEnvironment.current.defaults
        guard !defaults.bool(forKey: Constants.HotKey.migrateOpenBoardManCommandOptionV) else { return }
        defer {
            defaults.set(true, forKey: Constants.HotKey.migrateOpenBoardManCommandOptionV)
            defaults.synchronize()
        }

        guard let current = savedKeyCombo(forKey: Constants.HotKey.mainKeyCombo),
              current.QWERTYKeyCode == 9,
              current.modifiers == (Int(cmdKey) | Int(shiftKey)),
              current.doubledModifiers == false,
              let replacement = KeyCombo(
                QWERTYKeyCode: 9,
                carbonModifiers: Int(cmdKey) | Int(optionKey)
              ) else {
            return
        }
        defaults.set(replacement.archive(), forKey: Constants.HotKey.mainKeyCombo)
    }
}

// MARK: - Snippet HotKey
extension HotKeyService {
    private var folderKeyCombos: [String: KeyCombo]? {
        get {
            guard let data = AppEnvironment.current.defaults.object(forKey: Constants.HotKey.folderKeyCombos) as? Data else { return nil }
            return NSKeyedUnarchiver.unarchiveObject(with: data) as? [String: KeyCombo]
        }
        set {
            if let value = newValue {
                AppEnvironment.current.defaults.set(NSKeyedArchiver.archivedData(withRootObject: value), forKey: Constants.HotKey.folderKeyCombos)
            } else {
                AppEnvironment.current.defaults.removeObject(forKey: Constants.HotKey.folderKeyCombos)
            }
            AppEnvironment.current.defaults.synchronize()
        }
    }

    func snippetKeyCombo(forIdentifier identifier: String) -> KeyCombo? {
        return folderKeyCombos?[identifier]
    }

    func keyComboForSnippetFolder(identifier: String) -> KeyCombo? {
        return snippetKeyCombo(forIdentifier: identifier)
    }

    func setSnippetKeyCombo(_ keyCombo: KeyCombo?, forFolder identifier: String) {
        guard let keyCombo = keyCombo else {
            clearSnippetKeyCombo(forFolder: identifier)
            return
        }
        registerSnippetHotKey(with: identifier, keyCombo: keyCombo)
    }

    func clearSnippetKeyCombo(forFolder identifier: String) {
        unregisterSnippetHotKey(with: identifier)
    }

    func registerSnippetHotKey(with identifier: String, keyCombo: KeyCombo) {
        // Reset hotkey
        unregisterSnippetHotKey(with: identifier)
        // Register new hotkey
        let hotKey = HotKey(identifier: identifier, keyCombo: keyCombo, target: self, action: #selector(HotKeyService.popupSnippetFolder(_:)))
        hotKey.register()
        // Save key combos
        var keyCombos = folderKeyCombos ?? [String: KeyCombo]()
        keyCombos[identifier] = keyCombo
        folderKeyCombos = keyCombos
    }

    func unregisterSnippetHotKey(with identifier: String) {
        // Unregister
        HotKeyCenter.shared.unregisterHotKey(with: identifier)
        // Save key combos
        var keyCombos = folderKeyCombos ?? [String: KeyCombo]()
        keyCombos.removeValue(forKey: identifier)
        folderKeyCombos = keyCombos
    }

    @objc func popupSnippetFolder(_ object: AnyObject) {
        guard let hotKey = object as? HotKey else { return }
        let realm = try! Realm()
        guard let folder = realm.object(ofType: CPYFolder.self, forPrimaryKey: hotKey.identifier) else {
            // When already deleted folder, remove keycombos
            unregisterSnippetHotKey(with: hotKey.identifier)
            return
        }
        if !folder.enable { return }

        AppEnvironment.current.menuManager.popUpSnippetFolder(folder)
    }

    fileprivate func setupSnippetHotKeys() {
        folderKeyCombos?.forEach {
            let hotKey = HotKey(identifier: $0, keyCombo: $1, target: self, action: #selector(HotKeyService.popupSnippetFolder(_:)))
            hotKey.register()
        }
    }
}
