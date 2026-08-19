import Carbon
import Foundation
import Magnet
import Testing
@testable import Board_Man

@MainActor @Suite(.serialized)
final class HotKeyServiceTests {
    private let defaultsSuiteName = "BoardManHotKeyServiceTests"
    private lazy var defaults = UserDefaults(suiteName: defaultsSuiteName) ?? .standard

    init() {
        resetDefaults()
    }

    deinit {
        let cleanupDefaults = UserDefaults(suiteName: "BoardManHotKeyServiceTests") ?? .standard
        cleanupDefaults.removePersistentDomain(forName: "BoardManHotKeyServiceTests")
        cleanupDefaults.synchronize()
    }

    private func resetDefaults() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults.synchronize()
    }

    @Test
    func migrateDefaultSettings() throws {
        let service = HotKeyService(defaults: defaults)
        #expect(service.mainKeyCombo == nil)
        #expect(service.historyKeyCombo == nil)
        #expect(service.snippetKeyCombo == nil)

        #expect(defaults.bool(forKey: Constants.HotKey.migrateNewKeyCombo) == false)
        service.setupDefaultHotKeys()
        #expect(defaults.bool(forKey: Constants.HotKey.migrateNewKeyCombo) == true)

        let mainKeyCombo = try #require(service.mainKeyCombo)
        #expect(mainKeyCombo.QWERTYKeyCode == 9)
        #expect(mainKeyCombo.modifiers == (Int(cmdKey) | Int(optionKey)))
        #expect(mainKeyCombo.doubledModifiers == false)
        #expect(mainKeyCombo.keyEquivalent.uppercased() == "V")

        let historyKeyCombo = try #require(service.historyKeyCombo)
        #expect(historyKeyCombo.QWERTYKeyCode == 9)
        #expect(historyKeyCombo.modifiers == 4352)
        #expect(historyKeyCombo.doubledModifiers == false)
        #expect(historyKeyCombo.keyEquivalent.uppercased() == "V")

        let snippetKeyCombo = try #require(service.snippetKeyCombo)
        #expect(snippetKeyCombo.QWERTYKeyCode == 11)
        #expect(snippetKeyCombo.modifiers == 768)
        #expect(snippetKeyCombo.doubledModifiers == false)
        #expect(snippetKeyCombo.keyEquivalent.uppercased() == "B")
    }

    @Test
    func migrateCustomizeSettings() throws {
        let service = HotKeyService(defaults: defaults)
        #expect(service.mainKeyCombo == nil)
        #expect(service.historyKeyCombo == nil)
        #expect(service.snippetKeyCombo == nil)

        let defaultKeyCombos: [String: Any] = [Constants.Menu.clip: ["keyCode": 0, "modifiers": 4352],
                                               Constants.Menu.history: ["keyCode": 9, "modifiers": 768],
                                               Constants.Menu.snippet: ["keyCode": 11, "modifiers": 4352]]
        defaults.register(defaults: [Constants.UserDefaults.hotKeys: defaultKeyCombos])
        defaults.synchronize()

        #expect(defaults.bool(forKey: Constants.HotKey.migrateNewKeyCombo) == false)
        service.setupDefaultHotKeys()
        #expect(defaults.bool(forKey: Constants.HotKey.migrateNewKeyCombo) == true)

        let mainKeyCombo = try #require(service.mainKeyCombo)
        #expect(mainKeyCombo.QWERTYKeyCode == 0)
        #expect(mainKeyCombo.modifiers == 4352)
        #expect(mainKeyCombo.doubledModifiers == false)
        #expect(mainKeyCombo.keyEquivalent.uppercased() == "A")

        let historyKeyCombo = try #require(service.historyKeyCombo)
        #expect(historyKeyCombo.QWERTYKeyCode == 9)
        #expect(historyKeyCombo.modifiers == 768)
        #expect(historyKeyCombo.doubledModifiers == false)
        #expect(historyKeyCombo.keyEquivalent.uppercased() == "V")

        let snippetKeyCombo = try #require(service.snippetKeyCombo)
        #expect(snippetKeyCombo.QWERTYKeyCode == 11)
        #expect(snippetKeyCombo.modifiers == 4352)
        #expect(snippetKeyCombo.doubledModifiers == false)
        #expect(snippetKeyCombo.keyEquivalent.uppercased() == "B")
    }

    @Test
    func saveKeyCombos() throws {
        defaults.set(true, forKey: Constants.HotKey.migrateNewKeyCombo)

        let service = HotKeyService(defaults: defaults)
        #expect(service.mainKeyCombo == nil)
        #expect(service.historyKeyCombo == nil)
        #expect(service.snippetKeyCombo == nil)

        #expect(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.mainKeyCombo) == nil)
        #expect(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.historyKeyCombo) == nil)
        #expect(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.snippetKeyCombo) == nil)

        service.setupDefaultHotKeys()
        let restoredMainKeyCombo = try #require(service.mainKeyCombo)
        #expect(restoredMainKeyCombo.QWERTYKeyCode == 9)
        #expect(restoredMainKeyCombo.modifiers == (Int(cmdKey) | Int(optionKey)))
        #expect(restoredMainKeyCombo.doubledModifiers == false)
        #expect(service.historyKeyCombo == nil)
        #expect(service.snippetKeyCombo == nil)
        #expect(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.mainKeyCombo) != nil)

        let mainKeyCombo = try #require(KeyCombo(QWERTYKeyCode: 9, carbonModifiers: 768))
        let historyKeyCombo = try #require(KeyCombo(doubledCocoaModifiers: .command))
        let snippetKeyCombo = try #require(KeyCombo(QWERTYKeyCode: 0, cocoaModifiers: .shift))

        service.change(with: .main, keyCombo: mainKeyCombo)
        service.change(with: .history, keyCombo: historyKeyCombo)
        service.change(with: .snippet, keyCombo: snippetKeyCombo)

        let savedMainKeyCombo = try #require(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.mainKeyCombo))
        let savedHistoryKeyCombo = try #require(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.historyKeyCombo))
        let savedSnippetKeyCombo = try #require(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.snippetKeyCombo))

        #expect(savedMainKeyCombo.QWERTYKeyCode == 9)
        #expect(savedMainKeyCombo.modifiers == 768)
        #expect(savedMainKeyCombo.doubledModifiers == false)
        #expect(savedMainKeyCombo.keyEquivalent.uppercased() == "V")

        #expect(savedHistoryKeyCombo.QWERTYKeyCode == 0)
        #expect(savedHistoryKeyCombo.modifiers == cmdKey)
        #expect(savedHistoryKeyCombo.doubledModifiers == true)
        #expect(savedHistoryKeyCombo.keyEquivalent.uppercased() == "")

        #expect(savedSnippetKeyCombo.QWERTYKeyCode == 0)
        #expect(savedSnippetKeyCombo.modifiers == shiftKey)
        #expect(savedSnippetKeyCombo.doubledModifiers == false)
        #expect(savedSnippetKeyCombo.keyEquivalent.uppercased() == "A")

        service.change(with: .main, keyCombo: nil)
        #expect(service.mainKeyCombo == nil)
        #expect(defaults.archiveDataForKey(KeyCombo.self, key: Constants.HotKey.mainKeyCombo) == nil)
    }

    @Test
    func preservesCurrentShortcutProfileAcrossRelaunchWhenMainIsUnassigned() throws {
        defaults.set(true, forKey: Constants.HotKey.migrateNewKeyCombo)
        defaults.set(true, forKey: Constants.HotKey.migrateOpenBoardManCommandOptionV)

        let history = try #require(KeyCombo(
            QWERTYKeyCode: 9,
            carbonModifiers: Int(cmdKey) | Int(optionKey)
        ))
        let snippet = try #require(KeyCombo(
            QWERTYKeyCode: 11,
            carbonModifiers: Int(cmdKey) | Int(shiftKey)
        ))
        let quick = try #require(KeyCombo(
            QWERTYKeyCode: 8,
            carbonModifiers: Int(cmdKey) | Int(optionKey)
        ))
        defaults.setArchiveData(history, forKey: Constants.HotKey.historyKeyCombo)
        defaults.setArchiveData(snippet, forKey: Constants.HotKey.snippetKeyCombo)
        defaults.setArchiveData(quick, forKey: Constants.HotKey.quickModeKeyCombo)

        let firstLaunch = HotKeyService(defaults: defaults)
        firstLaunch.setupDefaultHotKeys()
        #expect(firstLaunch.mainKeyCombo == nil)
        #expect(firstLaunch.historyKeyCombo == history)
        #expect(firstLaunch.snippetKeyCombo == snippet)
        #expect(firstLaunch.quickModeKeyCombo == quick)
        #expect(defaults.bool(forKey: Constants.HotKey.mainKeyComboExplicitlyCleared))

        let secondLaunch = HotKeyService(defaults: defaults)
        secondLaunch.setupDefaultHotKeys()
        #expect(secondLaunch.mainKeyCombo == nil)
        #expect(secondLaunch.historyKeyCombo == history)
        #expect(secondLaunch.snippetKeyCombo == snippet)
        #expect(secondLaunch.quickModeKeyCombo == quick)
    }

    @Test
    func clearingMainShortcutPersistsAsAnIntentionalUnassignedState() throws {
        defaults.set(true, forKey: Constants.HotKey.migrateNewKeyCombo)
        defaults.set(true, forKey: Constants.HotKey.migrateOpenBoardManCommandOptionV)
        defaults.set(true, forKey: Constants.HotKey.migrateExplicitlyClearedMainKeyCombo)
        let initial = try #require(KeyCombo(
            QWERTYKeyCode: 9,
            carbonModifiers: Int(cmdKey) | Int(optionKey)
        ))
        defaults.setArchiveData(initial, forKey: Constants.HotKey.mainKeyCombo)

        let service = HotKeyService(defaults: defaults)
        service.setupDefaultHotKeys()
        #expect(service.mainKeyCombo == initial)
        service.change(with: .main, keyCombo: nil)
        #expect(defaults.bool(forKey: Constants.HotKey.mainKeyComboExplicitlyCleared))

        let relaunched = HotKeyService(defaults: defaults)
        relaunched.setupDefaultHotKeys()
        #expect(relaunched.mainKeyCombo == nil)
    }

    @Test
    func hotKeyRegistrationRetryBackoffIsBoundedAndFast() {
        #expect(HotKeyService.registrationRetryDelays == [0.20, 0.60, 1.40, 3.00])
    }

    @Test
    func unarchiveSavedKeyCombos() throws {
        defaults.set(true, forKey: Constants.HotKey.migrateNewKeyCombo)
        defaults.set(true, forKey: Constants.HotKey.migrateOpenBoardManCommandOptionV)

        let mainKeyCombo = try #require(KeyCombo(QWERTYKeyCode: 9, carbonModifiers: 768))
        let historyKeyCombo = try #require(KeyCombo(doubledCocoaModifiers: .command))
        let snippetKeyCombo = try #require(KeyCombo(QWERTYKeyCode: 0, cocoaModifiers: .shift))

        defaults.setArchiveData(mainKeyCombo, forKey: Constants.HotKey.mainKeyCombo)
        defaults.setArchiveData(historyKeyCombo, forKey: Constants.HotKey.historyKeyCombo)
        defaults.setArchiveData(snippetKeyCombo, forKey: Constants.HotKey.snippetKeyCombo)

        let service = HotKeyService(defaults: defaults)
        #expect(service.mainKeyCombo == nil)
        #expect(service.historyKeyCombo == nil)
        #expect(service.snippetKeyCombo == nil)

        service.setupDefaultHotKeys()

        let savedMainKeyCombo = try #require(service.mainKeyCombo)
        #expect(savedMainKeyCombo.QWERTYKeyCode == 9)
        #expect(savedMainKeyCombo.modifiers == 768)
        #expect(savedMainKeyCombo.doubledModifiers == false)
        #expect(savedMainKeyCombo.keyEquivalent.uppercased() == "V")

        let savedHistoryKeyCombo = try #require(service.historyKeyCombo)
        #expect(savedHistoryKeyCombo.QWERTYKeyCode == 0)
        #expect(savedHistoryKeyCombo.modifiers == cmdKey)
        #expect(savedHistoryKeyCombo.doubledModifiers == true)
        #expect(savedHistoryKeyCombo.keyEquivalent.uppercased() == "")

        let savedSnippetKeyCombo = try #require(service.snippetKeyCombo)
        #expect(savedSnippetKeyCombo.QWERTYKeyCode == 0)
        #expect(savedSnippetKeyCombo.modifiers == shiftKey)
        #expect(savedSnippetKeyCombo.doubledModifiers == false)
        #expect(savedSnippetKeyCombo.keyEquivalent.uppercased() == "A")
    }

    @Test
    func migratesLegacyDefaultMainShortcutToCommandOptionV() throws {
        defaults.set(true, forKey: Constants.HotKey.migrateNewKeyCombo)
        let legacy = try #require(KeyCombo(
            QWERTYKeyCode: 9,
            carbonModifiers: Int(cmdKey) | Int(shiftKey)
        ))
        defaults.setArchiveData(legacy, forKey: Constants.HotKey.mainKeyCombo)

        let service = HotKeyService(defaults: defaults)
        service.setupDefaultHotKeys()

        let migrated = try #require(service.mainKeyCombo)
        #expect(migrated.QWERTYKeyCode == 9)
        #expect(migrated.modifiers == (Int(cmdKey) | Int(optionKey)))
        #expect(defaults.bool(forKey: Constants.HotKey.migrateOpenBoardManCommandOptionV))
    }

    @Test
    func duplicateMainHotKeyCallbacksAreDebounced() {
        #expect(HotKeyService.shouldAcceptMainHotKeyInvocation(now: 10.0, last: 0))
        #expect(!HotKeyService.shouldAcceptMainHotKeyInvocation(now: 10.20, last: 10.0))
        #expect(!HotKeyService.shouldAcceptMainHotKeyInvocation(now: 10.75, last: 10.0))
        #expect(HotKeyService.shouldAcceptMainHotKeyInvocation(now: 10.76, last: 10.0))
    }

    @Test
    func systemRuntimeSideEffectsAreDisabledDuringXCTest() {
        let testEnvironment = [
            "XCTestConfigurationFilePath": "/tmp/Board-Man.xctestconfiguration"
        ]
        #expect(!HotKeyService.shouldRegisterSystemHotKeys(environment: testEnvironment))
        #expect(!AppDelegate.shouldStartRuntimeServices(environment: testEnvironment))
        #expect(!HotKeyService.shouldRegisterSystemHotKeys(
            environment: ["SWIFT_TESTING_ENABLED": "1"],
            arguments: [],
            bundlePaths: [],
            hasXCTestCase: false
        ))
        #expect(!HotKeyService.shouldRegisterSystemHotKeys(
            environment: [:],
            arguments: ["/tmp/Board-Man.xctest"],
            bundlePaths: [],
            hasXCTestCase: false
        ))
        #expect(HotKeyService.shouldRegisterSystemHotKeys(
            environment: [:],
            arguments: [],
            bundlePaths: [],
            hasXCTestCase: false
        ))
        #expect(AppDelegate.shouldStartRuntimeServices(
            environment: [:],
            arguments: [],
            bundlePaths: [],
            hasXCTestCase: false
        ))
    }

    @Test
    func defaultKeyCombos() {
        let keyCombos = HotKeyService.defaultKeyCombos
        let mainCombos = keyCombos[Constants.Menu.clip] as? [String: Int]
        let historyCombos = keyCombos[Constants.Menu.history] as? [String: Int]
        let snippetCombos = keyCombos[Constants.Menu.snippet] as? [String: Int]

        #expect(mainCombos?["keyCode"] == 9)
        #expect(mainCombos?["modifiers"] == (Int(cmdKey) | Int(optionKey)))

        #expect(historyCombos?["keyCode"] == 9)
        #expect(historyCombos?["modifiers"] == 4352)

        #expect(snippetCombos?["keyCode"] == 11)
        #expect(snippetCombos?["modifiers"] == 768)
    }

    @Test
    func addAndRemoveClearHistoryHotkey() throws {
        let service = HotKeyService(defaults: defaults)

        #expect(service.clearHistoryKeyCombo == nil)

        let keyCombo = try #require(KeyCombo(QWERTYKeyCode: 10, carbonModifiers: cmdKey))
        service.changeClearHistoryKeyCombo(keyCombo)

        #expect(service.clearHistoryKeyCombo != nil)
        #expect(service.clearHistoryKeyCombo == keyCombo)

        let savedData = try #require(defaults.object(forKey: Constants.HotKey.clearHistoryKeyCombo) as? Data)
        let savedKeyCombo = try #require(NSKeyedUnarchiver.unarchiveObject(with: savedData) as? KeyCombo)
        #expect(savedKeyCombo == keyCombo)

        service.changeClearHistoryKeyCombo(nil)
        #expect(service.clearHistoryKeyCombo == nil)
    }

    @Test
    func setAndClearSnippetFolderHotkey() throws {
        let service = HotKeyService(defaults: defaults)
        let keyCombo = try #require(KeyCombo(QWERTYKeyCode: 1, carbonModifiers: cmdKey))
        let folderIdentifier = "folder-1"

        #expect(service.keyComboForSnippetFolder(identifier: folderIdentifier) == nil)

        service.setSnippetKeyCombo(keyCombo, forFolder: folderIdentifier)
        #expect(service.keyComboForSnippetFolder(identifier: folderIdentifier) == keyCombo)

        let savedData = try #require(defaults.object(forKey: Constants.HotKey.folderKeyCombos) as? Data)
        let savedCombos = try #require(NSKeyedUnarchiver.unarchiveObject(with: savedData) as? [String: KeyCombo])
        #expect(savedCombos[folderIdentifier] == keyCombo)

        service.clearSnippetKeyCombo(forFolder: folderIdentifier)
        #expect(service.keyComboForSnippetFolder(identifier: folderIdentifier) == nil)
    }
}
