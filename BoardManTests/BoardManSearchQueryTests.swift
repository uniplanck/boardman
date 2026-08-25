import AppKit
import XCTest
@testable import Board_Man

final class BoardManSearchQueryTests: XCTestCase {
    func testParserExtractsTextAndStructuredFilters() {
        let parsed = BoardManSearchQueryParser.parse(
            "quarterly type:text app:\"Google Chrome\" after:2026-08-01 before:2026-09-01 is:pinned in:history",
            defaultScope: .all
        )

        XCTAssertEqual(parsed.request.text, "quarterly")
        XCTAssertEqual(parsed.request.scope, .history)
        XCTAssertEqual(parsed.request.itemTypes, [.text])
        XCTAssertEqual(parsed.request.sourceApplication, "Google Chrome")
        XCTAssertNotNil(parsed.request.copiedAfterMilliseconds)
        XCTAssertNotNil(parsed.request.copiedBeforeMilliseconds)
        XCTAssertTrue(parsed.pinnedOnly)
    }

    func testParserPreservesUnknownOrInvalidTokensAsText() {
        let parsed = BoardManSearchQueryParser.parse(
            "invoice type:audio after:not-a-date in:somewhere",
            defaultScope: .all
        )

        XCTAssertEqual(parsed.request.text, "invoice type:audio after:not-a-date in:somewhere")
        XCTAssertEqual(parsed.request.scope, .all)
        XCTAssertTrue(parsed.request.itemTypes.isEmpty)
        XCTAssertFalse(parsed.pinnedOnly)
    }

    func testExplicitScopeSwitchesPanelIntoMatchingActionContext() {
        let panel = BoardManPanel()
        panel.setBenchmarkIsolationForTesting(true)
        panel.loadItemsForTesting([])
        panel.selectHistoryTab()

        panel.setSearchQueryForTesting("in:templates")
        XCTAssertEqual(panel.activePanelTabForTesting, "snippets")

        panel.setSearchQueryForTesting("in:history")
        XCTAssertEqual(panel.activePanelTabForTesting, "history")
    }

    func testSQLiteStructuredSearchFiltersTypeAppAndCopyDate() throws {
        let store = try SQLiteBoardManStore.inMemoryForTesting()
        let augustStart = try XCTUnwrap(
            BoardManSearchQueryParser.parse("after:2026-08-01", defaultScope: .history)
                .request.copiedAfterMilliseconds
        )
        let septemberStart = try XCTUnwrap(
            BoardManSearchQueryParser.parse("before:2026-09-01", defaultScope: .history)
                .request.copiedBeforeMilliseconds
        )

        let matching = makeClip(identifier: "match", title: "Quarterly plan", createdTime: augustStart + 86_400_000)
        let wrongApp = makeClip(identifier: "wrong-app", title: "Quarterly plan", createdTime: augustStart + 86_400_000)
        let tooOld = makeClip(identifier: "too-old", title: "Quarterly plan", createdTime: augustStart - 86_400_000)
        [matching, wrongApp, tooOld].forEach(store.upsertClip)

        store.upsertHistorySearchMetadata(
            identifier: matching.dataHash,
            metadata: BoardManHistorySearchMetadata(text: "Quarterly plan", sourceApplicationName: "Google Chrome", sourceApplicationBundleID: "com.google.Chrome")
        )
        store.upsertHistorySearchMetadata(
            identifier: wrongApp.dataHash,
            metadata: BoardManHistorySearchMetadata(text: "Quarterly plan", sourceApplicationName: "Safari", sourceApplicationBundleID: "com.apple.Safari")
        )
        store.upsertHistorySearchMetadata(
            identifier: tooOld.dataHash,
            metadata: BoardManHistorySearchMetadata(text: "Quarterly plan", sourceApplicationName: "Google Chrome", sourceApplicationBundleID: "com.google.Chrome")
        )

        let request = BoardManSearchRequest(
            text: "quarterly",
            scope: .history,
            itemTypes: [.text],
            sourceApplication: "Chrome",
            copiedAfterMilliseconds: augustStart,
            copiedBeforeMilliseconds: septemberStart
        )
        XCTAssertEqual(store.search(request, limit: 10).map(\.identifier), [matching.dataHash])
    }

    func testSQLiteFilterOnlySearchSupportsFileAndTemplateScopes() throws {
        let store = try SQLiteBoardManStore.inMemoryForTesting()
        let fileClip = makeClip(identifier: "file", title: "Report", primaryType: NSPasteboard.PasteboardType.fileURL.rawValue)
        let textClip = makeClip(identifier: "text", title: "Report", primaryType: NSPasteboard.PasteboardType.string.rawValue)
        store.upsertClip(fileClip)
        store.upsertClip(textClip)
        store.upsertHistorySearchMetadata(
            identifier: fileClip.dataHash,
            metadata: BoardManHistorySearchMetadata(filePaths: ["/Users/example/Report.pdf"])
        )

        let folder = BoardManFolder()
        folder.identifier = "folder"
        folder.title = "Ops"
        folder.enable = true
        let snippet = BoardManSnippet()
        snippet.identifier = "snippet"
        snippet.title = "Restart"
        snippet.content = "launchctl kickstart"
        snippet.enable = true
        store.upsertFolder(folder)
        store.upsertSnippet(snippet, folderIdentifier: folder.identifier)

        XCTAssertEqual(
            store.search(BoardManSearchRequest(text: "", scope: .history, itemTypes: [.file]), limit: 10).map(\.identifier),
            [fileClip.dataHash]
        )
        XCTAssertEqual(
            store.search(BoardManSearchRequest(text: "", scope: .snippets), limit: 10).map(\.identifier),
            [snippet.identifier]
        )
    }

    private func makeClip(
        identifier: String,
        title: String,
        primaryType: String = NSPasteboard.PasteboardType.string.rawValue,
        createdTime: Int = Int(Date().timeIntervalSince1970 * 1_000)
    ) -> BoardManClip {
        let clip = BoardManClip()
        clip.dataHash = identifier
        clip.dataPath = "/tmp/\(identifier)"
        clip.title = title
        clip.primaryType = primaryType
        clip.createdTime = createdTime
        clip.updateTime = createdTime / 1_000
        return clip
    }
}
