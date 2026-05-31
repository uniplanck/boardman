// 
//  AccessibilityService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
// 
//  Created by Econa77 on 2018/10/03.
// 
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import Cocoa

final class AccessibilityService {
    private var lastBoardManPermissionAlertAt = Date.distantPast
    private let boardManPermissionAlertInterval: TimeInterval = 12
}

// MARK: - Permission
extension AccessibilityService {
    @discardableResult
    func isAccessibilityEnabled(isPrompt: Bool) -> Bool {
        // Accessibility permission is required for paste command from macOS 10.14 Mojave.
        // For macOS 10.14 and later only, check accessibility permission at startup and paste
        guard #available(macOS 10.14, *) else { return true }

        guard isPrompt else {
            return AXIsProcessTrusted()
        }

        let checkOptionPromptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [checkOptionPromptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    func showAccessibilityAuthenticationAlert() {
        guard !isAccessibilityEnabled(isPrompt: false) else { return }

        let now = Date()
        guard now.timeIntervalSince(lastBoardManPermissionAlertAt) > boardManPermissionAlertInterval else {
            return
        }
        lastBoardManPermissionAlertAt = now

        let alert = NSAlert()
        alert.messageText = "Board-Manにアクセシビリティ権限が必要です"
        alert.informativeText = "/Applications/Board-Man.app をアクセシビリティと入力監視に追加してONにしてください。ONに見えても効かない場合は、一度削除してから追加し直してください。"
        alert.icon = NSApplication.shared.applicationIconImage
        alert.addButton(withTitle: String(localized: "システム設定を開く"))
        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn {
            guard !isAccessibilityEnabled(isPrompt: false) else { return }
            guard !openAccessibilitySettingWindow() else { return }
            isAccessibilityEnabled(isPrompt: true)
        }
    }

    func openAccessibilitySettingWindow() -> Bool {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return false }
        return NSWorkspace.shared.open(url)
    }
}
