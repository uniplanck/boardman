//
//  BoardManSnippetsEditorWindowController.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/05/18.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import AEXML

final class BoardManSnippetsEditorWindowController: NSWindowController {

    // MARK: - Properties
    static let sharedController = BoardManSnippetsEditorWindowController(windowNibName: "BoardManSnippetsEditorWindowController")
    @IBOutlet private weak var splitView: BoardManSplitView!
    @IBOutlet private weak var folderSettingView: NSView!
    @IBOutlet private weak var folderTitleTextField: NSTextField!
    @IBOutlet private weak var folderShortcutRecordView: RecordView! {
        didSet {
            folderShortcutRecordView.delegate = self
        }
    }
    @IBOutlet private var textView: BoardManPlaceholderTextView! {
        didSet {
            textView.font = NSFont.systemFont(ofSize: 14)
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.enabledTextCheckingTypes = 0
            textView.isRichText = false
            textView.placeHolderText = String(localized: "Please fill in the contents of the snippet")
            configureSnippetTextViewAppearance()
        }
    }
    @IBOutlet private weak var outlineView: NSOutlineView! {
        didSet {
            // Enable Drag and Drop
            outlineView.registerForDraggedTypes([NSPasteboard.PasteboardType(rawValue: Constants.Common.draggedDataType)])
            configurePinnedSnippetContextMenu()
        }
    }

    private var folders = [BoardManFolder]()
    private var selectedSnippet: BoardManSnippet? {
        guard let snippet = outlineView.item(atRow: outlineView.selectedRow) as? BoardManSnippet else { return nil }
        return snippet
    }
    private var selectedFolder: BoardManFolder? {
        guard let item = outlineView.item(atRow: outlineView.selectedRow) else { return nil }
        if let folder = outlineView.parent(forItem: item) as? BoardManFolder {
            return folder
        } else if let folder = item as? BoardManFolder {
            return folder
        }
        return nil
    }

    // MARK: - Window Life Cycle
    override func windowDidLoad() {
        super.windowDidLoad()
        self.window?.collectionBehavior = NSWindow.CollectionBehavior.canJoinAllSpaces
        self.window?.backgroundColor = NSColor(white: 0.99, alpha: 1)
        if #available(OSX 10.10, *) {
            self.window?.titlebarAppearsTransparent = true
        }
        folders = BoardManStores.authoritative.foldersSortedByIndex()
        outlineView.reloadData()
        // Select first folder
        if let folder = folders.first {
            outlineView.selectRowIndexes(IndexSet(integer: outlineView.row(forItem: folder)), byExtendingSelection: false)
            changeItemFocus()
        }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(self)
    }
}

// MARK: - IBActions
extension BoardManSnippetsEditorWindowController {
    @IBAction private func addSnippetButtonTapped(_ sender: AnyObject) {
        guard let folder = selectedFolder else {
            NSSound.beep()
            return
        }
        let snippet = folder.createSnippet()
        folder.snippets.append(snippet)
        folder.mergeSnippet(snippet)
        outlineView.reloadData()
        outlineView.expandItem(folder)
        outlineView.selectRowIndexes(IndexSet(integer: outlineView.row(forItem: snippet)), byExtendingSelection: false)
        changeItemFocus()
    }

    @IBAction private func addFolderButtonTapped(_ sender: AnyObject) {
        let folder = BoardManFolder.create()
        folders.append(folder)
        folder.merge()
        outlineView.reloadData()
        outlineView.selectRowIndexes(IndexSet(integer: outlineView.row(forItem: folder)), byExtendingSelection: false)
        changeItemFocus()
    }

