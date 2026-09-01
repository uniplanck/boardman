//
//  BoardManSelectionMemoryPhase0.swift
//  Board-Man
//
//  Architecture-spike primitives for Selection Memory. Nothing in this file is wired into
//  application startup yet; Phase 0 exists to prove capture and pasteboard safety first.
//

import AppKit
import ApplicationServices
import Foundation

struct BoardManSelectionCaptureCandidate: Equatable {
    let text: String
    let sourceApplicationName: String
    let sourceBundleIdentifier: String
}

enum BoardManSelectionCapturePolicy {
    static func canCapture(isExcludedApplication: Bool, subrole: String?) -> Bool {
        guard !isExcludedApplication else { return false }
        return subrole != (kAXSecureTextFieldSubrole as String)
    }
}

struct BoardManSelectionCaptureCoalescer {
    let stabilityInterval: TimeInterval
    let duplicateSuppressionInterval: TimeInterval

    private static let timestampComparisonEpsilon: TimeInterval = 1e-9
    private var pending: (candidate: BoardManSelectionCaptureCandidate, since: TimeInterval)?
    private var lastEmittedCandidate: BoardManSelectionCaptureCandidate?
    private var lastEmittedAt: TimeInterval?

    init(stabilityInterval: TimeInterval = 0.18,
         duplicateSuppressionInterval: TimeInterval = 1.0) {
        self.stabilityInterval = max(0, stabilityInterval)
        self.duplicateSuppressionInterval = max(0, duplicateSuppressionInterval)
    }

    mutating func observe(_ candidate: BoardManSelectionCaptureCandidate, at timestamp: TimeInterval) {
        if pending?.candidate == candidate {
            return
        }
        pending = (candidate, timestamp)
    }

    mutating func flush(at timestamp: TimeInterval) -> BoardManSelectionCaptureCandidate? {
        guard let pending,
              timestamp - pending.since + Self.timestampComparisonEpsilon >= stabilityInterval else {
            return nil
        }
        self.pending = nil

        if lastEmittedCandidate == pending.candidate,
           let lastEmittedAt,
           timestamp - lastEmittedAt <= duplicateSuppressionInterval + Self.timestampComparisonEpsilon {
            self.lastEmittedAt = timestamp
            return nil
        }

        lastEmittedCandidate = pending.candidate
        lastEmittedAt = timestamp
        return pending.candidate
    }

    mutating func reset() {
        pending = nil
        lastEmittedCandidate = nil
        lastEmittedAt = nil
    }
}

final class BoardManSelectionCaptureProbe {
    static let defaultMaximumCharacters = 100_000

    private let accessibilityService: AccessibilityService
    private let excludeAppService: ExcludeAppService

    init(accessibilityService: AccessibilityService = AppEnvironment.current.accessibilityService,
         excludeAppService: ExcludeAppService = AppEnvironment.current.excludeAppService) {
        self.accessibilityService = accessibilityService
        self.excludeAppService = excludeAppService
    }

    /// Reads the currently focused accessibility selection without touching `NSPasteboard.general`
    /// and without synthesizing Command-C. Unsupported, excluded, secure, empty, and oversized
    /// selections fail closed.
    func readFocusedSelection(maximumCharacters: Int = defaultMaximumCharacters) -> BoardManSelectionCaptureCandidate? {
        guard maximumCharacters > 0,
              accessibilityService.isAccessibilityEnabled(isPrompt: false) else {
            return nil
        }

        let isExcluded = excludeAppService.frontProcessIsExcludedApplication()
        guard let focusedElement = Self.focusedElement(),
              BoardManSelectionCapturePolicy.canCapture(
                  isExcludedApplication: isExcluded,
                  subrole: Self.stringAttribute(kAXSubroleAttribute as CFString, from: focusedElement)
              ),
              let selectedText = Self.stringAttribute(kAXSelectedTextAttribute as CFString, from: focusedElement),
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              selectedText.count <= maximumCharacters else {
            return nil
        }

        let source = excludeAppService.frontApplicationSearchMetadata()
        return BoardManSelectionCaptureCandidate(
            text: selectedText,
            sourceApplicationName: source?.name ?? "",
            sourceBundleIdentifier: source?.bundleIdentifier ?? ""
        )
    }

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }
}

