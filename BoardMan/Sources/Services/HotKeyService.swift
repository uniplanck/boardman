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

enum BoardManRuntimeEnvironment {
    static let benchmarkProfileEnvironmentKey = "BOARDMAN_BENCHMARK_PROFILE"

    static func isBenchmarkProfile(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard let rawValue = environment[benchmarkProfileEnvironmentKey] else { return false }
        return ["1", "true", "yes", "on"].contains(rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    static func isRunningTests(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        bundlePaths: [String] = Bundle.allBundles.map(\.bundlePath),
        hasXCTestCase: Bool = NSClassFromString("XCTestCase") != nil
    ) -> Bool {
        let markers = ["xctest", "xcinject", "swift_testing"]
        if environment.contains(where: { key, value in
            markers.contains(where: {
                key.localizedCaseInsensitiveContains($0)
                    || value.localizedCaseInsensitiveContains($0)
            })
        }) {
            return true
        }
        if arguments.contains(where: { argument in
            markers.contains(where: { argument.localizedCaseInsensitiveContains($0) })
        }) {
            return true
        }
        return hasXCTestCase || bundlePaths.contains(where: {
            $0.localizedCaseInsensitiveContains(".xctest")
        })
    }
}

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
    private let defaults: UserDefaults
    private var globalMainHotKeyEventTap: CFMachPort?
    private var globalMainHotKeyRunLoopSource: CFRunLoopSource?
    private var globalMainHotKeyMonitor: Any?
    private var globalMainHotKeyActivationObserver: NSObjectProtocol?
    private var didRequestListenEventAccess = false
    private var mainCarbonHotKeyRegistered = false
    private var lastMainHotKeyInvocation: CFAbsoluteTime = 0
    private var registrationRetryWorkItems: [String: DispatchWorkItem] = [:]

    static let mainHotKeyInvocationDebounce: TimeInterval = 0.75
    static let registrationRetryDelays: [TimeInterval] = [0.20, 0.60, 1.40, 3.00]

    init(defaults: UserDefaults = .standard) {
        KeyCombo.registerLegacyArchiveMappings()
        self.defaults = defaults
        super.init()
    }

    static func shouldAcceptMainHotKeyInvocation(now: CFAbsoluteTime, last: CFAbsoluteTime) -> Bool {
        return last == 0 || now - last > mainHotKeyInvocationDebounce
    }

    static func shouldRegisterSystemHotKeys(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        bundlePaths: [String] = Bundle.allBundles.map(\.bundlePath),
        hasXCTestCase: Bool = NSClassFromString("XCTestCase") != nil
    ) -> Bool {
        guard !BoardManRuntimeEnvironment.isBenchmarkProfile(environment: environment) else { return false }
        return !BoardManRuntimeEnvironment.isRunningTests(
            environment: environment,
            arguments: arguments,
            bundlePaths: bundlePaths,
            hasXCTestCase: hasXCTestCase
        )
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
        registrationRetryWorkItems.values.forEach { $0.cancel() }
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
        if !defaults.bool(forKey: Constants.HotKey.migrateNewKeyCombo) {
            migrationKeyCombos()
            defaults.set(true, forKey: Constants.HotKey.migrateNewKeyCombo)
            defaults.synchronize()
        }
        migrateLegacyMainShortcutIfNeeded()
        migrateExplicitlyClearedMainShortcutIfNeeded()
        // Snippet hotkey
        setupSnippetHotKeys()

        // Main menu. Preserve an intentional "Not set" choice across app rebuilds/relaunches.
        let savedMainKeyCombo = savedKeyCombo(forKey: Constants.HotKey.mainKeyCombo)
        let mainKeyCombo = savedMainKeyCombo
            ?? (defaults.bool(forKey: Constants.HotKey.mainKeyComboExplicitlyCleared) ? nil : restoreDefaultMainKeyCombo())
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
        cancelRegistrationRetry(for: type)
        switch type {
        case .main:
            mainKeyCombo = keyCombo
            defaults.set(keyCombo == nil, forKey: Constants.HotKey.mainKeyComboExplicitlyCleared)
            defaults.synchronize()
        case .history:
            historyKeyCombo = keyCombo
        case .snippet:
            snippetKeyCombo = keyCombo
        }
        let registered = register(with: type, keyCombo: keyCombo)
        if let keyCombo, !registered {
            scheduleRegistrationRetry(for: type, keyCombo: keyCombo, attempt: 0)
        }
        if type == .main {
            mainCarbonHotKeyRegistered = registered
            setupGlobalMainHotKeyFallback()
        }
    }

    func changeClearHistoryKeyCombo(_ keyCombo: KeyCombo?) {
        clearHistoryKeyCombo = keyCombo
        defaults.set(keyCombo?.archive(), forKey: Constants.HotKey.clearHistoryKeyCombo)
        defaults.synchronize()
        guard Self.shouldRegisterSystemHotKeys() else { return }
        // Reset hotkey
        HotKeyCenter.shared.unregisterHotKey(with: "ClearHistory")
        // Register new hotkey
        guard let keyCombo = keyCombo else { return }
        let hotkey = HotKey(identifier: "ClearHistory", keyCombo: keyCombo, target: self, action: #selector(HotKeyService.popUpClearHistoryAlert))
        hotkey.register()
    }

    func changeQuickModeKeyCombo(_ keyCombo: KeyCombo?) {
        quickModeKeyCombo = keyCombo
        defaults.set(keyCombo?.archive(), forKey: Constants.HotKey.quickModeKeyCombo)
        defaults.synchronize()
        guard Self.shouldRegisterSystemHotKeys() else { return }
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
        guard let data = defaults.object(forKey: key) as? Data else { return nil }
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
        defaults.set(keyCombo.archive(), forKey: Constants.HotKey.mainKeyCombo)
        defaults.synchronize()
        NSLog("Board-Man main hotkey archive missing or invalid; restored default Command-Option-V")
        return keyCombo
    }
}

// MARK: - Global Main HotKey Fallback
private extension HotKeyService {
    func setupGlobalMainHotKeyFallback() {
        guard Self.shouldRegisterSystemHotKeys() else { return }
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
        return registerSystemHotKey(with: type, keyCombo: keyCombo)
    }

    @discardableResult
    func registerSystemHotKey(with type: MenuType, keyCombo: KeyCombo?) -> Bool {
        // Tests verify persistence and migration only. Registering real Carbon hotkeys inside
        // XCTest can terminate and relaunch the test host, producing a false test failure.
        guard Self.shouldRegisterSystemHotKeys() else { return keyCombo != nil }
        HotKeyCenter.shared.unregisterHotKey(with: type.rawValue)
        guard let keyCombo else { return false }
        let hotKey = HotKey(identifier: type.rawValue, keyCombo: keyCombo, target: self, action: type.hotKeySelector)
        let registered = hotKey.register()
        NSLog(
            "Board-Man hotkey %@ Carbon registration=%@",
            type.rawValue,
            registered.description
        )
        return registered
    }

    func currentKeyCombo(for type: MenuType) -> KeyCombo? {
        switch type {
        case .main: return mainKeyCombo
        case .history: return historyKeyCombo
        case .snippet: return snippetKeyCombo
        }
    }

    func cancelRegistrationRetry(for type: MenuType) {
        registrationRetryWorkItems.removeValue(forKey: type.rawValue)?.cancel()
    }

    func scheduleRegistrationRetry(for type: MenuType, keyCombo: KeyCombo, attempt: Int) {
        guard Self.shouldRegisterSystemHotKeys(), attempt < Self.registrationRetryDelays.count else { return }
        cancelRegistrationRetry(for: type)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.currentKeyCombo(for: type) == keyCombo else { return }
            let registered = self.registerSystemHotKey(with: type, keyCombo: keyCombo)
            NSLog(
                "Board-Man hotkey %@ retry=%d registration=%@",
                type.rawValue,
                attempt + 1,
                registered.description
            )
            if registered {
                self.registrationRetryWorkItems.removeValue(forKey: type.rawValue)
                if type == .main {
                    self.mainCarbonHotKeyRegistered = true
                    self.setupGlobalMainHotKeyFallback()
                }
            } else {
                self.scheduleRegistrationRetry(for: type, keyCombo: keyCombo, attempt: attempt + 1)
            }
        }
        registrationRetryWorkItems[type.rawValue] = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.registrationRetryDelays[attempt],
            execute: workItem
        )
    }

