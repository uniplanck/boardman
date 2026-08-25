//
//  BoardManPanelPasteCoordinator.swift
//  Board-Man
//
//  Owns panel-originated paste target restoration, paste dispatch, and timestamp shortcut sequencing.
//

import Cocoa

final class BoardManPanelPasteCoordinator {
    private let store: BoardManStore
    private var previousFrontmostApplication: NSRunningApplication?
    private var previousPasteTargetSnapshot: PasteTargetSnapshot?
    private var previousPasteFocusTarget: PasteFocusTarget?

    init(store: BoardManStore = BoardManStores.authoritative) {
        self.store = store
    }

    static func pasteTargetSettleDelay(bundleIdentifier: String?) -> TimeInterval {
        let normalizedIdentifier = bundleIdentifier?.lowercased() ?? ""
        let chromiumBundlePrefixes = [
            "com.google.chrome",
            "com.brave.browser",
            "com.microsoft.edgemac",
            "com.operasoftware.opera",
            "com.vivaldi.vivaldi",
            "org.chromium.chromium",
            "company.thebrowser.browser"
        ]
        return chromiumBundlePrefixes.contains(where: normalizedIdentifier.hasPrefix) ? 0.24 : 0.08
    }

    static func clampedTimestampShortcutDelay(_ value: TimeInterval) -> TimeInterval {
        return min(60, max(0, value))
    }

    func captureTarget(frontmostApplication: NSRunningApplication?) {
        guard let application = frontmostApplication,
              application.bundleIdentifier != Bundle.main.bundleIdentifier else {
            clearTarget()
            return
        }
        previousFrontmostApplication = application
        previousPasteFocusTarget = PasteTargetVerifier.focusTarget(for: application)
        previousPasteTargetSnapshot = PasteCountInputService.shared.editableTargetSnapshot(for: application)
    }

    func clearTarget() {
        previousFrontmostApplication = nil
        previousPasteTargetSnapshot = nil
        previousPasteFocusTarget = nil
    }

    func paste(
        item: BoardManHistoryItem,
        clickStartedAt: CFAbsoluteTime?,
        completion: (() -> Void)? = nil
    ) {
        switch item.source {
        case .clip:
            pasteHistory(dataHash: item.dataHash, clickStartedAt: clickStartedAt, completion: completion)
        case .snippet:
            pasteSnippet(identifier: item.dataHash, clickStartedAt: clickStartedAt, completion: completion)
        case .favorite:
            NSSound.beep()
            clearTarget()
        }
    }

    func performTimestampAction(
        item: BoardManHistoryItem,
        shortcut: KeyCombo,
        delay: TimeInterval,
        clickStartedAt: CFAbsoluteTime?
    ) {
        let dispatchShortcutAfterPaste = { [weak self] in
            guard let self else { return }
            let executionDelay = Self.clampedTimestampShortcutDelay(delay)
            DispatchQueue.main.asyncAfter(deadline: .now() + executionDelay) { [weak self] in
                guard let self else { return }
                let didSend = AppEnvironment.current.pasteService.sendShortcut(shortcut)
                if let clickStartedAt {
                    PasteCountInputService.shared.logBoardManPerformance(
                        "panel_timestamp_shortcut_dispatch",
                        startedAt: clickStartedAt,
                        details: "pasteFirst=true sent=\(didSend)"
                    )
                }
                if !didSend {
                    NSSound.beep()
                }
                self.clearTarget()
            }
        }

        paste(item: item, clickStartedAt: clickStartedAt, completion: dispatchShortcutAfterPaste)
    }

    private func restoreTarget(
        attempt: Int = 0,
        completion: @escaping () -> Void
    ) {
        guard let application = previousFrontmostApplication else {
            completion()
            return
        }

        application.activate(options: [.activateIgnoringOtherApps])
        let settleDelay = Self.pasteTargetSettleDelay(bundleIdentifier: application.bundleIdentifier)
        let isTargetFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
            == application.processIdentifier
        if isTargetFrontmost {
            if let focusTarget = previousPasteFocusTarget,
               !PasteTargetVerifier.isFocused(focusTarget) {
                _ = PasteTargetVerifier.restoreFocus(to: focusTarget)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: completion)
            return
        }

        guard attempt < 12 else {
            if let focusTarget = previousPasteFocusTarget {
                _ = PasteTargetVerifier.restoreFocus(to: focusTarget)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: completion)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.restoreTarget(attempt: attempt + 1, completion: completion)
        }
    }