enum BoardManTransientPasteboardRestoreResult: Equatable {
    case restored
    case skippedNewerClipboard
    case restoreFailed
    case notStaged
}

/// A bounded pasteboard transaction for the future dedicated Selection Memory paste shortcut.
/// It restores the previous clipboard only when the staged value is still current. If the user or
/// another app copied something newer in the meantime, that newer clipboard wins.
final class BoardManTransientPasteboardTransaction {
    private enum State {
        case ready
        case staged(changeCount: Int, fingerprint: Int)
        case finished
    }

    private let pasteboard: NSPasteboard
    private var state: State = .ready
    private var snapshotItems: [NSPasteboardItem] = []

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    @discardableResult
    func stage(text: String) -> Bool {
        guard case .ready = state else { return false }

        snapshotItems = Self.cloneItems(from: pasteboard)
        pasteboard.clearContents()

        let stagedItem = NSPasteboardItem()
        stagedItem.setString(text, forType: .string)
        guard pasteboard.writeObjects([stagedItem]) else {
            _ = restoreSnapshotUnconditionally()
            state = .finished
            return false
        }

        state = .staged(
            changeCount: pasteboard.changeCount,
            fingerprint: Self.fingerprint(of: pasteboard)
        )
        return true
    }

    func restoreIfUnchanged() -> BoardManTransientPasteboardRestoreResult {
        guard case .staged(let stagedChangeCount, let stagedFingerprint) = state else {
            return .notStaged
        }

        guard pasteboard.changeCount == stagedChangeCount,
              Self.fingerprint(of: pasteboard) == stagedFingerprint else {
            state = .finished
            return .skippedNewerClipboard
        }

        let restored = restoreSnapshotUnconditionally()
        state = .finished
        return restored ? .restored : .restoreFailed
    }

    private func restoreSnapshotUnconditionally() -> Bool {
        pasteboard.clearContents()
        guard !snapshotItems.isEmpty else { return true }
        return pasteboard.writeObjects(snapshotItems)
    }

    private static func cloneItems(from pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        return (pasteboard.pasteboardItems ?? []).map { source in
            let copy = NSPasteboardItem()
            for type in source.types {
                if let data = source.data(forType: type) {
                    copy.setData(data, forType: type)
                } else if let string = source.string(forType: type) {
                    copy.setString(string, forType: type)
                } else if let propertyList = source.propertyList(forType: type) {
                    copy.setPropertyList(propertyList, forType: type)
                }
            }
            return copy
        }
    }

    private static func fingerprint(of pasteboard: NSPasteboard) -> Int {
        var hasher = Hasher()
        let items = pasteboard.pasteboardItems ?? []
        hasher.combine(items.count)
        for item in items {
            for type in item.types.sorted(by: { $0.rawValue < $1.rawValue }) {
                hasher.combine(type.rawValue)
                if let data = item.data(forType: type) {
                    hasher.combine(data)
                } else if let string = item.string(forType: type) {
                    hasher.combine(string)
                } else if let propertyList = item.propertyList(forType: type) {
                    hasher.combine(String(describing: propertyList))
                }
            }
        }
        return hasher.finalize()
    }
}

// MARK: - Production Selection Clipboard

struct BoardManSelectionMemoryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let text: String
    let sourceApplicationName: String
    let sourceBundleIdentifier: String
    let capturedAt: Date

    init(
        id: UUID = UUID(),
        candidate: BoardManSelectionCaptureCandidate,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.text = candidate.text
        self.sourceApplicationName = candidate.sourceApplicationName
        self.sourceBundleIdentifier = candidate.sourceBundleIdentifier
        self.capturedAt = capturedAt
    }
}

@MainActor
final class BoardManSelectionMemoryStore {
    static let shared = BoardManSelectionMemoryStore()
    static let maximumItems = 100
    static let maximumTotalCharacters = 250_000

    private let fileURL: URL
    private let fileManager: FileManager
    private(set) var entries: [BoardManSelectionMemoryEntry]