    func save(with type: MenuType, keyCombo: KeyCombo?) {
        defaults.set(keyCombo?.archive(), forKey: type.userDefaultsKey)
        defaults.synchronize()
    }
}

// MARK: - Migration
private extension HotKeyService {
    /**
     *  Migration for changing the storage with v1.1.0
     *  Changed framework, PTHotKey to Magnet
     */
    func migrationKeyCombos() {
        guard let keyCombos = defaults.object(forKey: Constants.UserDefaults.hotKeys) as? [String: Any] else { return }

        // Main menu
        if let (keyCode, modifiers) = parse(with: keyCombos, forKey: Constants.Menu.clip) {
            if let keyCombo = KeyCombo(QWERTYKeyCode: keyCode, carbonModifiers: modifiers) {
                defaults.set(keyCombo.archive(), forKey: Constants.HotKey.mainKeyCombo)
            }
        }
        // History menu
        if let (keyCode, modifiers) = parse(with: keyCombos, forKey: Constants.Menu.history) {
            if let keyCombo = KeyCombo(QWERTYKeyCode: keyCode, carbonModifiers: modifiers) {
                defaults.set(keyCombo.archive(), forKey: Constants.HotKey.historyKeyCombo)
            }
        }
        // Snippet menu
        if let (keyCode, modifiers) = parse(with: keyCombos, forKey: Constants.Menu.snippet) {
            if let keyCombo = KeyCombo(QWERTYKeyCode: keyCode, carbonModifiers: modifiers) {
                defaults.set(keyCombo.archive(), forKey: Constants.HotKey.snippetKeyCombo)
            }
        }
    }

