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
    private var hasShownBoardManPermissionAlertThisLaunch = false
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

    func isListenEventAccessEnabled() -> Bool {
        return CGPreflightListenEventAccess()
    }

    func logPermissionStatus(context: String) {
        NSLog(
            "Board-Man permission status context=%@ accessibilityTrusted=%@ listenEventAccess=%@",
            context,
            isAccessibilityEnabled(isPrompt: false).description,
            isListenEventAccessEnabled().description
        )
    }

    func showAccessibilityAuthenticationAlert() {
        logPermissionStatus(context: "permission-alert-check")
        guard !isAccessibilityEnabled(isPrompt: false) || !isListenEventAccessEnabled() else { return }
        guard !hasShownBoardManPermissionAlertThisLaunch else {
            NSLog("Board-Man permission alert suppressed reason=already_shown_this_launch")
            return
        }
        hasShownBoardManPermissionAlertThisLaunch = true

        let alert = NSAlert()
        alert.messageText = "Board-Manに権限が必要です"
        alert.informativeText = "/Applications/Board-Man.app をアクセシビリティと入力監視に追加してONにしてください。ONに見えても効かない場合は、一度削除してから追加し直してください。"
        alert.icon = NSApplication.shared.applicationIconImage
        alert.addButton(withTitle: String(localized: "システム設定を開く"))
        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn {
            if !isAccessibilityEnabled(isPrompt: false) {
                guard !openAccessibilitySettingWindow() else { return }
                isAccessibilityEnabled(isPrompt: true)
                return
            }
            if !isListenEventAccessEnabled() {
                _ = openInputMonitoringSettingWindow()
            }
        }
    }

    func openAccessibilitySettingWindow() -> Bool {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return false }
        return NSWorkspace.shared.open(url)
    }

    func openInputMonitoringSettingWindow() -> Bool {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return false }
        return NSWorkspace.shared.open(url)
    }
}
