//
//  AppDelegate.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2015/06/21.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import Sparkle
import ServiceManagement

@NSApplicationMain
class AppDelegate: NSObject, NSMenuItemValidation {

    // MARK: - Properties
    private(set) var updaterController: SPUStandardUpdaterController?
    private lazy var screenshotObserver = BoardManScreenshotObserver()
    private var screenshotObserverThread: Thread?
    private var defaultsObserver: NSObjectProtocol?
    private var lastObservedLoginItem: Bool?
    private var lastObservedScreenshotEnabled: Bool?

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    static func shouldStartRuntimeServices(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        bundlePaths: [String] = Bundle.allBundles.map(\.bundlePath),
        hasXCTestCase: Bool = NSClassFromString("XCTestCase") != nil
    ) -> Bool {
        return !BoardManRuntimeEnvironment.isRunningTests(
            environment: environment,
            arguments: arguments,
            bundlePaths: bundlePaths,
            hasXCTestCase: hasXCTestCase
        )
    }

    // MARK: - Init
    override func awakeFromNib() {
        super.awakeFromNib()
        BoardManClipData.registerLegacyArchiveAliases()
        // Prepare the legacy schema only inside the migration compatibility boundary.
        BoardManHistoryPersistenceBootstrap.prepareLegacyRealmSchema()
        let historyBootstrap = BoardManHistoryPersistenceBootstrap.bootstrap()
        if historyBootstrap.shouldStartRealmShadowReplication {
            BoardManSQLiteShadowReplicator.shared.start()
        } else {
            BoardManSQLiteShadowReplicator.shared.stop()
        }
        if historyBootstrap.isSQLiteAuthoritative, Self.shouldStartRuntimeServices() {
            BoardManHistorySearchMetadataBackfiller.start()
        }
    }

