import AppKit

enum BoardManSnippetDialogCoordinator {
    static func promptCategoryTitle(
        on panel: NSPanel,
        title: String,
        initialTitle: String
    ) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = boardManText("Enter a group name.")
        alert.addButton(withTitle: boardManText("Save"))
        alert.addButton(withTitle: boardManText("Cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = initialTitle
        alert.accessoryView = field
        guard run(alert, on: panel, initialFirstResponder: field) == .alertFirstButtonReturn else {
            return nil
        }
        guard let title = BoardManSnippetCatalogService.normalizedCategoryTitle(field.stringValue) else {
            showValidation(message: boardManText("Group name is required."), on: panel)
            return nil
        }
        return title
    }

    static func confirmDeleteGroup(title: String, on panel: NSPanel) -> Bool {
        let alert = NSAlert()
        alert.messageText = boardManText("Delete Group")
        alert.informativeText = String(
            format: boardManText("Delete \"%@\"? Snippets in this group will be moved to Uncategorized."),
            title
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: boardManText("Delete Group"))
        alert.addButton(withTitle: boardManText("Cancel"))
        return run(alert, on: panel) == .alertFirstButtonReturn
    }

    static func confirmDeleteSnippet(title: String, on panel: NSPanel) -> Bool {
        let alert = NSAlert()
        alert.messageText = boardManText("Delete Snippet")
        alert.informativeText = String(
            format: boardManText("Delete \"%@\" from snippets? Clipboard history is not changed."),
            title
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: boardManText("Delete"))
        alert.addButton(withTitle: boardManText("Cancel"))
        return run(alert, on: panel) == .alertFirstButtonReturn
    }

    static func showValidation(message: String, on panel: NSPanel) {
        let alert = NSAlert()
        alert.messageText = boardManText("Snippet Not Saved")
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: boardManText("OK"))
        run(alert, on: panel)
    }

    @discardableResult
    static func run(
        _ alert: NSAlert,
        on panel: NSPanel,
        initialFirstResponder: NSView? = nil
    ) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        if panel.isVisible {
            panel.makeKey()
            panel.orderFrontRegardless()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
        alert.window.initialFirstResponder = initialFirstResponder
        alert.window.level = .modalPanel

        guard panel.isVisible else {
            alert.window.center()
            alert.window.orderFrontRegardless()
            return alert.runModal()
        }

        var response = NSApplication.ModalResponse.abort
        alert.beginSheetModal(for: panel) { result in
            response = result
            NSApp.stopModal()
        }
        NSApp.runModal(for: alert.window)
        return response
    }
}