    private func pasteHistory(
        dataHash: String,
        clickStartedAt: CFAbsoluteTime?,
        completion: (() -> Void)?
    ) {
        let targetApplication = previousFrontmostApplication
        let targetSnapshot = previousPasteTargetSnapshot
            ?? PasteCountInputService.shared.editableTargetSnapshot(for: targetApplication)
        let restoreStartedAt = CFAbsoluteTimeGetCurrent()

        restoreTarget { [weak self] in
            guard let self else { return }
            PasteCountInputService.shared.logBoardManPerformance(
                "paste_target_restore_settle",
                startedAt: restoreStartedAt,
                details: "source=history"
            )
            if let clickStartedAt {
                PasteCountInputService.shared.logBoardManPerformance(
                    "panel_direct_paste_dispatch",
                    startedAt: clickStartedAt
                )
            }

            let dispatchStartedAt = CFAbsoluteTimeGetCurrent()
            guard let clip = self.store.clip(identifier: dataHash) else {
                BoardManRuntimeSupport.sendDiagnosticLog("BoardMan direct paste: cannot fetch clip")
                NSSound.beep()
                self.clearTarget()
                return
            }

            let pasteCountKey = PasteCountStore.shared.key(for: clip)
            let didSend = AppEnvironment.current.pasteService.paste(with: clip)
            PasteCountInputService.shared.logBoardManPerformance(
                "paste_dispatch_overhead",
                startedAt: dispatchStartedAt,
                details: "source=history sent=\(didSend)"
            )
            guard didSend else {
                self.clearTarget()
                return
            }

            if let targetSnapshot {
                PasteCountInputService.shared.confirmPasteChange(from: targetSnapshot) { confirmed in
                    guard confirmed else { return }
                    if let confirmedClip = self.store.clip(identifier: dataHash) {
                        PasteCountStore.shared.markUsed(clip: confirmedClip)
                    }
                    PasteCountStore.shared.increment(forKey: pasteCountKey)
                }
            }
            if let completion {
                completion()
            } else {
                self.clearTarget()
            }
        }
    }

    private func pasteSnippet(
        identifier: String,
        clickStartedAt: CFAbsoluteTime?,
        completion: (() -> Void)?
    ) {
        let restoreStartedAt = CFAbsoluteTimeGetCurrent()
        restoreTarget { [weak self] in
            guard let self else { return }

            PasteCountInputService.shared.logBoardManPerformance(
                "paste_target_restore_settle",
                startedAt: restoreStartedAt,
                details: "source=snippet"
            )
            if let clickStartedAt {
                PasteCountInputService.shared.logBoardManPerformance(
                    "panel_snippet_paste_dispatch",
                    startedAt: clickStartedAt
                )
            }

            let dispatchStartedAt = CFAbsoluteTimeGetCurrent()
            guard let snippet = self.store.snippet(identifier: identifier) else {
                BoardManRuntimeSupport.sendDiagnosticLog("BoardMan direct paste: cannot fetch snippet")
                NSSound.beep()
                self.clearTarget()
                return
            }
            let folderEnabled = self.store.folderIdentifier(forSnippetIdentifier: identifier)
                .flatMap { self.store.folder(identifier: $0) }?.enable ?? true
            guard snippet.enable, folderEnabled else {
                NSSound.beep()
                self.clearTarget()
                return
            }

            AppEnvironment.current.pasteService.copyToPasteboard(with: snippet.content)
            let didSend = AppEnvironment.current.pasteService.paste()
            PasteCountInputService.shared.logBoardManPerformance(
                "paste_dispatch_overhead",
                startedAt: dispatchStartedAt,
                details: "source=snippet sent=\(didSend)"
            )
            guard didSend else {
                self.clearTarget()
                return
            }
            if let completion {
                completion()
            } else {
                self.clearTarget()
            }
        }
    }
}