    // MARK: - NSMenuItem Validation
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(AppDelegate.clearAllHistory) {
            return BoardManStores.authoritative.hasClips
        }
        return true
    }

    // MARK: - Class Methods
    static func storeTypesDictinary() -> [String: NSNumber] {
        var storeTypes = [String: NSNumber]()
        BoardManClipData.availableTypesString.forEach { storeTypes[$0] = NSNumber(value: true) }
        return storeTypes
    }

    // MARK: - Menu Actions
    @objc func openBoardMan() {
        AppEnvironment.current.menuManager.popUpMenu(.main)
    }

    @objc func openBoardManSettings() {
        AppEnvironment.current.menuManager.showBoardManSettingsPanel()
    }

    @objc func openBoardManSnippetsManager() {
        AppEnvironment.current.menuManager.showBoardManSnippetsPanel()
    }

    @objc func showPreferenceWindow() {
        AppEnvironment.current.menuManager.showBoardManSettingsPanel()
    }

    @objc func showSnippetEditorWindow() {
        NSApp.activate(ignoringOtherApps: true)
        BoardManSnippetsEditorWindowController.sharedController.showWindow(self)
    }

    @objc func restartBoardMan() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "sleep 0.35; exec /usr/bin/open -n \"$1\"",
            "boardman-restart",
            Bundle.main.bundlePath
        ]
        do {
            try process.run()
            terminateApplication()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Board-Man could not restart"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc func openArchivedTextHistory() {
        let store = TextHistoryArchiveStore.shared
        do {
            try store.ensureArchiveFileExists()
            NSWorkspace.shared.activateFileViewerSelecting([store.archiveFileURL])
        } catch {
            let alert = NSAlert()
            alert.messageText = "Archived history could not be opened"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc func terminate() {
        terminateApplication()
    }

    @objc func clearAllHistory() {
        let isShowAlert = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showAlertBeforeClearHistory)
        if isShowAlert {
            let alert = NSAlert()
            alert.messageText = String(localized: "Clear History")
            alert.informativeText = String(localized: "Are you sure you want to clear your clipboard history?")
            alert.addButton(withTitle: String(localized: "Clear History"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            alert.showsSuppressionButton = true

            NSApp.activate(ignoringOtherApps: true)

            let result = alert.runModal()
            if result != NSApplication.ModalResponse.alertFirstButtonReturn { return }

            if alert.suppressionButton?.state == NSControl.StateValue.on {
                AppEnvironment.current.defaults.set(false, forKey: Constants.UserDefaults.showAlertBeforeClearHistory)
            }
            AppEnvironment.current.defaults.synchronize()
        }

        AppEnvironment.current.clipService.clearAll()
    }

    @objc func selectClipMenuItem(_ sender: NSMenuItem) {
        BoardManRuntimeSupport.sendDiagnosticLog("selectClipMenuItem")
        guard let primaryKey = sender.representedObject as? String else {
            BoardManRuntimeSupport.sendDiagnosticLog("Cannot fetch clip primary key")
            NSSound.beep()
            return
        }
        guard let clip = BoardManStores.authoritative.clip(identifier: primaryKey) else {
            BoardManRuntimeSupport.sendDiagnosticLog("Cannot fetch clip data")
            NSSound.beep()
            return
        }

        let didPaste = AppEnvironment.current.pasteService.paste(with: clip)
        if didPaste {
            let pasteCountKey = PasteCountStore.shared.key(for: clip)
            PasteCountStore.shared.markUsed(clip: clip)
            PasteCountStore.shared.increment(forKey: pasteCountKey)
        }
    }

    @objc func selectSnippetMenuItem(_ sender: AnyObject) {
        BoardManRuntimeSupport.sendDiagnosticLog("selectSnippetMenuItem")
        guard let primaryKey = sender.representedObject as? String else {
            BoardManRuntimeSupport.sendDiagnosticLog("Cannot fetch snippet primary key")
            NSSound.beep()
            return
        }
        guard let snippet = BoardManStores.authoritative.snippet(identifier: primaryKey) else {
            BoardManRuntimeSupport.sendDiagnosticLog("Cannot fetch snippet data")
            NSSound.beep()
            return
        }
        AppEnvironment.current.pasteService.copyToPasteboard(with: snippet.content)
        AppEnvironment.current.pasteService.paste()
    }

    func terminateApplication() {
        PasteCountStore.shared.flushPendingPersistence()
        screenshotObserverThread?.cancel()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Login Item Methods
    private func promptToAddLoginItems() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Launch Board-Man on system startup?")
        alert.icon = NSApplication.shared.applicationIconImage
        alert.informativeText = "この設定はBoard-Man 設定から変更できます。"
        alert.addButton(withTitle: String(localized: "Launch on system startup"))
        alert.addButton(withTitle: String(localized: "Don't Launch"))
        alert.showsSuppressionButton = true
        NSApp.activate(ignoringOtherApps: true)

        //  Launch on system startup
        if alert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn {
            AppEnvironment.current.defaults.set(true, forKey: Constants.UserDefaults.loginItem)
            AppEnvironment.current.defaults.synchronize()
            reflectLoginItemState()
        }
        // Do not show this message again
        if alert.suppressionButton?.state == NSControl.StateValue.on {
            AppEnvironment.current.defaults.set(true, forKey: Constants.UserDefaults.suppressAlertForLoginItem)
            AppEnvironment.current.defaults.synchronize()
        }
    }

    private func toggleAddingToLoginItems(_ isEnable: Bool) {
        let loginItem = SMAppService.mainApp
        do {
            if isEnable {
                if loginItem.status != .enabled {
                    try loginItem.register()
                }
            } else if loginItem.status != .notRegistered {
                try loginItem.unregister()
            }
        } catch {
            BoardManRuntimeSupport.sendDiagnosticLog("Login item update failed: \(error.localizedDescription)")
        }
    }

    private func reflectLoginItemState() {
        guard !BoardManRuntimeEnvironment.isBenchmarkProfile() else { return }
        let isInLoginItems = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.loginItem)
        toggleAddingToLoginItems(isInLoginItems)
    }
}

// MARK: - NSApplication Delegate
extension AppDelegate: NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApplication.shared.applicationIconImage = NSImage(named: "AppIcon") ?? NSApplication.shared.applicationIconImage

        // Environments
        let runtimeDefaults = BoardManRuntimeSupport.runtimeDefaults()
        AppEnvironment.replaceCurrent(environment: AppEnvironment.fromStorage(defaults: runtimeDefaults))
        // UserDefaults
        BoardManRuntimeSupport.registerUserDefaults()

        // Unit tests use Board-Man as their host application. Starting clipboard monitors,
        // Login-item registration, Sparkle, global shortcuts, and background observers inside XCTest can
        // block or relaunch the test host. Keep the storage environment available to tests while
        // skipping normal application runtime services.
        guard Self.shouldStartRuntimeServices() else { return }

        // Restore a locally verified signed entitlement before gated services/UI are created.
        LicenseBootstrapService.shared.restoreEntitlement()
        // SDKs
        BoardManRuntimeSupport.initializeOptionalServices()
        // Check permissions without triggering repeated macOS prompts at launch.
        AppEnvironment.current.accessibilityService.logPermissionStatus(context: "launch")

        // Show Login Item
        if !AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.loginItem) && !AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.suppressAlertForLoginItem) {
            promptToAddLoginItems()
        }

        // Sparkle
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: AppEnvironment.current.defaults.bool(forKey: Constants.Update.enableAutomaticCheck),
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController?.updater.updateCheckInterval = TimeInterval(AppEnvironment.current.defaults.integer(forKey: Constants.Update.checkInterval))

        // Binding Events
        bind()

        // Services
        AppEnvironment.current.clipService.startMonitoring()
        AppEnvironment.current.dataCleanService.startMonitoring()
        AppEnvironment.current.excludeAppService.startMonitoring()
        AppEnvironment.current.hotKeyService.setupDefaultHotKeys()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.60) {
            PasteCountInputService.shared.startMonitoring()
        }

        // Managers
        AppEnvironment.current.menuManager.setup()

        // Build the hidden panel during idle launch time so the first global shortcut does not
        // pay the full AppKit construction + initial history load cost.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            AppEnvironment.current.menuManager.prewarmBoardManPanel()
        }

        // The explicit benchmark profile keeps normal runtime services active for representative
        // measurements, but never opens permission prompts that would invalidate launch/idle samples.
        guard !BoardManRuntimeEnvironment.isBenchmarkProfile() else { return }

