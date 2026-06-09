//
//  BoardManUpgradeRoute.swift
//
//  Clipy
//

import Cocoa

enum BoardManUpgradeRoute {
    private static let proPageURLString = "https://uniplanck.com/board-man"

    static func openProPage() {
        guard let url = URL(string: proPageURLString) else {
            assertionFailure("Invalid Board-Man Pro upgrade URL")
            NSLog("Invalid Board-Man Pro upgrade URL")
            return
        }

        NSWorkspace.shared.open(url)
    }
}
