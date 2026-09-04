import Foundation
import Testing
@testable import Board_Man

@Suite(.serialized)
final class BoardManSequentialPasteQueueServiceTests {
    @Test
    func modeRecordsCopiesAndConsumesThemInOrder() throws {
        let suite = "BoardManSequentialPasteQueueServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = try SQLiteBoardManStore.inMemoryForTesting()
        let first = makeClip(identifier: "first", title: "First")
        let second = makeClip(identifier: "second", title: "Second")
        store.upsertClip(first)
        store.upsertClip(second)
        var staged: [String] = []
        let service = BoardManSequentialPasteQueueService(
            defaults: defaults,
            store: store,
            stageClipForPaste: { staged.append($0.dataHash) }
        )

        #expect(service.setEnabled(true))
        service.recordCapturedClip(first)
        service.recordCapturedClip(second)
        #expect(service.items.map(\.clipIdentifier) == ["first", "second"])
        #expect(service.cursor == 0)

        #expect(service.prepareForCommandV(frontmostApplication: nil) == .prepared)
        #expect(staged == ["first"])
        #expect(service.cursor == 1)
        #expect(service.prepareForCommandV(frontmostApplication: nil) == .prepared)
        #expect(staged == ["first", "second"])
        #expect(service.cursor == 2)
        #expect(service.prepareForCommandV(frontmostApplication: nil) == .exhausted)
    }

    @Test
    func backSkipReverseAndMoveChangeQueueDeterministically() throws {
        let suite = "BoardManSequentialPasteQueueServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = try SQLiteBoardManStore.inMemoryForTesting()
        let first = makeClip(identifier: "first", title: "First")
        let second = makeClip(identifier: "second", title: "Second")
        let third = makeClip(identifier: "third", title: "Third")
        [first, second, third].forEach { store.upsertClip($0) }
        var staged: [String] = []
        let service = BoardManSequentialPasteQueueService(
            defaults: defaults,
            store: store,
            stageClipForPaste: { staged.append($0.dataHash) }
        )

        #expect(service.setEnabled(true))
        [first, second, third].forEach { service.recordCapturedClip($0) }
        #expect(service.move(clipIdentifier: "third", delta: -1))
        #expect(service.items.map(\.clipIdentifier) == ["first", "third", "second"])

        #expect(service.prepareForCommandV(frontmostApplication: nil) == .prepared)
        #expect(staged == ["first"])
        service.stepBack()
        #expect(service.cursor == 0)
        service.skip()
        #expect(service.cursor == 1)
        service.reverse()
        #expect(service.items.map(\.clipIdentifier) == ["second", "third", "first"])
        #expect(service.cursor == 0)
    }

    @Test
    func disablingModeLeavesQueueDataButStopsCommandVInterception() throws {
        let suite = "BoardManSequentialPasteQueueServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = try SQLiteBoardManStore.inMemoryForTesting()
        let clip = makeClip(identifier: "clip", title: "Clip")
        store.upsertClip(clip)
        var staged = 0
        let service = BoardManSequentialPasteQueueService(
            defaults: defaults,
            store: store,
            stageClipForPaste: { _ in staged += 1 }
        )

        #expect(service.setEnabled(true))
        service.recordCapturedClip(clip)
        #expect(service.setEnabled(false, startsFreshQueue: false) == false)
        #expect(service.items.count == 1)
        #expect(service.prepareForCommandV(frontmostApplication: nil) == .inactive)
        #expect(staged == 0)
    }

    @Test
    func selectionCaptureCanJoinSpecialQueueWithoutReplacingClipFlow() throws {
        let suite = "BoardManSequentialPasteQueueServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = try SQLiteBoardManStore.inMemoryForTesting()
        var stagedText: [String] = []
        let service = BoardManSequentialPasteQueueService(
            defaults: defaults,
            store: store,
            stageClipForPaste: { _ in Issue.record("Selection item should not stage a clip") },
            stageTextForPaste: { stagedText.append($0) }
        )

        #expect(service.setEnabled(true))
        defaults.set(true, forKey: Constants.UserDefaults.boardManSequentialPasteIncludesSelection)
        service.recordCapturedSelection(text: "selected alpha", sourceApplicationName: "Notes")
        #expect(service.items.count == 1)
        #expect(service.items.first?.selectionText == "selected alpha")
        #expect(service.prepareForCommandV(frontmostApplication: nil) == .prepared)
        #expect(stagedText == ["selected alpha"])

        defaults.set(false, forKey: Constants.UserDefaults.boardManSequentialPasteIncludesSelection)
        service.recordCapturedSelection(text: "selected beta", sourceApplicationName: "Safari")
        #expect(service.items.count == 1)
    }

    private func makeClip(identifier: String, title: String) -> BoardManClip {
        let clip = BoardManClip()
        clip.dataHash = identifier
        clip.title = title
        clip.primaryType = "public.utf8-plain-text"
        return clip
    }
}