    func parse(with keyCombos: [String: Any], forKey key: String) -> (Int, Int)? {
        guard let combos = keyCombos[key] as? [String: Any] else { return nil }
        guard let keyCode = combos["keyCode"] as? Int, let modifiers = combos["modifiers"] as? Int else { return nil }
        return (keyCode, modifiers)
    }

    func migrateLegacyMainShortcutIfNeeded() {
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

    func migrateExplicitlyClearedMainShortcutIfNeeded() {
        guard !defaults.bool(forKey: Constants.HotKey.migrateExplicitlyClearedMainKeyCombo) else { return }
        defer {
            defaults.set(true, forKey: Constants.HotKey.migrateExplicitlyClearedMainKeyCombo)
            defaults.synchronize()
        }

        guard defaults.bool(forKey: Constants.HotKey.migrateNewKeyCombo),
              savedKeyCombo(forKey: Constants.HotKey.mainKeyCombo) == nil else { return }
        let hasOtherModernShortcut = savedKeyCombo(forKey: Constants.HotKey.historyKeyCombo) != nil
            || savedKeyCombo(forKey: Constants.HotKey.snippetKeyCombo) != nil
            || savedKeyCombo(forKey: Constants.HotKey.quickModeKeyCombo) != nil
            || savedKeyCombo(forKey: Constants.HotKey.clearHistoryKeyCombo) != nil
        if hasOtherModernShortcut {
            defaults.set(true, forKey: Constants.HotKey.mainKeyComboExplicitlyCleared)
        }
    }
}

// MARK: - Snippet HotKey
extension HotKeyService {
    private var folderKeyCombos: [String: KeyCombo]? {
        get {
            guard let data = defaults.object(forKey: Constants.HotKey.folderKeyCombos) as? Data else { return nil }
            return NSKeyedUnarchiver.unarchiveObject(with: data) as? [String: KeyCombo]
        }
        set {
            if let value = newValue {
                defaults.set(NSKeyedArchiver.archivedData(withRootObject: value), forKey: Constants.HotKey.folderKeyCombos)
            } else {
                defaults.removeObject(forKey: Constants.HotKey.folderKeyCombos)
            }
            defaults.synchronize()
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
        // Register new hotkey outside XCTest only.
        if Self.shouldRegisterSystemHotKeys() {
            let hotKey = HotKey(identifier: identifier, keyCombo: keyCombo, target: self, action: #selector(HotKeyService.popupSnippetFolder(_:)))
            hotKey.register()
        }
        // Save key combos
        var keyCombos = folderKeyCombos ?? [String: KeyCombo]()
        keyCombos[identifier] = keyCombo
        folderKeyCombos = keyCombos
    }

    func unregisterSnippetHotKey(with identifier: String) {
        // Unregister from the OS only outside XCTest.
        if Self.shouldRegisterSystemHotKeys() {
            HotKeyCenter.shared.unregisterHotKey(with: identifier)
        }
        // Save key combos
        var keyCombos = folderKeyCombos ?? [String: KeyCombo]()
        keyCombos.removeValue(forKey: identifier)
        folderKeyCombos = keyCombos
    }

    @objc func popupSnippetFolder(_ object: AnyObject) {
        guard let hotKey = object as? HotKey else { return }
        guard let folder = BoardManStores.authoritative.folder(identifier: hotKey.identifier) else {
            // When already deleted folder, remove keycombos
            unregisterSnippetHotKey(with: hotKey.identifier)
            return
        }
        if !folder.enable { return }

        AppEnvironment.current.menuManager.popUpSnippetFolder(folder)
    }

    fileprivate func setupSnippetHotKeys() {
        guard Self.shouldRegisterSystemHotKeys() else { return }
        folderKeyCombos?.forEach {
            let hotKey = HotKey(identifier: $0, keyCombo: $1, target: self, action: #selector(HotKeyService.popupSnippetFolder(_:)))
            hotKey.register()
        }
    }
}
