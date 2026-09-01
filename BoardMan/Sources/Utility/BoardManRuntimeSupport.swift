//
//  BoardManRuntimeSupport.swift
//  Board-Man
//

import Cocoa

final class BoardManRuntimeSupport {
    private static let benchmarkDefaultsSuiteName = "com.uniplanck.BoardMan.Benchmark"

    static func applicationSupportFolder(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        let paths = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)
        let basePath = paths.first ?? NSTemporaryDirectory()
        let folderName = BoardManRuntimeEnvironment.isBenchmarkProfile(environment: environment)
            ? "\(Constants.Application.name) Benchmark"
            : Constants.Application.name
        return (basePath as NSString).appendingPathComponent(folderName)
    }

    static func benchmarkRealmFileURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        guard BoardManRuntimeEnvironment.isBenchmarkProfile(environment: environment) else { return nil }
        return URL(fileURLWithPath: applicationSupportFolder(environment: environment), isDirectory: true)
            .appendingPathComponent("benchmark.realm")
    }

    static func sqliteHistoryFileURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        URL(fileURLWithPath: applicationSupportFolder(environment: environment), isDirectory: true)
            .appendingPathComponent("BoardMan.sqlite")
    }

    static func sqliteMigrationStagingDirectoryURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        URL(fileURLWithPath: applicationSupportFolder(environment: environment), isDirectory: true)
            .appendingPathComponent("Migration Staging", isDirectory: true)
    }

    static func historyMigrationManifestURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        URL(fileURLWithPath: applicationSupportFolder(environment: environment), isDirectory: true)
            .appendingPathComponent("BoardMan-history-migration.json")
    }

    static func prefersSQLiteHistory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        let value = environment["BOARDMAN_SQLITE_HISTORY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return ["1", "true", "yes", "on"].contains(value)
    }

    static func legacyRealmBackupDirectoryURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        URL(fileURLWithPath: applicationSupportFolder(environment: environment), isDirectory: true)
            .appendingPathComponent("Legacy Realm Backups", isDirectory: true)
    }

    static func runtimeDefaults(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> UserDefaults {
        guard BoardManRuntimeEnvironment.isBenchmarkProfile(environment: environment) else { return .standard }
        guard let defaults = UserDefaults(suiteName: benchmarkDefaultsSuiteName) else {
            preconditionFailure("Board-Man benchmark defaults suite is unavailable")
        }
        return defaults
    }

    static func performanceLogDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        let directoryName = BoardManRuntimeEnvironment.isBenchmarkProfile(environment: environment)
            ? "Board-Man Benchmark"
            : "Board-Man"
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/\(directoryName)", isDirectory: true)
    }

    static func initializeOptionalServices() {
        guard AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.collectCrashReport) else { return }
        sendDiagnosticLog("applicationDidFinishLaunching")
    }

    static func registerUserDefaults() {
        var defaults = [String: Any]()
        defaults[Constants.UserDefaults.hotKeys] = HotKeyService.defaultKeyCombos
        defaults[Constants.UserDefaults.loginItem] = false
        defaults[Constants.UserDefaults.suppressAlertForLoginItem] = false
        defaults[Constants.UserDefaults.maxHistorySize] = 100
        defaults[Constants.UserDefaults.showStatusItem] = 1
        defaults[Constants.UserDefaults.storeTypes] = AppDelegate.storeTypesDictinary()
        defaults[Constants.UserDefaults.inputPasteCommand] = true
        defaults[Constants.UserDefaults.reorderClipsAfterPasting] = true
        defaults[Constants.UserDefaults.collectCrashReport] = true
        defaults[Constants.UserDefaults.menuIconSize] = 16
        defaults[Constants.UserDefaults.maxMenuItemTitleLength] = 20
        defaults[Constants.UserDefaults.numberOfItemsPlaceInline] = 0
        defaults[Constants.UserDefaults.numberOfItemsPlaceInsideFolder] = 10
        defaults[Constants.UserDefaults.menuItemsTitleStartWithZero] = false
        defaults[Constants.UserDefaults.showAlertBeforeClearHistory] = true
        defaults[Constants.UserDefaults.addClearHistoryMenuItem] = true
        defaults[Constants.UserDefaults.showIconInTheMenu] = true
        defaults[Constants.UserDefaults.menuItemsAreMarkedWithNumbers] = true
        defaults[Constants.UserDefaults.addNumericKeyEquivalents] = false
        defaults[Constants.UserDefaults.showToolTipOnMenuItem] = true
        defaults[Constants.UserDefaults.showImageInTheMenu] = true
        defaults[Constants.UserDefaults.maxLengthOfToolTip] = 200
        defaults[Constants.UserDefaults.thumbnailWidth] = 100
        defaults[Constants.UserDefaults.thumbnailHeight] = 32
        defaults[Constants.UserDefaults.overwriteSameHistory] = true
        defaults[Constants.UserDefaults.copySameHistory] = true
        defaults[Constants.UserDefaults.showColorPreviewInTheMenu] = true
        defaults[Constants.UserDefaults.boardManUsePanelUI] = true
        defaults[Constants.UserDefaults.boardManShowRowNumbers] = true
        defaults[Constants.UserDefaults.boardManHistoryUsageFilter] = "All"
        defaults[Constants.UserDefaults.boardManTimestampFormat] = "relative"
        defaults[Constants.UserDefaults.boardManRelativeTimestampTemplate] = "xh"
        defaults[Constants.UserDefaults.boardManRelativeNumberStyle] = "single"
        defaults[Constants.UserDefaults.boardManRelativeUnitStyle] = "symbol"
        defaults[Constants.UserDefaults.boardManRelativeSuffixStyle] = "none"
        defaults[Constants.UserDefaults.boardManRelativeNowStyle] = "localized"
        defaults[Constants.UserDefaults.boardManTimestampPosition] = "below"
        defaults[Constants.UserDefaults.boardManTimestampInteraction] = "click"
        defaults[Constants.UserDefaults.boardManTimestampShortcutEnabled] = false
        defaults[Constants.UserDefaults.boardManTimestampShortcutDelay] = 0.1
        defaults[Constants.UserDefaults.boardManPanelHeight] = 680
        defaults[Constants.UserDefaults.boardManShowUsageCount] = true
        defaults[Constants.UserDefaults.boardManUsageCountStyle] = "badge"
        defaults[Constants.UserDefaults.boardManUsedItemStyle] = "Default"
        defaults[Constants.UserDefaults.boardManPinLabelStyle] = "PIN"
        defaults[Constants.UserDefaults.boardManShowInlineImages] = true
        defaults[Constants.UserDefaults.boardManInlineImagePosition] = "Right"
        defaults[Constants.UserDefaults.boardManThemePreset] = "Default"
        defaults[Constants.UserDefaults.boardManLiquidGlass] = false
        defaults[Constants.UserDefaults.boardManThemeLighten] = false
        defaults[Constants.UserDefaults.boardManAppearanceMode] = "System"
        defaults[Constants.UserDefaults.boardManUIStyle] = "Default"
        defaults[Constants.UserDefaults.boardManFontChoice] = "System"
        defaults[Constants.UserDefaults.boardManItemTextScale] = 100
        defaults[Constants.UserDefaults.boardManLanguage] = "System"
        defaults[Constants.UserDefaults.boardManSkipPinnedInKeyboardNavigation] = false
        defaults[Constants.UserDefaults.boardManLongPressAction] = "togglePin"
        defaults[Constants.UserDefaults.boardManTimedPinDurationValue] = 1
        defaults[Constants.UserDefaults.boardManTimedPinDurationUnit] = "hours"
        defaults[Constants.UserDefaults.boardManTimedPinSelectedPresetID] = "default-1h"
        defaults[Constants.UserDefaults.boardManTextPreviewScale] = 100
        defaults[Constants.UserDefaults.boardManImagePreviewScale] = 100
        defaults[Constants.UserDefaults.boardManMaskedItemIdentifiers] = [String]()
        defaults[Constants.UserDefaults.boardManHidePreviewForMaskedItems] = false
        defaults[Constants.UserDefaults.boardManHideTitleForMaskedItems] = false
        // Selection Clipboard is privacy-sensitive and opt-in by default.
        defaults[Constants.UserDefaults.boardManSelectionMemoryEnabled] = false
        defaults[Constants.UserDefaults.boardManCustomAccentOpacity] = 1.0
        defaults[Constants.UserDefaults.boardManCustomPanelOpacity] = 0.16
        defaults[Constants.UserDefaults.boardManCustomUsedOpacity] = 0.18
        defaults[Constants.Update.enableAutomaticCheck] = false
        defaults[Constants.Update.checkInterval] = 86400
        defaults[Constants.Beta.pastePlainText] = true
        defaults[Constants.Beta.pastePlainTextModifier] = 0
        defaults[Constants.Beta.deleteHistory] = false
        defaults[Constants.Beta.deleteHistoryModifier] = 0
        defaults[Constants.Beta.pasteAndDeleteHistory] = false
        defaults[Constants.Beta.pasteAndDeleteHistoryModifier] = 0
        defaults[Constants.Beta.observerScreenshot] = false
        let runtimeDefaults = AppEnvironment.current.defaults
        runtimeDefaults.register(defaults: defaults)
        if BoardManRuntimeEnvironment.isBenchmarkProfile() {
            runtimeDefaults.set(false, forKey: Constants.UserDefaults.loginItem)
            runtimeDefaults.set(true, forKey: Constants.UserDefaults.suppressAlertForLoginItem)
            runtimeDefaults.set(false, forKey: Constants.UserDefaults.collectCrashReport)
            runtimeDefaults.set(false, forKey: Constants.Update.enableAutomaticCheck)
        }
    }

    static func prepareDirectory(at path: String) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            return true
        }
        do {
            try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }

    static func deleteData(at path: String) {
        autoreleasepool {
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: path) else { return }
            try? fileManager.removeItem(atPath: path)
        }
    }

    @discardableResult
    static func archiveRootObjectAtomically(_ object: Any, to path: String) -> Bool {
        do {
            let archive = try NSKeyedArchiver.archivedData(withRootObject: object, requiringSecureCoding: false)
            try archive.write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            sendDiagnosticLog("Payload archive write failed: \(error.localizedDescription)")
            return false
        }
    }

    static func redactedDiagnosticMessage(
        _ message: String,
        fileManager: FileManager = .default
    ) -> String {
        let homePath = fileManager.homeDirectoryForCurrentUser.path
        var redacted = message.replacingOccurrences(of: homePath, with: "~")
        redacted = redacted
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return String(redacted.prefix(1_024))
    }

    static func sendDiagnosticLog(_ name: String) {
        guard AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.collectCrashReport) else { return }
        NSLog("Board-Man: %@", redactedDiagnosticMessage(name))
    }
}