#if DEBUG
        let screenshotEnvironment = ProcessInfo.processInfo.environment
        if screenshotEnvironment["BOARDMAN_SCREENSHOT_OUTPUT"]?.isEmpty == false {
            let requestedDelay = screenshotEnvironment["BOARDMAN_SCREENSHOT_DELAY"]
                .flatMap(Double.init) ?? 4.5
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.5, requestedDelay)) {
                AppEnvironment.current.menuManager.popUpMenu(.main)
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                guard !AppEnvironment.current.accessibilityService.isAccessibilityEnabled(isPrompt: false) else { return }
                AppEnvironment.current.accessibilityService.showAccessibilityAuthenticationAlert()
            }
        }
#else
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard !AppEnvironment.current.accessibilityService.isAccessibilityEnabled(isPrompt: false) else { return }
            AppEnvironment.current.accessibilityService.showAccessibilityAuthenticationAlert()
        }
#endif
    }

}

// MARK: - Bind
private extension AppDelegate {
    func bind() {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        let defaults = AppEnvironment.current.defaults
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self, weak defaults] _ in
            guard let self, let defaults else { return }
            self.refreshObservedDefaults(from: defaults)
        }
        refreshObservedDefaults(from: defaults, force: true)
    }

    func refreshObservedDefaults(from defaults: UserDefaults, force: Bool = false) {
        let loginItem = defaults.bool(forKey: Constants.UserDefaults.loginItem)
        if force || loginItem != lastObservedLoginItem {
            lastObservedLoginItem = loginItem
            reflectLoginItemState()
        }

        let screenshotEnabled = defaults.bool(forKey: Constants.Beta.observerScreenshot)
        if force || screenshotEnabled != lastObservedScreenshotEnabled {
            lastObservedScreenshotEnabled = screenshotEnabled
            screenshotObserver.isEnabled = screenshotEnabled
            if screenshotEnabled {
                startScreenshotObserverIfNeeded()
            }
        }
    }

    func startScreenshotObserverIfNeeded() {
        guard screenshotObserverThread == nil else { return }
        screenshotObserver.delegate = self
        let thread = Thread { [weak self] in
            guard let self else { return }
            autoreleasepool {
                self.screenshotObserver.start()
                while !Thread.current.isCancelled {
                    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.5))
                }
                self.screenshotObserver.stop()
            }
        }
        thread.name = "com.uniplanck.BoardMan.ScreenShotObserver"
        thread.qualityOfService = .utility
        screenshotObserverThread = thread
        thread.start()
    }
}

// MARK: - Screenshot Observer Delegate
extension AppDelegate: BoardManScreenshotObserverDelegate {
    func screenshotObserver(_ observer: BoardManScreenshotObserver, addedFileAt path: String) {
        DispatchQueue.main.async {
            guard let image = NSImage(contentsOfFile: path) else { return }
            AppEnvironment.current.clipService.create(with: image)
        }
    }
}