    @IBAction private func deleteButtonTapped(_ sender: AnyObject) {
        guard let item = outlineView.item(atRow: outlineView.selectedRow) else {
            NSSound.beep()
            return
        }

        let alert = NSAlert()
        alert.messageText = String(localized: "Delete Item")
        alert.informativeText = String(localized: "Are you sure want to delete this item?")
        alert.addButton(withTitle: String(localized: "Delete Item"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        let result = alert.runModal()
        if result != NSApplication.ModalResponse.alertFirstButtonReturn { return }

        if let folder = item as? BoardManFolder {
            folders.removeObject(folder)
            folder.remove()
            AppEnvironment.current.hotKeyService.unregisterSnippetHotKey(with: folder.identifier)
        } else if let snippet = item as? BoardManSnippet, let folder = outlineView.parent(forItem: item) as? BoardManFolder, let index = folder.snippets.index(of: snippet) {
            folder.snippets.remove(at: index)
            snippet.remove()
        }
        outlineView.reloadData()
        changeItemFocus()
    }

    @IBAction private func changeStatusButtonTapped(_ sender: AnyObject) {
        guard let item = outlineView.item(atRow: outlineView.selectedRow) else {
            NSSound.beep()
            return
        }
        if let folder = item as? BoardManFolder {
            folder.enable = !folder.enable
            folder.merge()
        } else if let snippet = item as? BoardManSnippet {
            snippet.enable = !snippet.enable
            snippet.merge()
        }
        outlineView.reloadData()
        changeItemFocus()
    }

    @IBAction private func importSnippetButtonTapped(_ sender: AnyObject) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        panel.allowedFileTypes = [Constants.Xml.fileType]
        let returnCode = panel.runModal()

        if returnCode != NSApplication.ModalResponse.OK { return }

        let fileURLs = panel.urls
        guard let url = fileURLs.first else { return }
        guard let data = try? Data(contentsOf: url) else { return }

        do {
            let store = BoardManStores.authoritative
            let lastFolder = store.foldersSortedByIndex().last
            var folderIndex = (lastFolder?.index ?? -1) + 1
            // Create Document
            var options = AEXMLOptions()
            options.parserSettings.shouldTrimWhitespace = false
            let xmlDocument = try AEXMLDocument(xml: data, options: options)
            xmlDocument[Constants.Xml.rootElement]
                .children
                .forEach { folderElement in
                    let folder = BoardManFolder()
                    folder.title = folderElement[Constants.Xml.titleElement].value ?? "untitled folder"
                    folder.index = folderIndex
                    store.upsertFolder(folder)

                    var snippetIndex = 0
                    folderElement[Constants.Xml.snippetsElement][Constants.Xml.snippetElement]
                        .all?
                        .forEach { snippetElement in
                            let snippet = BoardManSnippet()
                            snippet.title = snippetElement[Constants.Xml.titleElement].value ?? "untitled snippet"
                            snippet.content = snippetElement[Constants.Xml.contentElement].value ?? ""
                            snippet.index = snippetIndex
                            store.upsertSnippet(snippet, folderIdentifier: folder.identifier)
                            folder.snippets.append(snippet)
                            snippetIndex += 1
                        }
                    folderIndex += 1
                    folders.append(folder)
                }
            outlineView.reloadData()
        } catch {
            NSSound.beep()
        }
    }

    @IBAction private func exportSnippetButtonTapped(_ sender: AnyObject) {
        let xmlDocument = AEXMLDocument()
        let rootElement = xmlDocument.addChild(name: Constants.Xml.rootElement)

        let folders = BoardManStores.authoritative.foldersSortedByIndex()
        folders.forEach { folder in
            let folderElement = rootElement.addChild(name: Constants.Xml.folderElement)

            folderElement.addChild(name: Constants.Xml.titleElement, value: folder.title)

            let snippetsElement = folderElement.addChild(name: Constants.Xml.snippetsElement)
            Array(folder.snippets)
                .sorted { $0.index < $1.index }
                .forEach { snippet in
                    let snippetElement = snippetsElement.addChild(name: Constants.Xml.snippetElement)
                    snippetElement.addChild(name: Constants.Xml.titleElement, value: snippet.title)
                    snippetElement.addChild(name: Constants.Xml.contentElement, value: snippet.content)
                }
        }

        let panel = NSSavePanel()
        panel.accessoryView = nil
        panel.canSelectHiddenExtension = true
        panel.allowedFileTypes = [Constants.Xml.fileType]
        panel.allowsOtherFileTypes = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        panel.nameFieldStringValue = "snippets"
        let returnCode = panel.runModal()

        if returnCode != NSApplication.ModalResponse.OK { return }

        guard let data = xmlDocument.xml.data(using: String.Encoding.utf8) else { return }
        guard let url = panel.url else { return }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            NSSound.beep()
        }
    }
}

// MARK: - Item Selected
private extension BoardManSnippetsEditorWindowController {
    func configureSnippetTextViewAppearance() {
        guard let textView = textView else { return }

        let font = textView.font ?? NSFont.systemFont(ofSize: 14)
        let foregroundColor = NSColor.labelColor
        let backgroundColor = NSColor.textBackgroundColor

        textView.drawsBackground = true
        textView.backgroundColor = backgroundColor
        textView.textColor = foregroundColor
        textView.insertionPointColor = foregroundColor

        textView.typingAttributes = [
            .font: font,
            .foregroundColor: foregroundColor
        ]

        if !textView.string.isEmpty {
            let range = NSRange(location: 0, length: (textView.string as NSString).length)
            textView.textStorage?.addAttributes([
                .font: font,
                .foregroundColor: foregroundColor
            ], range: range)
        }

        textView.enclosingScrollView?.drawsBackground = true
        textView.enclosingScrollView?.backgroundColor = backgroundColor
    }