    init(
        fileURL: URL = BoardManSelectionMemoryStore.defaultFileURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.entries = Self.load(from: fileURL)
        trimToBounds()
    }

    var latest: BoardManSelectionMemoryEntry? { entries.first }
    var count: Int { entries.count }

    @discardableResult
    func append(
        _ candidate: BoardManSelectionCaptureCandidate,
        capturedAt: Date = Date()
    ) -> BoardManSelectionMemoryEntry? {
        let text = candidate.text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        // Re-selecting the exact same source/text moves it to the front instead of filling history
        // with identical rows.
        entries.removeAll {
            $0.text == text && $0.sourceBundleIdentifier == candidate.sourceBundleIdentifier
        }
        let entry = BoardManSelectionMemoryEntry(candidate: candidate, capturedAt: capturedAt)
        entries.insert(entry, at: 0)
        trimToBounds()
        persist()
        return entry
    }

    func clear() {
        entries.removeAll(keepingCapacity: false)
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
        } catch {
            NSLog("Board-Man Selection Clipboard clear failed: %@", error.localizedDescription)
        }
    }

    private func trimToBounds() {
        if entries.count > Self.maximumItems {
            entries.removeLast(entries.count - Self.maximumItems)
        }
        var totalCharacters = entries.reduce(0) { $0 + $1.text.count }
        while entries.count > 1, totalCharacters > Self.maximumTotalCharacters {
            totalCharacters -= entries.removeLast().text.count
        }
    }

    private func persist() {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Board-Man Selection Clipboard persist failed: %@", error.localizedDescription)
        }
    }

    private static func load(from fileURL: URL) -> [BoardManSelectionMemoryEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([BoardManSelectionMemoryEntry].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.capturedAt > $1.capturedAt }
    }

    nonisolated private static func defaultFileURL() -> URL {
        if NSClassFromString("XCTestCase") != nil {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "Board-Man-SelectionClipboard-Tests-\(ProcessInfo.processInfo.processIdentifier)",
                    isDirectory: true
                )
                .appendingPathComponent("history.json", isDirectory: false)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Board-Man", isDirectory: true)
            .appendingPathComponent("SelectionClipboard", isDirectory: true)
            .appendingPathComponent("history.json", isDirectory: false)
    }
}

@MainActor
final class BoardManSelectionMemoryService {
    static let shared = BoardManSelectionMemoryService()
    static let pasteRestoreDelay: TimeInterval = 0.35

    private let defaults: UserDefaults
    private let store: BoardManSelectionMemoryStore
    private let readSelection: () -> BoardManSelectionCaptureCandidate?
    private let canUseFeature: () -> Bool
    private let pasteboard: NSPasteboard
    private let sendPaste: () -> Bool
    private let markPasteboardHandled: () -> Void

    private var mouseMonitor: Any?
    private var keyMonitor: Any?
    private var captureWorkItem: DispatchWorkItem?
    private var flushWorkItem: DispatchWorkItem?
    private var activePasteTransaction: BoardManTransientPasteboardTransaction?
    private var coalescer = BoardManSelectionCaptureCoalescer()

    init(
        defaults: UserDefaults = AppEnvironment.current.defaults,
        store: BoardManSelectionMemoryStore = .shared,
        pasteboard: NSPasteboard = .general,
        readSelection: (() -> BoardManSelectionCaptureCandidate?)? = nil,
        canUseFeature: (() -> Bool)? = nil,
        sendPaste: (() -> Bool)? = nil,
        markPasteboardHandled: (() -> Void)? = nil
    ) {
        self.defaults = defaults
        self.store = store
        self.pasteboard = pasteboard
        self.readSelection = readSelection ?? {
            BoardManSelectionCaptureProbe().readFocusedSelection()
        }
        self.canUseFeature = canUseFeature ?? {
            EntitlementGate.canUse(.selectionMemory)
        }
        self.sendPaste = sendPaste ?? {
            AppEnvironment.current.pasteService.sendShortcut(
                KeyCombo(key: .letterV, cocoaModifiers: .command)
            )
        }
        self.markPasteboardHandled = markPasteboardHandled ?? {
            AppEnvironment.current.clipService.markCurrentPasteboardChangeAsHandled()
        }
    }

