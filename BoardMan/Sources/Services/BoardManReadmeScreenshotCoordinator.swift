//
//  BoardManReadmeScreenshotCoordinator.swift
//  Board-Man
//
//  Keeps deterministic README/demo screenshot fixtures outside normal panel coordination.
//

import Cocoa

final class BoardManReadmeScreenshotCoordinator {
    struct Request: Equatable {
        let outputPath: String
        let scene: String
        let width: CGFloat?
        let height: CGFloat?
    }

    private let store: BoardManStore

    init(store: BoardManStore = BoardManStores.authoritative) {
        self.store = store
    }

    static func request(environment: [String: String]) -> Request? {
        guard let outputPath = environment["BOARDMAN_SCREENSHOT_OUTPUT"], !outputPath.isEmpty else { return nil }
        let scene = environment["BOARDMAN_SCREENSHOT_SCENE"]?.lowercased() ?? "history"
        let width = environment["BOARDMAN_SCREENSHOT_WIDTH"].flatMap(Double.init).map { CGFloat($0) }
        let height = environment["BOARDMAN_SCREENSHOT_HEIGHT"].flatMap(Double.init).map { CGFloat($0) }
        return Request(outputPath: outputPath, scene: scene, width: width, height: height)
    }

    func scheduleIfRequested(
        panel: BoardManPanel,
        reloadItems: (BoardManPanel) -> Void,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
#if DEBUG
        guard let request = Self.request(environment: environment) else { return }

        // Prewarming can occur before all deterministic clipboard samples are seeded. Reload the
        // isolated profile immediately before capture so every README scene reflects the complete
        // demo history rather than the first item observed during prewarm.
        seedDataIfNeeded(for: request.scene)
        reloadItems(panel)
        prepare(panel: panel, scene: request.scene, width: request.width, height: request.height)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak panel] in
            guard let panel else { return }
            Self.write(panel: panel, to: request.outputPath)
        }
#endif
    }

#if DEBUG
    private func seedDataIfNeeded(for scene: String) {
        guard scene == "templates" || scene == "snippets" else { return }
        guard store.foldersSortedByIndex().isEmpty else { return }

        let language = BoardManLanguage.allowed(
            AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManLanguage)
        ).resolved
        let groups: [(title: String, snippets: [(title: String, content: String)])]
        if language == .japanese {
            groups = [
                (
                    "返信",
                    [
                        ("確認返信", "確認しました。本日中にご連絡します。"),
                        ("日程調整", "候補日時を3つお送りします。")
                    ]
                ),
                (
                    "開発",
                    [
                        ("Git状態", "git status --short --branch"),
                        ("リリース確認", "テスト・署名・更新内容を確認する")
                    ]
                ),
                (
                    "リンク",
                    [("Board-Man", "https://github.com/uniplanck/boardman")]
                )
            ]
        } else {
            groups = [
                (
                    "Replies",
                    [
                        ("Review reply", "Thanks — I’ll review this today."),
                        ("Scheduling", "I’ll send three candidate times.")
                    ]
                ),
                (
                    "Development",
                    [
                        ("Git status", "git status --short --branch"),
                        ("Release check", "Review tests, signing, and release notes")
                    ]
                ),
                (
                    "Links",
                    [("Board-Man", "https://github.com/uniplanck/boardman")]
                )
            ]
        }

        for (folderIndex, group) in groups.enumerated() {
            let folder = BoardManFolder()
            folder.index = folderIndex
            folder.title = group.title
            folder.enable = true
            store.upsertFolder(folder)
            for (snippetIndex, value) in group.snippets.enumerated() {
                let snippet = BoardManSnippet()
                snippet.index = snippetIndex
                snippet.title = value.title
                snippet.content = value.content
                snippet.enable = true
                store.upsertSnippet(snippet, folderIdentifier: folder.identifier)
            }
        }
    }

    private func prepare(
        panel: BoardManPanel,
        scene: String,
        width: CGFloat?,
        height: CGFloat?
    ) {
        var targetFrame = panel.frame
        if let width {
            targetFrame.size.width = max(600, width)
        }
        if let height {
            targetFrame.size.height = max(500, height)
        }
        if targetFrame.size != panel.frame.size {
            panel.setFrame(targetFrame, display: false, animate: false)
        }

        switch scene {
        case "settings":
            panel.selectSettingsTab()
        case "templates", "snippets":
            panel.openSnippetsManagerMode(categoryIdentifier: nil)
            if panel.itemCount > 0 {
                panel.selectItem(at: 0)
            }
        default:
            panel.selectHistoryTab()
        }
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    private static func write(panel: BoardManPanel, to path: String) {
        guard let contentView = panel.contentView else { return }
        contentView.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()

        let captureBounds = contentView.bounds
        guard captureBounds.width > 0,
              captureBounds.height > 0,
              let representation = contentView.bitmapImageRepForCachingDisplay(in: captureBounds) else {
            return
        }
        contentView.cacheDisplay(in: captureBounds, to: representation)
        guard let pngData = representation.representation(using: .png, properties: [:]) else { return }

        let outputURL = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try pngData.write(to: outputURL, options: .atomic)
        } catch {
            NSLog("Board-Man README screenshot export failed: %@", error.localizedDescription)
        }
    }
#endif
}
