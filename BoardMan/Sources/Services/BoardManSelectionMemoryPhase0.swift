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
