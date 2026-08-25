import AppKit

struct BoardManSnippetEditorSelection: Equatable {
    let title: String
    let content: String
    let snippetEnabled: Bool
    let folderEnabled: Bool
}

struct BoardManSnippetEditorState: Equatable {
    let title: String
    let content: String
    let snippetEnabled: Bool
    let folderEnabled: Bool?
    let titleEnabled: Bool
    let titleEditable: Bool
    let titleSelectable: Bool
    let contentEditable: Bool
    let contentSelectable: Bool
    let shouldRefreshValues: Bool

    static let empty = BoardManSnippetEditorState(
        title: "",
        content: "",
        snippetEnabled: false,
        folderEnabled: nil,
        titleEnabled: false,
        titleEditable: false,
        titleSelectable: false,
        contentEditable: false,
        contentSelectable: false,
        shouldRefreshValues: true
    )
}

struct BoardManSnippetReorderState: Equatable {
    let canReorder: Bool
    let isReordering: Bool
    let buttonEnabled: Bool
    let buttonTitle: String
    let toolTip: String
    let hint: String
    let emphasizesHint: Bool
}

struct BoardManSnippetEditorLayout: Equatable {
    let titleLabelFrame: NSRect
    let titleFieldFrame: NSRect
    let folderEnableFrame: NSRect
    let snippetEnableFrame: NSRect
    let contentLabelFrame: NSRect
    let contentFrame: NSRect
    let saveFrame: NSRect
    let cancelFrame: NSRect
    let contentContainerSize: NSSize
}

enum BoardManSnippetPresentation {
    static func editorState(
        selection: BoardManSnippetEditorSelection?,
        isEditingSelection: Bool,
        isReorderMode: Bool
    ) -> BoardManSnippetEditorState {
        guard let selection else { return .empty }
        let canEditSelection = isEditingSelection && !isReorderMode
        return BoardManSnippetEditorState(
            title: selection.title,
            content: selection.content,
            snippetEnabled: selection.snippetEnabled,
            folderEnabled: selection.folderEnabled,
            titleEnabled: !isReorderMode,
            titleEditable: canEditSelection,
            titleSelectable: canEditSelection,
            contentEditable: canEditSelection,
            contentSelectable: true,
            shouldRefreshValues: !isEditingSelection
        )
    }

    static func reorderState(
        hasReorderableCategory: Bool,
        snippetCount: Int,
        isEditing: Bool,
        requestedReorderMode: Bool
    ) -> BoardManSnippetReorderState {
        let canReorder = hasReorderableCategory && snippetCount > 1 && !isEditing
        let isReordering = canReorder && requestedReorderMode
        let toolTip = hasReorderableCategory
            ? boardManText("Reorder mode: drag the handle on the left")
            : boardManText("Select a group to reorder")
        let hint: String
        if isReordering {
            hint = boardManText("Reorder mode: drag the handle on the left")
        } else if !hasReorderableCategory {
            hint = boardManText("Select a group to reorder")
        } else {
            hint = boardManText("Hover a snippet, then click the preview to edit • ⌘C Copy • ⌘P Pin")
        }
        return BoardManSnippetReorderState(
            canReorder: canReorder,
            isReordering: isReordering,
            buttonEnabled: canReorder || isReordering,
            buttonTitle: boardManText(isReordering ? "Reordering" : "Reorder"),
            toolTip: toolTip,
            hint: hint,
            emphasizesHint: isReordering
        )
    }

    static func validGroupIdentifiers(
        activeIdentifiers: Set<String>,
        folders: [BoardManFolder],
        includesUncategorized: Bool,
        uncategorizedIdentifier: String
    ) -> Set<String> {
        var availableIdentifiers = Set(folders.map(\.identifier))
        if includesUncategorized {
            availableIdentifiers.insert(uncategorizedIdentifier)
        }
        return activeIdentifiers.intersection(availableIdentifiers)
    }

    static func groupSummaryTitle(
        activeIdentifiers: Set<String>,
        folders: [BoardManFolder],
        uncategorizedIdentifier: String
    ) -> String {
        guard !activeIdentifiers.isEmpty else { return boardManText("All Groups") }
        if activeIdentifiers.count == 1, let identifier = activeIdentifiers.first {
            if identifier == uncategorizedIdentifier {
                return boardManText("Uncategorized")
            }
            if let folder = folders.first(where: { $0.identifier == identifier }) {
                let title = folder.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return title.isEmpty ? boardManText("Untitled folder") : title
            }
        }
        return String(format: boardManText("%d Groups"), activeIdentifiers.count)
    }

    static func editorLayout(
        width: CGFloat,
        height: CGFloat,
        controlHeight: CGFloat,
        actionButtonHeight: CGFloat
    ) -> BoardManSnippetEditorLayout {
        let inset: CGFloat = width < 330 ? 14 : 18
        let contentWidth = max(120, width - (inset * 2))
        let topY = height - inset
        let titleLabelHeight: CGFloat = 17
        let titleLabelY = topY - titleLabelHeight
        let titleFieldY = titleLabelY - 4 - controlHeight
        let toggleHeight: CGFloat = 22
        let toggleY = titleFieldY - 18 - toggleHeight
        let contentLabelHeight: CGFloat = 17
        let contentLabelY = toggleY - 16 - contentLabelHeight
        let contentTop = contentLabelY - 10
        let toggleGap: CGFloat = 8
        let toggleWidth = max(104, floor((contentWidth - toggleGap) / 2))
        let contentBottom = inset + actionButtonHeight + 14
        let contentHeight = max(90, contentTop - contentBottom)
        let actionGap: CGFloat = 10
        let actionWidth = max(80, floor((contentWidth - actionGap) / 2))

        return BoardManSnippetEditorLayout(
            titleLabelFrame: NSRect(x: inset, y: titleLabelY, width: contentWidth, height: titleLabelHeight).integral,
            titleFieldFrame: NSRect(x: inset, y: titleFieldY, width: contentWidth, height: controlHeight).integral,
            folderEnableFrame: NSRect(x: inset, y: toggleY, width: toggleWidth, height: toggleHeight).integral,
            snippetEnableFrame: NSRect(
                x: inset + toggleWidth + toggleGap,
                y: toggleY,
                width: toggleWidth,
                height: toggleHeight
            ).integral,
            contentLabelFrame: NSRect(x: inset, y: contentLabelY, width: contentWidth, height: contentLabelHeight).integral,
            contentFrame: NSRect(x: inset, y: contentBottom, width: contentWidth, height: contentHeight).integral,
            saveFrame: NSRect(x: inset, y: inset, width: actionWidth, height: actionButtonHeight).integral,
            cancelFrame: NSRect(
                x: inset + actionWidth + actionGap,
                y: inset,
                width: actionWidth,
                height: actionButtonHeight
            ).integral,
            contentContainerSize: NSSize(width: contentWidth, height: .greatestFiniteMagnitude)
        )
    }
}
