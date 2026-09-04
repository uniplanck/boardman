import AppKit
import Foundation

extension Notification.Name {
    static let boardManSequentialPasteQueueDidChange = Notification.Name("BoardManSequentialPasteQueueDidChange")
}

enum BoardManSequentialPastePreparation: Equatable {
    case inactive
    case prepared
    case exhausted
}

struct BoardManSequentialPasteQueueItem: Codable, Equatable, Identifiable {
    let id: UUID
    let clipIdentifier: String
    let title: String
    let capturedAt: Date
    let selectionText: String?

    init(
        id: UUID = UUID(),
        clipIdentifier: String,
        title: String,
        capturedAt: Date = Date(),
        selectionText: String? = nil
    ) {
        self.id = id
        self.clipIdentifier = clipIdentifier
        self.title = title
        self.capturedAt = capturedAt
        self.selectionText = selectionText
    }
}

final class BoardManSequentialPasteQueueService {
    static let shared = BoardManSequentialPasteQueueService()
    static let maximumItems = 200

    private let defaults: UserDefaults
    private let store: BoardManStore
    private let stageClipForPaste: (BoardManClip) -> Void
    private let stageTextForPaste: (String) -> Void
    private let lock = NSLock()
    private var itemsStorage: [BoardManSequentialPasteQueueItem]
    private var cursorStorage: Int

    init(
        defaults: UserDefaults = AppEnvironment.current.defaults,
        store: BoardManStore = BoardManStores.authoritative,
        stageClipForPaste: ((BoardManClip) -> Void)? = nil,
        stageTextForPaste: ((String) -> Void)? = nil
    ) {
        self.defaults = defaults
        self.store = store
        self.stageClipForPaste = stageClipForPaste ?? { clip in
            AppEnvironment.current.pasteService.copyToPasteboard(with: clip)
        }
        self.stageTextForPaste = stageTextForPaste ?? { text in
            AppEnvironment.current.pasteService.copyToPasteboard(with: text)
        }
        if let json = defaults.string(forKey: Constants.UserDefaults.boardManSequentialPasteQueueJSON),
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([BoardManSequentialPasteQueueItem].self, from: data) {
            self.itemsStorage = decoded
        } else {
            self.itemsStorage = []
        }
        self.cursorStorage = max(
            0,
            min(
                defaults.integer(forKey: Constants.UserDefaults.boardManSequentialPasteQueueCursor),
                itemsStorage.count
            )
        )
    }

    var isEnabled: Bool {
        defaults.bool(forKey: Constants.UserDefaults.boardManSequentialPasteModeEnabled)
    }

    var items: [BoardManSequentialPasteQueueItem] {
        lock.lock()
        defer { lock.unlock() }
        return itemsStorage
    }

    var cursor: Int {
        lock.lock()
        defer { lock.unlock() }
        return cursorStorage
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return itemsStorage.count
    }