    func changeItemFocus() {
        // Reset TextView Undo/Redo history
        textView.undoManager?.removeAllActions()
        guard let item = outlineView.item(atRow: outlineView.selectedRow) else {
            folderSettingView.isHidden = true
            textView.isHidden = true
            folderShortcutRecordView.keyCombo = nil
            folderTitleTextField.stringValue = ""
            return
        }
        if let folder = item as? BoardManFolder {
            textView.string = ""
            folderTitleTextField.stringValue = folder.title
            folderShortcutRecordView.keyCombo = AppEnvironment.current.hotKeyService.snippetKeyCombo(forIdentifier: folder.identifier)
            folderSettingView.isHidden = false
            textView.isHidden = true
        } else if let snippet = item as? BoardManSnippet {
            textView.string = snippet.content
            configureSnippetTextViewAppearance()
            folderTitleTextField.stringValue = ""
            folderShortcutRecordView.keyCombo = nil
            folderSettingView.isHidden = true
            textView.isHidden = false
        }
    }
}

// MARK: - NSSplitView Delegate
extension BoardManSnippetsEditorWindowController: NSSplitViewDelegate {
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return proposedMinimumPosition + 150
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return proposedMaximumPosition / 2
    }
}

// MARK: - NSOutlineView DataSource
extension BoardManSnippetsEditorWindowController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return Int(folders.count)
        } else if let folder = item as? BoardManFolder {
            return Int(folder.snippets.count)
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let folder = item as? BoardManFolder {
            return !folder.snippets.isEmpty
        }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return folders[index]
        } else if let folder = item as? BoardManFolder {
            return folder.snippets[index]
        }
        return ""
    }

    func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
        if let folder = item as? BoardManFolder {
            return folder.title
        } else if let snippet = item as? BoardManSnippet {
            return snippet.title
        }
        return ""
    }

    // MARK: - Drag and Drop
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        let pasteboardItem = NSPasteboardItem()
        if let folder = item as? BoardManFolder, let index = folders.firstIndex(of: folder) {
            let draggedData = BoardManDragPayload(type: .folder, folderIdentifier: folder.identifier, snippetIdentifier: nil, index: index)
            let data = NSKeyedArchiver.archivedData(withRootObject: draggedData)
            pasteboardItem.setData(data, forType: NSPasteboard.PasteboardType(rawValue: Constants.Common.draggedDataType))
        } else if let snippet = item as? BoardManSnippet, let folder = outlineView.parent(forItem: snippet) as? BoardManFolder {
            guard let index = folder.snippets.index(of: snippet) else { return nil }
            let draggedData = BoardManDragPayload(type: .snippet, folderIdentifier: folder.identifier, snippetIdentifier: snippet.identifier, index: Int(index))
            let data = NSKeyedArchiver.archivedData(withRootObject: draggedData)
            pasteboardItem.setData(data, forType: NSPasteboard.PasteboardType(rawValue: Constants.Common.draggedDataType))
        } else {
            return nil
        }
        return pasteboardItem
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        let pasteboard = info.draggingPasteboard
        guard let data = pasteboard.data(forType: NSPasteboard.PasteboardType(rawValue: Constants.Common.draggedDataType)) else { return NSDragOperation() }
        guard let draggedData = NSKeyedUnarchiver.unarchiveObject(with: data) as? BoardManDragPayload else { return NSDragOperation() }

        switch draggedData.type {
        case .folder where item == nil:
            return .move
        case .snippet where item is BoardManFolder:
            return .move
        default:
            return NSDragOperation()
        }
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let pasteboard = info.draggingPasteboard
        guard let data = pasteboard.data(forType: NSPasteboard.PasteboardType(rawValue: Constants.Common.draggedDataType)) else { return false }
        guard let draggedData = NSKeyedUnarchiver.unarchiveObject(with: data) as? BoardManDragPayload else { return false }

        switch draggedData.type {
        case .folder where index != draggedData.index:
            guard index >= 0 else { return false }
            guard let folder = folders.first(where: { $0.identifier == draggedData.folderIdentifier }) else { return false }
            folders.insert(folder, at: index)
            let removedIndex = (index < draggedData.index) ? draggedData.index + 1 : draggedData.index
            folders.remove(at: removedIndex)
            outlineView.reloadData()
            outlineView.selectRowIndexes(IndexSet(integer: outlineView.row(forItem: folder)), byExtendingSelection: false)
            BoardManFolder.rearrangesIndex(folders)
            changeItemFocus()
            return true
        case .snippet:
            guard let fromFolder = folders.first(where: { $0.identifier == draggedData.folderIdentifier }) else { return false }
            guard let toFolder = item as? BoardManFolder else { return false }
            guard let snippet = fromFolder.snippets.first(where: { $0.identifier == draggedData.snippetIdentifier }) else { return false }

            if fromFolder.identifier == toFolder.identifier {
                guard index >= 0 else { return false }
                if index == draggedData.index { return false }
                // Move to same folder
                fromFolder.snippets.insert(snippet, at: index)
                let removedIndex = (index < draggedData.index) ? draggedData.index + 1 : draggedData.index
                fromFolder.snippets.remove(at: removedIndex)
                outlineView.reloadData()
                outlineView.selectRowIndexes(NSIndexSet(index: outlineView.row(forItem: snippet)) as IndexSet, byExtendingSelection: false)
                fromFolder.rearrangesSnippetIndex()
                changeItemFocus()
                return true
            } else {
                // Move to other folder
                let index = max(0, index)
                toFolder.snippets.insert(snippet, at: index)
                fromFolder.snippets.remove(at: draggedData.index)
                outlineView.reloadData()
                outlineView.expandItem(toFolder)
                outlineView.selectRowIndexes(NSIndexSet(index: outlineView.row(forItem: snippet)) as IndexSet, byExtendingSelection: false)
                toFolder.insertSnippet(snippet, index: index)
                fromFolder.removeSnippet(snippet)
                changeItemFocus()
                return true
            }
        default: return false
        }
    }
}

