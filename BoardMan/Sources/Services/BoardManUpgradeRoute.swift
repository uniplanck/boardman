//
//  BoardManUpgradeRoute.swift
//  Board-Man
//

import Cocoa

enum BoardManUpgradeRoute {
    private static let lifetimePageURLString = "https://uniplanck.com/board-man"

    static func openProPage() {
        guard let url = URL(string: lifetimePageURLString) else {
            assertionFailure("Invalid Board-Man Lifetime purchase URL")
            NSLog("Invalid Board-Man Lifetime purchase URL")
            return
        }

        NSWorkspace.shared.open(url)
    }
}