    var remainingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return max(0, itemsStorage.count - cursorStorage)
    }

    var currentClipIdentifier: String? {
        lock.lock()
        defer { lock.unlock() }
        guard itemsStorage.indices.contains(cursorStorage) else { return nil }
        return itemsStorage[cursorStorage].clipIdentifier
    }

    @discardableResult
    func setEnabled(_ enabled: Bool, startsFreshQueue: Bool = true) -> Bool {
        lock.lock()
        if enabled && !isEnabled && startsFreshQueue {
            itemsStorage.removeAll()
            cursorStorage = 0
        }
        defaults.set(enabled, forKey: Constants.UserDefaults.boardManSequentialPasteModeEnabled)
        persistLocked()
        lock.unlock()
        postChange()
        return enabled
    }

    func recordCapturedClip(_ clip: BoardManClip, capturedAt: Date = Date()) {
        guard isEnabled else { return }
        appendItem(BoardManSequentialPasteQueueItem(
            clipIdentifier: clip.dataHash,
            title: clip.title,
            capturedAt: capturedAt
        ))
    }

    func recordCapturedSelection(
        text: String,
        sourceApplicationName: String,
        capturedAt: Date = Date()
    ) {
        guard isEnabled,
              defaults.bool(forKey: Constants.UserDefaults.boardManSequentialPasteIncludesSelection) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        let title = firstLine.count > 80 ? String(firstLine.prefix(77)) + "..." : firstLine
        appendItem(BoardManSequentialPasteQueueItem(
            clipIdentifier: "selection:\(UUID().uuidString)",
            title: sourceApplicationName.isEmpty ? title : "\(sourceApplicationName) · \(title)",
            capturedAt: capturedAt,
            selectionText: text
        ))
    }

    private func appendItem(_ item: BoardManSequentialPasteQueueItem) {
        lock.lock()
        itemsStorage.append(item)
        if itemsStorage.count > Self.maximumItems {
            let overflow = itemsStorage.count - Self.maximumItems
            itemsStorage.removeFirst(overflow)
            cursorStorage = max(0, cursorStorage - overflow)
        }
        persistLocked()
        lock.unlock()
        postChange()
    }

    func prepareForCommandV(frontmostApplication: NSRunningApplication?) -> BoardManSequentialPastePreparation {
        guard isEnabled else { return .inactive }
        if let bundleIdentifier = frontmostApplication?.bundleIdentifier,
           bundleIdentifier == Bundle.main.bundleIdentifier || bundleIdentifier == "com.uniplanck.BoardMan" {
            return .inactive
        }

        while true {
            let item: BoardManSequentialPasteQueueItem
            lock.lock()
            guard itemsStorage.indices.contains(cursorStorage) else {
                lock.unlock()
                return .exhausted
            }
            item = itemsStorage[cursorStorage]
            cursorStorage += 1
            persistLocked()
            lock.unlock()

            if let selectionText = item.selectionText {
                stageTextForPaste(selectionText)
                postChange()
                return .prepared
            }
            guard let clip = store.clip(identifier: item.clipIdentifier) else {
                postChange()
                continue
            }
            stageClipForPaste(clip)
            postChange()
            return .prepared
        }
    }

    func stepBack() {
        lock.lock()
        cursorStorage = max(0, cursorStorage - 1)
        persistLocked()
        lock.unlock()
        postChange()
    }

    func skip() {
        lock.lock()
        cursorStorage = min(itemsStorage.count, cursorStorage + 1)
        persistLocked()
        lock.unlock()
        postChange()
    }

    func reverse() {
        lock.lock()
        itemsStorage.reverse()
        cursorStorage = 0
        persistLocked()
        lock.unlock()
        postChange()
    }

    @discardableResult
    func move(clipIdentifier: String, delta: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard delta != 0,
              let sourceIndex = itemsStorage.indices.first(where: {
                  itemsStorage[$0].clipIdentifier == clipIdentifier && $0 >= cursorStorage
              }) ?? itemsStorage.firstIndex(where: { $0.clipIdentifier == clipIdentifier }) else {
            return false
        }
        let destinationIndex = min(max(0, sourceIndex + delta), itemsStorage.count - 1)
        guard destinationIndex != sourceIndex else { return false }
        let item = itemsStorage.remove(at: sourceIndex)
        itemsStorage.insert(item, at: destinationIndex)
        if sourceIndex == cursorStorage {
            cursorStorage = destinationIndex
        } else if sourceIndex < cursorStorage && destinationIndex >= cursorStorage {
            cursorStorage -= 1
        } else if sourceIndex >= cursorStorage && destinationIndex < cursorStorage {
            cursorStorage += 1
        }
        cursorStorage = min(max(0, cursorStorage), itemsStorage.count)
        persistLocked()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .boardManSequentialPasteQueueDidChange, object: nil)
        }
        return true
    }

    func clear() {
        lock.lock()
        itemsStorage.removeAll()
        cursorStorage = 0
        persistLocked()
        lock.unlock()
        postChange()
    }

    private func persistLocked() {
        let data = (try? JSONEncoder().encode(itemsStorage)) ?? Data("[]".utf8)
        defaults.set(String(decoding: data, as: UTF8.self), forKey: Constants.UserDefaults.boardManSequentialPasteQueueJSON)
        defaults.set(cursorStorage, forKey: Constants.UserDefaults.boardManSequentialPasteQueueCursor)
    }

    private func postChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .boardManSequentialPasteQueueDidChange, object: nil)
        }
    }
}
