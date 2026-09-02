import AppKit
import Testing
@testable import Board_Man

@MainActor @Suite(.serialized)
final class BoardManSnippetPresentationTests {
    @Test
    func editorStatePreservesDraftWhileEditingAndDisablesDuringReorder() {
        let selection = BoardManSnippetEditorSelection(
            title: "Deploy",
            content: "npm run deploy",
            snippetEnabled: true,
            folderEnabled: false
        )

        let viewing = BoardManSnippetPresentation.editorState(
            selection: selection,
            isEditingSelection: false,
            isReorderMode: false
        )
        #expect(viewing.shouldRefreshValues)
        #expect(viewing.title == "Deploy")
        #expect(viewing.content == "npm run deploy")
        #expect(viewing.titleEnabled)
        #expect(!viewing.titleEditable)
        #expect(viewing.contentSelectable)

        let editing = BoardManSnippetPresentation.editorState(
            selection: selection,
            isEditingSelection: true,
            isReorderMode: false
        )
        #expect(!editing.shouldRefreshValues)
        #expect(editing.titleEditable)
        #expect(editing.contentEditable)

        let reordering = BoardManSnippetPresentation.editorState(
            selection: selection,
            isEditingSelection: true,
            isReorderMode: true
        )
        #expect(!reordering.titleEnabled)
        #expect(!reordering.titleEditable)
        #expect(!reordering.contentEditable)

        #expect(BoardManSnippetPresentation.editorState(
            selection: nil,
            isEditingSelection: false,
            isReorderMode: false
        ) == .empty)
    }

    @Test
    func reorderPresentationRequiresAConcreteGroupAndMultipleItems() {
        let active = BoardManSnippetPresentation.reorderState(
            hasReorderableCategory: true,
            snippetCount: 3,
            isEditing: false,
            requestedReorderMode: true
        )
        #expect(active.canReorder)
        #expect(active.isReordering)
        #expect(active.buttonEnabled)
        #expect(active.emphasizesHint)

        let allGroups = BoardManSnippetPresentation.reorderState(
            hasReorderableCategory: false,
            snippetCount: 3,
            isEditing: false,
            requestedReorderMode: true
        )
        #expect(!allGroups.canReorder)
        #expect(!allGroups.isReordering)
        #expect(!allGroups.buttonEnabled)

        let editing = BoardManSnippetPresentation.reorderState(
            hasReorderableCategory: true,
            snippetCount: 3,
            isEditing: true,
            requestedReorderMode: true
        )
        #expect(!editing.canReorder)
        #expect(!editing.isReordering)
    }

    @Test
    func groupSummaryAndSelectionNormalizationStayDeterministic() {
        let first = BoardManFolder()
        first.title = "Work"
        let second = BoardManFolder()
        second.title = "   "
        let uncategorized = "__uncategorized__"

        let normalized = BoardManSnippetPresentation.validGroupIdentifiers(
            activeIdentifiers: [first.identifier, "missing", uncategorized],
            folders: [first, second],
            includesUncategorized: true,
            uncategorizedIdentifier: uncategorized
        )
        #expect(normalized == [first.identifier, uncategorized])
        #expect(BoardManSnippetPresentation.groupSummaryTitle(
            activeIdentifiers: [],
            folders: [first, second],
            uncategorizedIdentifier: uncategorized
        ) == boardManText("All Groups"))
        #expect(BoardManSnippetPresentation.groupSummaryTitle(
            activeIdentifiers: [first.identifier],
            folders: [first, second],
            uncategorizedIdentifier: uncategorized
        ) == "Work")
        #expect(BoardManSnippetPresentation.groupSummaryTitle(
            activeIdentifiers: [second.identifier],
            folders: [first, second],
            uncategorizedIdentifier: uncategorized
        ) == boardManText("Untitled folder"))
        #expect(BoardManSnippetPresentation.groupSummaryTitle(
            activeIdentifiers: [first.identifier, second.identifier],
            folders: [first, second],
            uncategorizedIdentifier: uncategorized
        ).contains("2"))
    }

    @Test
    func editorLayoutKeepsControlsBoundedAtCompactAndRegularWidths() {
        for width: CGFloat in [300, 360] {
            let layout = BoardManSnippetPresentation.editorLayout(
                width: width,
                height: 420,
                controlHeight: 30,
                actionButtonHeight: 30
            )
            #expect(layout.titleLabelFrame.minX >= 0)
            #expect(layout.titleFieldFrame.maxX <= width)
            #expect(layout.contentFrame.height >= 90)
            #expect(layout.saveFrame.maxX < layout.cancelFrame.maxX)
            #expect(layout.saveFrame.maxY <= layout.contentFrame.minY)
            #expect(layout.contentContainerSize.width == layout.contentFrame.width)
        }
    }
}
