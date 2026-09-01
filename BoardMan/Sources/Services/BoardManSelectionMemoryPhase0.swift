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
    static let maximumStackItems = 50

    private let fileURL: URL
    private let stackFileURL: URL
    private let fileManager: FileManager
    private(set) var entries: [BoardManSelectionMemoryEntry]
    private(set) var stackEntries: [BoardManSelectionMemoryEntry]

    init(
        fileURL: URL = BoardManSelectionMemoryStore.defaultFileURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.stackFileURL = fileURL.deletingLastPathComponent().appendingPathComponent("stack.json", isDirectory: false)
        self.fileManager = fileManager
        self.entries = Self.load(from: fileURL, newestFirst: true)
        self.stackEntries = Self.load(from: stackFileURL, newestFirst: false)
        trimToBounds()
        trimStackToBounds()
    }

    var latest: BoardManSelectionMemoryEntry? { entries.first }
    var count: Int { entries.count }
    var stackCount: Int { stackEntries.count }

    @discardableResult
    func append(
        _ candidate: BoardManSelectionCaptureCandidate,
        capturedAt: Date = Date()
    ) -> BoardManSelectionMemoryEntry? {
        let text = candidate.text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        entries.removeAll {
            $0.text == text && $0.sourceBundleIdentifier == candidate.sourceBundleIdentifier
        }
        let entry = BoardManSelectionMemoryEntry(candidate: candidate, capturedAt: capturedAt)
        entries.insert(entry, at: 0)
        trimToBounds()
        persistHistory()
        return entry
    }

    @discardableResult
    func appendToStack(
        _ candidate: BoardManSelectionCaptureCandidate,
        capturedAt: Date = Date()
    ) -> BoardManSelectionMemoryEntry? {
        guard !candidate.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let entry = BoardManSelectionMemoryEntry(candidate: candidate, capturedAt: capturedAt)
        stackEntries.append(entry)
        trimStackToBounds()
        persistStack()
        return entry
    }

    func clear() {
        entries.removeAll(keepingCapacity: false)
        removeFileIfPresent(fileURL, label: "history")
    }

    func clearStack() {
        stackEntries.removeAll(keepingCapacity: false)
        removeFileIfPresent(stackFileURL, label: "stack")
    }

    private func trimToBounds() {
        if entries.count > Self.maximumItems {
            entries.removeLast(entries.count - Self.maximumItems)
        }
        trimCharacterBudget(&entries, removeFromFront: false)
    }

    private func trimStackToBounds() {
        if stackEntries.count > Self.maximumStackItems {
            stackEntries.removeFirst(stackEntries.count - Self.maximumStackItems)
        }
        trimCharacterBudget(&stackEntries, removeFromFront: true)
    }

    private func trimCharacterBudget(
        _ values: inout [BoardManSelectionMemoryEntry],
        removeFromFront: Bool
    ) {
        var totalCharacters = values.reduce(0) { $0 + $1.text.count }
        while values.count > 1, totalCharacters > Self.maximumTotalCharacters {
            let removed = removeFromFront ? values.removeFirst() : values.removeLast()
            totalCharacters -= removed.text.count
        }
    }

    private func persistHistory() {
        persist(entries, to: fileURL, label: "history")
    }

    private func persistStack() {
        persist(stackEntries, to: stackFileURL, label: "stack")
    }

    private func persist(_ values: [BoardManSelectionMemoryEntry], to url: URL, label: String) {
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(values)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Board-Man Selection Clipboard %@ persist failed: %@", label, error.localizedDescription)
        }
    }

    private func removeFileIfPresent(_ url: URL, label: String) {
        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        } catch {
            NSLog("Board-Man Selection Clipboard %@ clear failed: %@", label, error.localizedDescription)
        }
    }

    private static func load(from fileURL: URL, newestFirst: Bool) -> [BoardManSelectionMemoryEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([BoardManSelectionMemoryEntry].self, from: data) else {
            return []
        }
        return decoded.sorted {
            newestFirst ? $0.capturedAt > $1.capturedAt : $0.capturedAt < $1.capturedAt
        }
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

    var isHarvestEnabled: Bool {
        defaults.bool(forKey: Constants.UserDefaults.boardManSelectionHarvestModeEnabled)
    }

    var isAvailable: Bool { canUseFeature() }
    var itemCount: Int { store.count }
    var stackCount: Int { store.stackCount }
    var latestEntry: BoardManSelectionMemoryEntry? { store.latest }
    var historyEntries: [BoardManSelectionMemoryEntry] { store.entries }
    var stackEntries: [BoardManSelectionMemoryEntry] { store.stackEntries }

    func setEnabled(_ enabled: Bool) -> Bool {
        guard !enabled || canUseFeature() else { return false }
        defaults.set(enabled, forKey: Constants.UserDefaults.boardManSelectionMemoryEnabled)
        if !enabled {
            defaults.set(false, forKey: Constants.UserDefaults.boardManSelectionHarvestModeEnabled)
        }
        defaults.synchronize()
        refreshMonitoringState()
        return true
    }

    func setHarvestEnabled(_ enabled: Bool) -> Bool {
        guard !enabled || (isEnabled && canUseFeature()) else { return false }
        defaults.set(enabled, forKey: Constants.UserDefaults.boardManSelectionHarvestModeEnabled)
        defaults.synchronize()
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

    func clearStack() {
        store.clearStack()
    }

    func showPicker() {
        guard canUseFeature(), isEnabled else {
            NSSound.beep()
            return
        }
        BoardManSelectionMemoryPickerController.shared.show(service: self)
    }

    @discardableResult
    func pasteLatest() -> Bool {
        guard let latest = store.latest else {
            NSSound.beep()
            return false
        }
        return paste(entry: latest)
    }

    @discardableResult
    func paste(entry: BoardManSelectionMemoryEntry) -> Bool {
        paste(text: entry.text)
    }

    @discardableResult
    func pasteStack(separator: String = "\n") -> Bool {
        let text = store.stackEntries.map(\.text).joined(separator: separator)
        guard !text.isEmpty else {
            NSSound.beep()
            return false
        }
        return paste(text: text)
    }

    func ingestForTesting(_ candidate: BoardManSelectionCaptureCandidate, at timestamp: TimeInterval) {
        coalescer.observe(candidate, at: timestamp)
        if let stable = coalescer.flush(at: timestamp + coalescer.stabilityInterval) {
            record(stable)
        }
    }

    static func shouldCaptureKeyboardSelection(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.shift) { return true }
        return event.keyCode == 0 && event.modifierFlags.contains(.command)
    }

    @discardableResult
    private func paste(text: String) -> Bool {
        guard canUseFeature() else {
            BoardManUpgradeRoute.presentFeatureLocked(.selectionMemory)
            return false
        }
        guard isEnabled, activePasteTransaction == nil else {
            NSSound.beep()
            return false
        }

        let transaction = BoardManTransientPasteboardTransaction(pasteboard: pasteboard)
        guard transaction.stage(text: text) else { return false }
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

    private func record(_ candidate: BoardManSelectionCaptureCandidate) {
        guard store.append(candidate) != nil else { return }
        if isHarvestEnabled {
            _ = store.appendToStack(candidate)
        }
        NSLog(
            "Board-Man Selection Clipboard captured source=%@ count=%d stack=%d",
            candidate.sourceBundleIdentifier,
            store.count,
            store.stackCount
        )
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
                self.record(stable)
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

@MainActor
private final class BoardManSelectionMemoryPickerTableView: NSTableView {
    var onConfirm: (() -> Void)?
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            onConfirm?()
        case 53:
            onEscape?()
        default:
            super.keyDown(with: event)
        }
    }
}

@MainActor
final class BoardManSelectionMemoryPickerController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = BoardManSelectionMemoryPickerController()

    private weak var service: BoardManSelectionMemoryService?
    private var targetApplication: NSRunningApplication?
    private var targetFocus: PasteFocusTarget?
    private var panel: NSPanel?
    private let modeControl = NSSegmentedControl(labels: ["History", "Stack"], trackingMode: .selectOne, target: nil, action: nil)
    private let harvestButton = NSButton(checkboxWithTitle: "Harvest Mode", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let tableView = BoardManSelectionMemoryPickerTableView(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)
    private let pasteButton = NSButton(title: "Paste", target: nil, action: nil)
    private let pasteStackButton = NSButton(title: "Paste Stack", target: nil, action: nil)
    private let clearStackButton = NSButton(title: "Clear Stack", target: nil, action: nil)

    private override init() {
        super.init()
        configureControls()
    }

    func show(service: BoardManSelectionMemoryService) {
        self.service = service
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
            targetApplication = frontmost
            targetFocus = PasteTargetVerifier.focusTarget(for: frontmost)
        } else {
            targetApplication = nil
            targetFocus = nil
        }
        let panel = ensurePanel()
        reload()
        position(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        if tableView.numberOfRows > 0 {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        panel.makeFirstResponder(tableView)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        displayedEntries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard displayedEntries.indices.contains(row) else { return nil }
        let entry = displayedEntries[row]
        let cell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 52))

        let text = NSTextField(wrappingLabelWithString: entry.text)
        text.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        text.lineBreakMode = .byTruncatingTail
        text.maximumNumberOfLines = 2
        text.frame = NSRect(x: 10, y: 21, width: max(120, tableView.bounds.width - 20), height: 28)
        cell.addSubview(text)

        let sourceName = entry.sourceApplicationName.isEmpty ? boardManText("Unknown App") : entry.sourceApplicationName
        let source = NSTextField(labelWithString: sourceName)
        source.font = NSFont.systemFont(ofSize: 10)
        source.textColor = .secondaryLabelColor
        source.lineBreakMode = .byTruncatingTail
        source.frame = NSRect(x: 10, y: 4, width: max(120, tableView.bounds.width - 20), height: 15)
        cell.addSubview(source)
        return cell
    }

    private var displayedEntries: [BoardManSelectionMemoryEntry] {
        guard let service else { return [] }
        if modeControl.selectedSegment == 1 {
            return Array(service.stackEntries.reversed())
        }
        return service.historyEntries
    }

    private func configureControls() {
        modeControl.selectedSegment = 0
        modeControl.target = self
        modeControl.action = #selector(modeChanged(_:))

        harvestButton.target = self
        harvestButton.action = #selector(harvestChanged(_:))
        harvestButton.font = NSFont.systemFont(ofSize: 11)

        statusLabel.font = NSFont.systemFont(ofSize: 10.5)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SelectionMemory"))
        column.title = ""
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 54
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(pasteSelected(_:))
        tableView.onConfirm = { [weak self] in self?.pasteSelected(nil) }
        tableView.onEscape = { [weak self] in self?.panel?.orderOut(nil) }

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        pasteButton.target = self
        pasteButton.action = #selector(pasteSelected(_:))
        pasteStackButton.target = self
        pasteStackButton.action = #selector(pasteStack(_:))
        clearStackButton.target = self
        clearStackButton.action = #selector(clearStack(_:))
        [pasteButton, pasteStackButton, clearStackButton].forEach {
            $0.bezelStyle = .rounded
            $0.font = NSFont.systemFont(ofSize: 11)
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let frame = NSRect(x: 0, y: 0, width: 580, height: 440)
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = boardManText("Selection Clipboard")
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 440, height: 320)
        panel.isReleasedWhenClosed = false

        let content = NSView(frame: frame)
        panel.contentView = content

        modeControl.frame = NSRect(x: 16, y: frame.height - 46, width: 188, height: 28)
        modeControl.autoresizingMask = [.minYMargin]
        content.addSubview(modeControl)

        harvestButton.frame = NSRect(x: 222, y: frame.height - 44, width: 150, height: 22)
        harvestButton.autoresizingMask = [.minYMargin]
        content.addSubview(harvestButton)

        statusLabel.frame = NSRect(x: 380, y: frame.height - 43, width: 184, height: 18)
        statusLabel.alignment = .right
        statusLabel.autoresizingMask = [.minXMargin, .minYMargin]
        content.addSubview(statusLabel)

        scrollView.frame = NSRect(x: 16, y: 56, width: frame.width - 32, height: frame.height - 112)
        scrollView.autoresizingMask = [.width, .height]
        content.addSubview(scrollView)

        pasteButton.frame = NSRect(x: 16, y: 16, width: 92, height: 28)
        pasteButton.autoresizingMask = [.maxXMargin, .maxYMargin]
        content.addSubview(pasteButton)

        pasteStackButton.frame = NSRect(x: 116, y: 16, width: 108, height: 28)
        pasteStackButton.autoresizingMask = [.maxXMargin, .maxYMargin]
        content.addSubview(pasteStackButton)

        clearStackButton.frame = NSRect(x: 232, y: 16, width: 100, height: 28)
        clearStackButton.autoresizingMask = [.maxXMargin, .maxYMargin]
        content.addSubview(clearStackButton)

        self.panel = panel
        return panel
    }

    private func reload() {
        guard let service else { return }
        harvestButton.state = service.isHarvestEnabled ? .on : .off
        let modeName = modeControl.selectedSegment == 1 ? boardManText("Stack") : boardManText("History")
        statusLabel.stringValue = "\(modeName) · \(displayedEntries.count)"
        pasteStackButton.isEnabled = service.stackCount > 0
        clearStackButton.isEnabled = service.stackCount > 0
        tableView.reloadData()
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            panel.center()
            return
        }
        let origin = NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.midY - panel.frame.height / 2
        )
        panel.setFrameOrigin(origin)
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        reload()
        if tableView.numberOfRows > 0 {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    @objc private func harvestChanged(_ sender: NSButton) {
        guard let service else { return }
        if !service.setHarvestEnabled(sender.state == .on) {
            sender.state = .off
            NSSound.beep()
        }
        reload()
    }

    @objc private func pasteSelected(_ sender: Any?) {
        guard let service else { return }
        let row = tableView.selectedRow
        guard displayedEntries.indices.contains(row) else {
            NSSound.beep()
            return
        }
        let entry = displayedEntries[row]
        pasteIntoCapturedTarget { service.paste(entry: entry) }
    }

    @objc private func pasteStack(_ sender: Any?) {
        guard let service else { return }
        pasteIntoCapturedTarget { service.pasteStack() }
    }

    private func pasteIntoCapturedTarget(_ paste: @escaping () -> Bool) {
        guard let targetApplication, !targetApplication.isTerminated else {
            NSSound.beep()
            return
        }
        panel?.orderOut(nil)
        targetApplication.activate(options: [.activateIgnoringOtherApps])
        if let targetFocus {
            _ = PasteTargetVerifier.restoreFocus(to: targetFocus)
        }
        let delay = BoardManPanelPasteCoordinator.pasteTargetSettleDelay(
            bundleIdentifier: targetApplication.bundleIdentifier
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if !paste() {
                NSSound.beep()
            }
        }
    }

    @objc private func clearStack(_ sender: Any?) {
        service?.clearStack()
        reload()
    }
}
