//
//  BoardManSelectionMemoryStore.swift
//  Board-Man
//
//  Persistent Selection Clipboard entry model and bounded local store.
//

import Foundation

extension Notification.Name {
    static let boardManSelectionMemoryDidChange = Notification.Name("BoardManSelectionMemoryDidChange")
}

enum BoardManSelectionMetadataPosition: String, CaseIterable {
    case right = "Right"
    case below = "Below"

    static func allowed(_ value: String?) -> BoardManSelectionMetadataPosition {
        allCases.first(where: { $0.rawValue.caseInsensitiveCompare(value ?? "") == .orderedSame }) ?? .right
    }

    var timestampPosition: BoardManTimestampPosition {
        self == .right ? .right : .below
    }
}

struct BoardManSelectionMemoryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let text: String
    let sourceApplicationName: String
    let sourceBundleIdentifier: String
    let capturedAt: Date
    let pasteCount: Int

    init(
        id: UUID = UUID(),
        candidate: BoardManSelectionCaptureCandidate,
        capturedAt: Date = Date(),
        pasteCount: Int = 0
    ) {
        self.id = id
        self.text = candidate.text
        self.sourceApplicationName = candidate.sourceApplicationName
        self.sourceBundleIdentifier = candidate.sourceBundleIdentifier
        self.capturedAt = capturedAt
        self.pasteCount = max(0, pasteCount)
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, sourceApplicationName, sourceBundleIdentifier, capturedAt, pasteCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        sourceApplicationName = try container.decode(String.self, forKey: .sourceApplicationName)
        sourceBundleIdentifier = try container.decode(String.self, forKey: .sourceBundleIdentifier)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        pasteCount = max(0, try container.decodeIfPresent(Int.self, forKey: .pasteCount) ?? 0)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(sourceApplicationName, forKey: .sourceApplicationName)
        try container.encode(sourceBundleIdentifier, forKey: .sourceBundleIdentifier)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encode(pasteCount, forKey: .pasteCount)
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

    @discardableResult
    func update(identifier: String, text: String) -> Bool {
        guard let entryIdentifier = UUID(uuidString: identifier) else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        func updatedEntry(from entry: BoardManSelectionMemoryEntry) -> BoardManSelectionMemoryEntry {
            BoardManSelectionMemoryEntry(
                id: entry.id,
                candidate: BoardManSelectionCaptureCandidate(
                    text: text,
                    sourceApplicationName: entry.sourceApplicationName,
                    sourceBundleIdentifier: entry.sourceBundleIdentifier
                ),
                capturedAt: entry.capturedAt,
                pasteCount: entry.pasteCount
            )
        }

        if let index = entries.firstIndex(where: { $0.id == entryIdentifier }) {
            entries[index] = updatedEntry(from: entries[index])
            trimToBounds()
            persistHistory()
            return true
        }
        if let index = stackEntries.firstIndex(where: { $0.id == entryIdentifier }) {
            stackEntries[index] = updatedEntry(from: stackEntries[index])
            trimStackToBounds()
            persistStack()
            return true
        }
        return false
    }

    @discardableResult
    func markUsed(identifier: String) -> Bool {
        guard let entryIdentifier = UUID(uuidString: identifier) else { return false }

        func usedEntry(from entry: BoardManSelectionMemoryEntry) -> BoardManSelectionMemoryEntry {
            BoardManSelectionMemoryEntry(
                id: entry.id,
                candidate: BoardManSelectionCaptureCandidate(
                    text: entry.text,
                    sourceApplicationName: entry.sourceApplicationName,
                    sourceBundleIdentifier: entry.sourceBundleIdentifier
                ),
                capturedAt: entry.capturedAt,
                pasteCount: entry.pasteCount + 1
            )
        }

        if let index = entries.firstIndex(where: { $0.id == entryIdentifier }) {
            entries[index] = usedEntry(from: entries[index])
            persistHistory()
            return true
        }
        if let index = stackEntries.firstIndex(where: { $0.id == entryIdentifier }) {
            stackEntries[index] = usedEntry(from: stackEntries[index])
            persistStack()
            return true
        }
        return false
    }

    @discardableResult
    func remove(identifier: String) -> Bool {
        guard let entryIdentifier = UUID(uuidString: identifier) else { return false }
        if let index = entries.firstIndex(where: { $0.id == entryIdentifier }) {
            entries.remove(at: index)
            persistHistory()
            return true
        }
        if let index = stackEntries.firstIndex(where: { $0.id == entryIdentifier }) {
            stackEntries.remove(at: index)
            persistStack()
            return true
        }
        return false
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