// MARK: - NSOutlineView Delegate
extension BoardManSnippetsEditorWindowController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, willDisplayCell cell: Any, for tableColumn: NSTableColumn?, item: Any) {
        guard let cell = cell as? BoardManTemplatesEditorCell else { return }
        if let folder = item as? BoardManFolder {
            cell.iconType = .folder
            cell.isItemEnabled = folder.enable
        } else if let snippet = item as? BoardManSnippet {
            cell.iconType = .none
            cell.isItemEnabled = snippet.enable
        }
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        changeItemFocus()
    }

    func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
        let text = fieldEditor.string
        guard !text.isEmpty else { return false }
        guard let outlineView = control as? NSOutlineView else { return false }
        guard let item = outlineView.item(atRow: outlineView.selectedRow) else { return false }
        if let folder = item as? BoardManFolder {
            folder.title = text
            folder.merge()
        } else if let snippet = item as? BoardManSnippet {
            snippet.title = text
            snippet.merge()
        }
        changeItemFocus()
        return true
    }
}

// MARK: - NSTextView Delegate
extension BoardManSnippetsEditorWindowController: NSTextViewDelegate {
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard let replacementString = replacementString else { return false }
        let text = textView.string
        guard let snippet = selectedSnippet else { return false }
        let string = (text as NSString).replacingCharacters(in: affectedCharRange, with: replacementString)
        snippet.content = string
        snippet.merge()
        return true
    }
}

// MARK: - RecordView Delegate
extension BoardManSnippetsEditorWindowController: RecordViewDelegate {
    func recordViewShouldBeginRecording(_ recordView: RecordView) -> Bool {
        guard selectedFolder != nil else { return false }
        return true
    }

    func recordView(_ recordView: RecordView, canRecordKeyCombo keyCombo: KeyCombo) -> Bool {
        guard selectedFolder != nil else { return false }
        return true
    }

    func recordView(_ recordView: RecordView, didChangeKeyCombo keyCombo: KeyCombo?) {
        guard let selectedFolder = selectedFolder else { return }
        guard let keyCombo = keyCombo else {
            AppEnvironment.current.hotKeyService.unregisterSnippetHotKey(with: selectedFolder.identifier)
            return
        }
        AppEnvironment.current.hotKeyService.registerSnippetHotKey(with: selectedFolder.identifier, keyCombo: keyCombo)
    }

    func recordViewDidEndRecording(_ recordView: RecordView) {}
}

// MARK: - Board-Man Pinned Snippets
private extension BoardManSnippetsEditorWindowController {

    func configurePinnedSnippetContextMenu() {
        let menu = NSMenu(title: "Snippet Actions")
        let togglePinnedItem = NSMenuItem(
            title: "Pin / Unpin",
            action: #selector(togglePinnedSnippetMenuItemTapped(_:)),
            keyEquivalent: ""
        )
        togglePinnedItem.target = self
        menu.addItem(togglePinnedItem)
        outlineView.menu = menu
    }

    @objc func togglePinnedSnippetMenuItemTapped(_ sender: NSMenuItem) {
        guard let snippet = selectedSnippet else {
            NSSound.beep()
            return
        }

        if PinnedSnippetStore.shared.isPinned(snippet.identifier) {
            PinnedSnippetStore.shared.remove(snippet.identifier)
        } else {
            _ = PinnedSnippetStore.shared.add(snippet.identifier)
        }
        outlineView.reloadData()
    }
}
