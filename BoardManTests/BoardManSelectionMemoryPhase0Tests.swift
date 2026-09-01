//
//  BoardManSelectionMemoryPhase0Tests.swift
//  Board-ManTests
//

import AppKit
import Testing
@testable import Board_Man

@Suite(.serialized)
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
}
