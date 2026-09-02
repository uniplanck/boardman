//
//  BoardManSelectionMemoryPhase0Tests.swift
//  Board-ManTests
//

import AppKit
import Testing
@testable import Board_Man

@MainActor @Suite(.serialized)
struct BoardManSelectionMemoryPhase0Tests {
    @Test
    func capturePolicyFailsClosedForExcludedAndSecureFields() {
        #expect(!BoardManSelectionCapturePolicy.canCapture(
            isExcludedApplication: true,
            subrole: nil
        ))
        #expect(!BoardManSelectionCapturePolicy.canCapture(
            isExcludedApplication: false,
            subrole: "AXSecureTextField"
        ))
        #expect(BoardManSelectionCapturePolicy.canCapture(
            isExcludedApplication: false,
            subrole: "AXStandardTextField"
        ))
    }

    @Test
    func coalescerWaitsForStableSelectionAndSuppressesImmediateDuplicate() throws {
        let partial = candidate("Board")
        let complete = candidate("Board-Man Selection Memory")
        var coalescer = BoardManSelectionCaptureCoalescer(
            stabilityInterval: 0.18,
            duplicateSuppressionInterval: 1.0
        )

        coalescer.observe(partial, at: 1.00)
        #expect(coalescer.flush(at: 1.10) == nil)

        coalescer.observe(complete, at: 1.12)
        #expect(coalescer.flush(at: 1.29) == nil)
        #expect(coalescer.flush(at: 1.30) == complete)

        coalescer.observe(complete, at: 1.31)
        #expect(coalescer.flush(at: 1.50) == nil)

        coalescer.observe(complete, at: 2.60)
        #expect(coalescer.flush(at: 2.79) == complete)
    }

    @Test
    func transientPasteboardRestoresOriginalRepresentations() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.clearContents() }
        let customType = NSPasteboard.PasteboardType("com.uniplanck.boardman.phase0-test")
        let original = NSPasteboardItem()
        original.setString("ordinary clipboard", forType: .string)
        original.setData(Data([0x01, 0x02, 0x03]), forType: customType)
        #expect(pasteboard.writeObjects([original]))

        let transaction = BoardManTransientPasteboardTransaction(pasteboard: pasteboard)
        #expect(transaction.stage(text: "selection memory"))
        #expect(pasteboard.string(forType: .string) == "selection memory")
        #expect(transaction.restoreIfUnchanged() == .restored)
        #expect(pasteboard.string(forType: .string) == "ordinary clipboard")
        #expect(pasteboard.data(forType: customType) == Data([0x01, 0x02, 0x03]))
    }

    @Test
    func transientPasteboardNeverOverwritesNewerClipboard() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.clearContents() }
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("ordinary clipboard", forType: .string)

        let transaction = BoardManTransientPasteboardTransaction(pasteboard: pasteboard)
        #expect(transaction.stage(text: "selection memory"))

        pasteboard.clearContents()
        pasteboard.setString("newer user copy", forType: .string)

        #expect(transaction.restoreIfUnchanged() == .skippedNewerClipboard)
        #expect(pasteboard.string(forType: .string) == "newer user copy")
    }

    @Test
    func transientPasteboardRestoresAnOriginallyEmptyClipboard() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.clearContents() }
        pasteboard.clearContents()

        let transaction = BoardManTransientPasteboardTransaction(pasteboard: pasteboard)
        #expect(transaction.stage(text: "selection memory"))
        #expect(transaction.restoreIfUnchanged() == .restored)
        #expect(pasteboard.pasteboardItems?.isEmpty ?? true)
    }

    @Test
    func productionStorePersistsLatestSelectionAndDeduplicatesBySource() throws {
        let fileURL = makeTemporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let store = BoardManSelectionMemoryStore(fileURL: fileURL)
        let first = candidate("first selection")
        let second = candidate("second selection")
        #expect(store.append(first, capturedAt: Date(timeIntervalSince1970: 1)) != nil)
        #expect(store.append(second, capturedAt: Date(timeIntervalSince1970: 2)) != nil)
        #expect(store.append(first, capturedAt: Date(timeIntervalSince1970: 3)) != nil)
        #expect(store.count == 2)
        #expect(store.latest?.text == "first selection")

        let reloaded = BoardManSelectionMemoryStore(fileURL: fileURL)
        #expect(reloaded.count == 2)
        #expect(reloaded.latest?.text == "first selection")
        #expect(reloaded.entries.map(\.text) == ["first selection", "second selection"])
    }

    @Test
    func productionServiceIsOptInAndFailsClosedWithoutLifetime() throws {
        let suite = "BoardManSelectionMemoryPhase0Tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storeURL = makeTemporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent()) }
        let store = BoardManSelectionMemoryStore(fileURL: storeURL)
        let service = BoardManSelectionMemoryService(
            defaults: defaults,
            store: store,
            pasteboard: makePasteboard(),
            readSelection: { nil },
            canUseFeature: { false },
            sendPaste: { false },
            markPasteboardHandled: {}
        )

        #expect(!service.isEnabled)
        #expect(!service.setEnabled(true))
        #expect(!defaults.bool(forKey: Constants.UserDefaults.boardManSelectionMemoryEnabled))
    }

    @Test
    func productionServiceCapturesPrivatelyAndRestoresNormalClipboardAfterDedicatedPaste() async throws {
        let suite = "BoardManSelectionMemoryPhase0Tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: Constants.UserDefaults.boardManSelectionMemoryEnabled)

        let storeURL = makeTemporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent()) }
        let store = BoardManSelectionMemoryStore(fileURL: storeURL)
        let pasteboard = makePasteboard()
        defer { pasteboard.clearContents() }
        pasteboard.clearContents()
        pasteboard.setString("ordinary clipboard sentinel", forType: .string)

        var pasteObservedText: String?
        var handledChangeCount = 0
        let service = BoardManSelectionMemoryService(
            defaults: defaults,
            store: store,
            pasteboard: pasteboard,
            readSelection: { nil },
            canUseFeature: { true },
            sendPaste: {
                pasteObservedText = pasteboard.string(forType: .string)
                return true
            },
            markPasteboardHandled: {
                handledChangeCount += 1
            }
        )
        service.ingestForTesting(candidate("privately captured selection"), at: 10)

        #expect(service.itemCount == 1)
        #expect(service.latestEntry?.text == "privately captured selection")
        #expect(pasteboard.string(forType: .string) == "ordinary clipboard sentinel")
        #expect(service.pasteLatest())
        #expect(pasteObservedText == "privately captured selection")

        try await Task.sleep(nanoseconds: 450_000_000)
        #expect(pasteboard.string(forType: .string) == "ordinary clipboard sentinel")
        #expect(handledChangeCount == 2)
    }

    @Test
    func productionStorePersistsHarvestStackInCaptureOrder() throws {
        let fileURL = makeTemporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let store = BoardManSelectionMemoryStore(fileURL: fileURL)

        #expect(store.appendToStack(candidate("first"), capturedAt: Date(timeIntervalSince1970: 1)) != nil)
        #expect(store.appendToStack(candidate("second"), capturedAt: Date(timeIntervalSince1970: 2)) != nil)
        #expect(store.stackEntries.map(\.text) == ["first", "second"])

        let reloaded = BoardManSelectionMemoryStore(fileURL: fileURL)
        #expect(reloaded.stackEntries.map(\.text) == ["first", "second"])
        reloaded.clearStack()
        #expect(reloaded.stackCount == 0)
    }

    @Test
    func harvestModeCollectsOrderedSelectionsAndPastesStackWithoutChangingNormalClipboard() async throws {
        let suite = "BoardManSelectionMemoryPhase0Tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: Constants.UserDefaults.boardManSelectionMemoryEnabled)

        let storeURL = makeTemporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent()) }
        let store = BoardManSelectionMemoryStore(fileURL: storeURL)
        let pasteboard = makePasteboard()
        defer { pasteboard.clearContents() }
        pasteboard.clearContents()
        pasteboard.setString("normal clipboard", forType: .string)

        var pastedText: String?
        let service = BoardManSelectionMemoryService(
            defaults: defaults,
            store: store,
            pasteboard: pasteboard,
            readSelection: { nil },
            canUseFeature: { true },
            sendPaste: {
                pastedText = pasteboard.string(forType: .string)
                return true
            },
            markPasteboardHandled: {}
        )

        #expect(service.setHarvestEnabled(true))
        service.ingestForTesting(candidate("alpha"), at: 10)
        service.ingestForTesting(candidate("beta"), at: 12)
        #expect(service.stackCount == 2)
        #expect(service.stackEntries.map(\.text) == ["alpha", "beta"])
        #expect(service.pasteStack())
        #expect(pastedText == "alpha\nbeta")

        try await Task.sleep(nanoseconds: 450_000_000)
        #expect(pasteboard.string(forType: .string) == "normal clipboard")
        #expect(service.setEnabled(false))
        #expect(!service.isHarvestEnabled)
    }

    private func candidate(_ text: String) -> BoardManSelectionCaptureCandidate {
        BoardManSelectionCaptureCandidate(
            text: text,
            sourceApplicationName: "Test App",
            sourceBundleIdentifier: "com.uniplanck.test"
        )
    }

    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("com.uniplanck.BoardMan.SelectionMemoryPhase0.\(UUID().uuidString)"))
    }

    private func makeTemporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BoardManSelectionMemoryTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("history.json", isDirectory: false)
    }
}
