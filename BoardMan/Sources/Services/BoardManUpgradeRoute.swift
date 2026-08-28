//
//  BoardManUpgradeRoute.swift
//  Board-Man
//

import Cocoa

enum BoardManUpgradeRoute {
    private static let lifetimePageURLString = "https://uniplanck.com/board-man"

    static func openLifetimePage() {
        guard let url = URL(string: lifetimePageURLString) else {
            assertionFailure("Invalid Board-Man Lifetime purchase URL")
            NSLog("Invalid Board-Man Lifetime purchase URL")
            return
        }

        NSWorkspace.shared.open(url)
    }

    // Compatibility for older call sites while the Free/Pro wording is retired.
    static func openProPage() {
        openLifetimePage()
    }

    static func presentLimitReached(_ limit: EntitlementLimit, limitValue: Int) {
        let noun: String
        switch limit {
        case .historyItems: noun = "stored history items"
        case .pinnedItems: noun = "pinned items"
        case .snippetItems: noun = "Templates"
        case .snippetFolders: noun = "Template folders"
        }
        presentLifetimePrompt(
            title: "Free limit reached",
            message: "Board-Man Free includes up to \(limitValue) \(noun). Existing data stays available. Buy Lifetime to add more."
        )
    }

    static func presentFeatureLocked(_ feature: EntitlementFeature) {
        let title: String
        switch feature {
        case .advancedAppearance: title = "Advanced appearance"
        case .pasteAnalytics: title = "Detailed local analytics"
        case .advancedSearch: title = "Advanced search"
        case .workflowActions: title = "Workflow actions"
        case .templateVariables: title = "Template variables"
        case .workspaceSessions: title = "Workspace and session features"
        case .advancedTimedPins: title = "Advanced timed PIN"
        case .unlimitedHistory: title = "Unlimited history"
        case .unlimitedSnippets: title = "Unlimited Templates"
        case .exportImport: title = "Export and import"
        case .futureSync, .cloudBackup, .aiAssist, .teamSharing, .accountServices, .apiAccess, .commercialSupport:
            title = "Connected service"
        }
        presentLifetimePrompt(
            title: "Board-Man Lifetime",
            message: "\(title) is available with Board-Man Lifetime. Free keeps the core local clipboard experience available."
        )
    }

    private static func presentLifetimePrompt(title: String, message: String) {
        NSSound.beep()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Buy Lifetime")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openLifetimePage()
        }
    }
}