    var isEnabled: Bool {
        defaults.bool(forKey: Constants.UserDefaults.boardManSelectionMemoryEnabled)
    }

    var isAvailable: Bool { canUseFeature() }
    var itemCount: Int { store.count }
    var latestEntry: BoardManSelectionMemoryEntry? { store.latest }

    func setEnabled(_ enabled: Bool) -> Bool {
        guard !enabled || canUseFeature() else { return false }
        defaults.set(enabled, forKey: Constants.UserDefaults.boardManSelectionMemoryEnabled)
        defaults.synchronize()
        refreshMonitoringState()
        return true
    }

    func refreshMonitoringState() {
        if isEnabled && canUseFeature() {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    func startMonitoring() {
        guard mouseMonitor == nil, keyMonitor == nil, isEnabled, canUseFeature() else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            DispatchQueue.main.async { self?.scheduleCapture() }
        }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyUp]) { [weak self] event in
            guard Self.shouldCaptureKeyboardSelection(event) else { return }
            DispatchQueue.main.async { self?.scheduleCapture() }
        }
        NSLog("Board-Man Selection Clipboard monitoring started")
    }

    func stopMonitoring() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        captureWorkItem?.cancel()
        flushWorkItem?.cancel()
        captureWorkItem = nil
        flushWorkItem = nil
        coalescer.reset()
    }

    func clearHistory() {
        store.clear()
    }

    @discardableResult
    func pasteLatest() -> Bool {
        guard canUseFeature() else {
            BoardManUpgradeRoute.presentFeatureLocked(.selectionMemory)
            return false
        }
        guard isEnabled, let latest = store.latest, activePasteTransaction == nil else {
            NSSound.beep()
            return false
        }

        let transaction = BoardManTransientPasteboardTransaction(pasteboard: pasteboard)
        guard transaction.stage(text: latest.text) else { return false }
        markPasteboardHandled()
        activePasteTransaction = transaction

        guard sendPaste() else {
            if transaction.restoreIfUnchanged() == .restored {
                markPasteboardHandled()
            }
            activePasteTransaction = nil
            return false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pasteRestoreDelay) { [weak self, weak transaction] in
            guard let self, let transaction else { return }
            let result = transaction.restoreIfUnchanged()
            if result == .restored {
                self.markPasteboardHandled()
            }
            if self.activePasteTransaction === transaction {
                self.activePasteTransaction = nil
            }
        }
        return true
    }

    func ingestForTesting(_ candidate: BoardManSelectionCaptureCandidate, at timestamp: TimeInterval) {
        coalescer.observe(candidate, at: timestamp)
        if let stable = coalescer.flush(at: timestamp + coalescer.stabilityInterval) {
            _ = store.append(stable)
        }
    }

    static func shouldCaptureKeyboardSelection(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.shift) { return true }
        // QWERTY key code 0 is A. Capture Command-A because it creates a selection without a mouse-up.
        return event.keyCode == 0 && event.modifierFlags.contains(.command)
    }

    private func scheduleCapture() {
        guard isEnabled, canUseFeature() else { return }
        captureWorkItem?.cancel()
        flushWorkItem?.cancel()

        let capture = DispatchWorkItem { [weak self] in
            guard let self, let candidate = self.readSelection() else { return }
            if candidate.sourceBundleIdentifier == Bundle.main.bundleIdentifier { return }
            let now = ProcessInfo.processInfo.systemUptime
            self.coalescer.observe(candidate, at: now)

            let flush = DispatchWorkItem { [weak self] in
                guard let self,
                      let stable = self.coalescer.flush(at: ProcessInfo.processInfo.systemUptime) else { return }
                if self.store.append(stable) != nil {
                    NSLog(
                        "Board-Man Selection Clipboard captured source=%@ count=%d",
                        stable.sourceBundleIdentifier,
                        self.store.count
                    )
                }
            }
            self.flushWorkItem = flush
            DispatchQueue.main.asyncAfter(
                deadline: .now() + self.coalescer.stabilityInterval,
                execute: flush
            )
        }
        captureWorkItem = capture
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: capture)
    }
}
