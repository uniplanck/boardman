//
//  MenuManager.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/03/08.
//
//  Copyright © 2015-2018 Clipy Project.
//

// swiftlint:disable file_length function_body_length type_body_length

import Cocoa
import PINCache
import RxCocoa
import RxSwift

final class MenuManager: NSObject {

    // MARK: - Properties
    // Menus
    fileprivate var clipMenu: NSMenu?
    fileprivate var historyMenu: NSMenu?
    fileprivate var snippetMenu: NSMenu?
    // StatusMenu
    fileprivate var statusItem: NSStatusItem?
    fileprivate var currentStatusType: StatusType?
    fileprivate var boardManPanel: BoardManPanel?
    fileprivate let panelPasteCoordinator = BoardManPanelPasteCoordinator()
    fileprivate let readmeScreenshotCoordinator = BoardManReadmeScreenshotCoordinator()
    fileprivate var panelItemsNeedRefresh = true
    // Icon Cache
    fileprivate let folderIcon = NSImage(resource: .iconFolder)
    fileprivate let snippetIcon = NSImage(resource: .iconText)
    // Other
    fileprivate let disposeBag = DisposeBag()
    fileprivate let notificationCenter = NotificationCenter.default
    fileprivate let kMaxKeyEquivalents = 10
    fileprivate let shortenSymbol = "..."
    fileprivate let store: BoardManStore = BoardManStores.authoritative

    // MARK: - Enum Values
    enum StatusType: Int {
        case none, black, white
    }

    // MARK: - Initialize
    override init() {
        super.init()
        folderIcon.isTemplate = true
        folderIcon.size = NSSize(width: 15, height: 13)
        snippetIcon.isTemplate = true
        snippetIcon.size = NSSize(width: 12, height: 13)
    }

    func setup() {
        bind()
    }

    func hideBoardManPanelForPreferences() {
        boardManPanel?.orderOut(nil)
        panelPasteCoordinator.clearTarget()
    }

}

// MARK: - Popup Menu
extension MenuManager {
    func popUpMenu(_ type: MenuType) {
        switch type {
        case .main:
            showBoardManPanel()
        case .history:
            showBoardManPanel()
            boardManPanel?.selectHistoryTab()
        case .snippet:
            showBoardManSnippetsPanel()
        }
    }

    func popUpSnippetFolder(_ folder: BoardManFolder) {
        showBoardManSnippetsPanel(folderIdentifier: folder.identifier)
    }

    fileprivate func showBoardManPanel(anchorPoint: NSPoint? = nil, quickMode: Bool = false) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        if let visiblePanel = boardManPanel, visiblePanel.isVisible {
            visiblePanel.orderFrontRegardless()
            visiblePanel.makeKeyAndOrderFront(nil)
            visiblePanel.focusTableForKeyboard()
            PasteCountInputService.shared.logBoardManPerformance(
                "panel_duplicate_open_ignored",
                startedAt: startedAt,
                details: "preserved_target=true"
            )
            return
        }

        panelPasteCoordinator.captureTarget(frontmostApplication: NSWorkspace.shared.frontmostApplication)
        let panel = prepareBoardManPanelIfNeeded()
        panel.setQuickMode(quickMode)
        let panelSize = quickMode
            ? BoardManPanel.quickPanelSize()
            : NSSize(width: BoardManPanel.preferredPanelWidth(), height: BoardManPanel.preferredPanelHeight())
        let finalFrame = BoardManPanel.cursorRelativeFrame(size: panelSize, anchorPoint: anchorPoint)
        panel.prepareForFirstVisibleOrder(frame: finalFrame)
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.focusTableForKeyboard()
        PasteCountInputService.shared.logBoardManPerformance("panel_visible_fast", startedAt: startedAt, details: "items=\(panel.itemCount)")

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) { [weak self, weak panel] in
            guard let self, let panel else { return }
            guard self.panelItemsNeedRefresh || !panel.hasLoadedPanelItems else { return }
            self.reloadBoardManPanelItems(panel)
            panel.focusTableForKeyboard()
        }
        scheduleReadmeScreenshotIfRequested(panel)
    }

    private func scheduleReadmeScreenshotIfRequested(_ panel: BoardManPanel) {
        readmeScreenshotCoordinator.scheduleIfRequested(panel: panel) { [weak self] panel in
            self?.reloadBoardManPanelItems(panel)
        }
    }

    func prewarmBoardManPanel() {
        guard boardManPanel == nil else { return }
        let startedAt = CFAbsoluteTimeGetCurrent()
        let panel = prepareBoardManPanelIfNeeded()
        panel.setQuickMode(false)
        reloadBoardManPanelItems(panel)
        panel.orderOut(nil)
        PasteCountInputService.shared.logBoardManPerformance("panel_prewarm", startedAt: startedAt, details: "items=\(panel.itemCount)")
    }

    private func prepareBoardManPanelIfNeeded() -> BoardManPanel {
        if let boardManPanel {
            return boardManPanel
        }

        let panel = BoardManPanel()
        panel.onPasteRequested = { [weak self, weak panel] item, clickStartedAt in
            guard let self else { return }
            switch item.source {
            case .clip, .snippet:
                panel?.orderOut(nil)
                self.panelPasteCoordinator.paste(item: item, clickStartedAt: clickStartedAt)
            case .favorite:
                NSSound.beep()
            }
        }
        panel.onTimestampActionRequested = { [weak self, weak panel] item, shortcut, delay, clickStartedAt in
            guard let self else { return }
            switch item.source {
            case .clip, .snippet:
                panel?.orderOut(nil)
                self.panelPasteCoordinator.performTimestampAction(
                    item: item,
                    shortcut: shortcut,
                    delay: delay,
                    clickStartedAt: clickStartedAt
                )
            case .favorite:
                NSSound.beep()
                self.panelPasteCoordinator.clearTarget()
            }
        }
        panel.onRefreshRequested = { [weak self] in
            guard let self, let panel = self.boardManPanel else { return }
            self.reloadBoardManPanelItems(panel)
        }
        boardManPanel = panel
        return panel
    }

    func showBoardManSettingsPanel() {
        showBoardManPanel()
        boardManPanel?.selectSettingsTab()
    }

    func showBoardManQuickPanel() {
        showBoardManPanel(quickMode: true)
        boardManPanel?.selectHistoryTab()
    }

    func showBoardManSnippetsPanel(folderIdentifier: String? = nil) {
        showBoardManPanel()
        guard let panel = boardManPanel else { return }
        panel.openSnippetsManagerMode(categoryIdentifier: folderIdentifier)
        if !panel.hasLoadedSnippetItems {
            panelItemsNeedRefresh = true
        }
        panel.focusTableForKeyboard()
    }

    fileprivate func boardManPanelItems() -> [BoardManHistoryItem] {
        return boardManHistoryItems() + boardManSnippetItems()
    }

    fileprivate func boardManInitialPanelItems() -> [BoardManHistoryItem] {
        return boardManHistoryItems()
    }

    fileprivate func reloadBoardManPanelItems(_ panel: BoardManPanel) {
        let items = panel.presentationItemScope == .complete
            ? boardManPanelItems()
            : boardManInitialPanelItems()
        panel.reloadHistoryItems(items)
        panelItemsNeedRefresh = false
    }

    fileprivate func boardManHistoryItems() -> [BoardManHistoryItem] {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let defaults = AppEnvironment.current.defaults
        let maxHistory = max(1, defaults.integer(forKey: Constants.UserDefaults.maxHistorySize))
        let usesRecentOrder = defaults.bool(forKey: Constants.UserDefaults.reorderClipsAfterPasting)
        let clipResults = usesRecentOrder
            ? BoardManStores.authoritative.clipsSortedByUpdateTimeDescending()
            : BoardManStores.authoritative.clipsSortedByCreatedTimeDescending()
        let showRowNumbers = defaults.object(forKey: Constants.UserDefaults.boardManShowRowNumbers) as? Bool ?? true
        let timestampFormat = BoardManPanel.allowedTimestampFormat(defaults.string(forKey: Constants.UserDefaults.boardManTimestampFormat))
        let relativeTimestampStyle = BoardManRelativeTimestampStyle.current(defaults: defaults)
        let showUsageCount = defaults.object(forKey: Constants.UserDefaults.boardManShowUsageCount) as? Bool ?? true
        let timestampReferenceDate = Date()

        let pinStore = PinnedSnippetStore.shared
        let timedPinStore = BoardManTimedPinStore.shared
        let displayNameStore = HistoryDisplayNameStore.shared
        let maskedItemStore = BoardManMaskedItemStore.shared
        let pasteCounts = PasteCountStore.shared.countsSnapshot()
        let items = Array(clipResults.prefix(maxHistory)).enumerated().map { index, clip in
            let rawTitle = clip.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let isImageClip = clip.isBoardManImageHistory
            let title = rawTitle.isEmpty ? (isImageClip ? BoardManPanel.imageClipTitle(for: clip) : "(empty clipboard item)") : rawTitle
            let firstLine = title.components(separatedBy: .newlines).first ?? title
            let clipped = firstLine.count > 120 ? String(firstLine.prefix(117)) + "..." : firstLine
            let customName = displayNameStore.name(for: clip.dataHash)
            let nameOnly = customName != nil && displayNameStore.isNameOnly(clip.dataHash)
            let visibleTitle = customName ?? clipped
            let pasteCount = PasteCountStore.shared.count(for: clip, in: pasteCounts)
            let isPinned = pinStore.isPinned(clip.dataHash) || timedPinStore.isPinned(clip.dataHash)
            let isMasked = maskedItemStore.isMasked(clip.dataHash)
            var contextParts: [String] = []
            if showRowNumbers {
                contextParts.append("\(index + 1).")
            }
            if isImageClip {
                contextParts.append("Image")
            }
            let timestamp = BoardManPanel.timestampText(
                for: clip.updateTime,
                format: timestampFormat,
                relativeStyle: relativeTimestampStyle,
                now: timestampReferenceDate
            )
            var belowParts = contextParts + (timestamp.isEmpty ? [] : [timestamp])
            if !isMasked, customName != nil && !nameOnly {
                belowParts.append(clipped)
            }
            let compactTitle = (contextParts + [visibleTitle]).joined(separator: " ")
            let countText = showUsageCount && pasteCount > 0 ? "\(pasteCount)" : ""
            let searchableTitle = [customName, title].compactMap { $0 }.joined(separator: " ")
            return BoardManHistoryItem(title: searchableTitle,
                                       primaryTitle: visibleTitle,
                                       compactTitle: compactTitle,
                                       metadataText: belowParts.joined(separator: "   "),
                                       timestampText: timestamp,
                                       countText: countText,
                                       previewTitle: title,
                                       dataHash: clip.dataHash,
                                       imageDataPath: clip.dataPath,
                                       inlineThumbnail: isImageClip ? PINCache.shared.object(forKey: clip.thumbnailPath) as? NSImage : nil,
                                       pasteCount: pasteCount,
                                       isPinned: isPinned,
                                       isMasked: isMasked,
                                       isEnabled: true,
                                       source: .clip,
                                       categoryIdentifier: nil,
                                       categoryTitle: nil)
        }
        let sortedItems = items.filter { $0.isPinned } + items.filter { !$0.isPinned }
        let pinnedCount = sortedItems.filter { $0.isPinned }.count
        PasteCountInputService.shared.logBoardManPerformance("history_reload", startedAt: startedAt, details: "items=\(sortedItems.count) pinned=\(pinnedCount)")
        return sortedItems
    }

    fileprivate func boardManSnippetItems() -> [BoardManHistoryItem] {
        let pinStore = PinnedSnippetStore.shared
        let timedPinStore = BoardManTimedPinStore.shared
        let maskedItemStore = BoardManMaskedItemStore.shared
        let folderResults = store.foldersSortedByIndex()
        let folderItems = folderResults
            .flatMap { folder -> [BoardManHistoryItem] in
                Array(folder.snippets)
                    .sorted { $0.index < $1.index }
                    .map { snippet in
                        let rawTitle = snippet.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let title = rawTitle.isEmpty ? "(untitled snippet)" : rawTitle
                        let folderTitle = folder.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let prefix = folderTitle.isEmpty ? "Snippet" : folderTitle
                        let isPinned = pinStore.isPinned(snippet.identifier) || timedPinStore.isPinned(snippet.identifier)
                        let disabled = folder.enable && snippet.enable ? "" : " [OFF]"
                        return BoardManHistoryItem(title: "\(prefix) / \(title)",
                                                   primaryTitle: title,
                                                   compactTitle: title,
                                                   metadataText: "\(prefix)\(disabled)",
                                                   timestampText: "",
                                                   countText: "",
                                                   previewTitle: snippet.content,
                                                   dataHash: snippet.identifier,
                                                   imageDataPath: "",
                                                   inlineThumbnail: nil,
                                                   pasteCount: 0,
                                                   isPinned: isPinned,
                                                   isMasked: maskedItemStore.isMasked(snippet.identifier),
                                                   isEnabled: folder.enable && snippet.enable,
                                                   source: .snippet,
                                                   categoryIdentifier: folder.identifier,
                                                   categoryTitle: prefix)
                    }
            }
        let uncategorizedItems = store.uncategorizedSnippetsSortedByIndex()
            .map { snippet -> BoardManHistoryItem in
                let rawTitle = snippet.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = rawTitle.isEmpty ? "(untitled snippet)" : rawTitle
                let isPinned = pinStore.isPinned(snippet.identifier) || timedPinStore.isPinned(snippet.identifier)
                let disabled = snippet.enable ? "" : " [OFF]"
                return BoardManHistoryItem(title: "Uncategorized / \(title)",
                                           primaryTitle: title,
                                           compactTitle: title,
                                           metadataText: "Uncategorized\(disabled)",
                                           timestampText: "",
                                           countText: "",
                                           previewTitle: snippet.content,
                                           dataHash: snippet.identifier,
                                           imageDataPath: "",
                                           inlineThumbnail: nil,
                                           pasteCount: 0,
                                           isPinned: isPinned,
                                           isMasked: maskedItemStore.isMasked(snippet.identifier),
                                           isEnabled: snippet.enable,
                                           source: .snippet,
                                           categoryIdentifier: BoardManPanel.uncategorizedCategoryIdentifier,
                                           categoryTitle: "Uncategorized")
            }
        // Manual snippet order is authoritative. Do not re-sort by title or pin state here,
        // otherwise a successful drag is immediately overwritten during panel reload.
        return folderItems + uncategorizedItems
    }

}

// MARK: - Binding
private extension MenuManager {
    func bind() {
        // History changes are observed through the persistence boundary so the UI does not
        // care whether Realm or SQLite is authoritative.
        notificationCenter.rx.notification(
            .boardManHistoryStoreDidChange,
            object: BoardManStores.authoritative
        )
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] _ in
                self?.panelItemsNeedRefresh = true
            })
            .disposed(by: disposeBag)

        notificationCenter.rx.notification(
            .boardManTemplatesStoreDidChange,
            object: BoardManStores.authoritative
        )
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] _ in
                self?.panelItemsNeedRefresh = true
            })
            .disposed(by: disposeBag)
        // Menu icon
        AppEnvironment.current.defaults.rx.observe(Int.self, Constants.UserDefaults.showStatusItem, retainSelf: false)
            .compactMap { $0 }
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] key in
                let type = StatusType(rawValue: key) ?? .black
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.changeStatusItem(type)
                }
            })
            .disposed(by: disposeBag)
        // Sort clips
        AppEnvironment.current.defaults.rx.observe(Bool.self, Constants.UserDefaults.reorderClipsAfterPasting, options: [.new], retainSelf: false)
            .compactMap { $0 }
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] _ in
                self?.panelItemsNeedRefresh = true
            })
            .disposed(by: disposeBag)
        // Edit snippets
        notificationCenter.rx.notification(Notification.Name(rawValue: Constants.Notification.closeSnippetEditor))
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] _ in
                self?.panelItemsNeedRefresh = true
            })
            .disposed(by: disposeBag)
        notificationCenter.rx.notification(Notification.Name(rawValue: Constants.Notification.boardManTimedPinDidChange))
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] _ in
                guard let self else { return }
                self.panelItemsNeedRefresh = true
                if let panel = self.boardManPanel, panel.isVisible {
                    self.reloadBoardManPanelItems(panel)
                }
            })
            .disposed(by: disposeBag)
        notificationCenter.rx.notification(Notification.Name(rawValue: Constants.Notification.pasteCountDidChange))
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] _ in
                self?.panelItemsNeedRefresh = true
            })
            .disposed(by: disposeBag)

        // The status menu is static and is built on-demand on right click. Legacy status menu
        // appearance preferences no longer need a dozen live KVO subscriptions. Only history
        // size can change the panel's data set outside the panel itself.
        AppEnvironment.current.defaults.rx.observe(Int.self, Constants.UserDefaults.maxHistorySize, options: [.new], retainSelf: false)
            .compactMap { $0 }
            .distinctUntilChanged()
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] _ in
                self?.panelItemsNeedRefresh = true
            })
            .disposed(by: disposeBag)
    }
}

// MARK: - Menus
private extension MenuManager {
    func createBoardManLiteMenu() {
        // The panel owns history and snippet browsing; keep the status menu lightweight.
        let menu = NSMenu(title: Constants.Application.name)
        menu.addItem(NSMenuItem(title: String(localized: "Open Board-Man"), action: #selector(AppDelegate.openBoardMan)))
        menu.addItem(NSMenuItem(title: String(localized: "Open Board-Man Settings"), action: #selector(AppDelegate.openBoardManSettings)))
        menu.addItem(NSMenuItem(title: String(localized: "Manage Snippets"), action: #selector(AppDelegate.openBoardManSnippetsManager)))
        menu.addItem(NSMenuItem(title: boardManText("Open Archived Text History"), action: #selector(AppDelegate.openArchivedTextHistory)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: boardManText("Restart Board-Man"), action: #selector(AppDelegate.restartBoardMan)))
        menu.addItem(NSMenuItem(title: boardManText("Quit Board-Man"), action: #selector(AppDelegate.terminate)))

        clipMenu = menu
        historyMenu = NSMenu(title: Constants.Menu.history)
        snippetMenu = NSMenu(title: Constants.Menu.snippet)
        statusItem?.menu = nil
    }

    func menuItemTitle(_ title: String, listNumber: NSInteger, isMarkWithNumber: Bool) -> String {
        return (isMarkWithNumber) ? "\(listNumber). \(title)" : title
    }

    func clipMenuItemTitle(_ title: String, clip: BoardManClip, listNumber: NSInteger, isMarkWithNumber: Bool) -> String {
        return PasteCountStore.shared.label(for: clip) + menuItemTitle(title, listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)
    }

    func applyPasteCountStyle(to menuItem: NSMenuItem, clip: BoardManClip) {
        let countLabel = PasteCountStore.shared.label(for: clip)
        let attributedTitle = NSMutableAttributedString(string: menuItem.title)
        let labelRange = NSRange(location: 0, length: (countLabel as NSString).length)
        if PasteCountStore.shared.count(for: clip) == 0 {
            let fullRange = NSRange(location: 0, length: (menuItem.title as NSString).length)
            attributedTitle.addAttributes([
                .backgroundColor: NSColor.selectedMenuItemColor.withAlphaComponent(0.28),
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            ], range: fullRange)
            attributedTitle.addAttributes([
                .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            ], range: labelRange)
        }
        menuItem.attributedTitle = attributedTitle
    }

    func makeSubmenuItem(_ count: Int, start: Int, end: Int, numberOfItems: Int) -> NSMenuItem {
        var count = count
        if start == 0 {
            count -= 1
        }
        var lastNumber = count + numberOfItems
        if end < lastNumber {
            lastNumber = end
        }
        let menuItemTitle = "\(count + 1) - \(lastNumber)"
        return makeSubmenuItem(menuItemTitle)
    }

    func makeSubmenuItem(_ title: String) -> NSMenuItem {
        let subMenu = NSMenu(title: "")
        let subMenuItem = NSMenuItem(title: title, action: nil)
        subMenuItem.submenu = subMenu
        subMenuItem.image = (AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu)) ? folderIcon : nil
        return subMenuItem
    }

    func incrementListNumber(_ listNumber: NSInteger, max: NSInteger, start: NSInteger) -> NSInteger {
        var listNumber = listNumber + 1
        if listNumber == max && max == 10 && start == 1 {
            listNumber = 0
        }
        return listNumber
    }

    func trimTitle(_ title: String?) -> String {
        if title == nil { return "" }
        let theString = title!.trimmingCharacters(in: .whitespacesAndNewlines) as NSString

        let aRange = NSRange(location: 0, length: 0)
        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        theString.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: aRange)

        var titleString = (lineEnd == theString.length) ? theString as String : theString.substring(to: contentsEnd)

        var maxMenuItemTitleLength = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxMenuItemTitleLength)
        if maxMenuItemTitleLength < shortenSymbol.count {
            maxMenuItemTitleLength = shortenSymbol.count
        }

        if titleString.utf16.count > maxMenuItemTitleLength {
            titleString = (titleString as NSString).substring(to: maxMenuItemTitleLength - shortenSymbol.count) + shortenSymbol
        }

        return titleString as String
    }
}

// MARK: - Clips
private extension MenuManager {
    func addHistoryItems(_ menu: NSMenu) {
        let placeInLine = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.numberOfItemsPlaceInline)
        let placeInsideFolder = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.numberOfItemsPlaceInsideFolder)
        let maxHistory = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxHistorySize)

        // History title
        let labelItem = NSMenuItem(title: String(localized: "History"), action: nil)
        labelItem.isEnabled = false
        menu.addItem(labelItem)

        // History
        let firstIndex = firstIndexOfMenuItems()
        var listNumber = firstIndex
        var subMenuCount = placeInLine
        var subMenuIndex = 1 + placeInLine

        let usesRecentOrder = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.reorderClipsAfterPasting)
        let clipResults = usesRecentOrder
            ? BoardManStores.authoritative.clipsSortedByUpdateTimeDescending()
            : BoardManStores.authoritative.clipsSortedByCreatedTimeDescending()
        let currentSize = Int(clipResults.count)
        var i = 0
        for clip in clipResults {
            if placeInLine < 1 || placeInLine - 1 < i {
                // Folder
                if i == subMenuCount {
                    let subMenuItem = makeSubmenuItem(subMenuCount, start: firstIndex, end: currentSize, numberOfItems: placeInsideFolder)
                    menu.addItem(subMenuItem)
                    listNumber = firstIndex
                }

                // Clip
                if let subMenu = menu.item(at: subMenuIndex)?.submenu {
                    let menuItem = makeClipMenuItem(clip, index: i, listNumber: listNumber)
                    subMenu.addItem(menuItem)
                    listNumber = incrementListNumber(listNumber, max: placeInsideFolder, start: firstIndex)
                }
            } else {
                // Clip
                let menuItem = makeClipMenuItem(clip, index: i, listNumber: listNumber)
                menu.addItem(menuItem)
                listNumber = incrementListNumber(listNumber, max: placeInLine, start: firstIndex)
            }

            i += 1
            if i == subMenuCount + placeInsideFolder {
                subMenuCount += placeInsideFolder
                subMenuIndex += 1
            }

            if maxHistory <= i { break }
        }
    }

    func makeClipMenuItem(_ clip: BoardManClip, index: Int, listNumber: Int) -> NSMenuItem {
        let isMarkWithNumber = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsAreMarkedWithNumbers)
        let isShowToolTip = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showToolTipOnMenuItem)
        let isShowImage = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showImageInTheMenu)
        let isShowColorCode = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showColorPreviewInTheMenu)
        let addNumbericKeyEquivalents = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.addNumericKeyEquivalents)

        var keyEquivalent = ""

        if addNumbericKeyEquivalents && (index <= kMaxKeyEquivalents) {
            let isStartFromZero = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsTitleStartWithZero)

            var shortCutNumber = (isStartFromZero) ? index : index + 1
            if shortCutNumber == kMaxKeyEquivalents {
                shortCutNumber = 0
            }
            keyEquivalent = "\(shortCutNumber)"
        }

        let primaryPboardType = NSPasteboard.PasteboardType(rawValue: clip.primaryType)
        let clipString = clip.title
        let title = trimTitle(clipString)
        let titleWithMark = clipMenuItemTitle(title, clip: clip, listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)

        let menuItem = NSMenuItem(title: titleWithMark, action: #selector(AppDelegate.selectClipMenuItem(_:)), keyEquivalent: keyEquivalent)
        menuItem.representedObject = clip.dataHash
        applyPasteCountStyle(to: menuItem, clip: clip)

        if isShowToolTip {
            let maxLengthOfToolTip = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxLengthOfToolTip)
            let toIndex = (clipString.count < maxLengthOfToolTip) ? clipString.count : maxLengthOfToolTip
            menuItem.toolTip = (clipString as NSString).substring(to: toIndex)
        }

        if primaryPboardType == .deprecatedTIFF {
            menuItem.title = clipMenuItemTitle("(Image)", clip: clip, listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)
            applyPasteCountStyle(to: menuItem, clip: clip)
        } else if primaryPboardType == .deprecatedPDF {
            menuItem.title = clipMenuItemTitle("(PDF)", clip: clip, listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)
            applyPasteCountStyle(to: menuItem, clip: clip)
        } else if primaryPboardType == .deprecatedFilenames && title.isEmpty {
            menuItem.title = clipMenuItemTitle("(Filenames)", clip: clip, listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)
            applyPasteCountStyle(to: menuItem, clip: clip)
        }

        if !clip.thumbnailPath.isEmpty && !clip.isColorCode && isShowImage {
            PINCache.shared.object(forKeyAsync: clip.thumbnailPath) { [weak menuItem] _, _, object in
                DispatchQueue.main.async {
                    menuItem?.image = object as? NSImage
                }
            }
        }
        if !clip.thumbnailPath.isEmpty && clip.isColorCode && isShowColorCode {
            PINCache.shared.object(forKeyAsync: clip.thumbnailPath) { [weak menuItem] _, _, object in
                DispatchQueue.main.async {
                    menuItem?.image = object as? NSImage
                }
            }
        }

        return menuItem
    }
}

// MARK: - Snippets
private extension MenuManager {
    func addPinnedSnippetItems(_ menu: NSMenu) {
        let pinnedIdentifiers = PinnedSnippetStore.shared.identifiers
        guard !pinnedIdentifiers.isEmpty else { return }

        let snippets = pinnedIdentifiers.compactMap { identifier -> BoardManSnippet? in
            guard let snippet = store.snippet(identifier: identifier), snippet.enable else { return nil }
            let folderEnabled = store.folderIdentifier(forSnippetIdentifier: identifier)
                .flatMap { store.folder(identifier: $0) }?.enable ?? true
            return folderEnabled ? snippet : nil
        }
        guard !snippets.isEmpty else { return }

        let labelItem = NSMenuItem(title: "Pinned Snippets", action: nil)
        labelItem.attributedTitle = NSAttributedString(
            string: "Pinned Snippets",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        labelItem.isEnabled = false
        menu.addItem(labelItem)

        snippets.enumerated().forEach { index, snippet in
            let menuItem = makeSnippetMenuItem(snippet, listNumber: index + 1)
            let pinnedTitle = "PIN  " + menuItem.title
            menuItem.title = pinnedTitle
            menuItem.attributedTitle = NSAttributedString(
                string: pinnedTitle,
                attributes: [
                    .font: NSFont.menuFont(ofSize: 0),
                    .foregroundColor: NSColor.labelColor
                ]
            )
            menu.addItem(menuItem)
        }

        menu.addItem(NSMenuItem.separator())
    }

    func addSnippetItems(_ menu: NSMenu, separateMenu: Bool) {
        let folderResults = store.foldersSortedByIndex()
        guard !folderResults.isEmpty else { return }
        if separateMenu {
            menu.addItem(NSMenuItem.separator())
        }

        // Snippet title
        let labelItem = NSMenuItem(title: String(localized: "Snippet"), action: nil)
        labelItem.isEnabled = false
        menu.addItem(labelItem)

        var subMenuIndex = menu.numberOfItems - 1
        let firstIndex = firstIndexOfMenuItems()

        folderResults
            .filter { $0.enable }
            .forEach { folder in
                let folderTitle = folder.title
                let subMenuItem = makeSubmenuItem(folderTitle)
                menu.addItem(subMenuItem)
                subMenuIndex += 1

                var i = firstIndex
                Array(folder.snippets)
                    .sorted { $0.index < $1.index }
                    .filter { $0.enable }
                    .forEach { snippet in
                        let subMenuItem = makeSnippetMenuItem(snippet, listNumber: i)
                        if let subMenu = menu.item(at: subMenuIndex)?.submenu {
                            subMenu.addItem(subMenuItem)
                            i += 1
                        }
                    }
            }
    }

    func makeSnippetMenuItem(_ snippet: BoardManSnippet, listNumber: Int) -> NSMenuItem {
        let isMarkWithNumber = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsAreMarkedWithNumbers)
        let isShowIcon = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu)

        let title = trimTitle(snippet.title)
        let titleWithMark = menuItemTitle(title, listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)

        let menuItem = NSMenuItem(title: titleWithMark, action: #selector(AppDelegate.selectSnippetMenuItem(_:)), keyEquivalent: "")
        menuItem.representedObject = snippet.identifier
        menuItem.toolTip = snippet.content
        menuItem.image = (isShowIcon) ? snippetIcon : nil

        return menuItem
    }
}

// MARK: - Status Item
private extension MenuManager {
    func changeStatusItem(_ type: StatusType) {
        if currentStatusType == type,
           (type == .none || statusItem != nil) {
            return
        }

        removeStatusItem()
        currentStatusType = type
        if type == .none { return }

        let image: NSImage?
        switch type {
        case .black:
            image = NSImage(resource: .statusbarMenuBlack)
        case .white:
            image = NSImage(resource: .statusbarMenuWhite)
        case .none: return
        }
        image?.isTemplate = true

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = image
        statusItem?.toolTip = "\(Constants.Application.name) \(Bundle.main.appVersion ?? "")"
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(statusItemClicked(_:))
        statusItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem?.menu = nil
    }

    @objc func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            createBoardManLiteMenu()
            guard let event, let menu = clipMenu, let button = statusItem?.button else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: button)
            return
        }

        if let button = statusItem?.button, let window = button.window {
            let buttonFrame = button.convert(button.bounds, to: nil)
            let screenFrame = window.convertToScreen(buttonFrame)
            showBoardManPanel(anchorPoint: NSPoint(x: screenFrame.midX, y: screenFrame.minY))
        } else {
            showBoardManPanel()
        }
    }

    func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
}

// MARK: - Settings
private extension MenuManager {
    func firstIndexOfMenuItems() -> NSInteger {
        return AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsTitleStartWithZero) ? 0 : 1
    }
}

// MARK: - Board-Man Pinned Snippets
final class PinnedSnippetStore {

    static let shared = PinnedSnippetStore()

    private let defaults: UserDefaults
    private let timedPinIdentifiers: () -> [String]
    private let key = "com.uniplanck.BoardMan.pinnedSnippetIdentifiers"

    init(
        defaults: UserDefaults = AppEnvironment.current.defaults,
        timedPinIdentifiers: @escaping () -> [String] = { BoardManTimedPinStore.shared.identifiers }
    ) {
        self.defaults = defaults
        self.timedPinIdentifiers = timedPinIdentifiers
    }

    var identifiers: [String] {
        return defaults.stringArray(forKey: key) ?? []
    }

    func isPinned(_ identifier: String) -> Bool {
        return identifiers.contains(identifier)
    }

    func toggle(_ identifier: String) {
        if isPinned(identifier) {
            remove(identifier)
        } else {
            _ = add(identifier)
        }
    }

    func add(_ identifier: String) -> Bool {
        var values = identifiers.filter { !$0.isEmpty }
        guard !values.contains(identifier) else { return true }
        BoardManTimedPinStore.shared.remove(identifier)
        values.append(identifier)
        save(values)
        return true
    }

    func remove(_ identifier: String) {
        save(identifiers.filter { $0 != identifier })
    }

    func oldestUnpinnedIdentifiers(in newestFirstIdentifiers: [String], maximumCount: Int) -> Set<String> {
        guard maximumCount > 0 else { return [] }
        let pinnedIdentifiers = Set(identifiers).union(timedPinIdentifiers())
        return Set(
            newestFirstIdentifiers
                .reversed()
                .filter { !pinnedIdentifiers.contains($0) }
                .prefix(maximumCount)
        )
    }

    private func save(_ values: [String]) {
        defaults.set(values, forKey: key)
        defaults.synchronize()
        NotificationCenter.default.post(name: Notification.Name(rawValue: Constants.Notification.closeSnippetEditor), object: nil)
    }
}

enum BoardManLongPressAction: String, CaseIterable {
    case togglePin
    case timedPin
    case toggleMask
    case none

    static func allowed(_ value: String?) -> BoardManLongPressAction {
        return allCases.first(where: { $0.rawValue == value }) ?? .togglePin
    }

    var title: String {
        switch self {
        case .togglePin: return boardManText("Pin / Unpin")
        case .timedPin: return boardManText("Timed Pin")
        case .toggleMask: return boardManText("Hide / Show Content")
        case .none: return boardManText("Do Nothing")
        }
    }
}

enum BoardManTimedPinUnit: String, CaseIterable, Codable {
    case minutes
    case hours
    case days
    case weeks

    static func allowed(_ value: String?) -> BoardManTimedPinUnit {
        return allCases.first(where: { $0.rawValue == value }) ?? .hours
    }

    var title: String {
        switch self {
        case .minutes: return boardManText("Minutes")
        case .hours: return boardManText("Hours")
        case .days: return boardManText("Days")
        case .weeks: return boardManText("Weeks")
        }
    }

    func interval(value: Int) -> TimeInterval {
        let safeValue = max(1, value)
        switch self {
        case .minutes: return TimeInterval(safeValue * 60)
        case .hours: return TimeInterval(safeValue * 3_600)
        case .days: return TimeInterval(safeValue * 86_400)
        case .weeks: return TimeInterval(safeValue * 604_800)
        }
    }

    func summary(value: Int) -> String {
        let safeValue = max(1, value)
        switch self {
        case .minutes: return boardManText("%d min").replacingOccurrences(of: "%d", with: "\(safeValue)")
        case .hours: return boardManText("%d hr").replacingOccurrences(of: "%d", with: "\(safeValue)")
        case .days: return boardManText("%d day").replacingOccurrences(of: "%d", with: "\(safeValue)")
        case .weeks: return boardManText("%d wk").replacingOccurrences(of: "%d", with: "\(safeValue)")
        }
    }
}

struct BoardManTimedPinPreset: Codable, Equatable {
    let id: String
    var value: Int
    var unit: BoardManTimedPinUnit

    var normalized: BoardManTimedPinPreset {
        return BoardManTimedPinPreset(id: id, value: min(999_999, max(1, value)), unit: unit)
    }

    var title: String {
        return unit.summary(value: value)
    }
}

enum BoardManTimedPinPresetStore {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func presets(defaults: UserDefaults = AppEnvironment.current.defaults) -> [BoardManTimedPinPreset] {
        if let json = defaults.string(forKey: Constants.UserDefaults.boardManTimedPinPresetsJSON),
           let data = json.data(using: .utf8),
           let decoded = try? decoder.decode([BoardManTimedPinPreset].self, from: data),
           !decoded.isEmpty {
            return decoded.map(\.normalized)
        }
        let legacyValue = max(1, defaults.integer(forKey: Constants.UserDefaults.boardManTimedPinDurationValue))
        let legacyUnit = BoardManTimedPinUnit.allowed(
            defaults.string(forKey: Constants.UserDefaults.boardManTimedPinDurationUnit)
        )
        var initial = [BoardManTimedPinPreset(id: "default-1h", value: legacyValue, unit: legacyUnit)]
        let standard = [
            BoardManTimedPinPreset(id: "default-1d", value: 1, unit: .days),
            BoardManTimedPinPreset(id: "default-1w", value: 1, unit: .weeks)
        ]
        standard.forEach { preset in
            if !initial.contains(where: { $0.value == preset.value && $0.unit == preset.unit }) {
                initial.append(preset)
            }
        }
        return initial
    }

    static func selectedPreset(defaults: UserDefaults = AppEnvironment.current.defaults) -> BoardManTimedPinPreset {
        let current = presets(defaults: defaults)
        let selectedID = defaults.string(forKey: Constants.UserDefaults.boardManTimedPinSelectedPresetID)
        return current.first(where: { $0.id == selectedID }) ?? current[0]
    }

    static func select(_ id: String, defaults: UserDefaults = AppEnvironment.current.defaults) {
        guard presets(defaults: defaults).contains(where: { $0.id == id }) else { return }
        defaults.set(id, forKey: Constants.UserDefaults.boardManTimedPinSelectedPresetID)
        defaults.synchronize()
    }

    @discardableResult
    static func add(defaults: UserDefaults = AppEnvironment.current.defaults) -> BoardManTimedPinPreset {
        var current = presets(defaults: defaults)
        let preset = BoardManTimedPinPreset(id: UUID().uuidString, value: 1, unit: .hours)
        current.append(preset)
        save(current, selectedID: preset.id, defaults: defaults)
        return preset
    }

    @discardableResult
    static func updateSelected(value: Int? = nil,
                               unit: BoardManTimedPinUnit? = nil,
                               defaults: UserDefaults = AppEnvironment.current.defaults) -> BoardManTimedPinPreset {
        var current = presets(defaults: defaults)
        let selected = selectedPreset(defaults: defaults)
        guard let index = current.firstIndex(where: { $0.id == selected.id }) else { return selected }
        if let value { current[index].value = min(999_999, max(1, value)) }
        if let unit { current[index].unit = unit }
        current[index] = current[index].normalized
        save(current, selectedID: current[index].id, defaults: defaults)
        return current[index]
    }

    @discardableResult
    static func removeSelected(defaults: UserDefaults = AppEnvironment.current.defaults) -> Bool {
        var current = presets(defaults: defaults)
        guard current.count > 1 else { return false }
        let selected = selectedPreset(defaults: defaults)
        current.removeAll { $0.id == selected.id }
        save(current, selectedID: current[0].id, defaults: defaults)
        return true
    }

    private static func save(_ presets: [BoardManTimedPinPreset],
                             selectedID: String,
                             defaults: UserDefaults) {
        let normalized = presets.map(\.normalized)
        guard let data = try? encoder.encode(normalized),
              let json = String(data: data, encoding: .utf8) else { return }
        defaults.set(json, forKey: Constants.UserDefaults.boardManTimedPinPresetsJSON)
        defaults.set(selectedID, forKey: Constants.UserDefaults.boardManTimedPinSelectedPresetID)
        if let selected = normalized.first(where: { $0.id == selectedID }) {
            defaults.set(selected.value, forKey: Constants.UserDefaults.boardManTimedPinDurationValue)
            defaults.set(selected.unit.rawValue, forKey: Constants.UserDefaults.boardManTimedPinDurationUnit)
        }
        defaults.synchronize()
    }
}

struct BoardManTimedPinRecord: Codable, Equatable {
    let expiresAt: Date
}

final class BoardManTimedPinStore {
    static let shared = BoardManTimedPinStore()

    private let defaults: UserDefaults
    private let now: () -> Date

    init(defaults: UserDefaults = AppEnvironment.current.defaults,
         now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    var identifiers: [String] {
        let current = activeRecords()
        return current.keys.sorted()
    }

    func isPinned(_ identifier: String) -> Bool {
        return activeRecords()[identifier] != nil
    }

    func expiration(for identifier: String) -> Date? {
        return activeRecords()[identifier]?.expiresAt
    }

    @discardableResult
    func setPin(_ identifier: String,
                durationValue: Int,
                unit: BoardManTimedPinUnit,
                maximumActiveCount: Int?) -> Bool {
        guard !identifier.isEmpty else { return false }
        var records = activeRecords()
        if records[identifier] == nil,
           let maximumActiveCount,
           records.count >= maximumActiveCount {
            return false
        }
        let expiresAt = now().addingTimeInterval(unit.interval(value: durationValue))
        records[identifier] = BoardManTimedPinRecord(expiresAt: expiresAt)
        save(records)
        scheduleExpiration(for: identifier, at: expiresAt)
        return true
    }

    func remove(_ identifier: String) {
        var records = activeRecords()
        guard records.removeValue(forKey: identifier) != nil else { return }
        save(records)
    }

    @discardableResult
    func removeExpired() -> Bool {
        let stored = decodedRecords
        let active = stored.filter { $0.value.expiresAt > now() }
        guard active.count != stored.count else { return false }
        save(active)
        return true
    }

    private var decodedRecords: [String: BoardManTimedPinRecord] {
        guard let json = defaults.string(forKey: Constants.UserDefaults.boardManTimedPinsJSON),
              let data = json.data(using: .utf8),
              let records = try? JSONDecoder().decode([String: BoardManTimedPinRecord].self, from: data) else {
            return [:]
        }
        return records
    }

    private func activeRecords() -> [String: BoardManTimedPinRecord] {
        let records = decodedRecords
        let active = records.filter { $0.value.expiresAt > now() }
        if active.count != records.count {
            save(active)
        }
        return active
    }

    private func save(_ records: [String: BoardManTimedPinRecord]) {
        guard let data = try? JSONEncoder().encode(records),
              let json = String(data: data, encoding: .utf8) else { return }
        defaults.set(json, forKey: Constants.UserDefaults.boardManTimedPinsJSON)
        defaults.synchronize()
        NotificationCenter.default.post(name: Notification.Name(rawValue: Constants.Notification.boardManTimedPinDidChange), object: nil)
    }

    private func scheduleExpiration(for identifier: String, at expiresAt: Date) {
        let delay = max(0, expiresAt.timeIntervalSince(now()))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.05) { [weak self] in
            guard let self,
                  let storedExpiration = self.expiration(for: identifier),
                  storedExpiration <= self.now() else { return }
            self.remove(identifier)
        }
    }
}

enum BoardManItemHighlight: String, CaseIterable, Codable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case gray

    var title: String {
        switch self {
        case .red: return boardManText("Red")
        case .orange: return boardManText("Orange")
        case .yellow: return boardManText("Yellow")
        case .green: return boardManText("Green")
        case .blue: return boardManText("Blue")
        case .purple: return boardManText("Purple")
        case .gray: return boardManText("Gray")
        }
    }

    var color: NSColor {
        switch self {
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .gray: return .systemGray
        }
    }
}

final class BoardManItemHighlightStore {
    static let shared = BoardManItemHighlightStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppEnvironment.current.defaults) {
        self.defaults = defaults
    }

    func highlight(for identifier: String) -> BoardManItemHighlight? {
        guard let rawValue = values[identifier] else { return nil }
        return BoardManItemHighlight(rawValue: rawValue)
    }

    func set(_ highlight: BoardManItemHighlight?, for identifier: String) {
        var next = values
        if let highlight {
            next[identifier] = highlight.rawValue
        } else {
            next.removeValue(forKey: identifier)
        }
        save(next)
    }

    func remove(_ identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        var next = values
        identifiers.forEach { next.removeValue(forKey: $0) }
        save(next)
    }

    private var values: [String: String] {
        guard let json = defaults.string(forKey: Constants.UserDefaults.boardManItemHighlightsJSON),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func save(_ values: [String: String]) {
        guard let data = try? JSONEncoder().encode(values),
              let json = String(data: data, encoding: .utf8) else { return }
        defaults.set(json, forKey: Constants.UserDefaults.boardManItemHighlightsJSON)
        defaults.synchronize()
        NotificationCenter.default.post(name: Notification.Name(rawValue: Constants.Notification.closeSnippetEditor), object: nil)
    }
}

final class BoardManMaskedItemStore {
    static let shared = BoardManMaskedItemStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppEnvironment.current.defaults) {
        self.defaults = defaults
    }

    func isMasked(_ identifier: String) -> Bool {
        return identifiers.contains(identifier)
    }

    @discardableResult
    func toggle(_ identifier: String) -> Bool {
        let next = !isMasked(identifier)
        setMasked(next, for: identifier)
        return next
    }

    func setMasked(_ masked: Bool, for identifier: String) {
        var next = identifiers
        if masked {
            next.insert(identifier)
        } else {
            next.remove(identifier)
        }
        save(next)
    }

    func remove(_ identifiersToRemove: [String]) {
        guard !identifiersToRemove.isEmpty else { return }
        save(identifiers.subtracting(identifiersToRemove))
    }

    private var identifiers: Set<String> {
        return Set(defaults.stringArray(forKey: Constants.UserDefaults.boardManMaskedItemIdentifiers) ?? [])
    }

    private func save(_ values: Set<String>) {
        defaults.set(Array(values).sorted(), forKey: Constants.UserDefaults.boardManMaskedItemIdentifiers)
        defaults.synchronize()
        NotificationCenter.default.post(
            name: Notification.Name(rawValue: Constants.Notification.closeSnippetEditor),
            object: nil
        )
    }
}

struct BoardManHistoryCSVRow: Equatable {
    let copiedAt: Date
    let updatedAt: Date
    let displayName: String
    let content: String
    let pasteCount: Int
    let isPinned: Bool
    let primaryType: String
}

enum BoardManHistoryCSVExporter {
    static func csv(rows: [BoardManHistoryCSVRow]) -> String {
        var lines = ["copied_at,updated_at,display_name,content,paste_count,pinned,primary_type"]
        let formatter = ISO8601DateFormatter()
        rows.forEach { row in
            lines.append([
                formatter.string(from: row.copiedAt),
                formatter.string(from: row.updatedAt),
                row.displayName,
                row.content,
                "\(row.pasteCount)",
                row.isPinned ? "true" : "false",
                row.primaryType
            ].map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func escape(_ value: String) -> String {
        let normalized = value.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard normalized.contains(",") || normalized.contains("\"") || normalized.contains("\n") else {
            return normalized
        }
        return "\"\(normalized.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

// MARK: - Board-Man History/Snippet Links
final class HistorySnippetLinkStore {

    static let shared = HistorySnippetLinkStore()

    private let defaults: UserDefaults
    private let linksKey = "com.uniplanck.BoardMan.historySnippetLinks"

    init(defaults: UserDefaults = AppEnvironment.current.defaults) {
        self.defaults = defaults
    }

    func link(snippetIdentifier: String, historyIdentifier: String) {
        guard !snippetIdentifier.isEmpty, !historyIdentifier.isEmpty else { return }
        var values = links
        values[snippetIdentifier] = historyIdentifier
        defaults.set(values, forKey: linksKey)
    }

    func historyIdentifier(forSnippet snippetIdentifier: String) -> String? {
        return links[snippetIdentifier]
    }

    func snippetIdentifiers(forHistory historyIdentifier: String) -> [String] {
        return links.compactMap { snippetIdentifier, linkedHistoryIdentifier in
            linkedHistoryIdentifier == historyIdentifier ? snippetIdentifier : nil
        }.sorted()
    }

    func unlinkSnippet(_ snippetIdentifier: String) {
        var values = links
        values.removeValue(forKey: snippetIdentifier)
        defaults.set(values, forKey: linksKey)
    }

    func unlinkHistory(_ historyIdentifier: String) {
        let values = links.filter { $0.value != historyIdentifier }
        defaults.set(values, forKey: linksKey)
    }

    private var links: [String: String] {
        return defaults.dictionary(forKey: linksKey) as? [String: String] ?? [:]
    }
}

// MARK: - BoardMan History Item (lightweight for panel)
enum BoardManPresentationItemScope: Equatable {
    case historyOnly
    case complete
}

enum BoardManLanguage: String, CaseIterable {
    case system = "System"
    case japanese = "日本語"
    case english = "English"
    case simplifiedChinese = "简体中文"
    case korean = "한국어"

    static func allowed(_ value: String?) -> BoardManLanguage {
        return allCases.first(where: { $0.rawValue == value }) ?? .system
    }

    var resolved: BoardManLanguage {
        guard self == .system else { return self }
        let code = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if code.hasPrefix("ja") { return .japanese }
        if code.hasPrefix("zh") { return .simplifiedChinese }
        if code.hasPrefix("ko") { return .korean }
        return .english
    }
}

func boardManText(_ english: String) -> String {
    let language = BoardManLanguage.allowed(
        AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManLanguage)
    ).resolved
    guard language != .english else {
        return english == "Snippets" ? "Templates" : english
    }

    let japanese: [String: String] = [
        "History": "履歴", "Snippets": "定型文", "Settings": "設定",
        "General": "一般", "Appearance": "外観", "Privacy": "プライバシー",
        "Updates": "アップデート", "License": "ライセンス",
        "Startup, menu bar, and keyboard shortcuts": "起動、メニューバー、キーボードショートカット",
        "Layout, timestamps, counts, and theme": "レイアウト、時刻、回数、テーマ",
        "Preview": "プレビュー", "Layout": "レイアウト", "Timestamp": "時刻", "Usage": "使用状況", "Theme & Colors": "テーマと色",
        "Advanced settings": "詳細設定", "Show advanced settings": "詳細設定を表示", "Hide advanced settings": "詳細設定を隠す",
        "See changes instantly before returning to History.": "履歴へ戻る前に変更結果をその場で確認できます。",
        "Panel size, row structure, and visual density.": "パネルサイズ、行構造、表示密度を調整します。",
        "Choose how time is formatted and placed.": "時刻の形式と表示位置を調整します。",
        "Paste counts and used-item treatment.": "使用回数と使用済み項目の見え方を調整します。",
        "Theme, mode, typography, and surface style.": "テーマ、表示モード、フォント、表面スタイルを調整します。",
        "Relative time details, custom colors, and preview scale.": "相対時刻の詳細、カスタム色、プレビュー倍率を調整します。",
        "Design review notes": "デザインレビューのメモ", "Release checklist": "リリース確認リスト",
        "Retention, duplicate handling, and cleanup": "保存件数、重複処理、履歴削除",
        "Folders, snippets, and folder shortcuts": "グループ、スニペット、グループショートカット",
        "Excluded apps, stored data, and filters": "除外アプリ、保存データ、フィルター",
        "Version and update channel": "バージョンとアップデート設定",
        "Plan, activation, and usage limits": "プラン、認証、利用制限",
        "Language": "言語", "Window mode": "ウインドウ表示", "Show in Dock": "Dockに表示",
        "Launch on Login": "ログイン時に起動", "Send Command+V": "Command+Vを送信",
        "Keyboard Shortcuts": "キーボードショートカット", "Rows": "行番号",
        "Time": "時刻", "Position": "位置", "Relative format": "相対時刻形式",
        "Number": "数値", "Unit": "単位", "Suffix": "表記", "Under 1 minute": "1分以内",
        "Time action": "時刻操作", "Shortcut after send": "送信後ショートカット",
        "Enable shortcut after send": "送信後ショートカットを有効化",
        "Shortcut for time action": "時刻操作ショートカット",
        "Enable shortcut for time action": "時刻操作でショートカットを実行",
        "Delay": "遅延", "Seconds": "秒",
        "Click": "クリック", "Long Press": "長押し",
        "Click: Paste and Send": "クリック：ペーストして送信", "Long Press: Paste and Send": "長押し：ペーストして送信",
        "Click: Run Shortcut Below": "クリック：下のショートカットを実行",
        "Long Press: Run Shortcut Below": "長押し：下のショートカットを実行",
        "Click: Hide / Show Content": "クリック：内容を非表示／表示",
        "Long Press: Hide / Show Content": "長押し：内容を非表示／表示",
        "Count": "使用回数", "Style": "表示形式",
        "Used": "使用済み", "Pin label": "Pin表記", "Images": "画像", "Image side": "画像位置",
        "Theme": "テーマ", "Mode": "表示モード", "UI": "UI",
        "Font": "フォント", "Text size": "文字サイズ", "Lighten": "明るくする", "Height": "高さ",
        "Accent": "アクセント", "Panel": "パネル", "Used color": "使用済み色",
        "Opacity": "透明度", "Reset colors": "色をリセット",
        "Restart Board-Man": "Board-Manを再起動", "Quit Board-Man": "Board-Manを終了",
        "Open Archived Text History": "退避したテキスト履歴を開く", "Visible history": "表示履歴数",
        "Set Display Name…": "表示名を設定…", "Show Name Only": "名前だけ表示", "Remove Display Name": "表示名を削除",
        "Manage Snippets": "スニペットを管理", "Move Up": "上へ移動", "Move Down": "下へ移動",
        "Edit Mode": "編集モード", "View Mode": "閲覧モード", "Cancel": "キャンセル",
        "Save Changes": "変更を保存", "Reorder": "並び替え", "Reordering": "並び替え中",
        "Select a group to reorder": "並び替えるグループを選択してください",
        "Reorder mode: drag the handle on the left": "並び替えモード：左端の≡をドラッグしてください",
        "Edit mode: change the fields, then save": "編集モード：内容を変更して保存してください",
        "Select a snippet to preview": "スニペットを選択してください",
        "Check for Updates": "今すぐ確認", "Automatically check for updates": "アップデートを自動確認",
        "Daily": "毎日", "Weekly": "毎週", "Monthly": "毎月",
        "Updates will be delivered through GitHub Releases once an appcast is published.": "appcast公開後、GitHub Releases経由でアップデートを配信します。",
        "Search clipboard history and snippets": "履歴とスニペットを検索", "Search": "検索",
        "Condition": "条件", "Condition ON": "条件 ON", "Recent Use": "最近使用順", "Copy Order": "コピー順",
        "No clipboard history yet": "クリップボード履歴はありません", "No snippets yet": "定型文はありません",
        "Open Board-Man": "Board-Manを開く", "Quick Mode": "クイックモード",
        "Open History": "履歴を開く", "Open Snippets": "スニペットを開く", "Clear History": "履歴を消去",
        "Show the main clipboard panel": "メインのクリップボードパネルを表示します",
        "Show the top 3 items from the selected History filter": "選択中の履歴フィルターから上位3件を表示します",
        "Jump directly to clipboard history": "クリップボード履歴を直接開きます",
        "Jump directly to snippets": "スニペットを直接開きます",
        "Clear history after confirmation": "確認後に履歴を消去します",
        "Add": "追加", "Edit": "編集", "Delete": "削除", "Clear": "消去", "Save": "保存", "Upgrade": "アップグレード", "OK": "OK",
        "Category": "グループ", "Add Group": "グループ追加", "Rename Group": "グループ名変更", "Delete Group": "グループ削除",
        "Title": "タイトル", "Content": "内容", "Group Enabled": "グループを有効化", "Snippet Enabled": "定型文を有効化",
        "Saved Filters": "保存フィルタ", "Save Current Filter…": "現在の条件を保存…",
        "Update Selected Filter": "選択中のフィルタを更新", "Rename Selected Filter…": "選択中のフィルタ名を変更…",
        "Delete Selected Filter": "選択中のフィルタを削除", "Clear Saved Filter": "保存フィルタの選択を解除",
        "Save Filter": "フィルタを保存", "Rename Filter": "フィルタ名を変更", "Filter name": "フィルタ名",
        "All Groups": "すべてのグループ", "%d Groups": "%dグループ",
        "Click the preview to edit": "右側のプレビューをクリックして編集",
        "Hover a snippet, then click the preview to edit • ⌘C Copy • ⌘P Pin": "スニペットにカーソルを合わせ、右側をクリックして編集 • ⌘C コピー • ⌘P Pin",
        "Skip pinned items with arrow keys": "上下キーではPin項目を飛ばす",
        "Long press": "長押し動作", "Pin duration": "期限Pinの期間", "Add duration": "期間を追加", "Remove duration": "期間を削除",
        "Pin / Unpin": "Pin切替", "Timed Pin": "期限付きPin", "Remove Timed Pin": "期限付きPinを解除",
        "Hide / Show Content": "内容を非表示／表示", "Hide Content": "内容を非表示", "Show Content": "内容を表示",
        "Hide preview when content is hidden": "内容非表示時はプレビューを表示しない",
        "Hide title when content is hidden": "内容非表示時はタイトルを表示しない",
        "Do Nothing": "何もしない", "None": "なし", "Localized": "言語連動",
        "Minutes": "分", "Hours": "時間", "Days": "日", "Weeks": "週", "%d min": "%d分", "%d hr": "%d時間", "%d day": "%d日", "%d wk": "%d週",
        "Highlight": "色で目立たせる", "Remove Highlight": "色付けを解除",
        "Red": "赤", "Orange": "オレンジ", "Yellow": "黄", "Green": "緑", "Blue": "青", "Purple": "紫", "Gray": "グレー",
        "Item highlighting is available with Pro.": "項目の色付けはPro限定です。",

        "Export History CSV": "履歴をCSV保存", "CSV export failed": "CSV保存に失敗しました",
        "Dedupe": "重複をまとめる", "Reuse top": "再利用時に先頭へ", "Overwrite same": "同一履歴を上書き",
        "Icon": "アイコン", "Black": "黒", "White": "白", "Hidden": "非表示",
        "All": "すべて", "Unused": "未使用",
        "Paste": "貼り付け", "Pin": "Pin", "Unpin": "Pin解除", "Copy": "コピー",
        "Add to Snippets": "スニペットへ追加", "Add Snippet": "スニペットを追加", "Rename Snippet…": "表示名を変更…", "Edit Snippet": "スニペットを編集", "Delete Snippet": "スニペットを削除",
        "Delete History Item": "履歴項目を削除", "Delete this item from clipboard history?": "この項目をクリップボード履歴から削除しますか？",
        "Pinned items must be unpinned before deletion.": "Pinを解除してから削除してください。",
        "This changes the name shown in the snippet list.": "スニペット一覧に表示する名前を変更します。",
        "Uncategorized": "未分類", "Row Actions": "項目操作",
        "Advanced appearance": "高度な外観設定", "Unlock Pro to customize advanced visual presets.": "Proで高度な外観プリセットを利用できます。",
        "System": "システム", "Light": "ライト", "Dark": "ダーク", "Default": "標準", "Simple": "シンプル", "Monochrome": "モノクロ",
        "Relative": "相対時刻", "24-hour": "24時間", "24-hour + seconds": "24時間＋秒", "12-hour": "12時間", "12-hour + seconds": "12時間＋秒", "Date + time": "日付＋時刻",
        "Below": "下", "Left": "左", "Right": "右", "Badge": "バッジ", "Compact": "コンパクト",
        "Subtle Red": "薄い赤", "Amber": "アンバー", "Teal": "ティール", "Indigo": "インディゴ",
        "Graphite": "グラファイト", "Ocean": "オーシャン", "Rose": "ローズ", "Scarlet": "スカーレット", "Emerald": "エメラルド", "Violet": "バイオレット",
        "Stored Types": "保存対象", "Manage Excluded Apps": "除外アプリを管理", "Hide Rules": "非表示ルール",
        "Free": "無料", "Owner Lifetime": "オーナー永久版", "Trial": "試用版", "Pro Active": "Pro有効", "Expired": "期限切れ", "Invalid": "無効", "Offline Grace": "オフライン猶予", "Locked": "ロック中",
        "Untitled folder": "名称未設定のグループ", "Untitled snippet": "名称未設定のスニペット",
        "Enabled": "有効", "Disabled": "無効", "snippets": "スニペット",
        "Click a shortcut field, then press the new key combination. Changes apply immediately.": "ショートカット欄をクリックし、新しいキーの組み合わせを押してください。変更は即時反映されます。",
        "Choose what clicking or holding the timestamp does.": "時刻部分をクリックまたは長押ししたときの動作を選びます。",
        "Shortcut executed by the selected timestamp action. It can be edited while disabled.": "選択した時刻操作で実行するショートカットです。無効中でも編集できます。",
        "Enter the timed Pin duration directly.": "期限付きPinの時間を直接入力できます。",
        "word or phrase": "単語またはフレーズ",
        "Hidden only in Board-Man, data is not deleted.": "Board-Manの一覧から隠すだけで、データは削除されません。",
        "Secure local license": "安全なローカルライセンス", "Activate": "認証",
        "Online activation is not connected yet.": "オンライン認証はまだ接続されていません。",
        "Verified licenses are stored in Keychain and bound to this Mac. Online purchase activation remains unavailable.": "確認済みライセンスはキーチェーンに保存され、このMacに紐づきます。オンライン購入認証は未接続です。",
        "UI states: Free / Trial / Pro Active / Expired / Invalid / Offline Grace / Locked": "表示状態: 無料 / 試用 / Pro有効 / 期限切れ / 無効 / オフライン猶予 / ロック中",
        "Glass options are available here.": "ガラス表示の設定はこちらです。",
        "Snippet Not Saved": "スニペットを保存できませんでした",
        "Delete \"%@\"? Snippets in this group will be moved to Uncategorized.": "「%@」を削除しますか？このグループのスニペットは未分類へ移動します。",
        "Delete \"%@\" from snippets? Clipboard history is not changed.": "スニペット「%@」を削除しますか？クリップボード履歴は変更されません。",
        "Enter a group name.": "グループ名を入力してください。", "Group name is required.": "グループ名は必須です。", "Pro limit reached": "Pro上限に達しました",
        "Enter a title, category, and content.": "タイトル、グループ、内容を入力してください。", "Snippet content is required.": "スニペットの内容は必須です。",
        "Snippet groups are available with Pro. Free snippets are saved as Uncategorized.": "スニペットのグループ作成はPro限定です。無料版のスニペットは未分類へ保存されます。",
        "Free plan includes 5 snippets. Upgrade or activate Founder Lifetime to add more.": "無料プランで作成できるスニペットは5件です。追加するにはアップグレードしてください。",
        "Free plan allows up to 3 pinned items. Pro has unlimited pins.": "無料プランでPinできる項目は3件までです。Proでは無制限にPinできます。",
        "Preview scale": "プレビュー倍率", "Text preview": "テキストプレビュー", "Image preview": "画像プレビュー",
        "Pro only: custom colors and preview scale. Free preview stays at 100%.": "Pro限定：カスタム色とプレビュー倍率を利用できます。無料版は100%固定です。",
        "Pro only: group creation, ordering, and folder shortcuts.": "Pro限定：グループ作成・並び替え・グループショートカットを利用できます。",
        "Pro only": "Pro限定", "Changes discarded": "変更を破棄しました", "Saved": "保存しました",
        "Hover to open group list": "カーソルを合わせるとグループ一覧を開きます",
        "Clear all clipboard history?": "クリップボード履歴をすべて消去しますか？",
        "Activation is not connected yet. Free remains the default runtime entitlement.": "オンライン認証はまだ接続されていません。現在は無料プランとして動作します。",
        "Filter %@ history": "%@履歴の絞り込み",
        "Only matching items remain visible. Empty fields are ignored; clearing every field removes this condition.": "条件に一致する項目だけを表示します。空欄は無視され、すべて空にすると条件を削除します。",
        "Applies only to the %@ tab": "%@タブだけに適用",
        "Enable this condition": "この条件を有効にする", "No limit": "制限なし", "Shell-script-like text only": "シェルスクリプト風の文字列だけ",
        "Minimum characters": "最小文字数", "Must contain": "含む必要がある語句", "Must not contain": "除外する語句",
        "The original clipboard content is preserved for paste and preview.": "貼り付けとプレビュー用の元データは保持されます。",
        "Display name": "表示名",
        "Contains text": "含む", "Starts with": "先頭一致", "Ends with": "末尾一致", "Exact match": "完全一致",
        "contains": "含む", "starts": "先頭一致", "ends": "末尾一致", "exact": "完全一致",
        "Add Rule": "追加", "Remove Last": "最後を削除", "Free plan": "無料プラン", "Upgrade to Pro": "Proへアップグレード"
    ]
    let chinese: [String: String] = [
        "History": "历史", "Snippets": "模板", "Settings": "设置", "General": "常规",
        "Appearance": "外观", "Privacy": "隐私", "Updates": "更新", "License": "许可证",
        "Preview": "预览", "Layout": "布局", "Timestamp": "时间", "Usage": "使用情况", "Theme & Colors": "主题与颜色",
        "Advanced settings": "高级设置", "Show advanced settings": "显示高级设置", "Hide advanced settings": "隐藏高级设置",
        "Language": "语言", "Window mode": "窗口模式", "Show in Dock": "在 Dock 中显示",
        "Rows": "行号", "Time": "时间", "Position": "位置", "Relative format": "相对时间格式", "Number": "数字", "Unit": "单位", "Suffix": "后缀", "Under 1 minute": "1分钟以内", "Count": "使用次数",
        "Style": "样式", "Used": "已使用", "Theme": "主题", "Mode": "模式", "Font": "字体",
        "Text size": "文字大小", "Lighten": "变亮", "Height": "高度", "Accent": "强调色", "Panel": "面板",
        "Used color": "已使用颜色", "Opacity": "透明度", "Reset colors": "重置颜色",
        "Restart Board-Man": "重启 Board-Man", "Quit Board-Man": "退出 Board-Man",
        "Move Up": "上移", "Move Down": "下移", "Edit Mode": "编辑模式", "View Mode": "查看模式",
        "Cancel": "取消", "Save Changes": "保存更改", "Reorder": "排序", "Reordering": "排序中",
        "Select a group to reorder": "请选择要排序的分组", "Check for Updates": "立即检查",
        "Automatically check for updates": "自动检查更新", "Daily": "每天", "Weekly": "每周", "Monthly": "每月",
        "Search clipboard history and snippets": "搜索历史和片段", "Condition": "条件",
        "Time action": "时间操作", "Shortcut after send": "发送后快捷键", "Enable shortcut after send": "启用发送后快捷键",
        "Shortcut for time action": "时间操作快捷键", "Enable shortcut for time action": "为时间操作启用快捷键", "Delay": "延迟", "Seconds": "秒",
        "Click: Paste and Send": "点击：粘贴并发送", "Long Press: Paste and Send": "长按：粘贴并发送",
        "Click: Run Shortcut Below": "点击：执行下方快捷键", "Long Press: Run Shortcut Below": "长按：执行下方快捷键",
        "Click: Hide / Show Content": "点击：隐藏／显示内容", "Long Press: Hide / Show Content": "长按：隐藏／显示内容",
        "Hide / Show Content": "隐藏／显示内容", "Hide Content": "隐藏内容", "Show Content": "显示内容",
        "Pin duration": "限时置顶时长", "Add duration": "添加时长", "Remove duration": "删除时长", "None": "无", "Localized": "跟随语言"
    ]
    let korean: [String: String] = [
        "History": "기록", "Snippets": "문구", "Settings": "설정", "General": "일반",
        "Appearance": "모양", "Privacy": "개인정보", "Updates": "업데이트", "License": "라이선스",
        "Preview": "미리보기", "Layout": "레이아웃", "Timestamp": "시간", "Usage": "사용 현황", "Theme & Colors": "테마 및 색상",
        "Advanced settings": "고급 설정", "Show advanced settings": "고급 설정 표시", "Hide advanced settings": "고급 설정 숨기기",
        "Language": "언어", "Window mode": "윈도우 모드", "Show in Dock": "Dock에 표시",
        "Rows": "행 번호", "Time": "시간", "Position": "위치", "Relative format": "상대 시간 형식", "Number": "숫자", "Unit": "단위", "Suffix": "표기", "Under 1 minute": "1분 이내", "Count": "사용 횟수",
        "Style": "스타일", "Used": "사용됨", "Theme": "테마", "Mode": "모드", "Font": "폰트",
        "Text size": "글자 크기", "Lighten": "밝게", "Height": "높이", "Accent": "강조색", "Panel": "패널",
        "Used color": "사용됨 색상", "Opacity": "투명도", "Reset colors": "색상 초기화",
        "Restart Board-Man": "Board-Man 재시작", "Quit Board-Man": "Board-Man 종료",
        "Move Up": "위로 이동", "Move Down": "아래로 이동", "Edit Mode": "편집 모드", "View Mode": "보기 모드",
        "Cancel": "취소", "Save Changes": "변경 저장", "Reorder": "순서 변경", "Reordering": "순서 변경 중",
        "Select a group to reorder": "순서를 변경할 그룹을 선택하세요", "Check for Updates": "지금 확인",
        "Automatically check for updates": "업데이트 자동 확인", "Daily": "매일", "Weekly": "매주", "Monthly": "매월",
        "Search clipboard history and snippets": "기록 및 스니펫 검색", "Condition": "조건",
        "Time action": "시간 동작", "Shortcut after send": "전송 후 단축키", "Enable shortcut after send": "전송 후 단축키 사용",
        "Shortcut for time action": "시간 동작 단축키", "Enable shortcut for time action": "시간 동작 단축키 사용", "Delay": "지연", "Seconds": "초",
        "Click: Paste and Send": "클릭: 붙여넣고 전송", "Long Press: Paste and Send": "길게 누르기: 붙여넣고 전송",
        "Click: Run Shortcut Below": "클릭: 아래 단축키 실행", "Long Press: Run Shortcut Below": "길게 누르기: 아래 단축키 실행",
        "Click: Hide / Show Content": "클릭: 내용 숨기기／표시", "Long Press: Hide / Show Content": "길게 누르기: 내용 숨기기／표시",
        "Hide / Show Content": "내용 숨기기／표시", "Hide Content": "내용 숨기기", "Show Content": "내용 표시",
        "Pin duration": "기간 Pin 시간", "Add duration": "기간 추가", "Remove duration": "기간 삭제", "None": "없음", "Localized": "언어 연동"
    ]
    switch language {
    case .japanese: return japanese[english] ?? english
    case .simplifiedChinese: return chinese[english] ?? english
    case .korean: return korean[english] ?? english
    case .system, .english: return english
    }
}

enum BoardManInlineSettingsCategory: Int, CaseIterable {
    case general, view, history, snippets, privacy, updates, license

    var title: String {
        switch self {
        case .general: return boardManText("General")
        case .view: return boardManText("Appearance")
        case .history: return boardManText("History")
        case .snippets: return boardManText("Snippets")
        case .privacy: return boardManText("Privacy")
        case .updates: return boardManText("Updates")
        case .license: return boardManText("License")
        }
    }

    var detail: String {
        switch self {
        case .general: return boardManText("Startup, menu bar, and keyboard shortcuts")
        case .view: return boardManText("Layout, timestamps, counts, and theme")
        case .history: return boardManText("Retention, duplicate handling, and cleanup")
        case .snippets: return boardManText("Folders, snippets, and folder shortcuts")
        case .privacy: return boardManText("Excluded apps, stored data, and filters")
        case .updates: return boardManText("Version and update channel")
        case .license: return boardManText("Plan, activation, and usage limits")
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .view: return "paintbrush"
        case .history: return "clock.arrow.circlepath"
        case .snippets: return "text.badge.plus"
        case .privacy: return "hand.raised"
        case .updates: return "arrow.triangle.2.circlepath"
        case .license: return "checkmark.seal"
        }
    }
}

private enum BoardManGlobalShortcutKind: Int, CaseIterable {
    case openBoardMan, quickMode, history, snippets, clearHistory

    var title: String {
        switch self {
        case .openBoardMan: return boardManText("Open Board-Man")
        case .quickMode: return boardManText("Quick Mode")
        case .history: return boardManText("Open History")
        case .snippets: return boardManText("Open Snippets")
        case .clearHistory: return boardManText("Clear History")
        }
    }

    var detail: String {
        switch self {
        case .openBoardMan: return boardManText("Show the main clipboard panel")
        case .quickMode: return boardManText("Show the top 3 items from the selected History filter")
        case .history: return boardManText("Jump directly to clipboard history")
        case .snippets: return boardManText("Jump directly to snippets")
        case .clearHistory: return boardManText("Clear history after confirmation")
        }
    }
}

private final class BoardManGlobalShortcutRow {
    let kind: BoardManGlobalShortcutKind
    let titleLabel: NSTextField
    let detailLabel: NSTextField
    let recordView: RecordView
    let clearButton: NSButton

    init(kind: BoardManGlobalShortcutKind, keyCombo: KeyCombo?) {
        self.kind = kind
        titleLabel = NSTextField(labelWithString: kind.title)
        titleLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        detailLabel = NSTextField(labelWithString: kind.detail)
        detailLabel.font = NSFont.systemFont(ofSize: 10.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail

        recordView = RecordView(frame: .zero)
        recordView.keyCombo = keyCombo

        clearButton = NSButton(title: boardManText("Clear"), target: nil, action: nil)
        clearButton.font = NSFont.systemFont(ofSize: 10)
        clearButton.bezelStyle = .rounded
        clearButton.tag = kind.rawValue
    }

    var views: [NSView] {
        return [titleLabel, detailLabel, recordView, clearButton]
    }
}

private final class BoardManSnippetShortcutRow {
    let folderIdentifier: String
    let titleLabel: NSTextField
    let detailLabel: NSTextField
    let recordView: RecordView
    let clearButton: NSButton

    init(folder: BoardManFolder, keyCombo: KeyCombo?) {
        folderIdentifier = folder.identifier

        let title = folder.title.trimmingCharacters(in: .whitespacesAndNewlines)
        titleLabel = NSTextField(labelWithString: title.isEmpty ? boardManText("Untitled folder") : title)
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        let enabledText = boardManText(folder.enable ? "Enabled" : "Disabled")
        detailLabel = NSTextField(labelWithString: "\(enabledText) / \(folder.snippets.count) \(boardManText("snippets"))")
        detailLabel.font = NSFont.systemFont(ofSize: 10)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail

        recordView = RecordView(frame: .zero)
        recordView.keyCombo = keyCombo

        clearButton = NSButton(title: boardManText("Clear"), target: nil, action: nil)
        clearButton.font = NSFont.systemFont(ofSize: 10)
        clearButton.bezelStyle = .rounded
        clearButton.identifier = NSUserInterfaceItemIdentifier(folder.identifier)
    }

    var views: [NSView] {
        return [titleLabel, detailLabel, recordView, clearButton]
    }
}

fileprivate enum BoardManHideRuleMode: String, Codable, CaseIterable {
    case contains
    case startsWith
    case endsWith
    case exact

    var title: String {
        switch self {
        case .contains: return boardManText("Contains text")
        case .startsWith: return boardManText("Starts with")
        case .endsWith: return boardManText("Ends with")
        case .exact: return boardManText("Exact match")
        }
    }

    var summaryTitle: String {
        switch self {
        case .contains: return boardManText("contains")
        case .startsWith: return boardManText("starts")
        case .endsWith: return boardManText("ends")
        case .exact: return boardManText("exact")
        }
    }
}

fileprivate struct BoardManHideRule: Codable {
    let mode: BoardManHideRuleMode
    let value: String

    var normalizedValue: String {
        return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func matches(_ text: String) -> Bool {
        let ruleValue = normalizedValue
        guard !ruleValue.isEmpty else { return false }
        let normalizedText = text.lowercased()
        switch mode {
        case .contains:
            return normalizedText.contains(ruleValue)
        case .startsWith:
            return normalizedText.hasPrefix(ruleValue)
        case .endsWith:
            return normalizedText.hasSuffix(ruleValue)
        case .exact:
            return normalizedText == ruleValue
        }
    }
}

fileprivate final class BoardManHideRuleStore {
    static let shared = BoardManHideRuleStore()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppEnvironment.current.defaults) {
        self.defaults = defaults
    }

    var rules: [BoardManHideRule] {
        guard let json = defaults.string(forKey: Constants.UserDefaults.boardManHideRulesJSON),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([BoardManHideRule].self, from: data) else {
            return []
        }
        return decoded.filter { !$0.normalizedValue.isEmpty }
    }

    func add(mode: BoardManHideRuleMode, value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var next = rules
        next.append(BoardManHideRule(mode: mode, value: trimmed))
        save(next)
    }

    func removeLast() {
        var next = rules
        guard !next.isEmpty else { return }
        next.removeLast()
        save(next)
    }

    func clear() {
        save([])
    }

    private func save(_ rules: [BoardManHideRule]) {
        guard let data = try? JSONEncoder().encode(rules),
              let json = String(data: data, encoding: .utf8) else { return }
        defaults.set(json, forKey: Constants.UserDefaults.boardManHideRulesJSON)
        defaults.synchronize()
    }
}

struct BoardManHistoryCondition: Codable, Equatable {
    var isEnabled: Bool
    var minimumLength: Int
    var includedTerms: [String]
    var excludedTerms: [String]
    var matchesAllIncludedTerms: Bool
    var shellLikeOnly: Bool

    static let empty = BoardManHistoryCondition(
        isEnabled: true,
        minimumLength: 0,
        includedTerms: [],
        excludedTerms: [],
        matchesAllIncludedTerms: true,
        shellLikeOnly: false
    )

    var hasCriteria: Bool {
        return minimumLength > 0 || !includedTerms.isEmpty || !excludedTerms.isEmpty || shellLikeOnly
    }

    func matches(_ text: String) -> Bool {
        guard isEnabled else { return true }
        let normalized = text.lowercased()
        if minimumLength > 0, text.count < minimumLength { return false }
        if shellLikeOnly, !Self.looksLikeShellScript(text) { return false }
        if !includedTerms.isEmpty {
            let results = includedTerms.map { normalized.contains($0.lowercased()) }
            if matchesAllIncludedTerms ? results.contains(false) : !results.contains(true) { return false }
        }
        if excludedTerms.contains(where: { normalized.contains($0.lowercased()) }) { return false }
        return true
    }

    static func parsedTerms(_ value: String) -> [String] {
        return value
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func looksLikeShellScript(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("#!") { return true }
        if normalized.contains(" && ") || normalized.contains(" || ") || normalized.contains("$(") { return true }
        let commandPattern = "(^|\\n)\\s*(sudo|cd|ls|grep|find|curl|wget|git|npm|pnpm|yarn|brew|docker|python|python3|node|chmod|chown|ssh|scp|rsync|echo|export|source)\\b"
        if normalized.range(of: commandPattern, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        return normalized.range(of: "\\s\\|\\s", options: .regularExpression) != nil
    }
}

fileprivate final class BoardManHistoryConditionStore {
    static let shared = BoardManHistoryConditionStore()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppEnvironment.current.defaults) {
        self.defaults = defaults
    }

    func condition(for filter: BoardManHistoryUsageFilter) -> BoardManHistoryCondition? {
        return conditions[filter.rawValue]
    }

    func save(_ condition: BoardManHistoryCondition, for filter: BoardManHistoryUsageFilter) {
        var next = conditions
        next[filter.rawValue] = condition
        save(next)
    }

    func setEnabled(_ enabled: Bool, for filter: BoardManHistoryUsageFilter) {
        var next = conditions
        guard var condition = next[filter.rawValue] else { return }
        condition.isEnabled = enabled
        next[filter.rawValue] = condition
        save(next)
    }

    func delete(for filter: BoardManHistoryUsageFilter) {
        var next = conditions
        next.removeValue(forKey: filter.rawValue)
        save(next)
    }

    private var conditions: [String: BoardManHistoryCondition] {
        guard let json = defaults.string(forKey: Constants.UserDefaults.boardManHistoryConditionsJSON),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: BoardManHistoryCondition].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func save(_ conditions: [String: BoardManHistoryCondition]) {
        guard let data = try? JSONEncoder().encode(conditions),
              let json = String(data: data, encoding: .utf8) else { return }
        defaults.set(json, forKey: Constants.UserDefaults.boardManHistoryConditionsJSON)
        defaults.synchronize()
    }
}

struct BoardManSavedFilterPreset: Codable, Equatable {
    let id: String
    var name: String
    var usageFilterRawValue: String
    var condition: BoardManHistoryCondition
    var snippetGroupIdentifiers: [String]

    var usageFilter: BoardManHistoryUsageFilter {
        return BoardManHistoryUsageFilter.allowed(usageFilterRawValue)
    }

    var hasCriteria: Bool {
        return usageFilter != .all || condition.hasCriteria || !snippetGroupIdentifiers.isEmpty
    }

    func validSnippetGroupIdentifiers(availableIdentifiers: Set<String>) -> [String] {
        return snippetGroupIdentifiers.filter { availableIdentifiers.contains($0) }
    }
}

final class BoardManSavedFilterStore {
    static let shared = BoardManSavedFilterStore()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppEnvironment.current.defaults) {
        self.defaults = defaults
    }

    var presets: [BoardManSavedFilterPreset] {
        guard let json = defaults.string(forKey: Constants.UserDefaults.boardManSavedFiltersJSON),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([BoardManSavedFilterPreset].self, from: data) else {
            return []
        }
        return decoded
    }

    var selectedPresetID: String? {
        let value = defaults.string(forKey: Constants.UserDefaults.boardManSelectedSavedFilterID)
        return value?.isEmpty == false ? value : nil
    }

    var selectedPreset: BoardManSavedFilterPreset? {
        guard let selectedPresetID else { return nil }
        return presets.first { $0.id == selectedPresetID }
    }

    func select(_ id: String?) {
        if let id {
            defaults.set(id, forKey: Constants.UserDefaults.boardManSelectedSavedFilterID)
        } else {
            defaults.removeObject(forKey: Constants.UserDefaults.boardManSelectedSavedFilterID)
        }
        defaults.synchronize()
    }

    @discardableResult
    func save(_ preset: BoardManSavedFilterPreset) -> BoardManSavedFilterPreset {
        var next = presets
        if let index = next.firstIndex(where: { $0.id == preset.id }) {
            next[index] = preset
        } else {
            next.append(preset)
        }
        persist(next)
        select(preset.id)
        return preset
    }

    func delete(_ id: String) {
        persist(presets.filter { $0.id != id })
        if selectedPresetID == id {
            select(nil)
        }
    }

    private func persist(_ presets: [BoardManSavedFilterPreset]) {
        guard let data = try? JSONEncoder().encode(presets),
              let json = String(data: data, encoding: .utf8) else { return }
        defaults.set(json, forKey: Constants.UserDefaults.boardManSavedFiltersJSON)
        defaults.synchronize()
    }
}

fileprivate final class BoardManProLockedControlView: NSView {

    private let feature: EntitlementFeature
    private let titleLabel = NSTextField(labelWithString: "")
    private let badgeLabel = NSTextField(labelWithString: "PRO")
    private let explanationLabel = NSTextField(labelWithString: "")
    private let upgradeButton: NSButton
    private let lockedControl: NSView
    private var lockImageView: NSImageView?

    init(title: String,
         explanation: String,
         feature: EntitlementFeature,
         control: NSView,
         upgradeTarget: AnyObject?,
         upgradeAction: Selector?) {
        self.feature = feature
        self.lockedControl = control
        self.upgradeButton = NSButton(title: boardManText("Upgrade"), target: upgradeTarget, action: upgradeAction)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1).cgColor
        layer?.borderColor = NSColor(calibratedWhite: 0.22, alpha: 1).cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 8

        if #available(macOS 11.0, *),
           let lockImage = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Locked") {
            let imageView = NSImageView(image: lockImage)
            imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            imageView.contentTintColor = .systemRed
            addSubview(imageView)
            lockImageView = imageView
        }

        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 2
        titleLabel.cell?.wraps = true
        addSubview(titleLabel)

        badgeLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        badgeLabel.textColor = .white
        badgeLabel.alignment = .center
        badgeLabel.wantsLayer = true
        badgeLabel.layer?.backgroundColor = NSColor.systemRed.cgColor
        badgeLabel.layer?.cornerRadius = 5
        badgeLabel.layer?.masksToBounds = true
        addSubview(badgeLabel)

        explanationLabel.stringValue = explanation
        explanationLabel.font = NSFont.systemFont(ofSize: 11)
        explanationLabel.textColor = .secondaryLabelColor
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.maximumNumberOfLines = 2
        explanationLabel.cell?.wraps = true
        addSubview(explanationLabel)

        upgradeButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        upgradeButton.bezelStyle = .rounded
        upgradeButton.toolTip = "Upgrade to unlock this Pro control."
        addSubview(upgradeButton)

        addSubview(lockedControl)
        refresh()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 10
        let lockSize: CGFloat = 14
        let badgeWidth: CGFloat = 34
        let buttonWidth: CGFloat = 78
        let controlGap: CGFloat = 10
        let controlWidth = max(96, bounds.width - (inset * 2) - buttonWidth - controlGap)
        let titleX = inset + lockSize + 6
        lockImageView?.frame = NSRect(x: inset, y: bounds.height - 27, width: lockSize, height: lockSize)
        badgeLabel.frame = NSRect(x: bounds.width - badgeWidth - inset, y: bounds.height - 28, width: badgeWidth, height: 18)
        titleLabel.frame = NSRect(x: titleX, y: bounds.height - 46, width: max(80, badgeLabel.frame.minX - titleX - 8), height: 36)
        explanationLabel.frame = NSRect(x: inset, y: bounds.height - 82, width: max(80, bounds.width - inset * 2), height: 34)
        lockedControl.frame = NSRect(x: inset, y: 10, width: controlWidth, height: 24)
        upgradeButton.frame = NSRect(x: lockedControl.frame.maxX + controlGap, y: 8, width: buttonWidth, height: 24)
    }

    func updateLocalizedText(title: String, explanation: String, upgradeTitle: String) {
        titleLabel.stringValue = title
        explanationLabel.stringValue = explanation
        upgradeButton.title = upgradeTitle
        needsLayout = true
    }

    func refresh() {
        let canUse = EntitlementGate.canUse(feature)
        setEnabled(canUse, in: lockedControl)
        lockedControl.alphaValue = canUse ? 1 : 0.48
        lockImageView?.isHidden = canUse
        badgeLabel.isHidden = canUse
        explanationLabel.textColor = canUse ? .secondaryLabelColor : .tertiaryLabelColor
        upgradeButton.isHidden = canUse
        toolTip = canUse ? "Available in your current plan." : "Pro feature. Upgrade to unlock this control."
    }

    private func setEnabled(_ enabled: Bool, in view: NSView) {
        if let control = view as? NSControl {
            control.isEnabled = enabled
        }
        view.subviews.forEach { setEnabled(enabled, in: $0) }
    }
}

private final class BoardManHistoryTableView: NSTableView {
    weak var panelKeyOwner: BoardManPanel?

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        enclosingScrollView?.hasHorizontalScroller = false
        enclosingScrollView?.horizontalScrollElasticity = .none
        gridStyleMask = []
    }

    override func keyDown(with event: NSEvent) {
        if panelKeyOwner?.handlePanelKey(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}

final class BoardManHistoryRowView: NSTableRowView {
    enum BackgroundKind: Equatable {
        case highlight
        case selected
        case hovered
        case used
        case plain
    }

    weak var previewOwner: BoardManPanel?
    private var hoverTrackingArea: NSTrackingArea?

    static func backgroundKind(isSelected: Bool,
                               isHovered: Bool,
                               hasHighlight: Bool,
                               hasUsedAppearance: Bool) -> BackgroundKind {
        if hasHighlight { return .highlight }
        if isSelected { return .selected }
        if isHovered { return .hovered }
        if hasUsedAppearance { return .used }
        return .plain
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        guard let tableView = superview as? NSTableView else { return }
        previewOwner?.setHoveredRow(tableView.row(for: self))
    }

    override func mouseExited(with event: NSEvent) {
        let row = (superview as? NSTableView)?.row(for: self) ?? -1
        previewOwner?.clearHoveredRow(row)
    }

    override func drawBackground(in dirtyRect: NSRect) {
        let row = (superview as? NSTableView)?.row(for: self) ?? -1
        let rowRect = bounds.insetBy(dx: 6, dy: 3)
        let useLiquidGlass = previewOwner?.isLiquidGlassEnabled == true
        let lightenTheme = previewOwner?.isThemeLightenEnabled == true
        let preset = previewOwner?.themePreset ?? .defaultPreset
        let accentColor = previewOwner?.themeAccentColor ?? preset.accentColor
        let isSelected = previewOwner?.isSelectedRow(row) == true
        let isHovered = previewOwner?.isHoveredRow(row) == true
        let isPinned = previewOwner?.isPinnedRow(row) == true
        let highlightAppearance = previewOwner?.itemHighlightAppearance(for: row)
        let usedAppearance = previewOwner?.usedItemAppearance(for: row)
        let kind = Self.backgroundKind(
            isSelected: isSelected,
            isHovered: isHovered,
            hasHighlight: highlightAppearance != nil,
            hasUsedAppearance: usedAppearance != nil
        )
        let path = NSBezierPath(roundedRect: rowRect, xRadius: 9, yRadius: 9)

        switch kind {
        case .highlight:
            if let appearance = highlightAppearance {
                appearance.background.setFill()
                path.fill()
                appearance.border.setStroke()
                path.lineWidth = appearance.borderWidth
                path.stroke()
            }
            if isSelected {
                let selectionPath = NSBezierPath(
                    roundedRect: rowRect.insetBy(dx: 1, dy: 1),
                    xRadius: 8,
                    yRadius: 8
                )
                accentColor.withAlphaComponent(lightenTheme ? 0.48 : 0.78).setStroke()
                selectionPath.lineWidth = 2
                selectionPath.stroke()
            }
        case .selected:
            accentColor.withAlphaComponent(lightenTheme ? 0.12 : (useLiquidGlass ? 0.34 : 0.28)).setFill()
            path.fill()
            accentColor.withAlphaComponent(lightenTheme ? 0.30 : (useLiquidGlass ? 0.54 : 0.46)).setStroke()
            path.lineWidth = 1
            path.stroke()
        case .hovered:
            accentColor.withAlphaComponent(lightenTheme ? 0.07 : (useLiquidGlass ? 0.18 : 0.16)).setFill()
            path.fill()
            preset.edgeColor(useLiquidGlass: useLiquidGlass, lighten: lightenTheme).setStroke()
            path.lineWidth = 1
            path.stroke()
        case .used:
            if let appearance = usedAppearance {
                appearance.background.setFill()
                path.fill()
                appearance.border.setStroke()
                path.lineWidth = appearance.borderWidth
                path.stroke()
            }
        case .plain:
            if row >= 0 {
                let separator = NSBezierPath()
                separator.move(to: NSPoint(x: 18, y: 0.5))
                separator.line(to: NSPoint(x: max(18, bounds.maxX - 18), y: 0.5))
                NSColor.separatorColor.withAlphaComponent(useLiquidGlass ? 0.22 : 0.34).setStroke()
                separator.lineWidth = 0.5
                separator.stroke()
            } else {
                super.drawBackground(in: dirtyRect)
            }
        }

        if isPinned {
            let indicatorRect = NSRect(x: 8, y: 10, width: 3, height: max(10, bounds.height - 20))
            let indicator = NSBezierPath(roundedRect: indicatorRect, xRadius: 1.5, yRadius: 1.5)
            accentColor.withAlphaComponent(lightenTheme ? 0.52 : 0.88).setFill()
            indicator.fill()
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        drawBackground(in: dirtyRect)
    }
}

final class BoardManHoverPopUpButton: NSPopUpButton {
    private var hoverTrackingArea: NSTrackingArea?
    private var hoverWorkItem: DispatchWorkItem?
    private(set) var isHovering = false
    var opensOnHover = true
    var hoverDelay: TimeInterval = 0.32

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        setHovering(true, opensMenu: true)
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        setHovering(false, opensMenu: false)
        super.mouseExited(with: event)
    }

    func setHoveringForTesting(_ value: Bool) {
        setHovering(value, opensMenu: false)
    }

    private func setHovering(_ value: Bool, opensMenu: Bool) {
        isHovering = value
        hoverWorkItem?.cancel()
        hoverWorkItem = nil
        guard value, opensMenu, opensOnHover, isEnabled, !isHidden, window != nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isHovering, self.isEnabled, self.window != nil else { return }
            self.performClick(nil)
        }
        hoverWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverDelay, execute: workItem)
    }
}

final class BoardManSettingsCategoryButton: NSButton {
    private var hoverTrackingArea: NSTrackingArea?
    private(set) var isHovering = false
    var hoverDidChange: (() -> Void)?

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        setHovering(true)
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        setHovering(false)
        super.mouseExited(with: event)
    }

    func setHoveringForTesting(_ value: Bool) {
        setHovering(value)
    }

    private func setHovering(_ value: Bool) {
        guard isHovering != value else { return }
        isHovering = value
        hoverDidChange?()
    }
}

final class BoardManSettingsCardView: NSView {
    private let iconView = NSImageView(frame: .zero)
    let titleLabel = NSTextField(labelWithString: "")
    let detailLabel = NSTextField(labelWithString: "")

    init(title: String, detail: String, symbolName: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1

        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        iconView.imageScaling = .scaleProportionallyDown
        if #available(macOS 10.14, *) {
            iconView.contentTintColor = .secondaryLabelColor
        }
        addSubview(iconView)

        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        detailLabel.stringValue = detail
        detailLabel.font = NSFont.systemFont(ofSize: 10.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        addSubview(detailLabel)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layout() {
        super.layout()
        let headerY = max(8, bounds.height - 34)
        iconView.frame = NSIntegralRect(NSRect(x: 14, y: headerY + 1, width: 16, height: 16))
        titleLabel.frame = NSIntegralRect(NSRect(x: 38, y: headerY + 1, width: max(80, bounds.width - 52), height: 17))
        detailLabel.frame = NSIntegralRect(NSRect(x: 38, y: headerY - 15, width: max(80, bounds.width - 52), height: 14))
    }

    func updateText(title: String, detail: String) {
        titleLabel.stringValue = title
        detailLabel.stringValue = detail
        iconView.image?.accessibilityDescription = title
    }

    func applyStyle(accentColor: NSColor, surfaceColor: NSColor, edgeColor: NSColor, simpleStyle: Bool) {
        layer?.backgroundColor = surfaceColor.cgColor
        layer?.borderColor = edgeColor.cgColor
        layer?.cornerRadius = simpleStyle ? 9 : 12
        titleLabel.textColor = .labelColor
        detailLabel.textColor = .secondaryLabelColor
        if #available(macOS 10.14, *) {
            iconView.contentTintColor = accentColor
        }
    }
}

final class BoardManAppearancePreviewView: NSView {
    struct Snapshot {
        let accentColor: NSColor
        let panelColor: NSColor
        let usedColor: NSColor
        let font: NSFont
        let showRows: Bool
        let showCount: Bool
        let timestampPosition: BoardManTimestampPosition
        let timestampText: String
        let compactCount: Bool
        let simpleStyle: Bool
        let uiStyleRawValue: String
    }

    private var snapshot = Snapshot(
        accentColor: .controlAccentColor,
        panelColor: .controlBackgroundColor,
        usedColor: .systemGray,
        font: .systemFont(ofSize: 11),
        showRows: true,
        showCount: true,
        timestampPosition: .right,
        timestampText: "now",
        compactCount: false,
        simpleStyle: false,
        uiStyleRawValue: "Default"
    )

    var uiStyleRawValueForTesting: String {
        return snapshot.uiStyleRawValue
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(_ snapshot: Snapshot) {
        self.snapshot = snapshot
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 40, bounds.height > 40 else { return }

        let outer = bounds.insetBy(dx: 1, dy: 1)
        let outerRadius: CGFloat = snapshot.simpleStyle ? 6 : 10
        let outerPath = NSBezierPath(roundedRect: outer, xRadius: outerRadius, yRadius: outerRadius)
        snapshot.panelColor.withAlphaComponent(snapshot.simpleStyle ? 0.96 : 0.72).setFill()
        outerPath.fill()
        (snapshot.simpleStyle ? NSColor.separatorColor : snapshot.accentColor.withAlphaComponent(0.24)).setStroke()
        outerPath.lineWidth = snapshot.simpleStyle ? 0.7 : 1
        outerPath.stroke()

        let headerHeight: CGFloat = 24
        let headerRect = NSRect(x: outer.minX + 1, y: outer.maxY - headerHeight - 1, width: outer.width - 2, height: headerHeight)
        if snapshot.simpleStyle {
            let separator = NSBezierPath()
            separator.move(to: NSPoint(x: headerRect.minX + 10, y: headerRect.minY))
            separator.line(to: NSPoint(x: headerRect.maxX - 10, y: headerRect.minY))
            NSColor.separatorColor.withAlphaComponent(0.55).setStroke()
            separator.lineWidth = 0.5
            separator.stroke()
        } else {
            let headerPath = NSBezierPath(roundedRect: headerRect, xRadius: 9, yRadius: 9)
            snapshot.accentColor.withAlphaComponent(0.09).setFill()
            headerPath.fill()
        }

        drawText(
            boardManText("History"),
            in: NSRect(x: headerRect.minX + 12, y: headerRect.minY + 5, width: 80, height: 14),
            font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
            color: .labelColor,
            alignment: .left
        )
        drawText(
            boardManText("Preview"),
            in: NSRect(x: headerRect.maxX - 82, y: headerRect.minY + 5, width: 70, height: 14),
            font: NSFont.systemFont(ofSize: 9.5, weight: .medium),
            color: snapshot.accentColor,
            alignment: .right
        )

        let rowsTop = headerRect.minY - 8
        let rowsBottom = outer.minY + 10
        let rowGap: CGFloat = 7
        let rowHeight = max(26, floor((rowsTop - rowsBottom - rowGap) / 2))
        let rowInset: CGFloat = 12
        let rowWidth = outer.width - (rowInset * 2)
        let firstFrame = NSRect(x: outer.minX + rowInset, y: rowsBottom + rowHeight + rowGap, width: rowWidth, height: rowHeight)
        let secondFrame = NSRect(x: outer.minX + rowInset, y: rowsBottom, width: rowWidth, height: rowHeight)
        drawPreviewRow(frame: firstFrame, index: 1, text: boardManText("Design review notes"), count: 3, used: false)
        drawPreviewRow(frame: secondFrame, index: 2, text: boardManText("Release checklist"), count: 7, used: true)
    }

    private func drawPreviewRow(frame: NSRect, index: Int, text: String, count: Int, used: Bool) {
        if snapshot.simpleStyle {
            let separator = NSBezierPath()
            separator.move(to: NSPoint(x: frame.minX, y: frame.minY))
            separator.line(to: NSPoint(x: frame.maxX, y: frame.minY))
            NSColor.separatorColor.withAlphaComponent(0.42).setStroke()
            separator.lineWidth = 0.5
            separator.stroke()
        } else {
            let rowPath = NSBezierPath(roundedRect: frame, xRadius: 7, yRadius: 7)
            (used ? snapshot.usedColor.withAlphaComponent(0.15) : NSColor.labelColor.withAlphaComponent(0.035)).setFill()
            rowPath.fill()
            (used ? snapshot.usedColor.withAlphaComponent(0.28) : NSColor.separatorColor.withAlphaComponent(0.20)).setStroke()
            rowPath.lineWidth = 0.8
            rowPath.stroke()
        }

        var left = frame.minX + 10
        let centerY = frame.midY
        if snapshot.showRows {
            drawText(
                "\(index)",
                in: NSRect(x: left, y: centerY - 7, width: 18, height: 14),
                font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium),
                color: .tertiaryLabelColor,
                alignment: .center
            )
            left += 26
        }

        var right = frame.maxX - 10
        if snapshot.showCount {
            let countWidth: CGFloat = snapshot.compactCount ? 20 : 30
            let countRect = NSRect(x: right - countWidth, y: centerY - 9, width: countWidth, height: 18)
            if !snapshot.simpleStyle {
                let badgePath = NSBezierPath(roundedRect: countRect, xRadius: 9, yRadius: 9)
                snapshot.accentColor.withAlphaComponent(0.16).setFill()
                badgePath.fill()
            }
            drawText(
                snapshot.compactCount ? "\(count)" : "×\(count)",
                in: countRect.insetBy(dx: 3, dy: 2),
                font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
                color: snapshot.accentColor,
                alignment: .center
            )
            right = countRect.minX - 8
        }

        let timestampWidth: CGFloat = 48
        if snapshot.timestampPosition == .left {
            drawText(snapshot.timestampText,
                     in: NSRect(x: left, y: centerY - 7, width: timestampWidth, height: 14),
                     font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
                     color: .secondaryLabelColor,
                     alignment: .center)
            left += timestampWidth + 8
        } else if snapshot.timestampPosition == .right {
            drawText(snapshot.timestampText,
                     in: NSRect(x: right - timestampWidth, y: centerY - 7, width: timestampWidth, height: 14),
                     font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
                     color: .secondaryLabelColor,
                     alignment: .center)
            right -= timestampWidth + 8
        }

        let titleY = snapshot.timestampPosition == .below ? centerY + 1 : centerY - 7
        drawText(
            text,
            in: NSRect(x: left, y: titleY, width: max(30, right - left), height: 14),
            font: snapshot.font,
            color: .labelColor,
            alignment: .left
        )
        if snapshot.timestampPosition == .below {
            drawText(snapshot.timestampText,
                     in: NSRect(x: left, y: centerY - 14, width: max(30, right - left), height: 12),
                     font: NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .regular),
                     color: .secondaryLabelColor,
                     alignment: .left)
        }
    }

    private func drawText(_ text: String,
                          in rect: NSRect,
                          font: NSFont,
                          color: NSColor,
                          alignment: NSTextAlignment) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }
}

final class BoardManCenteredTextFieldCell: NSTextFieldCell {
    var opticalYOffset: CGFloat = 0

    private func centeredTextRect(forBounds rect: NSRect) -> NSRect {
        var textRect = super.drawingRect(forBounds: rect)
        guard let font else { return textRect }
        let textHeight = min(textRect.height, ceil(font.ascender - font.descender + font.leading) + 2)
        textRect.origin.y = floor(rect.midY - (textHeight / 2) + opticalYOffset)
        textRect.size.height = textHeight
        return textRect
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        return centeredTextRect(forBounds: rect)
    }

    override func edit(withFrame aRect: NSRect,
                       in controlView: NSView,
                       editor textObj: NSText,
                       delegate: Any?,
                       event: NSEvent?) {
        super.edit(withFrame: centeredTextRect(forBounds: aRect),
                   in: controlView,
                   editor: textObj,
                   delegate: delegate,
                   event: event)
    }

    override func select(withFrame aRect: NSRect,
                         in controlView: NSView,
                         editor textObj: NSText,
                         delegate: Any?,
                         start selStart: Int,
                         length selLength: Int) {
        super.select(withFrame: centeredTextRect(forBounds: aRect),
                     in: controlView,
                     editor: textObj,
                     delegate: delegate,
                     start: selStart,
                     length: selLength)
    }
}

final class BoardManCenteredSearchFieldCell: NSSearchFieldCell {
    var opticalYOffset: CGFloat = 0
    var searchButtonOpticalYOffset: CGFloat = -2

    private func verticallyCentered(_ rect: NSRect, height: CGFloat) -> NSRect {
        let targetHeight = min(rect.height, height)
        return NSIntegralRect(NSRect(
            x: rect.origin.x,
            y: floor(rect.midY - (targetHeight / 2) + opticalYOffset),
            width: rect.width,
            height: targetHeight
        ))
    }

    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        let original = super.searchTextRect(forBounds: rect)
        guard let font else { return original }
        let textHeight = ceil(font.ascender - font.descender + font.leading) + 4
        return verticallyCentered(original, height: textHeight)
    }

    override func searchButtonRect(forBounds rect: NSRect) -> NSRect {
        let original = super.searchButtonRect(forBounds: rect)
        var centered = verticallyCentered(original, height: original.height)
        centered.origin.y += searchButtonOpticalYOffset
        return centered
    }

    override func cancelButtonRect(forBounds rect: NSRect) -> NSRect {
        let original = super.cancelButtonRect(forBounds: rect)
        return verticallyCentered(original, height: original.height)
    }

}

func boardManTimestampHitRect(
    timestampText: String,
    timestampPosition: BoardManTimestampPosition,
    timestampAccessoryFrame: NSRect,
    metadataLabel: NSTextField
) -> NSRect? {
    guard !timestampText.isEmpty, timestampPosition != .hidden else { return nil }
    if timestampPosition == .left || timestampPosition == .right {
        return timestampAccessoryFrame.insetBy(dx: -5, dy: -5)
    }
    guard timestampPosition == .below, !metadataLabel.isHidden,
          let font = metadataLabel.font else { return nil }
    let metadata = metadataLabel.stringValue as NSString
    let range = metadata.range(of: timestampText)
    guard range.location != NSNotFound else { return nil }
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    let prefixWidth = ceil((metadata.substring(to: range.location) as NSString).size(withAttributes: attributes).width)
    let valueWidth = ceil((metadata.substring(with: range) as NSString).size(withAttributes: attributes).width)
    return NSRect(
        x: metadataLabel.frame.minX + prefixWidth,
        y: metadataLabel.frame.minY,
        width: min(valueWidth, max(0, metadataLabel.frame.width - prefixWidth)),
        height: metadataLabel.frame.height
    ).insetBy(dx: -5, dy: -5)
}

func boardManCapCenteredTextFrame(
    for label: NSTextField,
    originX: CGFloat,
    width: CGFloat,
    capCenterY: CGFloat
) -> NSRect {
    guard let font = label.font else {
        return NSRect(x: originX, y: capCenterY, width: width, height: 0)
    }
    let descenderDepth = abs(font.descender)
    let metricsHeight = max(0, font.ascender - font.descender + font.leading)
    let requiredHeight = max(metricsHeight, label.firstBaselineOffsetFromTop + descenderDepth)
    let frameHeight = ceil(requiredHeight)
    let baselineY = capCenterY - (font.capHeight / 2)
    let frameMaxY = baselineY + label.firstBaselineOffsetFromTop
    return NSRect(
        x: originX,
        y: frameMaxY - frameHeight,
        width: width,
        height: frameHeight
    )
}

final class BoardManHistoryCellView: NSTableCellView {
    private let primaryLabel = NSTextField(labelWithString: "")
    private let metadataLabel = NSTextField(labelWithString: "")
    private let timestampAccessoryLabel = NSTextField(labelWithString: "")
    private let countBadge = NSTextField(labelWithString: "")
    private let pinBadge = NSTextField(labelWithString: "PIN")
    private let inlineImageView = NSImageView(frame: .zero)
    private let dragHandleLabel = NSTextField(labelWithString: "≡")
    private var timestampPosition: BoardManTimestampPosition = .below
    private var inlineImagePosition: BoardManInlineImagePosition = .right
    private var configuredTimestampText = ""
    private var showsDragHandle = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        primaryLabel.lineBreakMode = .byTruncatingTail
        primaryLabel.maximumNumberOfLines = 1
        primaryLabel.backgroundColor = .clear
        primaryLabel.drawsBackground = false
        primaryLabel.font = NSFont.systemFont(ofSize: 13.5, weight: .medium)
        primaryLabel.identifier = NSUserInterfaceItemIdentifier("BoardManHistoryPrimaryLabel")

        metadataLabel.lineBreakMode = .byTruncatingTail
        metadataLabel.maximumNumberOfLines = 1
        metadataLabel.backgroundColor = .clear
        metadataLabel.drawsBackground = false
        metadataLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)

        timestampAccessoryLabel.cell = BoardManCenteredTextFieldCell(textCell: "")
        timestampAccessoryLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        timestampAccessoryLabel.textColor = .secondaryLabelColor
        timestampAccessoryLabel.lineBreakMode = .byTruncatingTail
        timestampAccessoryLabel.maximumNumberOfLines = 1
        timestampAccessoryLabel.cell?.usesSingleLineMode = true
        timestampAccessoryLabel.cell?.wraps = false
        timestampAccessoryLabel.isBordered = false
        timestampAccessoryLabel.isEditable = false
        timestampAccessoryLabel.backgroundColor = .clear
        timestampAccessoryLabel.drawsBackground = false
        timestampAccessoryLabel.identifier = NSUserInterfaceItemIdentifier("BoardManHistoryTimestampLabel")

        let countBadgeCell = BoardManCenteredTextFieldCell(textCell: "")
        countBadgeCell.opticalYOffset = 2
        countBadge.cell = countBadgeCell
        countBadge.alignment = .center
        countBadge.lineBreakMode = .byTruncatingTail
        countBadge.maximumNumberOfLines = 1
        countBadge.cell?.usesSingleLineMode = true
        countBadge.cell?.wraps = false
        countBadge.isBordered = false
        countBadge.isEditable = false
        countBadge.wantsLayer = true
        countBadge.layer?.cornerRadius = 8
        countBadge.layer?.masksToBounds = true
        countBadge.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        countBadge.identifier = NSUserInterfaceItemIdentifier("BoardManHistoryCountBadge")

        let pinBadgeCell = BoardManCenteredTextFieldCell(textCell: "PIN")
        pinBadgeCell.opticalYOffset = 2
        pinBadge.cell = pinBadgeCell
        pinBadge.alignment = .center
        pinBadge.isBordered = false
        pinBadge.isEditable = false
        pinBadge.wantsLayer = true
        pinBadge.layer?.cornerRadius = 8
        pinBadge.layer?.masksToBounds = true
        pinBadge.font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
        pinBadge.toolTip = "Pinned • Hold the row or press ⌘P to unpin"
        pinBadge.identifier = NSUserInterfaceItemIdentifier("BoardManHistoryPinBadge")
        pinBadge.isHidden = true

        inlineImageView.imageScaling = .scaleProportionallyUpOrDown
        inlineImageView.imageAlignment = .alignCenter
        inlineImageView.wantsLayer = true
        inlineImageView.layer?.cornerRadius = 5
        inlineImageView.layer?.masksToBounds = true
        inlineImageView.layer?.borderWidth = 1

        dragHandleLabel.alignment = .center
        dragHandleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        dragHandleLabel.textColor = .secondaryLabelColor
        dragHandleLabel.toolTip = boardManText("Reorder mode: drag the handle on the left")
        dragHandleLabel.isHidden = true

        [primaryLabel, metadataLabel, timestampAccessoryLabel, countBadge, pinBadge].forEach {
            $0.cell?.truncatesLastVisibleLine = true
            $0.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        inlineImageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(primaryLabel)
        addSubview(metadataLabel)
        addSubview(timestampAccessoryLabel)
        addSubview(inlineImageView)
        addSubview(countBadge)
        addSubview(pinBadge)
        addSubview(dragHandleLabel)
    }

    func configure(item: BoardManHistoryItem,
                   isSelected: Bool,
                   usageStyle: String,
                   useLiquidGlass: Bool,
                   lightenTheme: Bool,
                   themePreset: BoardManThemePreset,
                   timestampPosition requestedTimestampPosition: BoardManTimestampPosition) {
        let fontChoice = BoardManFontChoice.allowed(
            AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManFontChoice)
        )
        let isNarrowRow = bounds.width < 640
        let textScale = CGFloat(BoardManPanel.clampedItemTextScale(
            AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.boardManItemTextScale)
        )) / 100
        let primaryBaseSize: CGFloat = isNarrowRow ? 12.75 : 13.5
        let metadataBaseSize: CGFloat = isNarrowRow ? 11 : 11.5
        let primaryFont = fontChoice.font(ofSize: primaryBaseSize * textScale, weight: .medium)
        let metadataFont = fontChoice.font(ofSize: metadataBaseSize * textScale, weight: .regular)
        primaryLabel.font = primaryFont
        metadataLabel.font = metadataFont
        timestampAccessoryLabel.font = fontChoice.font(ofSize: (isNarrowRow ? 10 : 10.5) * textScale, weight: .medium)
        countBadge.font = fontChoice.font(ofSize: isNarrowRow ? 10 : 10.5, weight: .medium)
        pinBadge.font = fontChoice.font(ofSize: 9.5, weight: .bold)
        timestampPosition = requestedTimestampPosition
        configuredTimestampText = item.timestampText
        let usesCompactRow = timestampPosition != .below
        let hidesMaskedTitle = item.isMasked && AppEnvironment.current.defaults.bool(
            forKey: Constants.UserDefaults.boardManHideTitleForMaskedItems
        )
        primaryLabel.isHidden = hidesMaskedTitle
        primaryLabel.stringValue = item.isMasked
            ? "＊＊＊＊＊"
            : (usesCompactRow ? item.compactTitle : item.primaryTitle)
        metadataLabel.stringValue = item.metadataText
        metadataLabel.isHidden = usesCompactRow
        timestampAccessoryLabel.stringValue = item.timestampText
        timestampAccessoryLabel.isHidden = item.timestampText.isEmpty || timestampPosition == .hidden || timestampPosition == .below
        timestampAccessoryLabel.alignment = .center
        let badgePrefix = usageStyle == "compact" ? "used " : "×"
        let shouldShowCount = item.pasteCount > 0 && !item.countText.isEmpty
        countBadge.stringValue = shouldShowCount ? "\(badgePrefix)\(item.countText)" : ""
        countBadge.isHidden = !shouldShowCount
        let pinLabelStyle = BoardManPinLabelStyle.allowed(
            AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManPinLabelStyle)
        )
        pinBadge.stringValue = pinLabelStyle.badgeTitle
        pinBadge.isHidden = !item.isPinned || pinLabelStyle == .off
        let showInlineImages = AppEnvironment.current.defaults.object(
            forKey: Constants.UserDefaults.boardManShowInlineImages
        ) as? Bool ?? true
        inlineImagePosition = BoardManInlineImagePosition.allowed(
            AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManInlineImagePosition)
        )
        inlineImageView.image = item.isMasked ? nil : item.inlineThumbnail
        inlineImageView.isHidden = item.isMasked || item.inlineThumbnail == nil || !showInlineImages

        if isSelected {
            primaryLabel.textColor = .selectedMenuItemTextColor
            metadataLabel.textColor = NSColor.selectedMenuItemTextColor.withAlphaComponent(0.86)
            timestampAccessoryLabel.textColor = NSColor.selectedMenuItemTextColor.withAlphaComponent(0.86)
            countBadge.textColor = .selectedMenuItemTextColor
            countBadge.layer?.backgroundColor = NSColor.selectedMenuItemTextColor.withAlphaComponent(useLiquidGlass ? 0.20 : 0.18).cgColor
            pinBadge.textColor = .selectedMenuItemTextColor
            pinBadge.layer?.backgroundColor = NSColor.selectedMenuItemTextColor.withAlphaComponent(useLiquidGlass ? 0.22 : 0.20).cgColor
            pinBadge.layer?.borderColor = NSColor.selectedMenuItemTextColor.withAlphaComponent(0.34).cgColor
            inlineImageView.layer?.backgroundColor = NSColor.selectedMenuItemTextColor.withAlphaComponent(0.10).cgColor
            inlineImageView.layer?.borderColor = NSColor.selectedMenuItemTextColor.withAlphaComponent(0.24).cgColor
        } else {
            let accentColor = themePreset.accentColor
            primaryLabel.textColor = .labelColor
            metadataLabel.textColor = useLiquidGlass ? NSColor.secondaryLabelColor.withAlphaComponent(0.92) : .secondaryLabelColor
            timestampAccessoryLabel.textColor = useLiquidGlass ? NSColor.secondaryLabelColor.withAlphaComponent(0.92) : .secondaryLabelColor
            countBadge.textColor = .labelColor
            countBadge.layer?.backgroundColor = accentColor.withAlphaComponent(lightenTheme ? 0.10 : (useLiquidGlass ? 0.22 : 0.18)).cgColor
            pinBadge.textColor = accentColor
            pinBadge.layer?.backgroundColor = accentColor.withAlphaComponent(lightenTheme ? 0.10 : (useLiquidGlass ? 0.20 : 0.14)).cgColor
            pinBadge.layer?.borderColor = accentColor.withAlphaComponent(lightenTheme ? 0.30 : 0.42).cgColor
            inlineImageView.layer?.backgroundColor = themePreset.surfaceTintColor(useLiquidGlass: useLiquidGlass, lighten: lightenTheme).cgColor
            inlineImageView.layer?.borderColor = accentColor.withAlphaComponent(lightenTheme ? 0.18 : (useLiquidGlass ? 0.34 : 0.28)).cgColor
        }
        countBadge.layer?.borderColor = themePreset.edgeColor(useLiquidGlass: useLiquidGlass, lighten: lightenTheme).cgColor
        countBadge.layer?.borderWidth = 0
        pinBadge.layer?.borderWidth = 1
        needsLayout = true
    }

    fileprivate func setSnippetInteractionMode(reorderMode: Bool, accentColor: NSColor) {
        showsDragHandle = reorderMode
        dragHandleLabel.isHidden = !reorderMode
        dragHandleLabel.textColor = reorderMode ? accentColor : .secondaryLabelColor
        needsLayout = true
    }

    private var timestampHitRect: NSRect? {
        return boardManTimestampHitRect(
            timestampText: configuredTimestampText,
            timestampPosition: timestampPosition,
            timestampAccessoryFrame: timestampAccessoryLabel.frame,
            metadataLabel: metadataLabel
        )
    }

    fileprivate func containsTimestamp(at point: NSPoint) -> Bool {
        return timestampHitRect?.contains(point) == true
    }

    fileprivate func containsTimestamp(windowPoint: NSPoint) -> Bool {
        guard let timestampHitRect else { return false }
        return convert(timestampHitRect, to: nil).contains(windowPoint)
    }

    static func usageBadgeFrame(in bounds: NSRect, intrinsicWidth: CGFloat) -> NSRect {
        let horizontalInset: CGFloat = 10
        let trailingInset: CGFloat = 24
        let badgeHeight: CGFloat = 20
        let maxContentWidth = max(0, bounds.width - horizontalInset - trailingInset)
        let badgeWidth = min(maxContentWidth, max(56, min(64, ceil(intrinsicWidth) + 20)))
        return NSIntegralRect(NSRect(
            x: max(horizontalInset, floor(bounds.maxX - trailingInset - badgeWidth)),
            y: floor(bounds.midY - (badgeHeight / 2)),
            width: badgeWidth,
            height: badgeHeight
        ))
    }

    static func synchronizedCellFrame(existingFrame: NSRect, safeWidth: CGFloat) -> NSRect {
        let maximumOriginX = max(0, floor(safeWidth) - 1)
        let preservedOriginX = min(max(0, floor(existingFrame.minX)), maximumOriginX)
        return NSIntegralRect(NSRect(
            x: preservedOriginX,
            y: existingFrame.minY,
            width: max(1, floor(safeWidth) - preservedOriginX),
            height: existingFrame.height
        ))
    }

    override func layout() {
        super.layout()
        let horizontalInset: CGFloat = 10
        let trailingInset: CGFloat = 24
        let accessoryGap: CGFloat = 12
        let titleSlotHeight: CGFloat = 18
        let metadataSlotHeight: CGFloat = 15
        let textGap: CGFloat = 4
        let timeWidth: CGFloat = 72
        let countWidth: CGFloat = 64
        let pinWidth: CGFloat = pinBadge.stringValue == "P" ? 28 : 44
        let accessoryHeight: CGFloat = 20
        var textLeft = horizontalInset
        var textRight = bounds.width - trailingInset

        dragHandleLabel.frame = .zero
        if showsDragHandle {
            dragHandleLabel.frame = NSIntegralRect(NSRect(
                x: horizontalInset,
                y: floor(bounds.midY - 14),
                width: 24,
                height: 28
            ))
            textLeft = dragHandleLabel.frame.maxX + 8
        }

        timestampAccessoryLabel.frame = .zero
        countBadge.frame = .zero
        pinBadge.frame = .zero
        inlineImageView.frame = .zero

        if !inlineImageView.isHidden, inlineImagePosition == .left {
            let imageSize: CGFloat = timestampPosition == .below ? 32 : 28
            inlineImageView.frame = NSIntegralRect(NSRect(
                x: textLeft,
                y: floor((bounds.height - imageSize) / 2),
                width: imageSize,
                height: imageSize
            ))
            textLeft = inlineImageView.frame.maxX + accessoryGap
        }

        if !pinBadge.isHidden {
            pinBadge.frame = NSIntegralRect(NSRect(
                x: textLeft,
                y: floor(bounds.midY - accessoryHeight / 2),
                width: pinWidth,
                height: accessoryHeight
            ))
            textLeft = pinBadge.frame.maxX + accessoryGap
        }

        if !timestampAccessoryLabel.isHidden, timestampPosition == .left {
            timestampAccessoryLabel.frame = NSIntegralRect(NSRect(
                x: textLeft,
                y: floor(bounds.midY - accessoryHeight / 2),
                width: timeWidth,
                height: accessoryHeight
            ))
            textLeft = timestampAccessoryLabel.frame.maxX + accessoryGap
        }

        if !timestampAccessoryLabel.isHidden, timestampPosition == .right {
            timestampAccessoryLabel.frame = NSIntegralRect(NSRect(
                x: textRight - timeWidth,
                y: floor(bounds.midY - accessoryHeight / 2),
                width: timeWidth,
                height: accessoryHeight
            ))
            textRight = timestampAccessoryLabel.frame.minX - accessoryGap
        }

        if !countBadge.isHidden {
            countBadge.frame = NSIntegralRect(NSRect(
                x: max(textLeft, textRight - countWidth),
                y: floor(bounds.midY - accessoryHeight / 2),
                width: countWidth,
                height: accessoryHeight
            ))
            textRight = countBadge.frame.minX - accessoryGap
        }

        if !inlineImageView.isHidden, inlineImagePosition == .right {
            let imageSize: CGFloat = timestampPosition == .below ? 32 : 28
            inlineImageView.frame = NSIntegralRect(NSRect(
                x: max(textLeft, textRight - imageSize),
                y: floor((bounds.height - imageSize) / 2),
                width: imageSize,
                height: imageSize
            ))
            textRight = inlineImageView.frame.minX - accessoryGap
        }

        let textWidth = max(0, textRight - textLeft)
        if timestampPosition == .below {
            let textBlockHeight = titleSlotHeight + textGap + metadataSlotHeight
            let textBottom = floor((bounds.height - textBlockHeight) / 2)
            let metadataCapCenterY = textBottom + (metadataSlotHeight / 2)
            let primaryCapCenterY = textBottom + metadataSlotHeight + textGap + (titleSlotHeight / 2)
            metadataLabel.frame = boardManCapCenteredTextFrame(
                for: metadataLabel,
                originX: textLeft,
                width: textWidth,
                capCenterY: metadataCapCenterY
            )
            primaryLabel.frame = boardManCapCenteredTextFrame(
                for: primaryLabel,
                originX: textLeft,
                width: textWidth,
                capCenterY: primaryCapCenterY
            )
        } else {
            metadataLabel.frame = .zero
            primaryLabel.frame = boardManCapCenteredTextFrame(
                for: primaryLabel,
                originX: textLeft,
                width: textWidth,
                capCenterY: bounds.midY
            )
        }
    }
}

// MARK: - BoardManPanel MVP Shell (embedded in MenuManager.swift per constraints)
class BoardManPanel: NSPanel {

    private let store: BoardManStore = BoardManStores.authoritative
    private lazy var searchCoordinator = BoardManSearchCoordinator(store: store)

    private typealias LayoutMetrics = BoardManPanelLayoutMetrics

    private var glassBackgroundView: NSVisualEffectView?
    private var searchField: NSSearchField?
    private var headerTabBar: BoardManHeaderTabBar?
    private var settingsButton: NSButton?
    private var historyUsageFilterControl: NSSegmentedControl?
    private var historySortButton: NSButton?
    private var historySavedFilterPopup: NSPopUpButton?
    private var historyConditionButton: NSButton?
    private var settingsBackgroundView: NSView?
    private var settingsSidebarView: NSView?
    private var settingsScrollView: NSScrollView?
    private var settingsDocumentView: NSView?
    private var settingsCategoryButtons: [NSButton] = []
    private var settingsPageTitleLabel: NSTextField?
    private var settingsPageDescriptionLabel: NSTextField?
    private var scrollView: NSScrollView?
    private var placeholderList: NSTableView?
    private var rowNumbersButton: NSButton?
    private var timestampLabel: NSTextField?
    private var timestampPopup: NSPopUpButton?
    private var timestampPositionLabel: NSTextField?
    private var timestampPositionPopup: NSPopUpButton?
    private var relativeNumberLabel: NSTextField?
    private var relativeNumberPopup: NSPopUpButton?
    private var relativeUnitLabel: NSTextField?
    private var relativeUnitPopup: NSPopUpButton?
    private var relativeSuffixLabel: NSTextField?
    private var relativeSuffixPopup: NSPopUpButton?
    private var relativeNowLabel: NSTextField?
    private var relativeNowPopup: NSPopUpButton?
    private var timestampInteractionLabel: NSTextField?
    private var timestampInteractionPopup: NSPopUpButton?
    private var timestampShortcutLabel: NSTextField?
    private var timestampShortcutEnabledButton: NSButton?
    private var timestampShortcutRecordView: RecordView?
    private var timestampShortcutDelayLabel: NSTextField?
    private var timestampShortcutDelayField: NSTextField?
    private var timestampShortcutDelayStepper: NSStepper?
    private var timestampShortcutDelayDecreaseButton: NSButton?
    private var timestampShortcutDelayIncreaseButton: NSButton?
    private var timestampShortcutSecondsLabel: NSTextField?
    private var usageCountButton: NSButton?
    private var usageStyleLabel: NSTextField?
    private var usageStylePopup: NSPopUpButton?
    private var usedItemStyleLabel: NSTextField?
    private var usedItemStylePopup: NSPopUpButton?
    private var pinLabelStyleLabel: NSTextField?
    private var pinLabelStylePopup: NSPopUpButton?
    private var showInlineImagesButton: NSButton?
    private var inlineImagePositionLabel: NSTextField?
    private var inlineImagePositionPopup: NSPopUpButton?
    private var themePresetLabel: NSTextField?
    private var themePresetPopup: NSPopUpButton?
    private var appearanceModeLabel: NSTextField?
    private var appearanceModePopup: NSPopUpButton?
    private var uiStyleLabel: NSTextField?
    private var uiStylePopup: NSPopUpButton?
    private var fontChoiceLabel: NSTextField?
    private var fontChoicePopup: NSPopUpButton?
    private var itemTextScaleLabel: NSTextField?
    private var itemTextScaleField: NSTextField?
    private var itemTextScaleDecreaseButton: NSButton?
    private var itemTextScaleIncreaseButton: NSButton?
    private var themeLightenButton: NSButton?
    private var customAccentLabel: NSTextField?
    private var customAccentColorWell: NSColorWell?
    private var customAccentOpacitySlider: NSSlider?
    private var customPanelLabel: NSTextField?
    private var customPanelColorWell: NSColorWell?
    private var customPanelOpacitySlider: NSSlider?
    private var customUsedColorLabel: NSTextField?
    private var customUsedColorWell: NSColorWell?
    private var customUsedOpacitySlider: NSSlider?
    private var resetCustomColorsButton: NSButton?
    private var generalSectionLabel: NSTextField?
    private var launchOnLoginButton: NSButton?
    private var inputPasteCommandButton: NSButton?
    private var languageLabel: NSTextField?
    private var languagePopup: NSPopUpButton?
    private var maxHistorySizeLabel: NSTextField?
    private var maxHistorySizeStepper: NSStepper?
    private var maxHistorySizeValueLabel: NSTextField?
    private var maxHistoryDecreaseButton: NSButton?
    private var maxHistoryIncreaseButton: NSButton?
    private var statusItemLabel: NSTextField?
    private var statusItemPopup: NSPopUpButton?
    private var shortcutSectionLabel: NSTextField?
    private var globalShortcutRows: [BoardManGlobalShortcutRow] = []
    private var shortcutStatusLabel: NSTextField?
    private var snippetSettingsSectionLabel: NSTextField?
    private var snippetSummaryLabel: NSTextField?
    private var snippetFoldersLabel: NSTextField?
    private var snippetGroupOrderPopup: NSPopUpButton?
    private var snippetGroupMoveUpButton: NSButton?
    private var snippetGroupMoveDownButton: NSButton?
    private var snippetShortcutsLabel: NSTextField?
    private var snippetShortcutScrollView: NSScrollView?
    private var snippetShortcutDocumentView: NSView?
    private var snippetShortcutRows: [BoardManSnippetShortcutRow] = []
    private var manageSnippetsButton: NSButton?
    private var dedupeButton: NSButton?
    private var overwriteSameHistoryButton: NSButton?
    private var reuseTopButton: NSButton?
    private var clearHistoryButton: NSButton?
    private var pauseRecordingButton: NSButton?
    private var excludedAppsButton: NSButton?
    private var excludedAppsSummaryLabel: NSTextField?
    private var storedTypesSectionLabel: NSTextField?
    private var storedTypeButtons: [NSButton] = []
    private var filterSectionLabel: NSTextField?
    private var hideRuleTextField: NSTextField?
    private var hideRuleModePopup: NSPopUpButton?
    private var addHideRuleButton: NSButton?
    private var removeLastHideRuleButton: NSButton?
    private var clearHideRulesButton: NSButton?
    private var hideRulesSummaryLabel: NSTextField?
    private var hideRulesExamplesLabel: NSTextField?
    private var hideRulesNoteLabel: NSTextField?
    private var licenseSectionLabel: NSTextField?
    private var licensePlanLabel: NSTextField?
    private var licenseStateLabel: NSTextField?
    private var licenseLimitsLabel: NSTextField?
    private var licenseKeyField: NSTextField?
    private var licenseActivateButton: NSButton?
    private var licenseActivationStatusLabel: NSTextField?
    private var licenseUpgradeButton: NSButton?
    private var licenseProLockedControlView: BoardManProLockedControlView?
    private var licenseMockNoteLabel: NSTextField?
    private var licenseStateExamplesLabel: NSTextField?
    private let updatesPreferenceViewController = BoardManUpdatesPreferenceViewController(nibName: "BoardManUpdatesPreferenceViewController", bundle: nil)
    private var updatesPreferenceView: NSView?
    private var viewSectionLabel: NSTextField?
    private var historySectionLabel: NSTextField?
    private var skipPinnedNavigationButton: NSButton?
    private var longPressActionLabel: NSTextField?
    private var longPressActionPopup: NSPopUpButton?
    private var timedPinDurationLabel: NSTextField?
    private var timedPinPresetPopup: NSPopUpButton?
    private var timedPinPresetAddButton: NSButton?
    private var timedPinPresetRemoveButton: NSButton?
    private var timedPinDurationStepper: NSStepper?
    private var timedPinDurationValueLabel: NSTextField?
    private var timedPinDurationDecreaseButton: NSButton?
    private var timedPinDurationIncreaseButton: NSButton?
    private var timedPinDurationUnitPopup: NSPopUpButton?
    private var textPreviewScaleLabel: NSTextField?
    private var textPreviewScaleSlider: NSSlider?
    private var textPreviewScaleValueLabel: NSTextField?
    private var imagePreviewScaleLabel: NSTextField?
    private var imagePreviewScaleSlider: NSSlider?
    private var imagePreviewScaleValueLabel: NSTextField?
    private var previewScaleProNoteLabel: NSTextField?
    private var appearancePreviewCard: BoardManSettingsCardView?
    private var appearanceLayoutCard: BoardManSettingsCardView?
    private var appearanceTimestampCard: BoardManSettingsCardView?
    private var appearanceUsageCard: BoardManSettingsCardView?
    private var appearanceThemeCard: BoardManSettingsCardView?
    private var appearanceAdvancedCard: BoardManSettingsCardView?
    private var appearancePreviewView: BoardManAppearancePreviewView?
    private var appearanceAdvancedButton: NSButton?
    private var appearanceAdvancedExpanded = false
    private var snippetGroupProNoteLabel: NSTextField?
    private var exportHistoryCSVButton: NSButton?
    private var privacySectionLabel: NSTextField?
    private var hideMaskedPreviewButton: NSButton?
    private var hideMaskedTitleButton: NSButton?
    private var labsSectionLabel: NSTextField?
    private var labsNoteLabel: NSTextField?
    private var heightControlLabel: NSTextField?
    private var heightStepper: NSStepper?
    private var heightLabel: NSTextField?
    private var heightDecreaseButton: NSButton?
    private var heightIncreaseButton: NSButton?
    private var footerNote: NSTextField?
    private var snippetCategoryLabel: NSTextField?
    private var snippetCategoryPopup: NSPopUpButton?
    private var snippetCategoryAddButton: NSButton?
    private var snippetCategoryRenameButton: NSButton?
    private var snippetCategoryDeleteButton: NSButton?
    private var snippetInteractionHintLabel: NSTextField?
    private var snippetReorderModeButton: NSButton?
    private var snippetAddButton: NSButton?
    private var snippetEditButton: NSButton?
    private var snippetDeleteButton: NSButton?
    private var snippetEditorView: NSView?
    private var snippetEditorTitleLabel: NSTextField?
    private var snippetEditorTitleField: NSTextField?
    private var snippetEditorContentLabel: NSTextField?
    private var snippetEditorScrollView: NSScrollView?
    private var snippetEditorTextView: NSTextView?
    private var snippetFolderEnableButton: NSButton?
    private var snippetEnableButton: NSButton?
    private var snippetSaveButton: NSButton?
    private var snippetCancelEditButton: NSButton?
    private var snippetEditorStatusLabel: NSTextField?
    private var snippetEditorClickGesture: NSClickGestureRecognizer?
    private var itemLongPressGesture: NSPressGestureRecognizer?
    private var horizontalScrollAccumulator: CGFloat = 0
    private var horizontalScrollResetWorkItem: DispatchWorkItem?
    private var previewBubblePanel: NSPanel?
    private var previewBubbleLabel: NSTextField?
    private var previewBubbleImageView: NSImageView?
    private var allItems: [BoardManHistoryItem] = []
    private var historyItems: [BoardManHistoryItem] = []
    private var selectedIndex: Int = -1
    private var hoveredRow: Int = -1
    private var keyboardPreviewLockUntil: CFAbsoluteTime = 0
    private var localKeyMonitor: Any?
    private var previewLifecycleObservers: [NSObjectProtocol] = []
    private var isPanelLayoutScheduled = false
    private var suppressSingleClickUntil: CFAbsoluteTime = 0
    private var pendingSnippetSingleClickWorkItem: DispatchWorkItem?
    private var isSnippetEditing = false
    private var editingSnippetIdentifier: String?
    private var isSnippetReorderMode = false
    private var isQuickMode = false
    private var activeTab: BoardManPanelTab = .history
    private var activeSettingsCategory: BoardManInlineSettingsCategory = .general
    private var activeSnippetCategoryIdentifier: String = BoardManPanel.allCategoriesIdentifier
    private var activeSnippetGroupIdentifiers: Set<String> = []
    private var shouldScrollSettingsToTop = true
    fileprivate var onPasteRequested: ((BoardManHistoryItem, CFAbsoluteTime?) -> Void)?
    fileprivate var onTimestampActionRequested: ((BoardManHistoryItem, KeyCombo, TimeInterval, CFAbsoluteTime?) -> Void)?
    var onRefreshRequested: (() -> Void)?
    var itemCount: Int {
        return historyItems.count
    }

    var hasLoadedPanelItems: Bool {
        return !allItems.isEmpty
    }

    var hasLoadedSnippetItems: Bool {
        return allItems.contains { $0.source == .snippet }
    }

    var presentationItemScope: BoardManPresentationItemScope {
        return activeTab == .snippets ? .complete : .historyOnly
    }

    func selectHistoryTab() {
        activateTab(.history)
    }

    func setQuickMode(_ enabled: Bool) {
        isQuickMode = enabled
        minSize = enabled
            ? NSSize(width: 520, height: 220)
            : NSSize(width: LayoutMetrics.minimumWidth, height: 600)
        if enabled {
            activeTab = .history
            headerTabBar?.setSelectedIndex(BoardManPanelTab.history.rawValue)
        }
        selectedIndex = -1
        hoveredRow = -1
        hidePreviewBubble()
        applyCurrentFilter()
    }

    func selectSettingsTab() {
        activeTab = .settings
        headerTabBar?.setSelectedIndex(-1)
        shouldScrollSettingsToTop = true
        updateSettingsButtonAppearance()
        refreshGlobalShortcutRows()
        refreshSnippetSettingsSummary()
        refreshExcludedAppsSummary()
        selectedIndex = -1
        hoveredRow = -1
        hidePreviewBubble()
        applyCurrentFilter()
        makeFirstResponder(self)
    }

    func openSnippetsManagerMode(categoryIdentifier: String? = nil) {
        activeTab = .snippets
        headerTabBar?.setSelectedIndex(BoardManPanelTab.snippets.rawValue)
        updateSettingsButtonAppearance()
        if let categoryIdentifier {
            setActiveSnippetGroupIdentifiers(
                categoryIdentifier == BoardManPanel.allCategoriesIdentifier ? [] : [categoryIdentifier]
            )
        }
        selectedIndex = -1
        hoveredRow = -1
        hidePreviewBubble()
        reloadSnippetCategoryPopup()
        applyCurrentFilter()
        layoutPanelSubviews()
        focusTableForKeyboard()
    }

    fileprivate var isLiquidGlassEnabled: Bool {
        return AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.boardManLiquidGlass)
    }

    fileprivate var isThemeLightenEnabled: Bool {
        return AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.boardManThemeLighten)
    }

    fileprivate var appearanceMode: BoardManAppearanceMode {
        return BoardManAppearanceMode.allowed(AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManAppearanceMode))
    }

    fileprivate var uiStyle: BoardManUIStyle {
        return BoardManUIStyle.allowed(AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManUIStyle))
    }

    fileprivate var fontChoice: BoardManFontChoice {
        return BoardManFontChoice.allowed(AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManFontChoice))
    }

    fileprivate var itemTextScale: CGFloat {
        let stored = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.boardManItemTextScale)
        return CGFloat(Self.clampedItemTextScale(stored)) / 100
    }

    fileprivate var timestampPosition: BoardManTimestampPosition {
        let format = BoardManPanel.allowedTimestampFormat(
            AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManTimestampFormat)
        )
        if format == "none" { return .hidden }
        return BoardManTimestampPosition.allowed(
            AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManTimestampPosition)
        )
    }

    fileprivate var selectedThemePreset: BoardManThemePreset {
        return BoardManThemePreset.allowed(AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManThemePreset))
    }

    fileprivate var themePreset: BoardManThemePreset {
        return uiStyle == .monochrome ? .graphite : selectedThemePreset
    }

    fileprivate var themeAccentColor: NSColor {
        let base = BoardManPanel.customColor(
            forKey: Constants.UserDefaults.boardManCustomAccentColor,
            fallback: themePreset.accentColor
        )
        let opacity = max(0.05, min(1, AppEnvironment.current.defaults.double(forKey: Constants.UserDefaults.boardManCustomAccentOpacity)))
        return base.withAlphaComponent(CGFloat(opacity))
    }

    fileprivate var customPanelTintColor: NSColor {
        let base = BoardManPanel.customColor(
            forKey: Constants.UserDefaults.boardManCustomPanelColor,
            fallback: themePreset.accentColor
        )
        let opacity = max(0, min(1, AppEnvironment.current.defaults.double(forKey: Constants.UserDefaults.boardManCustomPanelOpacity)))
        return base.withAlphaComponent(CGFloat(opacity))
    }

    fileprivate var customUsedTintColor: NSColor {
        let base = BoardManPanel.customColor(
            forKey: Constants.UserDefaults.boardManCustomUsedColor,
            fallback: .systemGray
        )
        let opacity = max(0, min(1, AppEnvironment.current.defaults.double(forKey: Constants.UserDefaults.boardManCustomUsedOpacity)))
        return base.withAlphaComponent(CGFloat(opacity))
    }

    private var effectiveTextPreviewScale: CGFloat {
        let stored = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.boardManTextPreviewScale)
        return CGFloat(Self.clampedPreviewScale(stored)) / 100
    }

    private var effectiveImagePreviewScale: CGFloat {
        let stored = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.boardManImagePreviewScale)
        return CGFloat(Self.clampedPreviewScale(stored)) / 100
    }

    static func customColor(forKey key: String, fallback: NSColor) -> NSColor {
        guard let value = AppEnvironment.current.defaults.string(forKey: key) else { return fallback }
        let hex = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let raw = UInt64(hex, radix: 16) else { return fallback }
        return NSColor(
            calibratedRed: CGFloat((raw >> 16) & 0xFF) / 255,
            green: CGFloat((raw >> 8) & 0xFF) / 255,
            blue: CGFloat(raw & 0xFF) / 255,
            alpha: 1
        )
    }

    static func storeCustomColor(_ color: NSColor, forKey key: String) {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return }
        let red = Int(round(rgb.redComponent * 255))
        let green = Int(round(rgb.greenComponent * 255))
        let blue = Int(round(rgb.blueComponent * 255))
        AppEnvironment.current.defaults.set(String(format: "%02X%02X%02X", red, green, blue), forKey: key)
    }

    static func preferredPanelHeight() -> CGFloat {
        return CGFloat(clampedPanelHeight(AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.boardManPanelHeight)))
    }

    static let snippetDragType = NSPasteboard.PasteboardType("com.uniplanck.boardman.snippet-row")
    static let allCategoriesIdentifier = "__boardman_all_categories__"
    static let uncategorizedCategoryIdentifier = "__boardman_uncategorized__"

    static func preferredPanelWidth() -> CGFloat {
        return LayoutMetrics.preferredWidth
    }

    static let quickItemLimit = 3

    static func clampedPreviewScale(_ value: Int) -> Int {
        let normalized = value == 0 ? 100 : value
        return min(200, max(50, normalized))
    }

    static func effectivePreviewScale(storedValue: Int, isPro: Bool) -> Int {
        return clampedPreviewScale(storedValue)
    }

    static func clampedItemTextScale(_ value: Int) -> Int {
        let normalized = value == 0 ? 100 : value
        return min(140, max(80, normalized))
    }

    static func clampedTimestampShortcutDelay(_ value: TimeInterval) -> TimeInterval {
        return BoardManTimestampPresentation.clampedShortcutDelay(value)
    }

    static func usesStackedHistorySettingsLayout(width: CGFloat) -> Bool {
        BoardManPanelLayoutPolicy.usesStackedHistorySettingsLayout(width: width)
    }

    static func usesStackedAppearanceSettingsLayout(width: CGFloat) -> Bool {
        BoardManPanelLayoutPolicy.usesStackedAppearanceSettingsLayout(width: width)
    }

    static func tabDelta(horizontalDelta: CGFloat, verticalDelta: CGFloat) -> Int? {
        guard abs(horizontalDelta) >= 18,
              abs(horizontalDelta) > abs(verticalDelta) * 1.2 else { return nil }
        return horizontalDelta < 0 ? 1 : -1
    }

    static func quickPanelSize() -> NSSize {
        return NSSize(width: 680, height: 260)
    }

    static func cursorRelativeFrame(size panelSize: NSSize, anchorPoint: NSPoint? = nil) -> NSRect {
        let anchor = anchorPoint ?? NSEvent.mouseLocation
        var originX = anchor.x - (panelSize.width / 2)
        var originY = anchor.y - (panelSize.height / 2)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(anchor, $0.frame, false) }) ?? NSScreen.main {
            let visibleFrame = screen.visibleFrame
            originX = max(visibleFrame.minX + 20, min(originX, visibleFrame.maxX - panelSize.width - 20))
            originY = max(visibleFrame.minY + 20, min(originY, visibleFrame.maxY - panelSize.height - 40))
        }
        return NSRect(x: originX, y: originY, width: panelSize.width, height: panelSize.height)
    }

    static func clampedPanelHeight(_ value: Int) -> Int {
        return min(1200, max(520, value == 0 ? 760 : value))
    }

    static func allowedTimestampFormat(_ value: String?) -> String {
        return BoardManTimestampPresentation.allowedFormat(value)
    }

    static func timestampText(
        for updateTime: Int,
        format: String,
        relativeStyle: BoardManRelativeTimestampStyle = .current(),
        now: Date = Date()
    ) -> String {
        return BoardManTimestampPresentation.text(
            for: updateTime,
            format: format,
            relativeStyle: relativeStyle,
            now: now
        )
    }

    static func isImageClip(_ clip: BoardManClip) -> Bool {
        if !clip.thumbnailPath.isEmpty && !clip.isColorCode {
            return true
        }
        let type = NSPasteboard.PasteboardType(rawValue: clip.primaryType)
        return type == .png || type == .tiff || type == .deprecatedTIFF
    }

    static func imageClipTitle(for clip: BoardManClip) -> String {
        let type = NSPasteboard.PasteboardType(rawValue: clip.primaryType)
        if type == .png {
            return "PNG image"
        }
        if type == .tiff || type == .deprecatedTIFF {
            return "TIFF image"
        }
        return "Image"
    }

    private static func timestampMenuTitle(for value: String?) -> String {
        return BoardManTimestampPresentation.menuTitle(for: value)
    }

    private static func timestampFormat(forMenuTitle title: String?) -> String {
        return BoardManTimestampPresentation.format(forMenuTitle: title)
    }

    private static func allowedUsageCountStyle(_ value: String?) -> String {
        return value == "compact" ? "compact" : "badge"
    }

    private static func allowedUsedItemStyle(_ value: String?) -> String {
        let allowed = [
            "Default", "Subtle Red", "Amber", "Blue", "Teal",
            "Green", "Purple", "Indigo", "Gray", "Monochrome"
        ]
        guard let value, allowed.contains(value) else { return "Default" }
        return value
    }

    private static func allowedThemePresetTitle(_ value: String?) -> String {
        return BoardManThemePreset.allowed(value).title
    }

    private enum StatusItemValue {
        static let hidden = 0
        static let black = 1
        static let white = 2
    }

    private static func statusItemTitle(for rawValue: Int) -> String {
        switch rawValue {
        case StatusItemValue.hidden: return "Hidden"
        case StatusItemValue.white: return "White"
        default: return "Black"
        }
    }

    private static func statusItemValue(for title: String?) -> Int {
        switch title {
        case "Hidden": return StatusItemValue.hidden
        case "White": return StatusItemValue.white
        default: return StatusItemValue.black
        }
    }

    private static func shortcutText(_ keyCombo: KeyCombo?) -> String {
        guard let keyCombo else { return "Not set" }
        let key = keyCombo.characters.isEmpty ? keyCombo.keyEquivalent : keyCombo.characters
        let text = keyCombo.keyEquivalentModifierMaskString + key.uppercased()
        return text.isEmpty ? "Set" : text
    }

    private func globalShortcutKeyCombo(for kind: BoardManGlobalShortcutKind) -> KeyCombo? {
        switch kind {
        case .openBoardMan: return AppEnvironment.current.hotKeyService.mainKeyCombo
        case .quickMode: return AppEnvironment.current.hotKeyService.quickModeKeyCombo
        case .history: return AppEnvironment.current.hotKeyService.historyKeyCombo
        case .snippets: return AppEnvironment.current.hotKeyService.snippetKeyCombo
        case .clearHistory: return AppEnvironment.current.hotKeyService.clearHistoryKeyCombo
        }
    }

    private func refreshGlobalShortcutRows() {
        globalShortcutRows.forEach { row in
            row.recordView.keyCombo = globalShortcutKeyCombo(for: row.kind)
        }
        shortcutStatusLabel?.stringValue = boardManText("Click a shortcut field, then press the new key combination. Changes apply immediately.")
        updateSettingsSidebarSelection()
    }

    private func refreshSnippetSettingsSummary() {
        let folders = store.foldersSortedByIndex()
        let snippets = store.snippetsSortedByIndex()
        let snippetCount = snippets.count
        let enabledSnippetCount = snippets.filter(\.enable).count
        let enabledFolderCount = folders.filter { $0.enable }.count
        let shortcutCount = folders.filter { AppEnvironment.current.hotKeyService.snippetKeyCombo(forIdentifier: $0.identifier) != nil }.count
        let topFolderNames = folders.prefix(4).map { folder -> String in
            let title = folder.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? "untitled folder" : title
        }
        let isJapanese = BoardManLanguage.allowed(
            AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManLanguage)
        ).resolved == .japanese
        let folderPreview = topFolderNames.isEmpty
            ? (isJapanese ? "グループはまだありません" : "No folders yet")
            : topFolderNames.joined(separator: ", ")

        if isJapanese {
            snippetSummaryLabel?.stringValue = "スニペット \(snippetCount)件、グループ \(folders.count)件（有効 \(enabledSnippetCount)件 / \(enabledFolderCount)件）"
            snippetFoldersLabel?.stringValue = "グループ: \(folderPreview)"
            snippetShortcutsLabel?.stringValue = "設定済みグループショートカット: \(shortcutCount)件"
        } else {
            snippetSummaryLabel?.stringValue = "\(snippetCount) snippets, \(folders.count) folders (\(enabledSnippetCount) snippets enabled, \(enabledFolderCount) folders enabled)"
            snippetFoldersLabel?.stringValue = "Folders: \(folderPreview)"
            snippetShortcutsLabel?.stringValue = "Folder shortcuts configured: \(shortcutCount)"
        }
        let selectedIdentifier = snippetGroupOrderPopup?.selectedItem?.representedObject as? String
        snippetGroupOrderPopup?.removeAllItems()
        folders.forEach { folder in
            let title = folder.title.trimmingCharacters(in: .whitespacesAndNewlines)
            snippetGroupOrderPopup?.addItem(withTitle: title.isEmpty ? "untitled folder" : title)
            snippetGroupOrderPopup?.lastItem?.representedObject = folder.identifier
        }
        if let selectedIdentifier,
           let item = snippetGroupOrderPopup?.itemArray.first(where: { ($0.representedObject as? String) == selectedIdentifier }) {
            snippetGroupOrderPopup?.select(item)
        }
        snippetGroupOrderPopup?.isEnabled = !folders.isEmpty
        updateSnippetGroupMoveButtons(folders: folders)
        reloadSnippetShortcutRows(with: folders)
    }

    private func updateSnippetGroupMoveButtons(folders: [BoardManFolder]? = nil) {
        let orderedFolders: [BoardManFolder]
        if let folders {
            orderedFolders = folders
        } else {
            orderedFolders = store.foldersSortedByIndex()
        }
        guard let identifier = snippetGroupOrderPopup?.selectedItem?.representedObject as? String,
              let index = orderedFolders.firstIndex(where: { $0.identifier == identifier }) else {
            snippetGroupMoveUpButton?.isEnabled = false
            snippetGroupMoveDownButton?.isEnabled = false
            return
        }
        snippetGroupMoveUpButton?.isEnabled = index > 0
        snippetGroupMoveDownButton?.isEnabled = index < orderedFolders.count - 1
    }

    @objc private func snippetGroupOrderSelectionChanged(_ sender: NSPopUpButton) {
        updateSnippetGroupMoveButtons()
    }

    @objc private func moveSnippetGroupUp(_ sender: Any?) {
        moveSelectedSnippetGroup(by: -1)
    }

    @objc private func moveSnippetGroupDown(_ sender: Any?) {
        moveSelectedSnippetGroup(by: 1)
    }

    private func moveSelectedSnippetGroup(by delta: Int) {
        let folders = store.foldersSortedByIndex()
        guard let identifier = snippetGroupOrderPopup?.selectedItem?.representedObject as? String,
              let sourceIndex = folders.firstIndex(where: { $0.identifier == identifier }) else { return }
        let destinationIndex = sourceIndex + delta
        guard folders.indices.contains(destinationIndex) else { return }
        var reordered = folders
        let folder = reordered.remove(at: sourceIndex)
        reordered.insert(folder, at: destinationIndex)
        BoardManFolder.rearrangesIndex(reordered)
        refreshSnippetSettingsSummary()
        if let item = snippetGroupOrderPopup?.itemArray.first(where: { ($0.representedObject as? String) == identifier }) {
            snippetGroupOrderPopup?.select(item)
        }
        updateSnippetGroupMoveButtons()
        onRefreshRequested?()
    }

    private func reloadSnippetShortcutRows(with folders: [BoardManFolder]) {
        guard let documentView = snippetShortcutDocumentView else { return }
        snippetShortcutRows.flatMap { $0.views }.forEach { $0.removeFromSuperview() }
        snippetShortcutRows = folders.map { folder in
            let keyCombo = AppEnvironment.current.hotKeyService.keyComboForSnippetFolder(identifier: folder.identifier)
            let row = BoardManSnippetShortcutRow(folder: folder, keyCombo: keyCombo)
            row.recordView.delegate = self
            row.clearButton.target = self
            row.clearButton.action = #selector(clearSnippetFolderShortcut(_:))
            row.clearButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            row.clearButton.controlSize = .regular
            row.views.forEach { documentView.addSubview($0) }
            return row
        }
    }

    private static func makeSectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: boardManText(title))
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    private static func paddedSidebarSymbol(named symbolName: String, title: String) -> NSImage? {
        guard #available(macOS 11.0, *),
              let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) else {
            return nil
        }
        let configured = symbol.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        ) ?? symbol
        let symbolSize = NSSize(width: 15, height: 15)
        let imageSize = NSSize(
            width: LayoutMetrics.sidebarSymbolLeadingInset + symbolSize.width,
            height: symbolSize.height
        )
        let padded = NSImage(size: imageSize, flipped: false) { _ in
            configured.draw(in: NSRect(
                x: LayoutMetrics.sidebarSymbolLeadingInset,
                y: 0,
                width: symbolSize.width,
                height: symbolSize.height
            ))
            return true
        }
        padded.isTemplate = true
        padded.accessibilityDescription = title
        return padded
    }

    private func applyControlMetrics() {
        let actionButtons: [NSButton?] = [
            manageSnippetsButton, clearHistoryButton, exportHistoryCSVButton, excludedAppsButton,
            addHideRuleButton, removeLastHideRuleButton, clearHideRulesButton,
            resetCustomColorsButton,
            snippetGroupMoveUpButton, snippetGroupMoveDownButton, snippetReorderModeButton,
            licenseActivateButton, licenseUpgradeButton,
            snippetCategoryAddButton, snippetCategoryRenameButton, snippetCategoryDeleteButton,
            snippetAddButton, snippetEditButton, snippetDeleteButton, snippetSaveButton, snippetCancelEditButton
        ]
        actionButtons.forEach { button in
            button?.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            button?.controlSize = .regular
            button?.bezelStyle = .rounded
        }

        let checkboxButtons: [NSButton?] = [
            launchOnLoginButton, inputPasteCommandButton,
            rowNumbersButton, usageCountButton, themeLightenButton, dedupeButton,
            skipPinnedNavigationButton,
            overwriteSameHistoryButton, reuseTopButton, pauseRecordingButton,
            snippetFolderEnableButton, snippetEnableButton
        ]
        (checkboxButtons + storedTypeButtons.map { Optional($0) }).forEach { button in
            button?.font = NSFont.systemFont(ofSize: 12)
            button?.controlSize = .regular
        }

        let popups: [NSPopUpButton?] = [
            languagePopup, statusItemPopup, timestampPopup, timestampPositionPopup, usageStylePopup, usedItemStylePopup,
            longPressActionPopup, timedPinDurationUnitPopup, snippetGroupOrderPopup,
            themePresetPopup, appearanceModePopup, uiStylePopup, fontChoicePopup,
            hideRuleModePopup, snippetCategoryPopup
        ]
        popups.forEach { popup in
            popup?.font = NSFont.systemFont(ofSize: 12)
            popup?.controlSize = .regular
        }

        globalShortcutRows.forEach { row in
            row.clearButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            row.clearButton.controlSize = .regular
        }
        [snippetDeleteButton, snippetCategoryDeleteButton, clearHistoryButton, clearHideRulesButton].forEach {
            $0?.contentTintColor = .systemRed
        }
    }

    convenience init() {
        let contentRect = NSRect(x: 0, y: 0, width: BoardManPanel.preferredPanelWidth(), height: BoardManPanel.preferredPanelHeight())
        self.init(contentRect: contentRect,
                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                  backing: .buffered,
                  defer: false)
        self.minSize = NSSize(width: LayoutMetrics.minimumWidth, height: 600)
        self.title = "Board-Man"
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.isFloatingPanel = true
        self.hidesOnDeactivate = true
        self.becomesKeyOnlyIfNeeded = false
        self.worksWhenModal = true
        self.level = .popUpMenu
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        self.backgroundColor = NSColor.windowBackgroundColor
        self.hasShadow = true
        self.isRestorable = false
        self.setFrameAutosaveName("")
        self.appearance = appearanceMode.appearance
        setupPanelContainer()
        setupUI()
        applyLocalizedStrings()
        setupPreviewBubble()
        installPreviewLifecycleObservers()
        applyLiquidGlassStyle()
    }

    deinit {
        hidePreviewBubble()
        removeLocalKeyMonitor()
        previewLifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func setupPanelContainer() {
        if let contentView = contentView {
            contentView.wantsLayer = true
            if #available(macOS 10.15, *) {
                contentView.layer?.cornerRadius = 18
                contentView.layer?.masksToBounds = true
            }
            contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            contentView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
            contentView.layer?.borderWidth = 1
        }
    }

    private func setupGlassBackgroundIfNeeded() {
        guard glassBackgroundView == nil, let contentView = contentView else { return }
        let glass = NSVisualEffectView(frame: contentView.bounds)
        glass.autoresizingMask = [.width, .height]
        glass.blendingMode = .behindWindow
        glass.material = .hudWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.18).cgColor
        glass.isHidden = true
        contentView.addSubview(glass, positioned: .below, relativeTo: nil)
        glassBackgroundView = glass
    }

    private func setupUI() {
        guard let contentView = contentView else { return }
        setupGlassBackgroundIfNeeded()

        let search = NSSearchField(frame: .zero)
        let searchCell = BoardManCenteredSearchFieldCell(textCell: "")
        searchCell.opticalYOffset = 2
        search.cell = searchCell
        search.placeholderString = boardManText("Search clipboard history and snippets")
        search.target = self
        search.action = #selector(searchTextChanged(_:))
        search.sendsSearchStringImmediately = true
        search.delegate = self
        search.focusRingType = .none
        search.controlSize = .regular
        search.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        search.isEditable = true
        search.isSelectable = true
        search.isEnabled = true
        contentView.addSubview(search)
        searchField = search

        // History and Templates remain the two primary tabs. Settings lives in the trailing gear button.
        // This is intentionally custom-drawn instead of NSSegmentedControl so AppKit cannot add
        // a system hover/focus halo around the capsule edges.
        let tabs = BoardManHeaderTabBar(frame: .zero)
        tabs.configureTab(
            index: BoardManPanelTab.history.rawValue,
            title: BoardManPanelTab.history.title,
            toolTip: BoardManPanelTab.history.title,
            image: NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: BoardManPanelTab.history.title)
        )
        tabs.configureTab(
            index: BoardManPanelTab.snippets.rawValue,
            title: BoardManPanelTab.snippets.title,
            toolTip: BoardManPanelTab.snippets.title,
            image: NSImage(systemSymbolName: "text.badge.plus", accessibilityDescription: BoardManPanelTab.snippets.title)
        )
        tabs.selectionDidChange = { [weak self] index in
            let tab: BoardManPanelTab = index == BoardManPanelTab.snippets.rawValue ? .snippets : .history
            self?.activateTab(tab)
        }
        contentView.addSubview(tabs)
        headerTabBar = tabs

        let gear = NSButton(title: "", target: self, action: #selector(settingsButtonPressed(_:)))
        gear.bezelStyle = .rounded
        gear.controlSize = .large
        gear.imagePosition = .imageOnly
        gear.toolTip = boardManText("Settings")
        gear.setAccessibilityLabel(boardManText("Settings"))
        gear.identifier = NSUserInterfaceItemIdentifier("BoardManSettingsButton")
        if #available(macOS 11.0, *) {
            gear.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: boardManText("Settings"))
        } else {
            gear.title = "⚙"
        }
        contentView.addSubview(gear)
        settingsButton = gear

        let historyFilter = NSSegmentedControl(frame: .zero)
        historyFilter.segmentCount = BoardManHistoryUsageFilter.allCases.count
        historyFilter.trackingMode = .selectOne
        historyFilter.segmentStyle = .rounded
        historyFilter.controlSize = .small
        historyFilter.target = self
        historyFilter.action = #selector(historyUsageFilterChanged(_:))
        let selectedUsageFilter = BoardManHistoryUsageFilter.allowed(
            AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManHistoryUsageFilter)
        )
        for (index, filter) in BoardManHistoryUsageFilter.allCases.enumerated() {
            historyFilter.setLabel(filter.rawValue, forSegment: index)
            historyFilter.setToolTip(filter.toolTip, forSegment: index)
            if #available(macOS 11.0, *) {
                historyFilter.setLabel("", forSegment: index)
                historyFilter.setImage(NSImage(systemSymbolName: filter.symbolName, accessibilityDescription: filter.rawValue), forSegment: index)
            }
        }
        historyFilter.selectedSegment = BoardManHistoryUsageFilter.allCases.firstIndex(of: selectedUsageFilter) ?? 0
        historyFilter.setAccessibilityLabel("History usage filter")
        contentView.addSubview(historyFilter)
        historyUsageFilterControl = historyFilter

        let historySort = NSButton(title: "", target: self, action: #selector(historySortOrderChanged(_:)))
        historySort.setButtonType(.toggle)
        historySort.bezelStyle = .rounded
        historySort.controlSize = .small
        historySort.imagePosition = .imageOnly
        historySort.state = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.reorderClipsAfterPasting) ? .on : .off
        historySort.setAccessibilityLabel("History sort order")
        contentView.addSubview(historySort)
        historySortButton = historySort
        updateHistorySortButton()

        let historyCondition = NSButton(title: "", target: self, action: #selector(historyConditionButtonPressed(_:)))
        historyCondition.bezelStyle = .rounded
        historyCondition.controlSize = .small
        historyCondition.imagePosition = .imageOnly
        historyCondition.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        historyCondition.setAccessibilityLabel("Edit history condition")
        historyCondition.identifier = NSUserInterfaceItemIdentifier("BoardManHistoryConditionButton")
        contentView.addSubview(historyCondition)
        historyConditionButton = historyCondition
        updateHistoryConditionButton()

        let savedFilter = NSPopUpButton(frame: .zero, pullsDown: false)
        savedFilter.controlSize = .small
        savedFilter.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        savedFilter.target = self
        savedFilter.action = #selector(savedFilterPopupChanged(_:))
        savedFilter.identifier = NSUserInterfaceItemIdentifier("BoardManSavedFilterPopup")
        savedFilter.setAccessibilityLabel(boardManText("Saved Filters"))
        contentView.addSubview(savedFilter)
        historySavedFilterPopup = savedFilter
        reloadSavedFilterPopup()

        let settingsBackground = NSView(frame: .zero)
        settingsBackground.wantsLayer = true
        settingsBackground.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        settingsBackground.layer?.cornerRadius = LayoutMetrics.cardCornerRadius
        contentView.addSubview(settingsBackground)
        settingsBackgroundView = settingsBackground

        let settingsDocument = NSView(frame: .zero)
        settingsDocument.wantsLayer = true
        let settingsScroll = NSScrollView(frame: .zero)
        settingsScroll.documentView = settingsDocument
        settingsScroll.hasVerticalScroller = true
        settingsScroll.hasHorizontalScroller = false
        settingsScroll.autohidesScrollers = true
        settingsScroll.borderType = .noBorder
        settingsScroll.drawsBackground = false
        settingsScroll.scrollerStyle = .overlay
        settingsScroll.identifier = NSUserInterfaceItemIdentifier("BoardManSettingsScrollView")
        settingsScroll.isHidden = true
        contentView.addSubview(settingsScroll)
        settingsScrollView = settingsScroll
        settingsDocumentView = settingsDocument

        let sidebar = NSView(frame: .zero)
        sidebar.wantsLayer = true
        sidebar.layer?.cornerRadius = LayoutMetrics.cardCornerRadius
        sidebar.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor
        sidebar.layer?.borderWidth = 1
        sidebar.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.34).cgColor
        contentView.addSubview(sidebar)
        settingsSidebarView = sidebar

        settingsCategoryButtons = BoardManInlineSettingsCategory.allCases.map { category in
            let button = BoardManSettingsCategoryButton(title: category.title, target: self, action: #selector(settingsCategoryButtonPressed(_:)))
            button.tag = category.rawValue
            button.isBordered = false
            button.alignment = .left
            button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.wantsLayer = true
            button.layer?.cornerRadius = 8
            button.toolTip = category.detail
            button.image = BoardManPanel.paddedSidebarSymbol(
                named: category.symbolName,
                title: category.title
            )
            button.hoverDidChange = { [weak self] in
                self?.updateSettingsSidebarSelection()
            }
            sidebar.addSubview(button)
            return button
        }

        let pageTitle = NSTextField(labelWithString: activeSettingsCategory.title)
        pageTitle.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        pageTitle.textColor = .labelColor
        contentView.addSubview(pageTitle)
        settingsPageTitleLabel = pageTitle

        let pageDescription = NSTextField(labelWithString: activeSettingsCategory.detail)
        pageDescription.font = NSFont.systemFont(ofSize: 12)
        pageDescription.textColor = .secondaryLabelColor
        pageDescription.lineBreakMode = .byWordWrapping
        pageDescription.maximumNumberOfLines = 2
        pageDescription.cell?.wraps = true
        contentView.addSubview(pageDescription)
        settingsPageDescriptionLabel = pageDescription

        let generalTitle = BoardManPanel.makeSectionLabel("General")
        contentView.addSubview(generalTitle)
        generalSectionLabel = generalTitle

        let launchOnLogin = NSButton(checkboxWithTitle: boardManText("Launch on Login"), target: self, action: #selector(launchOnLoginChanged(_:)))
        launchOnLogin.state = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.loginItem) ? .on : .off
        launchOnLogin.font = NSFont.systemFont(ofSize: 11)
        if #available(macOS 10.14, *) {
            launchOnLogin.contentTintColor = .labelColor
        }
        contentView.addSubview(launchOnLogin)
        launchOnLoginButton = launchOnLogin

        let pasteCommand = NSButton(checkboxWithTitle: boardManText("Send Command+V"), target: self, action: #selector(inputPasteCommandChanged(_:)))
        pasteCommand.state = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.inputPasteCommand) ? .on : .off
        pasteCommand.font = NSFont.systemFont(ofSize: 11)
        pasteCommand.toolTip = "Sends Command+V after selecting a clipboard item."
        if #available(macOS 10.14, *) {
            pasteCommand.contentTintColor = .labelColor
        }
        contentView.addSubview(pasteCommand)
        inputPasteCommandButton = pasteCommand

        let languageText = NSTextField(labelWithString: boardManText("Language"))
        languageText.font = NSFont.systemFont(ofSize: 11)
        languageText.textColor = .labelColor
        contentView.addSubview(languageText)
        languageLabel = languageText

        let languageControl = NSPopUpButton(frame: .zero, pullsDown: false)
        languageControl.addItems(withTitles: BoardManLanguage.allCases.map(\.rawValue))
        languageControl.selectItem(withTitle: BoardManLanguage.allowed(
            AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManLanguage)
        ).rawValue)
        languageControl.font = NSFont.systemFont(ofSize: 11)
        languageControl.target = self
        languageControl.action = #selector(languageChanged(_:))
        contentView.addSubview(languageControl)
        languagePopup = languageControl

        let maxHistoryLabel = NSTextField(labelWithString: boardManText("Visible history"))
        maxHistoryLabel.font = NSFont.systemFont(ofSize: 11)
        maxHistoryLabel.textColor = .labelColor
        contentView.addSubview(maxHistoryLabel)
        maxHistorySizeLabel = maxHistoryLabel

        let maxHistoryStepper = NSStepper(frame: .zero)
        maxHistoryStepper.minValue = 1
        maxHistoryStepper.maxValue = 1000
        maxHistoryStepper.increment = 10
        maxHistoryStepper.integerValue = max(1, AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxHistorySize))
        maxHistoryStepper.target = self
        maxHistoryStepper.action = #selector(maxHistorySizeChanged(_:))
        maxHistoryStepper.identifier = NSUserInterfaceItemIdentifier("BoardManVisibleHistoryStepper")
        contentView.addSubview(maxHistoryStepper)
        maxHistorySizeStepper = maxHistoryStepper

        let maxHistoryValue = NSTextField(frame: .zero)
        maxHistoryValue.cell = BoardManCenteredTextFieldCell(textCell: "\(maxHistoryStepper.integerValue)")
        maxHistoryValue.alignment = .right
        maxHistoryValue.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        maxHistoryValue.textColor = .labelColor
        maxHistoryValue.isEditable = true
        maxHistoryValue.isSelectable = true
        maxHistoryValue.isEnabled = true
        maxHistoryValue.target = self
        maxHistoryValue.action = #selector(maxHistorySizeFieldChanged(_:))
        maxHistoryValue.delegate = self
        let maxHistoryFormatter = NumberFormatter()
        maxHistoryFormatter.numberStyle = .none
        maxHistoryFormatter.minimum = 1
        maxHistoryFormatter.maximum = 1000
        maxHistoryFormatter.allowsFloats = false
        maxHistoryValue.formatter = maxHistoryFormatter
        maxHistoryValue.identifier = NSUserInterfaceItemIdentifier("BoardManVisibleHistoryField")
        configureSettingsInputField(maxHistoryValue)
        contentView.addSubview(maxHistoryValue)
        maxHistorySizeValueLabel = maxHistoryValue

        let maxHistoryDecrease = makeAdjustmentButton(
            title: "−",
            action: #selector(adjustMaxHistorySize(_:)),
            identifier: "BoardManVisibleHistoryDecreaseButton",
            delta: -1
        )
        contentView.addSubview(maxHistoryDecrease)
        maxHistoryDecreaseButton = maxHistoryDecrease

        let maxHistoryIncrease = makeAdjustmentButton(
            title: "+",
            action: #selector(adjustMaxHistorySize(_:)),
            identifier: "BoardManVisibleHistoryIncreaseButton",
            delta: 1
        )
        contentView.addSubview(maxHistoryIncrease)
        maxHistoryIncreaseButton = maxHistoryIncrease

        let statusLabel = NSTextField(labelWithString: boardManText("Icon"))
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .labelColor
        contentView.addSubview(statusLabel)
        statusItemLabel = statusLabel

        let statusPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        statusPopup.addItems(withTitles: ["Black", "White", "Hidden"])
        statusPopup.selectItem(withTitle: BoardManPanel.statusItemTitle(for: AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.showStatusItem)))
        statusPopup.font = NSFont.systemFont(ofSize: 11)
        statusPopup.target = self
        statusPopup.action = #selector(statusItemChanged(_:))
        contentView.addSubview(statusPopup)
        statusItemPopup = statusPopup

        let shortcutTitle = BoardManPanel.makeSectionLabel("Keyboard Shortcuts")
        contentView.addSubview(shortcutTitle)
        shortcutSectionLabel = shortcutTitle

        globalShortcutRows = BoardManGlobalShortcutKind.allCases.map { kind in
            let row = BoardManGlobalShortcutRow(kind: kind, keyCombo: globalShortcutKeyCombo(for: kind))
            row.recordView.delegate = self
            row.clearButton.target = self
            row.clearButton.action = #selector(clearGlobalShortcut(_:))
            row.views.forEach { contentView.addSubview($0) }
            return row
        }

        let shortcutStatus = NSTextField(labelWithString: boardManText("Click a shortcut field, then press the new key combination. Changes apply immediately."))
        shortcutStatus.font = NSFont.systemFont(ofSize: 10.5)
        shortcutStatus.textColor = .secondaryLabelColor
        shortcutStatus.lineBreakMode = .byWordWrapping
        shortcutStatus.maximumNumberOfLines = 2
        shortcutStatus.cell?.wraps = true
        contentView.addSubview(shortcutStatus)
        shortcutStatusLabel = shortcutStatus

        let snippetsTitle = BoardManPanel.makeSectionLabel("Snippets")
        contentView.addSubview(snippetsTitle)
        snippetSettingsSectionLabel = snippetsTitle

        let snippetSummary = NSTextField(labelWithString: "")
        snippetSummary.font = NSFont.systemFont(ofSize: 11)
        snippetSummary.textColor = .labelColor
        snippetSummary.lineBreakMode = .byTruncatingTail
        contentView.addSubview(snippetSummary)
        snippetSummaryLabel = snippetSummary

        let snippetFolders = NSTextField(labelWithString: "")
        snippetFolders.font = NSFont.systemFont(ofSize: 11)
        snippetFolders.textColor = .secondaryLabelColor
        snippetFolders.lineBreakMode = .byTruncatingTail
        contentView.addSubview(snippetFolders)
        snippetFoldersLabel = snippetFolders

        let groupProNote = NSTextField(labelWithString: boardManText("Pro only: group creation, ordering, and folder shortcuts."))
        groupProNote.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        groupProNote.textColor = .tertiaryLabelColor
        groupProNote.lineBreakMode = .byWordWrapping
        groupProNote.maximumNumberOfLines = 2
        contentView.addSubview(groupProNote)
        snippetGroupProNoteLabel = groupProNote

        let groupOrderPopup = BoardManHoverPopUpButton(frame: .zero, pullsDown: false)
        groupOrderPopup.toolTip = boardManText("Hover to open group list")
        groupOrderPopup.font = NSFont.systemFont(ofSize: 11)
        groupOrderPopup.target = self
        groupOrderPopup.action = #selector(snippetGroupOrderSelectionChanged(_:))
        groupOrderPopup.toolTip = boardManText("Hover to open group list")
        contentView.addSubview(groupOrderPopup)
        snippetGroupOrderPopup = groupOrderPopup

        let groupMoveUp = NSButton(title: boardManText("Move Up"), target: self, action: #selector(moveSnippetGroupUp(_:)))
        groupMoveUp.font = NSFont.systemFont(ofSize: 11)
        groupMoveUp.bezelStyle = .rounded
        contentView.addSubview(groupMoveUp)
        snippetGroupMoveUpButton = groupMoveUp

        let groupMoveDown = NSButton(title: boardManText("Move Down"), target: self, action: #selector(moveSnippetGroupDown(_:)))
        groupMoveDown.font = NSFont.systemFont(ofSize: 11)
        groupMoveDown.bezelStyle = .rounded
        contentView.addSubview(groupMoveDown)
        snippetGroupMoveDownButton = groupMoveDown

        let snippetShortcuts = NSTextField(labelWithString: "")
        snippetShortcuts.font = NSFont.systemFont(ofSize: 11)
        snippetShortcuts.textColor = .secondaryLabelColor
        snippetShortcuts.lineBreakMode = .byTruncatingTail
        contentView.addSubview(snippetShortcuts)
        snippetShortcutsLabel = snippetShortcuts

        let shortcutDocument = NSView(frame: .zero)
        let shortcutScrollView = NSScrollView(frame: .zero)
        shortcutScrollView.documentView = shortcutDocument
        shortcutScrollView.hasVerticalScroller = true
        shortcutScrollView.hasHorizontalScroller = false
        shortcutScrollView.drawsBackground = false
        shortcutScrollView.borderType = .noBorder
        shortcutScrollView.identifier = NSUserInterfaceItemIdentifier("BoardManSnippetShortcutScrollView")
        contentView.addSubview(shortcutScrollView)
        snippetShortcutDocumentView = shortcutDocument
        snippetShortcutScrollView = shortcutScrollView

        let manageSnippets = NSButton(title: boardManText("Manage Snippets"), target: self, action: #selector(openSnippetManager(_:)))
        manageSnippets.font = NSFont.systemFont(ofSize: 11)
        manageSnippets.bezelStyle = .rounded
        manageSnippets.identifier = NSUserInterfaceItemIdentifier("BoardManManageSnippetsButton")
        manageSnippets.toolTip = "Opens the Board-Man Snippets tab. Existing snippet shortcuts are preserved."
        contentView.addSubview(manageSnippets)
        manageSnippetsButton = manageSnippets

        let previewCard = BoardManSettingsCardView(
            title: boardManText("Preview"),
            detail: boardManText("See changes instantly before returning to History."),
            symbolName: "rectangle.on.rectangle"
        )
        previewCard.identifier = NSUserInterfaceItemIdentifier("BoardManAppearancePreviewCard")
        contentView.addSubview(previewCard)
        appearancePreviewCard = previewCard

        let previewSurface = BoardManAppearancePreviewView(frame: .zero)
        previewSurface.identifier = NSUserInterfaceItemIdentifier("BoardManAppearanceLivePreview")
        contentView.addSubview(previewSurface)
        appearancePreviewView = previewSurface

        let layoutCard = BoardManSettingsCardView(
            title: boardManText("Layout"),
            detail: boardManText("Panel size, row structure, and visual density."),
            symbolName: "rectangle.3.group"
        )
        layoutCard.identifier = NSUserInterfaceItemIdentifier("BoardManAppearanceLayoutCard")
        contentView.addSubview(layoutCard)
        appearanceLayoutCard = layoutCard

        let timestampCard = BoardManSettingsCardView(
            title: boardManText("Timestamp"),
            detail: boardManText("Choose how time is formatted and placed."),
            symbolName: "clock"
        )
        timestampCard.identifier = NSUserInterfaceItemIdentifier("BoardManAppearanceTimestampCard")
        contentView.addSubview(timestampCard)
        appearanceTimestampCard = timestampCard

        let usageCard = BoardManSettingsCardView(
            title: boardManText("Usage"),
            detail: boardManText("Paste counts and used-item treatment."),
            symbolName: "chart.bar"
        )
        usageCard.identifier = NSUserInterfaceItemIdentifier("BoardManAppearanceUsageCard")
        contentView.addSubview(usageCard)
        appearanceUsageCard = usageCard

        let themeCard = BoardManSettingsCardView(
            title: boardManText("Theme & Colors"),
            detail: boardManText("Theme, mode, typography, and surface style."),
            symbolName: "paintpalette"
        )
        themeCard.identifier = NSUserInterfaceItemIdentifier("BoardManAppearanceThemeCard")
        contentView.addSubview(themeCard)
        appearanceThemeCard = themeCard

        let advancedCard = BoardManSettingsCardView(
            title: boardManText("Advanced settings"),
            detail: boardManText("Relative time details, custom colors, and preview scale."),
            symbolName: "slider.horizontal.3"
        )
        advancedCard.identifier = NSUserInterfaceItemIdentifier("BoardManAppearanceAdvancedCard")
        contentView.addSubview(advancedCard)
        appearanceAdvancedCard = advancedCard

        let advancedButton = NSButton(
            title: boardManText("Show advanced settings"),
            target: self,
            action: #selector(toggleAppearanceAdvancedSettings(_:))
        )
        advancedButton.bezelStyle = .inline
        advancedButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        advancedButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        advancedButton.imagePosition = .imageLeading
        advancedButton.identifier = NSUserInterfaceItemIdentifier("BoardManAppearanceAdvancedToggle")
        contentView.addSubview(advancedButton)
        appearanceAdvancedButton = advancedButton

        let viewTitle = BoardManPanel.makeSectionLabel("Appearance")
        contentView.addSubview(viewTitle)
        viewSectionLabel = viewTitle

        let numbers = NSButton(checkboxWithTitle: boardManText("Rows"), target: self, action: #selector(rowNumbersChanged(_:)))
        numbers.state = (AppEnvironment.current.defaults.object(forKey: Constants.UserDefaults.boardManShowRowNumbers) as? Bool ?? true) ? .on : .off
        numbers.font = NSFont.systemFont(ofSize: 11)
        if #available(macOS 10.14, *) {
            numbers.contentTintColor = .labelColor
        }
        contentView.addSubview(numbers)
        rowNumbersButton = numbers

        let timeText = NSTextField(labelWithString: boardManText("Time"))
        timeText.font = NSFont.systemFont(ofSize: 11)
        timeText.textColor = .labelColor
        contentView.addSubview(timeText)
        timestampLabel = timeText

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: ["Relative", "24-hour", "24-hour + seconds", "12-hour", "12-hour + seconds", "Date + time"])
        let storedTimestampTitle = BoardManPanel.timestampMenuTitle(
            for: AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManTimestampFormat)
        )
        popup.selectItem(withTitle: storedTimestampTitle == "Hidden" ? "Relative" : storedTimestampTitle)
        popup.font = NSFont.systemFont(ofSize: 11)
        popup.target = self
        popup.action = #selector(timestampFormatChanged(_:))
        popup.toolTip = "時刻の表示形式を選択します。"
        contentView.addSubview(popup)
        timestampPopup = popup

        let timePositionText = NSTextField(labelWithString: boardManText("Position"))
        timePositionText.font = NSFont.systemFont(ofSize: 11)
        timePositionText.textColor = .labelColor
        contentView.addSubview(timePositionText)
        timestampPositionLabel = timePositionText

        let timePositionControl = NSPopUpButton(frame: .zero, pullsDown: false)
        timePositionControl.addItems(withTitles: BoardManTimestampPosition.allCases.map(\.rawValue))
        timePositionControl.selectItem(withTitle: timestampPosition.rawValue)
        timePositionControl.font = NSFont.systemFont(ofSize: 11)
        timePositionControl.target = self
        timePositionControl.action = #selector(timestampPositionChanged(_:))
        timePositionControl.toolTip = "Hiddenで1行表示、Left/Rightで固定幅の時刻列、Belowで2行表示にします。"
        contentView.addSubview(timePositionControl)
        timestampPositionPopup = timePositionControl

        let relativeLanguage = BoardManLanguage.allowed(
            AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManLanguage)
        ).resolved

        let numberLabel = NSTextField(labelWithString: boardManText("Number"))
        numberLabel.font = NSFont.systemFont(ofSize: 11)
        numberLabel.textColor = .labelColor
        contentView.addSubview(numberLabel)
        relativeNumberLabel = numberLabel

        let numberPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        BoardManRelativeNumberStyle.allCases.forEach { style in
            numberPopup.addItem(withTitle: style.title)
            numberPopup.lastItem?.representedObject = style.rawValue
        }
        numberPopup.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        numberPopup.target = self
        numberPopup.action = #selector(relativeNumberStyleChanged(_:))
        numberPopup.identifier = NSUserInterfaceItemIdentifier("BoardManRelativeNumberStylePopup")
        contentView.addSubview(numberPopup)
        relativeNumberPopup = numberPopup

        let unitLabel = NSTextField(labelWithString: boardManText("Unit"))
        unitLabel.font = NSFont.systemFont(ofSize: 11)
        unitLabel.textColor = .labelColor
        contentView.addSubview(unitLabel)
        relativeUnitLabel = unitLabel

        let unitPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        BoardManRelativeUnitStyle.allCases.forEach { style in
            unitPopup.addItem(withTitle: style.title(language: relativeLanguage))
            unitPopup.lastItem?.representedObject = style.rawValue
        }
        unitPopup.font = NSFont.systemFont(ofSize: 11)
        unitPopup.target = self
        unitPopup.action = #selector(relativeUnitStyleChanged(_:))
        unitPopup.identifier = NSUserInterfaceItemIdentifier("BoardManRelativeUnitStylePopup")
        contentView.addSubview(unitPopup)
        relativeUnitPopup = unitPopup

        let suffixLabel = NSTextField(labelWithString: boardManText("Suffix"))
        suffixLabel.font = NSFont.systemFont(ofSize: 11)
        suffixLabel.textColor = .labelColor
        contentView.addSubview(suffixLabel)
        relativeSuffixLabel = suffixLabel

        let suffixPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        BoardManRelativeSuffixStyle.allCases.forEach { style in
            suffixPopup.addItem(withTitle: style.title(language: relativeLanguage))
            suffixPopup.lastItem?.representedObject = style.rawValue
        }
        suffixPopup.font = NSFont.systemFont(ofSize: 11)
        suffixPopup.target = self
        suffixPopup.action = #selector(relativeSuffixStyleChanged(_:))
        suffixPopup.identifier = NSUserInterfaceItemIdentifier("BoardManRelativeSuffixStylePopup")
        contentView.addSubview(suffixPopup)
        relativeSuffixPopup = suffixPopup

        let nowLabel = NSTextField(labelWithString: boardManText("Under 1 minute"))
        nowLabel.font = NSFont.systemFont(ofSize: 11)
        nowLabel.textColor = .labelColor
        contentView.addSubview(nowLabel)
        relativeNowLabel = nowLabel

        let nowPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        BoardManRelativeNowStyle.allCases.forEach { style in
            nowPopup.addItem(withTitle: style.title(language: relativeLanguage))
            nowPopup.lastItem?.representedObject = style.rawValue
        }
        nowPopup.font = NSFont.systemFont(ofSize: 11)
        nowPopup.target = self
        nowPopup.action = #selector(relativeNowStyleChanged(_:))
        nowPopup.identifier = NSUserInterfaceItemIdentifier("BoardManRelativeNowStylePopup")
        contentView.addSubview(nowPopup)
        relativeNowPopup = nowPopup

        let interactionLabel = NSTextField(labelWithString: boardManText("Time action"))
        interactionLabel.font = NSFont.systemFont(ofSize: 11)
        interactionLabel.textColor = .labelColor
        contentView.addSubview(interactionLabel)
        timestampInteractionLabel = interactionLabel

        let interactionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        BoardManTimestampInteraction.allCases.forEach { interaction in
            interactionPopup.addItem(withTitle: interaction.title)
            interactionPopup.lastItem?.representedObject = interaction.rawValue
        }
        let storedInteraction = BoardManTimestampInteraction.allowed(
            AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManTimestampInteraction)
        )
        if let item = interactionPopup.itemArray.first(where: {
            ($0.representedObject as? String) == storedInteraction.rawValue
        }) {
            interactionPopup.select(item)
        }
        interactionPopup.font = NSFont.systemFont(ofSize: 11)
        interactionPopup.target = self
        interactionPopup.action = #selector(timestampInteractionChanged(_:))
        interactionPopup.toolTip = boardManText("Choose what clicking or holding the timestamp does.")
        contentView.addSubview(interactionPopup)
        timestampInteractionPopup = interactionPopup

        let timestampShortcutToggle = NSButton(
            checkboxWithTitle: boardManText("Enable shortcut for time action"),
            target: self,
            action: #selector(timestampShortcutEnabledChanged(_:))
        )
        timestampShortcutToggle.state = AppEnvironment.current.defaults.bool(
            forKey: Constants.UserDefaults.boardManTimestampShortcutEnabled
        ) ? .on : .off
        timestampShortcutToggle.font = NSFont.systemFont(ofSize: 11)
        timestampShortcutToggle.identifier = NSUserInterfaceItemIdentifier("BoardManTimestampShortcutEnabledButton")
        contentView.addSubview(timestampShortcutToggle)
        timestampShortcutEnabledButton = timestampShortcutToggle

        let timestampShortcutText = NSTextField(labelWithString: boardManText("Shortcut for time action"))
        timestampShortcutText.font = NSFont.systemFont(ofSize: 11)
        timestampShortcutText.textColor = .labelColor
        contentView.addSubview(timestampShortcutText)
        timestampShortcutLabel = timestampShortcutText

        let timestampShortcut = RecordView(frame: .zero)
        timestampShortcut.keyCombo = BoardManTimestampShortcutStore.keyCombo()
        timestampShortcut.delegate = self
        timestampShortcut.identifier = NSUserInterfaceItemIdentifier("BoardManTimestampShortcutRecordView")
        timestampShortcut.toolTip = boardManText("Shortcut executed by the selected timestamp action. It can be edited while disabled.")
        contentView.addSubview(timestampShortcut)
        timestampShortcutRecordView = timestampShortcut

        let shortcutDelayLabel = NSTextField(labelWithString: boardManText("Delay"))
        shortcutDelayLabel.font = NSFont.systemFont(ofSize: 11)
        shortcutDelayLabel.textColor = .labelColor
        contentView.addSubview(shortcutDelayLabel)
        timestampShortcutDelayLabel = shortcutDelayLabel

        let shortcutDelayField = NSTextField(frame: .zero)
        shortcutDelayField.cell = BoardManCenteredTextFieldCell(textCell: "")
        shortcutDelayField.alignment = .right
        shortcutDelayField.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        shortcutDelayField.doubleValue = BoardManPanel.clampedTimestampShortcutDelay(
            AppEnvironment.current.defaults.double(forKey: Constants.UserDefaults.boardManTimestampShortcutDelay)
        )
        let shortcutDelayFormatter = NumberFormatter()
        shortcutDelayFormatter.numberStyle = .decimal
        shortcutDelayFormatter.minimum = 0
        shortcutDelayFormatter.maximum = 60
        shortcutDelayFormatter.minimumFractionDigits = 0
        shortcutDelayFormatter.maximumFractionDigits = 2
        shortcutDelayField.formatter = shortcutDelayFormatter
        shortcutDelayField.target = self
        shortcutDelayField.action = #selector(timestampShortcutDelayFieldChanged(_:))
        shortcutDelayField.delegate = self
        shortcutDelayField.identifier = NSUserInterfaceItemIdentifier("BoardManTimestampShortcutDelayField")
        configureSettingsInputField(shortcutDelayField)
        contentView.addSubview(shortcutDelayField)
        timestampShortcutDelayField = shortcutDelayField

        let shortcutDelayDecrease = makeAdjustmentButton(
            title: "−",
            action: #selector(adjustTimestampShortcutDelay(_:)),
            identifier: "BoardManTimestampShortcutDelayDecreaseButton",
            delta: -1
        )
        contentView.addSubview(shortcutDelayDecrease)
        timestampShortcutDelayDecreaseButton = shortcutDelayDecrease

        let shortcutDelayIncrease = makeAdjustmentButton(
            title: "+",
            action: #selector(adjustTimestampShortcutDelay(_:)),
            identifier: "BoardManTimestampShortcutDelayIncreaseButton",
            delta: 1
        )
        contentView.addSubview(shortcutDelayIncrease)
        timestampShortcutDelayIncreaseButton = shortcutDelayIncrease

        let shortcutDelayStepper = NSStepper(frame: .zero)
        shortcutDelayStepper.minValue = 0
        shortcutDelayStepper.maxValue = 60
        shortcutDelayStepper.increment = 0.1
        shortcutDelayStepper.doubleValue = shortcutDelayField.doubleValue
        shortcutDelayStepper.target = self
        shortcutDelayStepper.action = #selector(timestampShortcutDelayChanged(_:))
        shortcutDelayStepper.identifier = NSUserInterfaceItemIdentifier("BoardManTimestampShortcutDelayStepper")
        contentView.addSubview(shortcutDelayStepper)
        timestampShortcutDelayStepper = shortcutDelayStepper

        let shortcutSecondsLabel = NSTextField(labelWithString: boardManText("Seconds"))
        shortcutSecondsLabel.font = NSFont.systemFont(ofSize: 11)
        shortcutSecondsLabel.textColor = .secondaryLabelColor
        contentView.addSubview(shortcutSecondsLabel)
        timestampShortcutSecondsLabel = shortcutSecondsLabel

        let usage = NSButton(checkboxWithTitle: boardManText("Count"), target: self, action: #selector(usageCountChanged(_:)))
        usage.state = (AppEnvironment.current.defaults.object(forKey: Constants.UserDefaults.boardManShowUsageCount) as? Bool ?? true) ? .on : .off
        usage.font = NSFont.systemFont(ofSize: 11)
        if #available(macOS 10.14, *) {
            usage.contentTintColor = .labelColor
        }
        contentView.addSubview(usage)
        usageCountButton = usage

        let styleText = NSTextField(labelWithString: boardManText("Style"))
        styleText.font = NSFont.systemFont(ofSize: 11)
        styleText.textColor = .labelColor
        contentView.addSubview(styleText)
        usageStyleLabel = styleText

        let usageStyle = NSPopUpButton(frame: .zero, pullsDown: false)
        usageStyle.addItems(withTitles: ["badge", "compact"])
        usageStyle.selectItem(withTitle: BoardManPanel.allowedUsageCountStyle(AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManUsageCountStyle)))
        usageStyle.font = NSFont.systemFont(ofSize: 11)
        usageStyle.target = self
        usageStyle.action = #selector(usageStyleChanged(_:))
        contentView.addSubview(usageStyle)
        usageStylePopup = usageStyle

        let usedItemText = NSTextField(labelWithString: boardManText("Used"))
        usedItemText.font = NSFont.systemFont(ofSize: 11)
        usedItemText.textColor = .labelColor
        contentView.addSubview(usedItemText)
        usedItemStyleLabel = usedItemText

        let usedItemStyle = NSPopUpButton(frame: .zero, pullsDown: false)
        usedItemStyle.addItems(withTitles: [
            "Default", "Subtle Red", "Amber", "Blue", "Teal",
            "Green", "Purple", "Indigo", "Gray", "Monochrome"
        ])
        usedItemStyle.selectItem(withTitle: BoardManPanel.allowedUsedItemStyle(AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManUsedItemStyle)))
        usedItemStyle.font = NSFont.systemFont(ofSize: 11)
        usedItemStyle.target = self
        usedItemStyle.action = #selector(usedItemStyleChanged(_:))
        contentView.addSubview(usedItemStyle)
        usedItemStylePopup = usedItemStyle

        let pinLabelText = NSTextField(labelWithString: boardManText("Pin label"))
        pinLabelText.font = NSFont.systemFont(ofSize: 11)
        pinLabelText.textColor = .labelColor
        contentView.addSubview(pinLabelText)
        pinLabelStyleLabel = pinLabelText

        let pinLabelStyle = NSPopUpButton(frame: .zero, pullsDown: false)
        BoardManPinLabelStyle.allCases.forEach { style in
            pinLabelStyle.addItem(withTitle: style.rawValue)
            pinLabelStyle.lastItem?.representedObject = style.rawValue
        }
        let storedPinLabelStyle = BoardManPinLabelStyle.allowed(
            AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManPinLabelStyle)
        )
        pinLabelStyle.selectItem(withTitle: storedPinLabelStyle.rawValue)
        pinLabelStyle.font = NSFont.systemFont(ofSize: 11)
        pinLabelStyle.target = self
        pinLabelStyle.action = #selector(pinLabelStyleChanged(_:))
        pinLabelStyle.identifier = NSUserInterfaceItemIdentifier("BoardManPinLabelStylePopup")
        contentView.addSubview(pinLabelStyle)
        pinLabelStylePopup = pinLabelStyle

        let showInlineImages = NSButton(
            checkboxWithTitle: boardManText("Images"),
            target: self,
            action: #selector(showInlineImagesChanged(_:))
        )
        showInlineImages.state = (AppEnvironment.current.defaults.object(
            forKey: Constants.UserDefaults.boardManShowInlineImages
        ) as? Bool ?? true) ? .on : .off
        showInlineImages.font = NSFont.systemFont(ofSize: 11)
        contentView.addSubview(showInlineImages)
        showInlineImagesButton = showInlineImages

        let imagePositionText = NSTextField(labelWithString: boardManText("Image side"))
        imagePositionText.font = NSFont.systemFont(ofSize: 11)
        imagePositionText.textColor = .labelColor
        contentView.addSubview(imagePositionText)
        inlineImagePositionLabel = imagePositionText

        let imagePosition = NSPopUpButton(frame: .zero, pullsDown: false)
        BoardManInlineImagePosition.allCases.forEach { position in
            imagePosition.addItem(withTitle: boardManText(position.rawValue))
            imagePosition.lastItem?.representedObject = position.rawValue
        }
        let storedImagePosition = BoardManInlineImagePosition.allowed(
            AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManInlineImagePosition)
        )
        imagePosition.selectItem(at: BoardManInlineImagePosition.allCases.firstIndex(of: storedImagePosition) ?? 1)
        imagePosition.font = NSFont.systemFont(ofSize: 11)
        imagePosition.target = self
        imagePosition.action = #selector(inlineImagePositionChanged(_:))
        imagePosition.identifier = NSUserInterfaceItemIdentifier("BoardManInlineImagePositionPopup")
        contentView.addSubview(imagePosition)
        inlineImagePositionPopup = imagePosition

        let themeText = NSTextField(labelWithString: boardManText("Theme"))
        themeText.font = NSFont.systemFont(ofSize: 11)
        themeText.textColor = .labelColor
        contentView.addSubview(themeText)
        themePresetLabel = themeText

        let themePresetControl = NSPopUpButton(frame: .zero, pullsDown: false)
        BoardManThemePreset.allCases.forEach { preset in
            themePresetControl.addItem(withTitle: preset.title)
            themePresetControl.lastItem?.representedObject = preset.rawValue
        }
        let storedThemePreset = BoardManThemePreset.allowed(
            AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManThemePreset)
        )
        if let item = themePresetControl.itemArray.first(where: { ($0.representedObject as? String) == storedThemePreset.rawValue }) {
            themePresetControl.select(item)
        }
        themePresetControl.font = NSFont.systemFont(ofSize: 11)
        themePresetControl.target = self
        themePresetControl.action = #selector(themePresetChanged(_:))
        themePresetControl.toolTip = "Changes Board-Man panel accents only."
        contentView.addSubview(themePresetControl)
        themePresetPopup = themePresetControl

        let appearanceText = NSTextField(labelWithString: boardManText("Mode"))
        appearanceText.font = NSFont.systemFont(ofSize: 11)
        appearanceText.textColor = .labelColor
        contentView.addSubview(appearanceText)
        appearanceModeLabel = appearanceText

        let appearanceControl = NSPopUpButton(frame: .zero, pullsDown: false)
        appearanceControl.addItems(withTitles: BoardManAppearanceMode.allCases.map { $0.rawValue })
        appearanceControl.selectItem(withTitle: appearanceMode.rawValue)
        appearanceControl.font = NSFont.systemFont(ofSize: 11)
        appearanceControl.target = self
        appearanceControl.action = #selector(appearanceModeChanged(_:))
        appearanceControl.toolTip = "Follow macOS, force Light, or force Dark for Board-Man."
        contentView.addSubview(appearanceControl)
        appearanceModePopup = appearanceControl

        let uiStyleText = NSTextField(labelWithString: boardManText("UI"))
        uiStyleText.font = NSFont.systemFont(ofSize: 11)
        uiStyleText.textColor = .labelColor
        contentView.addSubview(uiStyleText)
        uiStyleLabel = uiStyleText

        let uiStyleControl = NSPopUpButton(frame: .zero, pullsDown: false)
        uiStyleControl.addItems(withTitles: BoardManUIStyle.allCases.map { $0.rawValue })
        uiStyleControl.selectItem(withTitle: uiStyle.rawValue)
        uiStyleControl.font = NSFont.systemFont(ofSize: 11)
        uiStyleControl.target = self
        uiStyleControl.action = #selector(uiStyleChanged(_:))
        uiStyleControl.toolTip = "Default keeps the full visual system, Simple reduces decoration, and Monochrome removes hue."
        contentView.addSubview(uiStyleControl)
        uiStylePopup = uiStyleControl

        let fontText = NSTextField(labelWithString: boardManText("Font"))
        fontText.font = NSFont.systemFont(ofSize: 11)
        fontText.textColor = .labelColor
        contentView.addSubview(fontText)
        fontChoiceLabel = fontText

        let fontControl = NSPopUpButton(frame: .zero, pullsDown: false)
        BoardManFontChoice.builtIns.forEach { fontControl.addItem(withTitle: $0.rawValue) }
        fontControl.menu?.addItem(.separator())
        let installedHeader = NSMenuItem(title: BoardManLanguage.allowed(AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManLanguage)).resolved == .japanese ? "インストール済みフォント" : "Installed Fonts", action: nil, keyEquivalent: "")
        installedHeader.isEnabled = false
        fontControl.menu?.addItem(installedHeader)
        BoardManFontChoice.installedFamilies.forEach { fontControl.addItem(withTitle: $0) }
        fontControl.selectItem(withTitle: fontChoice.rawValue)
        fontControl.font = NSFont.systemFont(ofSize: 11)
        fontControl.target = self
        fontControl.action = #selector(fontChoiceChanged(_:))
        fontControl.toolTip = "Macにインストール済みのフォントを選択できます。日本語グリフはmacOSのフォールバックで補完します。"
        contentView.addSubview(fontControl)
        fontChoicePopup = fontControl

        let itemTextLabel = NSTextField(labelWithString: boardManText("Text size"))
        itemTextLabel.font = NSFont.systemFont(ofSize: 11)
        itemTextLabel.textColor = .labelColor
        contentView.addSubview(itemTextLabel)
        itemTextScaleLabel = itemTextLabel

        let itemTextScaleValue = BoardManPanel.clampedItemTextScale(
            AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.boardManItemTextScale)
        )
        let itemTextField = NSTextField(frame: .zero)
        itemTextField.cell = BoardManCenteredTextFieldCell(textCell: "\(itemTextScaleValue)")
        itemTextField.alignment = .right
        itemTextField.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        itemTextField.textColor = .labelColor
        itemTextField.integerValue = itemTextScaleValue
        itemTextField.isEditable = true
        itemTextField.isSelectable = true
        itemTextField.isEnabled = true
        itemTextField.target = self
        itemTextField.action = #selector(itemTextScaleFieldChanged(_:))
        itemTextField.delegate = self
        let itemTextFormatter = NumberFormatter()
        itemTextFormatter.numberStyle = .none
        itemTextFormatter.minimum = 80
        itemTextFormatter.maximum = 140
        itemTextFormatter.allowsFloats = false
        itemTextField.formatter = itemTextFormatter
        itemTextField.identifier = NSUserInterfaceItemIdentifier("BoardManItemTextScaleField")
        configureSettingsInputField(itemTextField)
        contentView.addSubview(itemTextField)
        itemTextScaleField = itemTextField

        let itemTextDecrease = makeAdjustmentButton(
            title: "−",
            action: #selector(adjustItemTextScale(_:)),
            identifier: "BoardManItemTextScaleDecreaseButton",
            delta: -1
        )
        contentView.addSubview(itemTextDecrease)
        itemTextScaleDecreaseButton = itemTextDecrease

        let itemTextIncrease = makeAdjustmentButton(
            title: "+",
            action: #selector(adjustItemTextScale(_:)),
            identifier: "BoardManItemTextScaleIncreaseButton",
            delta: 1
        )
        contentView.addSubview(itemTextIncrease)
        itemTextScaleIncreaseButton = itemTextIncrease

        let lighten = NSButton(checkboxWithTitle: boardManText("Lighten"), target: self, action: #selector(themeLightenChanged(_:)))
        lighten.state = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.boardManThemeLighten) ? .on : .off
        lighten.font = NSFont.systemFont(ofSize: 11)
        lighten.toolTip = "Softens Board-Man theme tint, accent, surface, and glass intensity."
        if #available(macOS 10.14, *) {
            lighten.contentTintColor = .labelColor
        }
        contentView.addSubview(lighten)
        themeLightenButton = lighten

        let accentLabel = NSTextField(labelWithString: boardManText("Accent"))
        accentLabel.font = NSFont.systemFont(ofSize: 11)
        accentLabel.textColor = .labelColor
        contentView.addSubview(accentLabel)
        customAccentLabel = accentLabel

        let accentWell = NSColorWell(frame: .zero)
        accentWell.color = BoardManPanel.customColor(
            forKey: Constants.UserDefaults.boardManCustomAccentColor,
            fallback: selectedThemePreset.accentColor
        )
        accentWell.target = self
        accentWell.action = #selector(customColorChanged(_:))
        accentWell.tag = 0
        contentView.addSubview(accentWell)
        customAccentColorWell = accentWell

        let accentOpacity = NSSlider(value: AppEnvironment.current.defaults.double(forKey: Constants.UserDefaults.boardManCustomAccentOpacity),
                                     minValue: 0.05, maxValue: 1.0, target: self, action: #selector(customOpacityChanged(_:)))
        accentOpacity.tag = 0
        accentOpacity.toolTip = boardManText("Opacity")
        contentView.addSubview(accentOpacity)
        customAccentOpacitySlider = accentOpacity

        let panelLabel = NSTextField(labelWithString: boardManText("Panel"))
        panelLabel.font = NSFont.systemFont(ofSize: 11)
        panelLabel.textColor = .labelColor
        contentView.addSubview(panelLabel)
        customPanelLabel = panelLabel

        let panelWell = NSColorWell(frame: .zero)
        panelWell.color = BoardManPanel.customColor(
            forKey: Constants.UserDefaults.boardManCustomPanelColor,
            fallback: selectedThemePreset.tintColor
        )
        panelWell.target = self
        panelWell.action = #selector(customColorChanged(_:))
        panelWell.tag = 1
        contentView.addSubview(panelWell)
        customPanelColorWell = panelWell

        let panelOpacity = NSSlider(value: AppEnvironment.current.defaults.double(forKey: Constants.UserDefaults.boardManCustomPanelOpacity),
                                    minValue: 0.0, maxValue: 1.0, target: self, action: #selector(customOpacityChanged(_:)))
        panelOpacity.tag = 1
        panelOpacity.toolTip = boardManText("Opacity")
        contentView.addSubview(panelOpacity)
        customPanelOpacitySlider = panelOpacity

        let usedColorLabel = NSTextField(labelWithString: boardManText("Used color"))
        usedColorLabel.font = NSFont.systemFont(ofSize: 11)
        usedColorLabel.textColor = .labelColor
        contentView.addSubview(usedColorLabel)
        customUsedColorLabel = usedColorLabel

        let usedColorWell = NSColorWell(frame: .zero)
        usedColorWell.color = BoardManPanel.customColor(
            forKey: Constants.UserDefaults.boardManCustomUsedColor,
            fallback: .systemGray
        )
        usedColorWell.target = self
        usedColorWell.action = #selector(customColorChanged(_:))
        usedColorWell.tag = 2
        contentView.addSubview(usedColorWell)
        customUsedColorWell = usedColorWell

        let usedOpacity = NSSlider(value: AppEnvironment.current.defaults.double(forKey: Constants.UserDefaults.boardManCustomUsedOpacity),
                                   minValue: 0.0, maxValue: 1.0, target: self, action: #selector(customOpacityChanged(_:)))
        usedOpacity.tag = 2
        usedOpacity.toolTip = boardManText("Opacity")
        contentView.addSubview(usedOpacity)
        customUsedOpacitySlider = usedOpacity

        let resetColors = NSButton(title: boardManText("Reset colors"), target: self, action: #selector(resetCustomColors(_:)))
        resetColors.font = NSFont.systemFont(ofSize: 11)
        resetColors.bezelStyle = .rounded
        contentView.addSubview(resetColors)
        resetCustomColorsButton = resetColors

        let textPreviewLabel = NSTextField(labelWithString: boardManText("Text preview"))
        textPreviewLabel.font = NSFont.systemFont(ofSize: 11)
        contentView.addSubview(textPreviewLabel)
        textPreviewScaleLabel = textPreviewLabel

        let textPreviewSlider = NSSlider(
            value: Double(BoardManPanel.clampedPreviewScale(AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.boardManTextPreviewScale))),
            minValue: 50,
            maxValue: 200,
            target: self,
            action: #selector(previewScaleChanged(_:))
        )
        textPreviewSlider.tag = 0
        textPreviewSlider.numberOfTickMarks = 7
        textPreviewSlider.identifier = NSUserInterfaceItemIdentifier("BoardManTextPreviewScaleSlider")
        contentView.addSubview(textPreviewSlider)
        textPreviewScaleSlider = textPreviewSlider

        let textPreviewValue = NSTextField(labelWithString: "\(Int(textPreviewSlider.doubleValue))%")
        textPreviewValue.alignment = .right
        textPreviewValue.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        contentView.addSubview(textPreviewValue)
        textPreviewScaleValueLabel = textPreviewValue

        let imagePreviewLabel = NSTextField(labelWithString: boardManText("Image preview"))
        imagePreviewLabel.font = NSFont.systemFont(ofSize: 11)
        contentView.addSubview(imagePreviewLabel)
        imagePreviewScaleLabel = imagePreviewLabel

        let imagePreviewSlider = NSSlider(
            value: Double(BoardManPanel.clampedPreviewScale(AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.boardManImagePreviewScale))),
            minValue: 50,
            maxValue: 200,
            target: self,
            action: #selector(previewScaleChanged(_:))
        )
        imagePreviewSlider.tag = 1
        imagePreviewSlider.numberOfTickMarks = 7
        imagePreviewSlider.identifier = NSUserInterfaceItemIdentifier("BoardManImagePreviewScaleSlider")
        contentView.addSubview(imagePreviewSlider)
        imagePreviewScaleSlider = imagePreviewSlider

        let imagePreviewValue = NSTextField(labelWithString: "\(Int(imagePreviewSlider.doubleValue))%")
        imagePreviewValue.alignment = .right
        imagePreviewValue.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        contentView.addSubview(imagePreviewValue)
        imagePreviewScaleValueLabel = imagePreviewValue

        let previewScaleNote = NSTextField(labelWithString: boardManText("Pro only: custom colors and preview scale. Free preview stays at 100%."))
        previewScaleNote.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        previewScaleNote.textColor = .tertiaryLabelColor
        previewScaleNote.lineBreakMode = .byWordWrapping
        previewScaleNote.maximumNumberOfLines = 2
        contentView.addSubview(previewScaleNote)
        previewScaleProNoteLabel = previewScaleNote

        let historyTitle = BoardManPanel.makeSectionLabel("History")
        contentView.addSubview(historyTitle)
        historySectionLabel = historyTitle

        let dedupe = NSButton(checkboxWithTitle: boardManText("Dedupe"), target: self, action: #selector(dedupeChanged(_:)))
        dedupe.state = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.copySameHistory) ? .off : .on
        dedupe.font = NSFont.systemFont(ofSize: 11)
        if #available(macOS 10.14, *) {
            dedupe.contentTintColor = .labelColor
        }
        contentView.addSubview(dedupe)
        dedupeButton = dedupe

        let overwrite = NSButton(checkboxWithTitle: boardManText("Overwrite same"), target: self, action: #selector(overwriteSameHistoryChanged(_:)))
        overwrite.state = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.overwriteSameHistory) ? .on : .off
        overwrite.font = NSFont.systemFont(ofSize: 11)
        overwrite.toolTip = "Uses the same stored history item when duplicate content is allowed."
        if #available(macOS 10.14, *) {
            overwrite.contentTintColor = .labelColor
        }
        contentView.addSubview(overwrite)
        overwriteSameHistoryButton = overwrite

        let reuseTop = NSButton(checkboxWithTitle: boardManText("Reuse top"), target: self, action: #selector(reuseTopChanged(_:)))
        reuseTop.state = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.reorderClipsAfterPasting) ? .on : .off
        reuseTop.font = NSFont.systemFont(ofSize: 11)
        if #available(macOS 10.14, *) {
            reuseTop.contentTintColor = .labelColor
        }
        contentView.addSubview(reuseTop)
        reuseTopButton = reuseTop

        let clear = NSButton(title: boardManText("Clear"), target: self, action: #selector(clearHistoryRequested(_:)))
        clear.font = NSFont.systemFont(ofSize: 11)
        clear.bezelStyle = .rounded
        contentView.addSubview(clear)
        clearHistoryButton = clear

        let skipPinned = NSButton(checkboxWithTitle: boardManText("Skip pinned items with arrow keys"), target: self, action: #selector(skipPinnedNavigationChanged(_:)))
        skipPinned.state = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.boardManSkipPinnedInKeyboardNavigation) ? .on : .off
        skipPinned.font = NSFont.systemFont(ofSize: 11)
        skipPinned.toolTip = "When enabled, Up/Down starts from and moves only through unpinned items."
        contentView.addSubview(skipPinned)
        skipPinnedNavigationButton = skipPinned

        let longPressLabel = NSTextField(labelWithString: boardManText("Long press"))
        longPressLabel.font = NSFont.systemFont(ofSize: 11)
        longPressLabel.textColor = .labelColor
        contentView.addSubview(longPressLabel)
        longPressActionLabel = longPressLabel

        let longPressPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        BoardManLongPressAction.allCases.forEach { action in
            longPressPopup.addItem(withTitle: action.title)
            longPressPopup.lastItem?.representedObject = action.rawValue
        }
        let storedLongPressAction = BoardManLongPressAction.allowed(
            AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManLongPressAction)
        )
        if let item = longPressPopup.itemArray.first(where: { ($0.representedObject as? String) == storedLongPressAction.rawValue }) {
            longPressPopup.select(item)
        }
        longPressPopup.font = NSFont.systemFont(ofSize: 11)
        longPressPopup.target = self
        longPressPopup.action = #selector(longPressActionChanged(_:))
        contentView.addSubview(longPressPopup)
        longPressActionPopup = longPressPopup

        let durationLabel = NSTextField(labelWithString: boardManText("Pin duration"))
        durationLabel.font = NSFont.systemFont(ofSize: 11)
        durationLabel.textColor = .labelColor
        contentView.addSubview(durationLabel)
        timedPinDurationLabel = durationLabel

        let selectedTimedPinPreset = BoardManTimedPinPresetStore.selectedPreset()
        let presetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        BoardManTimedPinPresetStore.presets().forEach { preset in
            presetPopup.addItem(withTitle: preset.title)
            presetPopup.lastItem?.representedObject = preset.id
        }
        if let item = presetPopup.itemArray.first(where: {
            ($0.representedObject as? String) == selectedTimedPinPreset.id
        }) {
            presetPopup.select(item)
        }
        presetPopup.font = NSFont.systemFont(ofSize: 11)
        presetPopup.target = self
        presetPopup.action = #selector(timedPinPresetChanged(_:))
        presetPopup.identifier = NSUserInterfaceItemIdentifier("BoardManTimedPinPresetPopup")
        contentView.addSubview(presetPopup)
        timedPinPresetPopup = presetPopup

        let addDuration = NSButton(title: "+", target: self, action: #selector(addTimedPinPreset(_:)))
        addDuration.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        addDuration.bezelStyle = .rounded
        addDuration.toolTip = boardManText("Add duration")
        addDuration.identifier = NSUserInterfaceItemIdentifier("BoardManTimedPinPresetAddButton")
        contentView.addSubview(addDuration)
        timedPinPresetAddButton = addDuration

        let removeDuration = NSButton(title: "−", target: self, action: #selector(removeTimedPinPreset(_:)))
        removeDuration.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        removeDuration.bezelStyle = .rounded
        removeDuration.toolTip = boardManText("Remove duration")
        removeDuration.identifier = NSUserInterfaceItemIdentifier("BoardManTimedPinPresetRemoveButton")
        contentView.addSubview(removeDuration)
        timedPinPresetRemoveButton = removeDuration

        let durationStepper = NSStepper(frame: .zero)
        durationStepper.minValue = 1
        durationStepper.maxValue = 999_999
        durationStepper.increment = 1
        durationStepper.integerValue = selectedTimedPinPreset.value
        durationStepper.target = self
        durationStepper.action = #selector(timedPinDurationChanged(_:))
        durationStepper.identifier = NSUserInterfaceItemIdentifier("BoardManTimedPinDurationStepper")
        contentView.addSubview(durationStepper)
        timedPinDurationStepper = durationStepper

        let durationValue = NSTextField(frame: .zero)
        durationValue.cell = BoardManCenteredTextFieldCell(textCell: "\(durationStepper.integerValue)")
        durationValue.alignment = .right
        durationValue.isEditable = true
        durationValue.isSelectable = true
        durationValue.isEnabled = true
        durationValue.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        durationValue.textColor = .labelColor
        durationValue.target = self
        durationValue.action = #selector(timedPinDurationFieldChanged(_:))
        durationValue.delegate = self
        let durationFormatter = NumberFormatter()
        durationFormatter.numberStyle = .none
        durationFormatter.minimum = 1
        durationFormatter.maximum = 999_999
        durationFormatter.allowsFloats = false
        durationValue.formatter = durationFormatter
        durationValue.identifier = NSUserInterfaceItemIdentifier("BoardManTimedPinDurationField")
        durationValue.toolTip = boardManText("Enter the timed Pin duration directly.")
        configureSettingsInputField(durationValue)
        contentView.addSubview(durationValue)
        timedPinDurationValueLabel = durationValue

        let durationDecrease = makeAdjustmentButton(
            title: "−",
            action: #selector(adjustTimedPinDuration(_:)),
            identifier: "BoardManTimedPinDurationDecreaseButton",
            delta: -1
        )
        contentView.addSubview(durationDecrease)
        timedPinDurationDecreaseButton = durationDecrease

        let durationIncrease = makeAdjustmentButton(
            title: "+",
            action: #selector(adjustTimedPinDuration(_:)),
            identifier: "BoardManTimedPinDurationIncreaseButton",
            delta: 1
        )
        contentView.addSubview(durationIncrease)
        timedPinDurationIncreaseButton = durationIncrease

        let durationUnit = NSPopUpButton(frame: .zero, pullsDown: false)
        BoardManTimedPinUnit.allCases.forEach { unit in
            durationUnit.addItem(withTitle: unit.title)
            durationUnit.lastItem?.representedObject = unit.rawValue
        }
        let storedDurationUnit = selectedTimedPinPreset.unit
        if let item = durationUnit.itemArray.first(where: { ($0.representedObject as? String) == storedDurationUnit.rawValue }) {
            durationUnit.select(item)
        }
        durationUnit.font = NSFont.systemFont(ofSize: 11)
        durationUnit.target = self
        durationUnit.action = #selector(timedPinDurationUnitChanged(_:))
        contentView.addSubview(durationUnit)
        timedPinDurationUnitPopup = durationUnit

        let exportCSV = NSButton(title: boardManText("Export History CSV"), target: self, action: #selector(exportHistoryCSV(_:)))
        exportCSV.font = NSFont.systemFont(ofSize: 11)
        exportCSV.bezelStyle = .rounded
        exportCSV.toolTip = "Save the currently stored clipboard history as CSV."
        contentView.addSubview(exportCSV)
        exportHistoryCSVButton = exportCSV

        let privacyTitle = BoardManPanel.makeSectionLabel("Privacy")
        contentView.addSubview(privacyTitle)
        privacySectionLabel = privacyTitle

        let hideMaskedPreview = NSButton(
            checkboxWithTitle: boardManText("Hide preview when content is hidden"),
            target: self,
            action: #selector(maskedContentVisibilityChanged(_:))
        )
        hideMaskedPreview.state = AppEnvironment.current.defaults.bool(
            forKey: Constants.UserDefaults.boardManHidePreviewForMaskedItems
        ) ? .on : .off
        hideMaskedPreview.font = NSFont.systemFont(ofSize: 11)
        hideMaskedPreview.tag = 0
        contentView.addSubview(hideMaskedPreview)
        hideMaskedPreviewButton = hideMaskedPreview

        let hideMaskedTitle = NSButton(
            checkboxWithTitle: boardManText("Hide title when content is hidden"),
            target: self,
            action: #selector(maskedContentVisibilityChanged(_:))
        )
        hideMaskedTitle.state = AppEnvironment.current.defaults.bool(
            forKey: Constants.UserDefaults.boardManHideTitleForMaskedItems
        ) ? .on : .off
        hideMaskedTitle.font = NSFont.systemFont(ofSize: 11)
        hideMaskedTitle.tag = 1
        contentView.addSubview(hideMaskedTitle)
        hideMaskedTitleButton = hideMaskedTitle

        let typesTitle = BoardManPanel.makeSectionLabel("Stored Types")
        contentView.addSubview(typesTitle)
        storedTypesSectionLabel = typesTitle

        let storedTypes = AppEnvironment.current.defaults.dictionary(forKey: Constants.UserDefaults.storeTypes) as? [String: NSNumber] ?? AppDelegate.storeTypesDictinary()
        storedTypeButtons = BoardManClipData.availableTypesString.map { typeName in
            let button = NSButton(checkboxWithTitle: typeName, target: self, action: #selector(storedTypeChanged(_:)))
            button.state = (storedTypes[typeName]?.boolValue ?? true) ? .on : .off
            button.font = NSFont.systemFont(ofSize: 11)
            button.identifier = NSUserInterfaceItemIdentifier(rawValue: typeName)
            if #available(macOS 10.14, *) {
                button.contentTintColor = .labelColor
            }
            contentView.addSubview(button)
            return button
        }

        let exclude = NSButton(title: boardManText("Manage Excluded Apps"), target: self, action: #selector(openExcludedAppsSettings(_:)))
        exclude.font = NSFont.systemFont(ofSize: 11)
        exclude.bezelStyle = .rounded
        exclude.toolTip = "Choose apps that Board-Man should ignore."
        contentView.addSubview(exclude)
        excludedAppsButton = exclude

        let excludedSummary = NSTextField(labelWithString: "")
        excludedSummary.font = NSFont.systemFont(ofSize: 11)
        excludedSummary.textColor = .secondaryLabelColor
        excludedSummary.lineBreakMode = .byTruncatingTail
        contentView.addSubview(excludedSummary)
        excludedAppsSummaryLabel = excludedSummary
        refreshExcludedAppsSummary()

        let filtersTitle = BoardManPanel.makeSectionLabel("Hide Rules")
        contentView.addSubview(filtersTitle)
        filterSectionLabel = filtersTitle

        let hideText = NSTextField(frame: .zero)
        hideText.cell = BoardManCenteredTextFieldCell(textCell: "")
        hideText.placeholderString = boardManText("word or phrase")
        hideText.font = NSFont.systemFont(ofSize: 11)
        hideText.target = self
        hideText.action = #selector(addHideRuleRequested(_:))
        configureSettingsInputField(hideText)
        contentView.addSubview(hideText)
        hideRuleTextField = hideText

        let hideMode = NSPopUpButton(frame: .zero, pullsDown: false)
        hideMode.addItems(withTitles: BoardManHideRuleMode.allCases.map { $0.title })
        hideMode.selectItem(withTitle: BoardManHideRuleMode.contains.title)
        hideMode.font = NSFont.systemFont(ofSize: 11)
        contentView.addSubview(hideMode)
        hideRuleModePopup = hideMode

        let addRule = NSButton(title: boardManText("Add"), target: self, action: #selector(addHideRuleRequested(_:)))
        addRule.font = NSFont.systemFont(ofSize: 11)
        addRule.bezelStyle = .rounded
        contentView.addSubview(addRule)
        addHideRuleButton = addRule

        let removeRule = NSButton(title: boardManText("Remove Last"), target: self, action: #selector(removeLastHideRuleRequested(_:)))
        removeRule.font = NSFont.systemFont(ofSize: 11)
        removeRule.bezelStyle = .rounded
        contentView.addSubview(removeRule)
        removeLastHideRuleButton = removeRule

        let clearRules = NSButton(title: boardManText("Clear"), target: self, action: #selector(clearHideRulesRequested(_:)))
        clearRules.font = NSFont.systemFont(ofSize: 11)
        clearRules.bezelStyle = .rounded
        contentView.addSubview(clearRules)
        clearHideRulesButton = clearRules

        let ruleSummary = NSTextField(labelWithString: "")
        ruleSummary.font = NSFont.systemFont(ofSize: 11)
        ruleSummary.textColor = .labelColor
        ruleSummary.lineBreakMode = .byTruncatingTail
        contentView.addSubview(ruleSummary)
        hideRulesSummaryLabel = ruleSummary

        let ruleExamples = NSTextField(labelWithString: "")
        ruleExamples.font = NSFont.systemFont(ofSize: 11)
        ruleExamples.textColor = .secondaryLabelColor
        ruleExamples.lineBreakMode = .byTruncatingTail
        contentView.addSubview(ruleExamples)
        hideRulesExamplesLabel = ruleExamples

        let ruleNote = NSTextField(labelWithString: boardManText("Hidden only in Board-Man, data is not deleted."))
        ruleNote.font = NSFont.systemFont(ofSize: 11)
        ruleNote.textColor = .secondaryLabelColor
        ruleNote.lineBreakMode = .byTruncatingTail
        contentView.addSubview(ruleNote)
        hideRulesNoteLabel = ruleNote
        refreshHideRulesSummary()

        let updatesView = updatesPreferenceViewController.view
        updatesView.isHidden = true
        contentView.addSubview(updatesView)
        updatesPreferenceView = updatesView

        let licenseTitle = BoardManPanel.makeSectionLabel("License")
        contentView.addSubview(licenseTitle)
        licenseSectionLabel = licenseTitle

        let planLabel = NSTextField(labelWithString: "")
        planLabel.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        planLabel.textColor = .labelColor
        planLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(planLabel)
        licensePlanLabel = planLabel

        let stateLabel = NSTextField(labelWithString: "")
        stateLabel.font = NSFont.systemFont(ofSize: 11)
        stateLabel.textColor = .secondaryLabelColor
        stateLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(stateLabel)
        licenseStateLabel = stateLabel

        let limitsLabel = NSTextField(labelWithString: "")
        limitsLabel.font = NSFont.systemFont(ofSize: 11)
        limitsLabel.textColor = .secondaryLabelColor
        limitsLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(limitsLabel)
        licenseLimitsLabel = limitsLabel

        let licenseKey = NSTextField(frame: .zero)
        licenseKey.cell = BoardManCenteredTextFieldCell(textCell: "")
        licenseKey.placeholderString = boardManText("Secure local license")
        licenseKey.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        licenseKey.isEnabled = false
        licenseKey.toolTip = "Verified licenses are stored securely in Keychain."
        contentView.addSubview(licenseKey)
        licenseKeyField = licenseKey

        let activate = NSButton(title: boardManText("Activate"), target: self, action: #selector(activateLicenseRequested(_:)))
        activate.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        activate.bezelStyle = .rounded
        activate.isEnabled = false
        activate.toolTip = "Activation is not connected yet."
        contentView.addSubview(activate)
        licenseActivateButton = activate

        let activationStatus = NSTextField(labelWithString: boardManText("Online activation is not connected yet."))
        activationStatus.font = NSFont.systemFont(ofSize: 11)
        activationStatus.textColor = .secondaryLabelColor
        activationStatus.lineBreakMode = .byWordWrapping
        contentView.addSubview(activationStatus)
        licenseActivationStatusLabel = activationStatus

        let upgrade = NSButton(title: boardManText("Upgrade to Pro"), target: self, action: #selector(openLicensePurchasePage(_:)))
        upgrade.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        upgrade.bezelStyle = .rounded
        upgrade.toolTip = "Opens uniplanck.com for the future purchase flow."
        contentView.addSubview(upgrade)
        licenseUpgradeButton = upgrade

        let proControl = NSPopUpButton(frame: .zero, pullsDown: false)
        proControl.addItems(withTitles: ["Encrypted Sync", "Encrypted Backup"])
        proControl.font = NSFont.systemFont(ofSize: 11)
        proControl.toolTip = "Optional connected services require a Pro entitlement."
        let lockedProControl = BoardManProLockedControlView(
            title: boardManText("Connected services"),
            explanation: boardManText("Pro adds optional encrypted sync and backup services."),
            feature: .futureSync,
            control: proControl,
            upgradeTarget: self,
            upgradeAction: #selector(openLicensePurchasePage(_:))
        )
        contentView.addSubview(lockedProControl)
        licenseProLockedControlView = lockedProControl

        let licenseNote = NSTextField(labelWithString: boardManText("Verified licenses are stored in Keychain and bound to this Mac. Online purchase activation remains unavailable."))
        licenseNote.font = NSFont.systemFont(ofSize: 11)
        licenseNote.textColor = .secondaryLabelColor
        licenseNote.lineBreakMode = .byWordWrapping
        contentView.addSubview(licenseNote)
        licenseMockNoteLabel = licenseNote

        let examples = NSTextField(labelWithString: boardManText("UI states: Free / Trial / Pro Active / Expired / Invalid / Offline Grace / Locked"))
        examples.font = NSFont.systemFont(ofSize: 10)
        examples.textColor = .tertiaryLabelColor
        examples.lineBreakMode = .byTruncatingTail
        contentView.addSubview(examples)
        licenseStateExamplesLabel = examples
        refreshLicenseSummary()

        let labsTitle = BoardManPanel.makeSectionLabel("Labs")
        contentView.addSubview(labsTitle)
        labsSectionLabel = labsTitle

        let labsNote = NSTextField(labelWithString: boardManText("Glass options are available here."))
        labsNote.font = NSFont.systemFont(ofSize: 11)
        labsNote.textColor = .secondaryLabelColor
        contentView.addSubview(labsNote)
        labsNoteLabel = labsNote

        let heightTitle = NSTextField(labelWithString: boardManText("Height"))
        heightTitle.font = NSFont.systemFont(ofSize: 11)
        heightTitle.textColor = .labelColor
        contentView.addSubview(heightTitle)
        heightControlLabel = heightTitle

        let stepper = NSStepper(frame: .zero)
        stepper.minValue = 520
        stepper.maxValue = 1200
        stepper.increment = 40
        stepper.integerValue = BoardManPanel.clampedPanelHeight(AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.boardManPanelHeight))
        stepper.target = self
        stepper.action = #selector(panelHeightChanged(_:))
        contentView.addSubview(stepper)
        heightStepper = stepper

        let heightText = NSTextField(frame: .zero)
        heightText.cell = BoardManCenteredTextFieldCell(textCell: "\(stepper.integerValue)")
        heightText.alignment = .right
        heightText.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        heightText.textColor = .labelColor
        heightText.integerValue = stepper.integerValue
        heightText.isEditable = true
        heightText.isSelectable = true
        heightText.target = self
        heightText.action = #selector(panelHeightFieldChanged(_:))
        heightText.delegate = self
        let heightFormatter = NumberFormatter()
        heightFormatter.numberStyle = .none
        heightFormatter.minimum = 520
        heightFormatter.maximum = 1200
        heightFormatter.allowsFloats = false
        heightText.formatter = heightFormatter
        heightText.identifier = NSUserInterfaceItemIdentifier("BoardManPanelHeightField")
        configureSettingsInputField(heightText)
        contentView.addSubview(heightText)
        heightLabel = heightText

        let heightDecrease = makeAdjustmentButton(
            title: "−",
            action: #selector(adjustPanelHeight(_:)),
            identifier: "BoardManPanelHeightDecreaseButton",
            delta: -1
        )
        contentView.addSubview(heightDecrease)
        heightDecreaseButton = heightDecrease

        let heightIncrease = makeAdjustmentButton(
            title: "+",
            action: #selector(adjustPanelHeight(_:)),
            identifier: "BoardManPanelHeightIncreaseButton",
            delta: 1
        )
        contentView.addSubview(heightIncrease)
        heightIncreaseButton = heightIncrease

        // Scroll list: one native surface avoids stacked cards and unnecessary visual-effect layers.
        let scroll = NSScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.horizontalScrollElasticity = .none
        scroll.hasHorizontalScroller = false
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentView.autoresizesSubviews = true
        scroll.contentView.drawsBackground = false
        scroll.wantsLayer = true
        scroll.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor
        scroll.layer?.cornerRadius = LayoutMetrics.cardCornerRadius
        scroll.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.42).cgColor
        scroll.layer?.borderWidth = 1

        let table = BoardManHistoryTableView(frame: .zero)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: "main"))
        column.title = "Items"
        column.width = 360
        column.minWidth = 120
        column.maxWidth = CGFloat.greatestFiniteMagnitude
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil  // no oversized header
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.rowHeight = LayoutMetrics.historyRowHeight
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.gridStyleMask = []
        table.usesAlternatingRowBackgroundColors = false
        table.selectionHighlightStyle = .none
        table.backgroundColor = .clear
        table.autoresizingMask = [.width, .height]
        table.autoresizesSubviews = true
        table.allowsEmptySelection = false
        table.allowsMultipleSelection = false
        table.refusesFirstResponder = false
        table.panelKeyOwner = self
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(handleTableSingleClick(_:))
        table.doubleAction = #selector(handleTableDoubleClick(_:))
        table.registerForDraggedTypes([BoardManPanel.snippetDragType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        table.verticalMotionCanBeginDrag = true
        table.draggingDestinationFeedbackStyle = .gap
        // Right-click on row shows safe actions menu (Paste + Pin + placeholders)
        let rightClick = NSClickGestureRecognizer(target: self, action: #selector(handleRightClick(_:)))
        rightClick.buttonMask = 0x2
        rightClick.numberOfClicksRequired = 1
        rightClick.delegate = self
        table.addGestureRecognizer(rightClick)
        let longPress = NSPressGestureRecognizer(target: self, action: #selector(handleItemLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        longPress.allowableMovement = 8
        longPress.delaysPrimaryMouseButtonEvents = true
        longPress.delegate = self
        table.addGestureRecognizer(longPress)
        itemLongPressGesture = longPress

        scroll.documentView = table
        contentView.addSubview(scroll)
        scrollView = scroll
        placeholderList = table

        let categoryLabel = NSTextField(labelWithString: boardManText("Category"))
        categoryLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        categoryLabel.textColor = .labelColor
        categoryLabel.isHidden = true
        contentView.addSubview(categoryLabel)
        snippetCategoryLabel = categoryLabel

        let categoryPopup = BoardManHoverPopUpButton(frame: .zero, pullsDown: false)
        categoryPopup.font = NSFont.systemFont(ofSize: 11)
        categoryPopup.target = self
        categoryPopup.action = #selector(snippetCategoryFilterChanged(_:))
        categoryPopup.identifier = NSUserInterfaceItemIdentifier("BoardManSnippetGroupPopup")
        categoryPopup.isHidden = true
        categoryPopup.toolTip = boardManText("Hover to open group list")
        contentView.addSubview(categoryPopup)
        snippetCategoryPopup = categoryPopup

        let addSnippet = NSButton(title: boardManText("Add"), target: self, action: #selector(addSnippetFromPanel(_:)))
        addSnippet.font = NSFont.systemFont(ofSize: 11)
        addSnippet.bezelStyle = .rounded
        addSnippet.isHidden = true
        addSnippet.toolTip = "Add a snippet."
        contentView.addSubview(addSnippet)
        snippetAddButton = addSnippet

        let editSnippet = NSButton(title: boardManText("Edit Mode"), target: self, action: #selector(editSelectedSnippetFromPanel(_:)))
        editSnippet.identifier = NSUserInterfaceItemIdentifier("BoardManSnippetEditButton")
        editSnippet.font = NSFont.systemFont(ofSize: 11)
        editSnippet.bezelStyle = .rounded
        editSnippet.isHidden = true
        editSnippet.toolTip = "Edit the selected snippet"
        contentView.addSubview(editSnippet)
        snippetEditButton = editSnippet

        let deleteSnippet = NSButton(title: boardManText("Delete"), target: self, action: #selector(deleteSelectedSnippetFromPanel(_:)))
        deleteSnippet.font = NSFont.systemFont(ofSize: 11)
        deleteSnippet.bezelStyle = .rounded
        deleteSnippet.isHidden = true
        deleteSnippet.toolTip = "Delete the selected snippet."
        contentView.addSubview(deleteSnippet)
        snippetDeleteButton = deleteSnippet

        let addCategory = NSButton(title: boardManText("Add Group"), target: self, action: #selector(addSnippetCategoryFromPanel(_:)))
        addCategory.font = NSFont.systemFont(ofSize: 11)
        addCategory.bezelStyle = .rounded
        addCategory.isHidden = true
        contentView.addSubview(addCategory)
        snippetCategoryAddButton = addCategory

        let renameCategory = NSButton(title: boardManText("Rename Group"), target: self, action: #selector(renameSnippetCategoryFromPanel(_:)))
        renameCategory.font = NSFont.systemFont(ofSize: 11)
        renameCategory.bezelStyle = .rounded
        renameCategory.isHidden = true
        contentView.addSubview(renameCategory)
        snippetCategoryRenameButton = renameCategory

        let deleteCategory = NSButton(title: boardManText("Delete Group"), target: self, action: #selector(deleteSnippetCategoryFromPanel(_:)))
        deleteCategory.font = NSFont.systemFont(ofSize: 11)
        deleteCategory.bezelStyle = .rounded
        deleteCategory.isHidden = true
        contentView.addSubview(deleteCategory)
        snippetCategoryDeleteButton = deleteCategory

        let interactionHint = NSTextField(labelWithString: boardManText("Hover a snippet, then click the preview to edit • ⌘C Copy • ⌘P Pin"))
        interactionHint.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        interactionHint.textColor = .secondaryLabelColor
        interactionHint.lineBreakMode = .byTruncatingTail
        interactionHint.maximumNumberOfLines = 1
        interactionHint.isHidden = true
        contentView.addSubview(interactionHint)
        snippetInteractionHintLabel = interactionHint

        let reorderMode = NSButton(title: boardManText("Reorder"), target: self, action: #selector(toggleSnippetReorderMode(_:)))
        reorderMode.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        reorderMode.bezelStyle = .rounded
        reorderMode.setButtonType(.toggle)
        reorderMode.toolTip = boardManText("Select a group to reorder")
        reorderMode.isHidden = true
        contentView.addSubview(reorderMode)
        snippetReorderModeButton = reorderMode

        let editorView = NSView(frame: .zero)
        editorView.wantsLayer = true
        editorView.layer?.cornerRadius = LayoutMetrics.cardCornerRadius
        editorView.layer?.borderWidth = 1
        editorView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        editorView.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.45).cgColor
        editorView.isHidden = true
        editorView.toolTip = boardManText("Click the preview to edit")
        let editorClick = NSClickGestureRecognizer(target: self, action: #selector(snippetEditorClicked(_:)))
        editorClick.buttonMask = 0x1
        editorClick.numberOfClicksRequired = 1
        editorClick.delaysPrimaryMouseButtonEvents = false
        editorClick.delegate = self
        editorView.addGestureRecognizer(editorClick)
        snippetEditorClickGesture = editorClick
        contentView.addSubview(editorView)
        snippetEditorView = editorView

        let editorTitleLabel = NSTextField(labelWithString: boardManText("Title"))
        editorTitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        editorTitleLabel.textColor = .labelColor
        editorView.addSubview(editorTitleLabel)
        snippetEditorTitleLabel = editorTitleLabel

        let editorTitle = NSTextField(frame: .zero)
        editorTitle.cell = BoardManCenteredTextFieldCell(textCell: "")
        editorTitle.font = NSFont.systemFont(ofSize: 12)
        editorTitle.textColor = .textColor
        editorTitle.backgroundColor = .textBackgroundColor
        editorTitle.drawsBackground = true
        editorTitle.placeholderString = boardManText("Untitled snippet")
        editorTitle.identifier = NSUserInterfaceItemIdentifier("BoardManSnippetEditorTitleField")
        editorTitle.target = self
        editorTitle.action = #selector(snippetTitleFieldChanged(_:))
        editorTitle.delegate = self
        editorView.addSubview(editorTitle)
        snippetEditorTitleField = editorTitle

        let editorContentLabel = NSTextField(labelWithString: boardManText("Content"))
        editorContentLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        editorContentLabel.textColor = .labelColor
        editorView.addSubview(editorContentLabel)
        snippetEditorContentLabel = editorContentLabel

        let editorScroll = NSScrollView(frame: .zero)
        editorScroll.identifier = NSUserInterfaceItemIdentifier("BoardManSnippetEditorScrollView")
        editorScroll.hasVerticalScroller = true
        editorScroll.borderType = .bezelBorder
        editorScroll.autohidesScrollers = true
        editorScroll.drawsBackground = true
        editorScroll.backgroundColor = .textBackgroundColor
        let editorText = NSTextView(frame: .zero)
        editorText.identifier = NSUserInterfaceItemIdentifier("BoardManSnippetEditorTextView")
        editorText.font = NSFont.systemFont(ofSize: 12)
        editorText.textColor = .textColor
        editorText.backgroundColor = .textBackgroundColor
        editorText.insertionPointColor = .textColor
        editorText.drawsBackground = true
        editorText.textContainerInset = NSSize(width: 8, height: 8)
        editorText.isRichText = false
        editorText.isAutomaticQuoteSubstitutionEnabled = false
        editorText.enabledTextCheckingTypes = 0
        editorScroll.documentView = editorText
        editorView.addSubview(editorScroll)
        snippetEditorScrollView = editorScroll
        snippetEditorTextView = editorText

        let folderEnable = NSButton(checkboxWithTitle: boardManText("Group Enabled"), target: self, action: #selector(snippetFolderEnableChanged(_:)))
        folderEnable.font = NSFont.systemFont(ofSize: 11)
        editorView.addSubview(folderEnable)
        snippetFolderEnableButton = folderEnable

        let snippetEnable = NSButton(checkboxWithTitle: boardManText("Snippet Enabled"), target: self, action: #selector(snippetEnableChanged(_:)))
        snippetEnable.font = NSFont.systemFont(ofSize: 11)
        editorView.addSubview(snippetEnable)
        snippetEnableButton = snippetEnable

        let saveSnippet = NSButton(title: boardManText("Save Changes"), target: self, action: #selector(saveSelectedSnippetFromPanel(_:)))
        saveSnippet.identifier = NSUserInterfaceItemIdentifier("BoardManSnippetSaveButton")
        saveSnippet.font = NSFont.systemFont(ofSize: 11)
        saveSnippet.bezelStyle = .rounded
        editorView.addSubview(saveSnippet)
        snippetSaveButton = saveSnippet

        let cancelEdit = NSButton(title: boardManText("Cancel"), target: self, action: #selector(cancelSnippetEditing(_:)))
        cancelEdit.identifier = NSUserInterfaceItemIdentifier("BoardManSnippetCancelButton")
        cancelEdit.font = NSFont.systemFont(ofSize: 11)
        cancelEdit.bezelStyle = .rounded
        editorView.addSubview(cancelEdit)
        snippetCancelEditButton = cancelEdit

        let editorStatus = NSTextField(labelWithString: boardManText("Select a snippet to preview"))
        editorStatus.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        editorStatus.textColor = .secondaryLabelColor
        editorStatus.alignment = .center
        editorStatus.lineBreakMode = .byWordWrapping
        editorStatus.maximumNumberOfLines = 2
        editorStatus.cell?.wraps = true
        editorStatus.wantsLayer = true
        editorStatus.layer?.cornerRadius = 7
        editorStatus.layer?.masksToBounds = true
        editorStatus.identifier = NSUserInterfaceItemIdentifier("BoardManSnippetEditorStatusLabel")
        editorView.addSubview(editorStatus)
        snippetEditorStatusLabel = editorStatus

        let bubbleLabel = NSTextField(labelWithString: "")
        bubbleLabel.font = NSFont.systemFont(ofSize: 12)
        bubbleLabel.textColor = .labelColor
        bubbleLabel.backgroundColor = .clear
        bubbleLabel.drawsBackground = false
        bubbleLabel.maximumNumberOfLines = 8
        if let textFieldCell = bubbleLabel.cell {
            textFieldCell.wraps = true
            textFieldCell.lineBreakMode = .byWordWrapping
        }
        previewBubbleLabel = bubbleLabel

        let bubbleImage = NSImageView(frame: .zero)
        bubbleImage.imageScaling = .scaleProportionallyUpOrDown
        bubbleImage.imageAlignment = .alignCenter
        bubbleImage.isHidden = true
        previewBubbleImageView = bubbleImage

        // Move only the right settings pane into its scroll document. The sidebar remains fixed.
        installSettingsScrollHierarchy()

        // Load initial data
        applyControlMetrics()
        layoutPanelSubviews()
        table.reloadData()
        synchronizeListGeometry()
    }

    private var settingsContentViews: [NSView] {
        let controls: [NSView?] = [
            settingsPageTitleLabel, settingsPageDescriptionLabel,
            generalSectionLabel, launchOnLoginButton, inputPasteCommandButton, languageLabel, languagePopup,
            maxHistorySizeLabel, maxHistorySizeStepper, maxHistorySizeValueLabel,
            maxHistoryDecreaseButton, maxHistoryIncreaseButton,
            statusItemLabel, statusItemPopup, shortcutSectionLabel, shortcutStatusLabel,
            snippetSettingsSectionLabel, snippetSummaryLabel, snippetFoldersLabel, snippetGroupProNoteLabel,
            snippetGroupOrderPopup, snippetGroupMoveUpButton, snippetGroupMoveDownButton,
            snippetShortcutsLabel, snippetShortcutScrollView, manageSnippetsButton,
            appearancePreviewCard, appearanceLayoutCard, appearanceTimestampCard, appearanceUsageCard, appearanceThemeCard,
            appearanceAdvancedCard, appearancePreviewView, appearanceAdvancedButton,
            viewSectionLabel, rowNumbersButton, timestampLabel, timestampPopup, timestampPositionLabel, timestampPositionPopup,
            relativeNumberLabel, relativeNumberPopup, relativeUnitLabel, relativeUnitPopup,
            relativeSuffixLabel, relativeSuffixPopup, relativeNowLabel, relativeNowPopup,
            timestampInteractionLabel, timestampInteractionPopup,
            timestampShortcutEnabledButton, timestampShortcutLabel, timestampShortcutRecordView,
            timestampShortcutDelayLabel, timestampShortcutDelayField, timestampShortcutDelayStepper,
            timestampShortcutDelayDecreaseButton, timestampShortcutDelayIncreaseButton, timestampShortcutSecondsLabel,
            usageCountButton, usageStyleLabel, usageStylePopup, usedItemStyleLabel, usedItemStylePopup,
            pinLabelStyleLabel, pinLabelStylePopup, showInlineImagesButton, inlineImagePositionLabel, inlineImagePositionPopup,
            themePresetLabel, themePresetPopup, appearanceModeLabel, appearanceModePopup,
            uiStyleLabel, uiStylePopup, fontChoiceLabel, fontChoicePopup,
            itemTextScaleLabel, itemTextScaleField, itemTextScaleDecreaseButton, itemTextScaleIncreaseButton, themeLightenButton,
            customAccentLabel, customAccentColorWell, customAccentOpacitySlider,
            customPanelLabel, customPanelColorWell, customPanelOpacitySlider,
            customUsedColorLabel, customUsedColorWell, customUsedOpacitySlider, resetCustomColorsButton,
            textPreviewScaleLabel, textPreviewScaleSlider, textPreviewScaleValueLabel,
            imagePreviewScaleLabel, imagePreviewScaleSlider, imagePreviewScaleValueLabel, previewScaleProNoteLabel,
            historySectionLabel, dedupeButton, overwriteSameHistoryButton, reuseTopButton, clearHistoryButton,
            skipPinnedNavigationButton, longPressActionLabel, longPressActionPopup,
            timedPinDurationLabel, timedPinPresetPopup, timedPinPresetAddButton, timedPinPresetRemoveButton,
            timedPinDurationStepper, timedPinDurationValueLabel,
            timedPinDurationDecreaseButton, timedPinDurationIncreaseButton,
            timedPinDurationUnitPopup, exportHistoryCSVButton,
            privacySectionLabel, hideMaskedPreviewButton, hideMaskedTitleButton,
            excludedAppsButton, excludedAppsSummaryLabel, storedTypesSectionLabel,
            filterSectionLabel, hideRuleTextField, hideRuleModePopup, addHideRuleButton,
            removeLastHideRuleButton, clearHideRulesButton, hideRulesSummaryLabel,
            hideRulesExamplesLabel, hideRulesNoteLabel,
            updatesPreferenceView,
            licenseSectionLabel, licensePlanLabel, licenseStateLabel, licenseLimitsLabel,
            licenseKeyField, licenseActivateButton, licenseActivationStatusLabel,
            licenseUpgradeButton, licenseProLockedControlView, licenseMockNoteLabel, licenseStateExamplesLabel,
            labsSectionLabel, labsNoteLabel,
            heightControlLabel, heightLabel, heightStepper, heightDecreaseButton, heightIncreaseButton,
            pauseRecordingButton
        ]
        return controls.compactMap { $0 }
            + globalShortcutRows.flatMap { $0.views }
            + storedTypeButtons
    }

    private func installSettingsScrollHierarchy() {
        guard let document = settingsDocumentView else { return }
        for view in settingsContentViews where view.superview !== document {
            view.removeFromSuperview()
            document.addSubview(view)
        }
    }

    private func configureSettingsInputField(_ field: NSTextField) {
        field.isEditable = true
        field.isSelectable = true
        field.isEnabled = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.focusRingType = .default
    }

    private func makeAdjustmentButton(title: String, action: Selector, identifier: String, delta: Int) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        button.tag = delta
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        return button
    }

    private func inferredFontWeight(_ font: NSFont) -> NSFont.Weight {
        let traits = font.fontDescriptor.symbolicTraits
        if traits.contains(.bold) { return .semibold }
        return .regular
    }

    private func applyTypography() {
        let choice = fontChoice
        func apply(to view: NSView) {
            if let textField = view as? NSTextField, let currentFont = textField.font {
                textField.font = choice.font(ofSize: currentFont.pointSize, weight: inferredFontWeight(currentFont))
            } else if let button = view as? NSButton, let currentFont = button.font {
                button.font = choice.font(ofSize: currentFont.pointSize, weight: inferredFontWeight(currentFont))
            } else if let popup = view as? NSPopUpButton, let currentFont = popup.font {
                popup.font = choice.font(ofSize: currentFont.pointSize, weight: inferredFontWeight(currentFont))
            } else if let textView = view as? NSTextView, let currentFont = textView.font {
                textView.font = choice.font(ofSize: currentFont.pointSize, weight: inferredFontWeight(currentFont))
            }
            view.subviews.forEach(apply)
        }
        if let contentView { apply(to: contentView) }
        if let bubbleContent = previewBubblePanel?.contentView { apply(to: bubbleContent) }
        placeholderList?.reloadData()
    }

    private func applyAppearanceMode() {
        appearance = appearanceMode.appearance
        previewBubblePanel?.appearance = appearanceMode.appearance
    }

    private func refreshAppearancePreview() {
        guard let preview = appearancePreviewView else { return }
        let defaults = AppEnvironment.current.defaults
        let showRows = defaults.object(forKey: Constants.UserDefaults.boardManShowRowNumbers) as? Bool ?? true
        let showCount = defaults.object(forKey: Constants.UserDefaults.boardManShowUsageCount) as? Bool ?? true
        let format = BoardManPanel.allowedTimestampFormat(defaults.string(forKey: Constants.UserDefaults.boardManTimestampFormat))
        let timestamp = BoardManPanel.timestampText(
            for: Int(Date().addingTimeInterval(-4_200).timeIntervalSince1970),
            format: format == "none" ? "relative" : format
        )
        let hasCustomPanelColor = defaults.string(forKey: Constants.UserDefaults.boardManCustomPanelColor) != nil
        let panelColor: NSColor
        if uiStyle == .simple {
            panelColor = NSColor.controlBackgroundColor
        } else if hasCustomPanelColor {
            panelColor = customPanelTintColor
        } else {
            panelColor = themePreset.surfaceTintColor(
                useLiquidGlass: isLiquidGlassEnabled,
                lighten: isThemeLightenEnabled
            )
        }
        let hasCustomUsedColor = defaults.string(forKey: Constants.UserDefaults.boardManCustomUsedColor) != nil
        let usedColor = hasCustomUsedColor ? customUsedTintColor : NSColor.systemGray
        let countStyle = BoardManPanel.allowedUsageCountStyle(
            defaults.string(forKey: Constants.UserDefaults.boardManUsageCountStyle)
        )
        preview.update(.init(
            accentColor: themeAccentColor,
            panelColor: panelColor,
            usedColor: usedColor,
            font: fontChoice.font(ofSize: 10.5 * itemTextScale, weight: .medium),
            showRows: showRows,
            showCount: showCount,
            timestampPosition: timestampPosition,
            timestampText: timestamp,
            compactCount: countStyle == "compact",
            simpleStyle: uiStyle == .simple,
            uiStyleRawValue: uiStyle.rawValue
        ))
    }

    private func applyLocalizedStrings() {
        func rebuildPopup(_ popup: NSPopUpButton?, entries: [(raw: String, title: String)], selectedRaw: String) {
            guard let popup else { return }
            popup.removeAllItems()
            entries.forEach { entry in
                popup.addItem(withTitle: entry.title)
                popup.lastItem?.representedObject = entry.raw
            }
            if let selected = popup.itemArray.first(where: { ($0.representedObject as? String) == selectedRaw }) {
                popup.select(selected)
            }
        }

        applyResponsiveTabPresentation(
            isCompact: (contentView?.bounds.width ?? LayoutMetrics.preferredWidth) < 720
        )
        searchField?.placeholderString = boardManText("Search clipboard history and snippets")
        for (button, category) in zip(settingsCategoryButtons, BoardManInlineSettingsCategory.allCases) {
            button.title = category.title
            button.toolTip = category.detail
            button.image = BoardManPanel.paddedSidebarSymbol(named: category.symbolName, title: category.title)
        }
        settingsPageTitleLabel?.stringValue = activeSettingsCategory.title
        settingsPageDescriptionLabel?.stringValue = activeSettingsCategory.detail
        generalSectionLabel?.stringValue = boardManText("General")
        shortcutSectionLabel?.stringValue = boardManText("Keyboard Shortcuts")
        viewSectionLabel?.stringValue = boardManText("Appearance")
        appearancePreviewCard?.updateText(
            title: boardManText("Preview"),
            detail: boardManText("See changes instantly before returning to History.")
        )
        appearanceLayoutCard?.updateText(
            title: boardManText("Layout"),
            detail: boardManText("Panel size, row structure, and visual density.")
        )
        appearanceTimestampCard?.updateText(
            title: boardManText("Timestamp"),
            detail: boardManText("Choose how time is formatted and placed.")
        )
        appearanceUsageCard?.updateText(
            title: boardManText("Usage"),
            detail: boardManText("Paste counts and used-item treatment.")
        )
        appearanceThemeCard?.updateText(
            title: boardManText("Theme & Colors"),
            detail: boardManText("Theme, mode, typography, and surface style.")
        )
        appearanceAdvancedCard?.updateText(
            title: boardManText("Advanced settings"),
            detail: boardManText("Relative time details, custom colors, and preview scale.")
        )
        appearanceAdvancedButton?.title = boardManText(
            appearanceAdvancedExpanded ? "Hide advanced settings" : "Show advanced settings"
        )
        historySectionLabel?.stringValue = boardManText("History")
        snippetSettingsSectionLabel?.stringValue = boardManText("Snippets")
        privacySectionLabel?.stringValue = boardManText("Privacy")
        hideMaskedPreviewButton?.title = boardManText("Hide preview when content is hidden")
        hideMaskedTitleButton?.title = boardManText("Hide title when content is hidden")
        languageLabel?.stringValue = boardManText("Language")
        launchOnLoginButton?.title = boardManText("Launch on Login")
        inputPasteCommandButton?.title = boardManText("Send Command+V")
        rowNumbersButton?.title = boardManText("Rows")
        timestampLabel?.stringValue = boardManText("Time")
        timestampPositionLabel?.stringValue = boardManText("Position")
        relativeNumberLabel?.stringValue = boardManText("Number")
        relativeUnitLabel?.stringValue = boardManText("Unit")
        relativeSuffixLabel?.stringValue = boardManText("Suffix")
        relativeNowLabel?.stringValue = boardManText("Under 1 minute")
        timestampInteractionLabel?.stringValue = boardManText("Time action")
        timestampShortcutEnabledButton?.title = boardManText("Enable shortcut for time action")
        timestampShortcutLabel?.stringValue = boardManText("Shortcut for time action")
        timestampShortcutDelayLabel?.stringValue = boardManText("Delay")
        timestampShortcutSecondsLabel?.stringValue = boardManText("Seconds")
        usageCountButton?.title = boardManText("Count")
        usageStyleLabel?.stringValue = boardManText("Style")
        usedItemStyleLabel?.stringValue = boardManText("Used")
        pinLabelStyleLabel?.stringValue = boardManText("Pin label")
        showInlineImagesButton?.title = boardManText("Images")
        inlineImagePositionLabel?.stringValue = boardManText("Image side")
        themePresetLabel?.stringValue = boardManText("Theme")
        appearanceModeLabel?.stringValue = boardManText("Mode")
        uiStyleLabel?.stringValue = boardManText("UI")
        fontChoiceLabel?.stringValue = boardManText("Font")
        itemTextScaleLabel?.stringValue = boardManText("Text size")
        themeLightenButton?.title = boardManText("Lighten")
        heightControlLabel?.stringValue = boardManText("Height")
        customAccentLabel?.stringValue = boardManText("Accent")
        customPanelLabel?.stringValue = boardManText("Panel")
        customUsedColorLabel?.stringValue = boardManText("Used color")
        customAccentOpacitySlider?.toolTip = boardManText("Opacity")
        customPanelOpacitySlider?.toolTip = boardManText("Opacity")
        customUsedOpacitySlider?.toolTip = boardManText("Opacity")
        resetCustomColorsButton?.title = boardManText("Reset colors")
        textPreviewScaleLabel?.stringValue = boardManText("Text preview")
        imagePreviewScaleLabel?.stringValue = boardManText("Image preview")
        previewScaleProNoteLabel?.stringValue = boardManText("Custom colors and preview scale are available locally.")
        snippetGroupProNoteLabel?.stringValue = boardManText("Group creation, ordering, and folder shortcuts are available locally.")
        manageSnippetsButton?.title = boardManText("Manage Snippets")
        snippetAddButton?.title = boardManText("Add")
        snippetEditButton?.title = boardManText("Edit")
        snippetDeleteButton?.title = boardManText("Delete")
        snippetSaveButton?.title = boardManText("Save Changes")
        snippetCancelEditButton?.title = boardManText("Cancel")
        snippetCategoryLabel?.stringValue = boardManText("Category")
        snippetCategoryAddButton?.title = boardManText("Add Group")
        snippetCategoryRenameButton?.title = boardManText("Rename Group")
        snippetCategoryDeleteButton?.title = boardManText("Delete Group")
        snippetEditorTitleLabel?.stringValue = boardManText("Title")
        snippetEditorContentLabel?.stringValue = boardManText("Content")
        snippetFolderEnableButton?.title = boardManText("Group Enabled")
        snippetEnableButton?.title = boardManText("Snippet Enabled")
        snippetEditorView?.toolTip = boardManText("Click the preview to edit")
        snippetInteractionHintLabel?.stringValue = boardManText("Hover a snippet, then click the preview to edit • ⌘C Copy • ⌘P Pin")
        snippetGroupMoveUpButton?.title = boardManText("Move Up")
        snippetGroupMoveDownButton?.title = boardManText("Move Down")
        dedupeButton?.title = boardManText("Dedupe")
        reuseTopButton?.title = boardManText("Reuse top")
        overwriteSameHistoryButton?.title = boardManText("Overwrite same")
        skipPinnedNavigationButton?.title = boardManText("Skip pinned items with arrow keys")
        longPressActionLabel?.stringValue = boardManText("Long press")
        timedPinDurationLabel?.stringValue = boardManText("Pin duration")
        timedPinPresetAddButton?.toolTip = boardManText("Add duration")
        timedPinPresetRemoveButton?.toolTip = boardManText("Remove duration")
        exportHistoryCSVButton?.title = boardManText("Export History CSV")
        clearHistoryButton?.title = boardManText("Clear")
        statusItemLabel?.stringValue = boardManText("Icon")
        storedTypesSectionLabel?.stringValue = boardManText("Stored Types")
        excludedAppsButton?.title = boardManText("Manage Excluded Apps")
        filterSectionLabel?.stringValue = boardManText("Hide Rules")
        addHideRuleButton?.title = boardManText("Add Rule")
        removeLastHideRuleButton?.title = boardManText("Remove Last")
        clearHideRulesButton?.title = boardManText("Clear")
        licenseUpgradeButton?.title = boardManText("Upgrade to Pro")
        licenseProLockedControlView?.updateLocalizedText(
            title: boardManText("Connected services"),
            explanation: boardManText("Pro adds optional encrypted sync and backup services."),
            upgradeTitle: boardManText("Upgrade")
        )
        globalShortcutRows.forEach { row in
            row.titleLabel.stringValue = row.kind.title
            row.detailLabel.stringValue = row.kind.detail
            row.clearButton.title = boardManText("Clear")
        }

        rebuildPopup(
            statusItemPopup,
            entries: ["Black", "White", "Hidden"].map { ($0, boardManText($0)) },
            selectedRaw: BoardManPanel.statusItemTitle(for: AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.showStatusItem))
        )
        let timestampRawValues = ["Relative", "24-hour", "24-hour + seconds", "12-hour", "12-hour + seconds", "Date + time"]
        rebuildPopup(
            timestampPopup,
            entries: timestampRawValues.map { ($0, boardManText($0)) },
            selectedRaw: BoardManPanel.timestampMenuTitle(for: AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManTimestampFormat))
        )
        rebuildPopup(
            timestampPositionPopup,
            entries: BoardManTimestampPosition.allCases.map { ($0.rawValue, boardManText($0.rawValue)) },
            selectedRaw: timestampPosition.rawValue
        )
        let relativeLanguage = BoardManLanguage.allowed(
            AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManLanguage)
        ).resolved
        rebuildPopup(
            relativeNumberPopup,
            entries: BoardManRelativeNumberStyle.allCases.map { ($0.rawValue, $0.title) },
            selectedRaw: BoardManRelativeNumberStyle.allowed(
                AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManRelativeNumberStyle)
            ).rawValue
        )
        rebuildPopup(
            relativeUnitPopup,
            entries: BoardManRelativeUnitStyle.allCases.map { ($0.rawValue, $0.title(language: relativeLanguage)) },
            selectedRaw: BoardManRelativeUnitStyle.allowed(
                AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManRelativeUnitStyle)
            ).rawValue
        )
        rebuildPopup(
            relativeSuffixPopup,
            entries: BoardManRelativeSuffixStyle.allCases.map { ($0.rawValue, $0.title(language: relativeLanguage)) },
            selectedRaw: BoardManRelativeSuffixStyle.allowed(
                AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManRelativeSuffixStyle)
            ).rawValue
        )
        rebuildPopup(
            relativeNowPopup,
            entries: BoardManRelativeNowStyle.allCases.map { ($0.rawValue, $0.title(language: relativeLanguage)) },
            selectedRaw: BoardManRelativeNowStyle.allowed(
                AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManRelativeNowStyle)
            ).rawValue
        )
        rebuildPopup(
            timestampInteractionPopup,
            entries: BoardManTimestampInteraction.allCases.map { ($0.rawValue, $0.title) },
            selectedRaw: BoardManTimestampInteraction.allowed(
                AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManTimestampInteraction)
            ).rawValue
        )
        rebuildPopup(
            usageStylePopup,
            entries: [("badge", boardManText("Badge")), ("compact", boardManText("Compact"))],
            selectedRaw: BoardManPanel.allowedUsageCountStyle(AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManUsageCountStyle))
        )
        let usedStyles = ["Default", "Subtle Red", "Amber", "Blue", "Teal", "Green", "Purple", "Indigo", "Gray", "Monochrome"]
        rebuildPopup(
            usedItemStylePopup,
            entries: usedStyles.map { ($0, boardManText($0)) },
            selectedRaw: BoardManPanel.allowedUsedItemStyle(AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManUsedItemStyle))
        )
        rebuildPopup(
            themePresetPopup,
            entries: BoardManThemePreset.allCases.map { ($0.rawValue, $0.title) },
            selectedRaw: selectedThemePreset.rawValue
        )
        rebuildPopup(
            appearanceModePopup,
            entries: BoardManAppearanceMode.allCases.map { ($0.rawValue, boardManText($0.rawValue)) },
            selectedRaw: appearanceMode.rawValue
        )
        rebuildPopup(
            uiStylePopup,
            entries: BoardManUIStyle.allCases.map { ($0.rawValue, boardManText($0.rawValue)) },
            selectedRaw: uiStyle.rawValue
        )
        rebuildPopup(
            longPressActionPopup,
            entries: BoardManLongPressAction.allCases.map { ($0.rawValue, $0.title) },
            selectedRaw: configuredLongPressAction.rawValue
        )
        rebuildPopup(
            timedPinDurationUnitPopup,
            entries: BoardManTimedPinUnit.allCases.map { ($0.rawValue, $0.title) },
            selectedRaw: configuredTimedPinUnit.rawValue
        )
        refreshTimedPinSettingsControls()
        refreshTimestampShortcutControls()
        refreshProFeatureAvailability()
        applyUpdatesLocalization()
        updateSnippetModeUI()
        refreshSnippetEditor()
        updateHistorySortButton()
        updateHistoryConditionButton()
        updateSettingsSidebarSelection()
    }

    private func applyUpdatesLocalization() {
        guard let root = updatesPreferenceView else { return }
        func visit(_ view: NSView) {
            if let button = view as? NSButton {
                let normalized = button.title.lowercased()
                if normalized.contains("check for updates") || normalized.contains("今すぐ") || normalized.contains("立即") || normalized.contains("지금") {
                    button.title = boardManText("Check for Updates")
                } else if normalized.contains("automatically") || normalized.contains("自動") || normalized.contains("자동") {
                    button.title = boardManText("Automatically check for updates")
                }
            } else if let popup = view as? NSPopUpButton {
                popup.itemArray.forEach { item in
                    switch item.tag {
                    case 86_400: item.title = boardManText("Daily")
                    case 604_800: item.title = boardManText("Weekly")
                    case 2_592_000: item.title = boardManText("Monthly")
                    default: break
                    }
                }
            } else if let textField = view as? NSTextField,
                      textField.stringValue.contains("GitHub Releases") {
                textField.stringValue = boardManText("Updates will be delivered through GitHub Releases once an appcast is published.")
            }
            view.subviews.forEach(visit)
        }
        visit(root)
    }

    private func applyLiquidGlassStyle() {
        applyAppearanceMode()
        let simpleStyle = uiStyle == .simple
        let useGlass = isLiquidGlassEnabled && !simpleStyle
        let lightenTheme = isThemeLightenEnabled
        let preset = themePreset
        let accentColor = themeAccentColor
        let hasCustomPanelColor = AppEnvironment.current.defaults.string(
            forKey: Constants.UserDefaults.boardManCustomPanelColor
        ) != nil
        let presetTint = hasCustomPanelColor
            ? customPanelTintColor
            : preset.panelTintColor(useLiquidGlass: useGlass, lighten: lightenTheme)
        let tintColor = simpleStyle
            ? (hasCustomPanelColor ? customPanelTintColor : NSColor.controlBackgroundColor.withAlphaComponent(0.18))
            : presetTint
        let surfaceTint = hasCustomPanelColor
            ? customPanelTintColor
            : (simpleStyle
                ? NSColor.controlBackgroundColor.withAlphaComponent(0.24)
                : preset.surfaceTintColor(useLiquidGlass: useGlass, lighten: lightenTheme))
        backgroundColor = useGlass ? .clear : .windowBackgroundColor
        isOpaque = !useGlass
        hasShadow = !simpleStyle
        contentView?.layer?.cornerRadius = simpleStyle ? 10 : 18
        glassBackgroundView?.isHidden = !useGlass
        glassBackgroundView?.material = preset.glassMaterial
        glassBackgroundView?.layer?.backgroundColor = tintColor.cgColor
        glassBackgroundView?.layer?.borderColor = preset.edgeColor(useLiquidGlass: useGlass, lighten: lightenTheme).cgColor
        glassBackgroundView?.layer?.borderWidth = useGlass ? 1 : 0
        contentView?.layer?.backgroundColor = (useGlass
            ? tintColor
            : NSColor.windowBackgroundColor).cgColor
        contentView?.layer?.borderColor = preset.edgeColor(useLiquidGlass: useGlass, lighten: lightenTheme).cgColor
        contentView?.layer?.isOpaque = !useGlass
        searchField?.isBezeled = true
        searchField?.isBordered = true
        searchField?.drawsBackground = true
        searchField?.backgroundColor = useGlass
            ? surfaceTint.withAlphaComponent(0.26)
            : NSColor.controlBackgroundColor.withAlphaComponent(0.78)
        headerTabBar?.refreshVisualState()
        updateHistorySortButton()
        updateHistoryConditionButton()
        settingsSidebarView?.layer?.backgroundColor = (useGlass
            ? surfaceTint.withAlphaComponent(0.28)
            : NSColor.controlBackgroundColor.withAlphaComponent(simpleStyle ? 0.42 : 0.72)).cgColor
        settingsSidebarView?.layer?.cornerRadius = simpleStyle ? 7 : LayoutMetrics.cardCornerRadius
        settingsSidebarView?.layer?.borderColor = preset.edgeColor(useLiquidGlass: useGlass, lighten: lightenTheme).cgColor
        settingsCategoryButtons.forEach { button in
            if #available(macOS 10.14, *) {
                button.contentTintColor = themePreset == .defaultPreset ? .labelColor : accentColor
            }
        }
        updateSettingsSidebarSelection()
        settingsBackgroundView?.layer?.backgroundColor = (useGlass
            ? surfaceTint.withAlphaComponent(0.42)
            : tintColor).cgColor
        settingsBackgroundView?.layer?.cornerRadius = simpleStyle ? 7 : LayoutMetrics.cardCornerRadius
        settingsBackgroundView?.layer?.borderColor = preset.edgeColor(useLiquidGlass: useGlass, lighten: lightenTheme).cgColor
        settingsBackgroundView?.layer?.borderWidth = 1
        settingsBackgroundView?.layer?.shadowOpacity = 0
        let cardSurface = useGlass
            ? surfaceTint.withAlphaComponent(simpleStyle ? 0.22 : 0.34)
            : NSColor.controlBackgroundColor.withAlphaComponent(simpleStyle ? 0.54 : 0.76)
        let cardEdge = preset.edgeColor(useLiquidGlass: useGlass, lighten: lightenTheme)
            .withAlphaComponent(simpleStyle ? 0.22 : 0.48)
        [appearancePreviewCard, appearanceLayoutCard, appearanceTimestampCard,
         appearanceUsageCard, appearanceThemeCard, appearanceAdvancedCard].forEach { card in
            card?.applyStyle(
                accentColor: themePreset == .defaultPreset ? NSColor.secondaryLabelColor : accentColor,
                surfaceColor: cardSurface,
                edgeColor: cardEdge,
                simpleStyle: simpleStyle
            )
        }
        appearancePreviewView?.layer?.backgroundColor = NSColor.clear.cgColor
        if #available(macOS 10.14, *) {
            appearanceAdvancedButton?.contentTintColor = themePreset == .defaultPreset ? .secondaryLabelColor : accentColor
        }
        refreshAppearancePreview()
        scrollView?.layer?.backgroundColor = (useGlass
            ? surfaceTint.withAlphaComponent(0.30)
            : tintColor).cgColor
        scrollView?.layer?.cornerRadius = simpleStyle ? 7 : LayoutMetrics.cardCornerRadius
        scrollView?.layer?.borderColor = preset.edgeColor(useLiquidGlass: useGlass, lighten: lightenTheme).cgColor
        scrollView?.layer?.borderWidth = 1
        scrollView?.layer?.shadowOpacity = 0
        scrollView?.drawsBackground = !useGlass
        placeholderList?.backgroundColor = .clear
        ([launchOnLoginButton, inputPasteCommandButton, rowNumbersButton, usageCountButton, themeLightenButton, dedupeButton, overwriteSameHistoryButton, reuseTopButton, skipPinnedNavigationButton, timestampShortcutEnabledButton, snippetFolderEnableButton, snippetEnableButton] + storedTypeButtons.map { Optional($0) }).forEach { button in
            if #available(macOS 10.14, *) {
                button?.contentTintColor = accentColor
            }
        }
        [snippetCategoryAddButton, snippetCategoryRenameButton, snippetAddButton, snippetEditButton, snippetSaveButton, snippetCancelEditButton, snippetReorderModeButton, addHideRuleButton, removeLastHideRuleButton, excludedAppsButton, resetCustomColorsButton, exportHistoryCSVButton].forEach { button in
            if #available(macOS 10.14, *) {
                button?.contentTintColor = themePreset == .defaultPreset ? .labelColor : accentColor
            }
        }
        [snippetDeleteButton, snippetCategoryDeleteButton, clearHistoryButton, clearHideRulesButton].forEach { button in
            if #available(macOS 10.14, *) {
                button?.contentTintColor = .systemRed
            }
        }
        [generalSectionLabel, shortcutSectionLabel, viewSectionLabel, historySectionLabel, privacySectionLabel, storedTypesSectionLabel, filterSectionLabel, labsSectionLabel, snippetCategoryLabel, snippetEditorTitleLabel, snippetEditorContentLabel].forEach { label in
            label?.textColor = themePreset == .defaultPreset ? .labelColor : accentColor
        }
        [languageLabel, maxHistorySizeLabel, statusItemLabel, themePresetLabel, appearanceModeLabel,
         uiStyleLabel, fontChoiceLabel, itemTextScaleLabel, timestampLabel, timestampPositionLabel,
         relativeNumberLabel, relativeUnitLabel, relativeSuffixLabel, relativeNowLabel,
         timestampInteractionLabel, timestampShortcutLabel, timestampShortcutDelayLabel,
         usageStyleLabel, usedItemStyleLabel, heightControlLabel, customAccentLabel,
         customPanelLabel, customUsedColorLabel, longPressActionLabel, timedPinDurationLabel].forEach { label in
            label?.textColor = NSColor.labelColor.withAlphaComponent(useGlass ? 0.96 : 1)
        }
        globalShortcutRows.forEach { row in
            row.titleLabel.textColor = .labelColor
            row.detailLabel.textColor = .secondaryLabelColor
            if #available(macOS 10.14, *) {
                row.clearButton.contentTintColor = themePreset == .defaultPreset ? .labelColor : accentColor
            }
        }
        settingsPageTitleLabel?.textColor = .labelColor
        settingsPageDescriptionLabel?.textColor = .secondaryLabelColor
        snippetCategoryPopup?.wantsLayer = true
        snippetCategoryPopup?.layer?.cornerRadius = useGlass ? 9 : 6
        snippetCategoryPopup?.layer?.backgroundColor = useGlass ? surfaceTint.withAlphaComponent(0.30).cgColor : NSColor.clear.cgColor
        snippetEditorView?.layer?.cornerRadius = simpleStyle ? 7 : LayoutMetrics.cardCornerRadius
        snippetEditorView?.layer?.backgroundColor = (useGlass ? surfaceTint.withAlphaComponent(0.30) : tintColor).cgColor
        snippetEditorView?.layer?.borderColor = (useGlass ? preset.edgeColor(useLiquidGlass: true, lighten: lightenTheme) : accentColor.withAlphaComponent(lightenTheme ? 0.18 : 0.42)).cgColor
        previewBubblePanel?.contentView?.layer?.cornerRadius = useGlass ? 11 : 8
        previewBubblePanel?.contentView?.layer?.backgroundColor = surfaceTint.withAlphaComponent(useGlass ? 0.42 : 0.95).cgColor
        previewBubblePanel?.contentView?.layer?.borderColor = accentColor.withAlphaComponent(lightenTheme ? 0.18 : (useGlass ? 0.46 : 0.42)).cgColor
        themePresetPopup?.isEnabled = uiStyle != .monochrome
        if let item = appearanceModePopup?.itemArray.first(where: { ($0.representedObject as? String) == appearanceMode.rawValue }) {
            appearanceModePopup?.select(item)
        }
        if let item = uiStylePopup?.itemArray.first(where: { ($0.representedObject as? String) == uiStyle.rawValue }) {
            uiStylePopup?.select(item)
        }
        fontChoicePopup?.selectItem(withTitle: fontChoice.rawValue)
        if let item = themePresetPopup?.itemArray.first(where: { ($0.representedObject as? String) == selectedThemePreset.rawValue }) {
            themePresetPopup?.select(item)
        }
        refreshProFeatureAvailability()
        applyTypography()
        placeholderList?.reloadData()
        synchronizeListGeometry()
    }

    private func setupPreviewBubble() {
        guard let label = previewBubbleLabel else { return }
        let bubble = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 120),
                             styleMask: [.borderless],
                             backing: .buffered,
                             defer: false)
        bubble.isReleasedWhenClosed = false
        bubble.hidesOnDeactivate = true
        bubble.level = .popUpMenu
        bubble.hasShadow = true
        bubble.backgroundColor = .clear
        bubble.isOpaque = false
        bubble.ignoresMouseEvents = true
        let bubbleContent = NSVisualEffectView(frame: bubble.contentRect(forFrameRect: bubble.frame))
        bubbleContent.blendingMode = .behindWindow
        bubbleContent.material = .hudWindow
        bubbleContent.state = .active
        bubble.contentView = bubbleContent
        bubble.contentView?.wantsLayer = true
        bubble.contentView?.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.18).cgColor
        bubble.contentView?.layer?.borderColor = themeAccentColor.withAlphaComponent(0.42).cgColor
        bubble.contentView?.layer?.borderWidth = 1
        bubble.contentView?.layer?.cornerRadius = 8
        bubble.contentView?.layer?.shadowColor = themeAccentColor.cgColor
        bubble.contentView?.layer?.shadowOpacity = 0.16
        bubble.contentView?.layer?.shadowRadius = 12
        bubble.contentView?.layer?.shadowOffset = NSSize(width: 0, height: -3)
        bubble.contentView?.addSubview(label)
        if let imageView = previewBubbleImageView {
            bubble.contentView?.addSubview(imageView)
        }
        previewBubblePanel = bubble
        addChildWindow(bubble, ordered: .above)
    }

    private func installPreviewLifecycleObservers() {
        let center = NotificationCenter.default
        previewLifecycleObservers = [
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.hidePreviewBubble()
                if self.isVisible {
                    self.orderOut(nil)
                }
            },
            center.addObserver(forName: NSApplication.didHideNotification, object: NSApp, queue: .main) { [weak self] _ in
                self?.hidePreviewBubble()
            }
        ]
    }

    private func layoutPanelSubviews() {
        guard let contentView = contentView else { return }
        let isSettings = activeTab == .settings && !isQuickMode
        let layout = BoardManPanelLayoutPolicy.panelLayout(
            bounds: contentView.bounds,
            isQuickMode: isQuickMode,
            activeTab: activeTab,
            activeSettingsCategory: activeSettingsCategory,
            appearanceAdvancedExpanded: appearanceAdvancedExpanded,
            searchIntrinsicHeight: searchField?.intrinsicContentSize.height ?? 30
        )

        headerTabBar?.frame = layout.tabsFrame
        headerTabBar?.isHidden = isQuickMode
        applyResponsiveTabPresentation(isCompact: layout.isCompact)
        settingsButton?.isHidden = isQuickMode
        settingsButton?.frame = layout.settingsButtonFrame
        updateSettingsButtonAppearance()

        searchField?.isHidden = isSettings || isQuickMode
        searchField?.frame = layout.searchFrame
        searchField?.placeholderString = boardManText(
            layout.usesCompactSearchPlaceholder ? "Search" : "Search clipboard history and snippets"
        )
        let snippetButtons = [snippetAddButton, snippetEditButton, snippetDeleteButton]
        snippetButtons.forEach { $0?.isHidden = !layout.showsSnippetButtons }
        for (button, frame) in zip(snippetButtons, layout.snippetButtonFrames) {
            button?.frame = frame
        }
        updateSnippetActionButtons()

        historyUsageFilterControl?.isHidden = !layout.showsHistoryToolbar
        historySortButton?.isHidden = !layout.showsHistoryToolbar
        historyConditionButton?.isHidden = !layout.showsHistoryToolbar
        historySavedFilterPopup?.isHidden = !layout.showsHistoryToolbar
        if layout.showsHistoryToolbar {
            historyUsageFilterControl?.frame = layout.historyUsageFilterFrame
            if let filter = historyUsageFilterControl {
                let segmentWidth = floor(layout.historyUsageFilterFrame.width / CGFloat(max(1, filter.segmentCount)))
                for segment in 0..<filter.segmentCount {
                    filter.setWidth(segmentWidth, forSegment: segment)
                }
            }
            historySortButton?.frame = layout.historySortFrame
            historyConditionButton?.frame = layout.historyConditionFrame
            historySavedFilterPopup?.frame = layout.historySavedFilterFrame
        }

        settingsSidebarView?.isHidden = !isSettings
        settingsSidebarView?.frame = layout.settingsSidebarFrame
        layoutSettingsSidebar(
            width: layout.settingsSidebarFrame.width,
            height: layout.settingsSidebarFrame.height
        )
        settingsBackgroundView?.isHidden = !isSettings
        settingsBackgroundView?.frame = layout.settingsFrame
        settingsScrollView?.isHidden = !isSettings
        settingsScrollView?.frame = layout.settingsFrame
        settingsDocumentView?.frame = NSRect(
            x: 0,
            y: 0,
            width: layout.settingsFrame.width,
            height: layout.settingsDocumentHeight
        )
        layoutInlineSettingsControls(
            margin: 0,
            width: layout.settingsFrame.width,
            topY: layout.settingsDocumentHeight,
            isVisible: isSettings
        )
        if isSettings, shouldScrollSettingsToTop, let scroll = settingsScrollView {
            let topOrigin = max(0, layout.settingsDocumentHeight - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: topOrigin))
            scroll.reflectScrolledClipView(scroll.contentView)
            shouldScrollSettingsToTop = false
        }

        footerNote?.isHidden = true
        scrollView?.isHidden = isSettings
        snippetEditorView?.isHidden = !layout.showsSnippetCategories
        let snippetCategoryControls: [NSView?] = [
            snippetCategoryLabel, snippetCategoryPopup, snippetCategoryAddButton,
            snippetCategoryRenameButton, snippetCategoryDeleteButton,
            snippetInteractionHintLabel, snippetReorderModeButton
        ]
        snippetCategoryControls.forEach { $0?.isHidden = !layout.showsSnippetCategories }
        if layout.showsSnippetCategories {
            snippetCategoryLabel?.frame = layout.snippetCategoryLabelFrame
            snippetCategoryPopup?.frame = layout.snippetCategoryPopupFrame
            let categoryButtons = [snippetCategoryAddButton, snippetCategoryRenameButton, snippetCategoryDeleteButton]
            for (button, frame) in zip(categoryButtons, layout.snippetCategoryButtonFrames) {
                button?.frame = frame
            }
            snippetInteractionHintLabel?.frame = layout.snippetInteractionHintFrame
            snippetReorderModeButton?.frame = layout.snippetReorderFrame
        }

        scrollView?.frame = layout.listFrame
        if layout.showsSnippetCategories {
            snippetEditorView?.frame = layout.snippetEditorFrame
            layoutSnippetEditorControls(
                width: layout.snippetEditorFrame.width,
                height: layout.snippetEditorFrame.height
            )
        }
        synchronizeListGeometry(
            frameWidth: layout.listFrame.width,
            height: layout.listFrame.height
        )
        hidePreviewBubble()
    }

    private func layoutSnippetEditorControls(width: CGFloat, height: CGFloat) {
        let layout = BoardManSnippetPresentation.editorLayout(
            width: width,
            height: height,
            controlHeight: LayoutMetrics.controlHeight,
            actionButtonHeight: LayoutMetrics.actionButtonHeight
        )
        snippetEditorTitleLabel?.frame = layout.titleLabelFrame
        snippetEditorTitleField?.frame = layout.titleFieldFrame
        snippetEditorStatusLabel?.isHidden = true
        snippetEditorStatusLabel?.frame = .zero
        snippetFolderEnableButton?.frame = layout.folderEnableFrame
        snippetEnableButton?.frame = layout.snippetEnableFrame
        snippetEditorContentLabel?.frame = layout.contentLabelFrame
        snippetEditorScrollView?.frame = layout.contentFrame
        snippetEditorTextView?.minSize = NSSize(width: 0, height: layout.contentFrame.height)
        snippetEditorTextView?.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        snippetEditorTextView?.isVerticallyResizable = true
        snippetEditorTextView?.isHorizontallyResizable = false
        snippetEditorTextView?.textContainer?.containerSize = layout.contentContainerSize
        snippetEditorTextView?.textContainer?.widthTracksTextView = true
        snippetSaveButton?.frame = layout.saveFrame
        snippetCancelEditButton?.frame = layout.cancelFrame
    }

    fileprivate func synchronizeListGeometry(frameWidth: CGFloat? = nil, height: CGFloat? = nil) {
        guard let scrollView, let table = placeholderList else { return }

        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .none
        scrollView.contentView.bounds.origin.x = 0

        let safeWidth = max(1, floor((frameWidth ?? scrollView.bounds.width) - 10))
        let safeHeight = max(1, floor(height ?? scrollView.bounds.height))
        let rowHeight = max(table.rowHeight, 1)
        let rowCount = max(table.numberOfRows, 1)
        let documentHeight = max(safeHeight, CGFloat(rowCount) * rowHeight)

        table.frame = NSRect(x: 0, y: 0, width: safeWidth, height: documentHeight)
        table.bounds = NSRect(x: 0, y: 0, width: safeWidth, height: documentHeight)

        for column in table.tableColumns {
            column.minWidth = safeWidth
            column.width = safeWidth
            column.maxWidth = safeWidth
        }

        table.enclosingScrollView?.hasHorizontalScroller = false
        table.needsLayout = true
        table.needsDisplay = true

        table.enumerateAvailableRowViews { rowView, _ in
            rowView.setFrameSize(NSSize(width: safeWidth, height: rowView.frame.height))
            rowView.needsLayout = true
            rowView.needsDisplay = true

            if let cellView = rowView.view(atColumn: 0) as? NSView {
                cellView.frame = BoardManHistoryCellView.synchronizedCellFrame(
                    existingFrame: cellView.frame,
                    safeWidth: safeWidth
                )
                cellView.needsLayout = true
                cellView.needsDisplay = true
            }
        }
    }

    private func applyResponsiveTabPresentation(isCompact: Bool) {
        guard let headerTabBar else { return }
        headerTabBar.setFont(NSFont.systemFont(
            ofSize: isCompact ? 11.25 : 12.5,
            weight: .medium
        ))
        for tab in [BoardManPanelTab.history, BoardManPanelTab.snippets] {
            let symbolName = tab == .history ? "clock.arrow.circlepath" : "text.badge.plus"
            headerTabBar.configureTab(
                index: tab.rawValue,
                title: tab.title(compact: isCompact),
                toolTip: tab.title,
                image: NSImage(systemSymbolName: symbolName, accessibilityDescription: tab.title)
            )
        }
    }

    private func settingsDocumentHeight(viewportHeight: CGFloat, contentWidth: CGFloat) -> CGFloat {
        BoardManPanelLayoutPolicy.settingsDocumentHeight(
            viewportHeight: viewportHeight,
            contentWidth: contentWidth,
            category: activeSettingsCategory,
            appearanceAdvancedExpanded: appearanceAdvancedExpanded
        )
    }

    private func layoutSettingsSidebar(width: CGFloat, height: CGFloat) {
        guard let sidebar = settingsSidebarView else { return }
        let frames = BoardManPanelLayoutPolicy.settingsSidebarButtonFrames(
            width: width,
            height: height,
            count: settingsCategoryButtons.count
        )
        for (button, frame) in zip(settingsCategoryButtons, frames) {
            button.frame = frame
        }
        sidebar.needsLayout = true
        updateSettingsSidebarSelection()
    }

    private func updateSettingsSidebarSelection() {
        settingsPageTitleLabel?.stringValue = activeSettingsCategory.title
        settingsPageDescriptionLabel?.stringValue = activeSettingsCategory.detail
        for button in settingsCategoryButtons {
            let isSelected = button.tag == activeSettingsCategory.rawValue
            let isHovering = (button as? BoardManSettingsCategoryButton)?.isHovering == true
            button.state = isSelected ? .on : .off
            if isSelected {
                button.layer?.backgroundColor = themeAccentColor
                    .withAlphaComponent(isThemeLightenEnabled ? 0.12 : 0.18).cgColor
            } else if isHovering {
                button.layer?.backgroundColor = themeAccentColor
                    .withAlphaComponent(isThemeLightenEnabled ? 0.07 : 0.11).cgColor
            } else {
                button.layer?.backgroundColor = NSColor.clear.cgColor
            }
            button.layer?.borderWidth = (isSelected || isHovering) ? 1 : 0
            button.layer?.borderColor = themeAccentColor
                .withAlphaComponent(isSelected ? 0.32 : 0.20).cgColor
        }
    }

    private func layoutInlineSettingsControls(margin: CGFloat, width: CGFloat, topY: CGFloat, isVisible: Bool) {
        let allControls: [NSView?] = [
            settingsPageTitleLabel, settingsPageDescriptionLabel,
            generalSectionLabel, launchOnLoginButton, inputPasteCommandButton, languageLabel, languagePopup,
            maxHistorySizeLabel, maxHistorySizeStepper, maxHistorySizeValueLabel,
            maxHistoryDecreaseButton, maxHistoryIncreaseButton,
            statusItemLabel, statusItemPopup, shortcutSectionLabel, shortcutStatusLabel,
            snippetSettingsSectionLabel, snippetSummaryLabel, snippetFoldersLabel, snippetGroupProNoteLabel,
            snippetGroupOrderPopup, snippetGroupMoveUpButton, snippetGroupMoveDownButton,
            snippetShortcutsLabel, snippetShortcutScrollView, manageSnippetsButton,
            appearancePreviewCard, appearanceLayoutCard, appearanceTimestampCard, appearanceUsageCard, appearanceThemeCard,
            appearanceAdvancedCard, appearancePreviewView, appearanceAdvancedButton,
            viewSectionLabel, rowNumbersButton, timestampLabel, timestampPopup, timestampPositionLabel, timestampPositionPopup,
            relativeNumberLabel, relativeNumberPopup, relativeUnitLabel, relativeUnitPopup,
            relativeSuffixLabel, relativeSuffixPopup, relativeNowLabel, relativeNowPopup,
            timestampInteractionLabel, timestampInteractionPopup,
            timestampShortcutEnabledButton, timestampShortcutLabel, timestampShortcutRecordView,
            timestampShortcutDelayLabel, timestampShortcutDelayField, timestampShortcutDelayStepper,
            timestampShortcutDelayDecreaseButton, timestampShortcutDelayIncreaseButton, timestampShortcutSecondsLabel,
            usageCountButton, usageStyleLabel, usageStylePopup, usedItemStyleLabel, usedItemStylePopup,
            pinLabelStyleLabel, pinLabelStylePopup, showInlineImagesButton, inlineImagePositionLabel, inlineImagePositionPopup,
            themePresetLabel, themePresetPopup, appearanceModeLabel, appearanceModePopup,
            uiStyleLabel, uiStylePopup, fontChoiceLabel, fontChoicePopup,
            itemTextScaleLabel, itemTextScaleField, itemTextScaleDecreaseButton, itemTextScaleIncreaseButton, themeLightenButton,
            customAccentLabel, customAccentColorWell, customAccentOpacitySlider,
            customPanelLabel, customPanelColorWell, customPanelOpacitySlider,
            customUsedColorLabel, customUsedColorWell, customUsedOpacitySlider, resetCustomColorsButton,
            textPreviewScaleLabel, textPreviewScaleSlider, textPreviewScaleValueLabel,
            imagePreviewScaleLabel, imagePreviewScaleSlider, imagePreviewScaleValueLabel, previewScaleProNoteLabel,
            historySectionLabel, dedupeButton, overwriteSameHistoryButton, reuseTopButton, clearHistoryButton,
            skipPinnedNavigationButton, longPressActionLabel, longPressActionPopup,
            timedPinDurationLabel, timedPinPresetPopup, timedPinPresetAddButton, timedPinPresetRemoveButton,
            timedPinDurationStepper, timedPinDurationValueLabel,
            timedPinDurationDecreaseButton, timedPinDurationIncreaseButton,
            timedPinDurationUnitPopup, exportHistoryCSVButton,
            privacySectionLabel, hideMaskedPreviewButton, hideMaskedTitleButton,
            excludedAppsButton, excludedAppsSummaryLabel, storedTypesSectionLabel,
            filterSectionLabel, hideRuleTextField, hideRuleModePopup, addHideRuleButton,
            removeLastHideRuleButton, clearHideRulesButton, hideRulesSummaryLabel,
            hideRulesExamplesLabel, hideRulesNoteLabel,
            licenseSectionLabel, licensePlanLabel, licenseStateLabel, licenseLimitsLabel,
            licenseKeyField, licenseActivateButton, licenseActivationStatusLabel, licenseUpgradeButton,
            licenseProLockedControlView, licenseMockNoteLabel, licenseStateExamplesLabel,
            labsSectionLabel, labsNoteLabel,
            heightControlLabel, heightLabel, heightStepper, heightDecreaseButton, heightIncreaseButton
        ]
        allControls.forEach { $0?.isHidden = true }
        globalShortcutRows.flatMap { $0.views }.forEach { $0.isHidden = true }
        updatesPreferenceView?.isHidden = true
        pauseRecordingButton?.isHidden = true
        storedTypeButtons.forEach { $0.isHidden = true }
        guard isVisible else { return }
        refreshSnippetSettingsSummary()
        refreshGlobalShortcutRows()

        let rowH = LayoutMetrics.controlHeight
        let rowGap: CGFloat = 38
        let fieldLabelWidth = LayoutMetrics.settingsLabelWidth
        let contentX = margin + LayoutMetrics.settingsInset
        let contentWidth = max(240, width - (LayoutMetrics.settingsInset * 2))
        let columnWidth = contentWidth
        let leftX = contentX
        settingsPageTitleLabel?.isHidden = false
        settingsPageDescriptionLabel?.isHidden = false
        settingsPageTitleLabel?.frame = NSRect(x: leftX, y: topY - 52, width: columnWidth, height: 30)
        settingsPageDescriptionLabel?.frame = NSRect(x: leftX, y: topY - 92, width: columnWidth, height: 34)
        let firstY = topY - 134

        var generalControls: [NSView?] = [
            generalSectionLabel, launchOnLoginButton, inputPasteCommandButton,
            languageLabel, languagePopup,
            maxHistorySizeLabel, maxHistorySizeValueLabel, maxHistoryDecreaseButton, maxHistoryIncreaseButton,
            statusItemLabel, statusItemPopup, shortcutSectionLabel, shortcutStatusLabel
        ]
        generalControls.append(contentsOf: globalShortcutRows.flatMap { $0.views }.map { Optional($0) })
        let viewControls: [NSView?] = [
            appearancePreviewCard, appearanceLayoutCard, appearanceTimestampCard, appearanceUsageCard, appearanceThemeCard,
            appearanceAdvancedCard, appearancePreviewView, appearanceAdvancedButton,
            viewSectionLabel, rowNumbersButton, timestampLabel, timestampPopup,
            timestampPositionLabel, timestampPositionPopup,
            relativeNumberLabel, relativeNumberPopup, relativeUnitLabel, relativeUnitPopup,
            relativeSuffixLabel, relativeSuffixPopup, relativeNowLabel, relativeNowPopup,
            usageCountButton, usageStyleLabel, usageStylePopup, usedItemStyleLabel,
            usedItemStylePopup, pinLabelStyleLabel, pinLabelStylePopup, showInlineImagesButton,
            inlineImagePositionLabel, inlineImagePositionPopup, themePresetLabel, themePresetPopup,
            appearanceModeLabel, appearanceModePopup, uiStyleLabel, uiStylePopup,
            fontChoiceLabel, fontChoicePopup,
            itemTextScaleLabel, itemTextScaleField, itemTextScaleDecreaseButton, itemTextScaleIncreaseButton, themeLightenButton,
            customAccentLabel, customAccentColorWell, customAccentOpacitySlider,
            customPanelLabel, customPanelColorWell, customPanelOpacitySlider,
            customUsedColorLabel, customUsedColorWell, customUsedOpacitySlider, resetCustomColorsButton,
            textPreviewScaleLabel, textPreviewScaleSlider, textPreviewScaleValueLabel,
            imagePreviewScaleLabel, imagePreviewScaleSlider, imagePreviewScaleValueLabel, previewScaleProNoteLabel,
            heightControlLabel, heightLabel, heightDecreaseButton, heightIncreaseButton
        ]
        let historyControls: [NSView?] = [
            historySectionLabel, dedupeButton, overwriteSameHistoryButton, reuseTopButton,
            skipPinnedNavigationButton, longPressActionLabel, longPressActionPopup,
            timestampInteractionLabel, timestampInteractionPopup,
            timestampShortcutEnabledButton, timestampShortcutLabel, timestampShortcutRecordView,
            timestampShortcutDelayLabel, timestampShortcutDelayField,
            timestampShortcutDelayDecreaseButton, timestampShortcutDelayIncreaseButton, timestampShortcutSecondsLabel,
            timedPinDurationLabel, timedPinPresetPopup, timedPinPresetAddButton, timedPinPresetRemoveButton,
            timedPinDurationValueLabel, timedPinDurationDecreaseButton, timedPinDurationIncreaseButton,
            timedPinDurationUnitPopup, exportHistoryCSVButton, clearHistoryButton
        ]
        let snippetControls: [NSView?] = [snippetSettingsSectionLabel, snippetSummaryLabel, snippetFoldersLabel, snippetGroupProNoteLabel, snippetGroupOrderPopup, snippetGroupMoveUpButton, snippetGroupMoveDownButton, snippetShortcutsLabel, snippetShortcutScrollView, manageSnippetsButton]
        let privacyControls: [NSView?] = [
            privacySectionLabel, hideMaskedPreviewButton, hideMaskedTitleButton,
            excludedAppsButton, excludedAppsSummaryLabel,
            storedTypesSectionLabel, filterSectionLabel, hideRuleTextField,
            hideRuleModePopup, addHideRuleButton, removeLastHideRuleButton,
            clearHideRulesButton, hideRulesSummaryLabel, hideRulesExamplesLabel,
            hideRulesNoteLabel
        ] + storedTypeButtons.map { $0 as NSView }
        let licenseControls: [NSView?] = [
            licenseSectionLabel, licensePlanLabel, licenseStateLabel,
            licenseLimitsLabel, licenseKeyField, licenseActivateButton,
            licenseActivationStatusLabel, licenseUpgradeButton, licenseProLockedControlView,
            licenseMockNoteLabel, licenseStateExamplesLabel
        ]
        let updatesControls: [NSView?] = [updatesPreferenceView]

        func show(_ controls: [NSView?]) {
            controls.forEach { $0?.isHidden = false }
        }

        func popupWidth(in columnWidth: CGFloat, labelWidth: CGFloat = fieldLabelWidth) -> CGFloat {
            return max(118, columnWidth - labelWidth - 12)
        }

        func placeHeader(_ label: NSTextField?, originX: CGFloat, originY: CGFloat, width: CGFloat) {
            label?.frame = NSRect(x: originX, y: originY, width: width, height: 18)
        }

        func placeLabeledRow(label: NSTextField?, control: NSView?, originX: CGFloat, originY: CGFloat, width: CGFloat, labelWidth: CGFloat = fieldLabelWidth) {
            label?.frame = NSIntegralRect(NSRect(x: originX, y: originY + 7, width: labelWidth, height: 16))
            control?.frame = NSIntegralRect(NSRect(
                x: originX + labelWidth + 12,
                y: originY,
                width: popupWidth(in: width, labelWidth: labelWidth),
                height: rowH
            ))
        }

        func placeGeneralSection(originX: CGFloat, originY: CGFloat, width: CGFloat) {
            let layout = BoardManGeneralSettingsLayoutPolicy.generalSection(
                originX: originX,
                originY: originY,
                width: width,
                rowHeight: rowH,
                labelWidth: fieldLabelWidth
            )
            generalSectionLabel?.frame = layout.sectionHeaderFrame
            launchOnLoginButton?.frame = layout.launchOnLoginFrame
            inputPasteCommandButton?.frame = layout.inputPasteCommandFrame
            languageLabel?.frame = layout.languageLabelFrame
            languagePopup?.frame = layout.languageControlFrame
            maxHistorySizeLabel?.frame = layout.maxHistoryLabelFrame
            maxHistoryDecreaseButton?.frame = layout.maxHistoryDecreaseFrame
            maxHistorySizeValueLabel?.frame = layout.maxHistoryValueFrame
            maxHistoryIncreaseButton?.frame = layout.maxHistoryIncreaseFrame
            statusItemLabel?.frame = layout.statusItemLabelFrame
            statusItemPopup?.frame = layout.statusItemControlFrame
        }

        func placeShortcutSection(originX: CGFloat, originY: CGFloat, width: CGFloat) {
            let layout = BoardManGeneralSettingsLayoutPolicy.shortcutSection(
                originX: originX,
                originY: originY,
                width: width,
                rowCount: globalShortcutRows.count
            )
            shortcutSectionLabel?.frame = layout.sectionHeaderFrame
            for (row, rowLayout) in zip(globalShortcutRows, layout.rows) {
                row.titleLabel.frame = rowLayout.titleFrame
                row.detailLabel.frame = rowLayout.detailFrame
                row.recordView.frame = rowLayout.recordFrame
                row.clearButton.frame = rowLayout.clearFrame
            }
            shortcutStatusLabel?.frame = layout.statusFrame
        }

        func placeViewSection(originX: CGFloat, originY: CGFloat, width: CGFloat) {
            viewSectionLabel?.isHidden = true
            let cardGap: CGFloat = 14
            let columnGap: CGFloat = 14
            let stacksCards = Self.usesStackedAppearanceSettingsLayout(width: width)
            let halfWidth = stacksCards ? width : max(188, floor((width - columnGap) / 2))
            let rightX = stacksCards ? originX : originX + halfWidth + columnGap
            let compactLabelWidth: CGFloat = stacksCards ? 82 : 64
            let cardInset: CGFloat = 16

            let advancedControls: [NSView?] = [
                relativeNumberLabel, relativeNumberPopup, relativeUnitLabel, relativeUnitPopup,
                relativeSuffixLabel, relativeSuffixPopup, relativeNowLabel, relativeNowPopup,
                customAccentLabel, customAccentColorWell, customAccentOpacitySlider,
                customPanelLabel, customPanelColorWell, customPanelOpacitySlider,
                customUsedColorLabel, customUsedColorWell, customUsedOpacitySlider, resetCustomColorsButton,
                textPreviewScaleLabel, textPreviewScaleSlider, textPreviewScaleValueLabel,
                imagePreviewScaleLabel, imagePreviewScaleSlider, imagePreviewScaleValueLabel, previewScaleProNoteLabel
            ]

            let previewHeight: CGFloat = 172
            let previewY = originY - previewHeight
            let previewInset: CGFloat = 22
            appearancePreviewCard?.frame = NSIntegralRect(NSRect(x: originX, y: previewY, width: width, height: previewHeight))
            appearancePreviewCard?.needsLayout = true
            appearancePreviewView?.frame = NSIntegralRect(NSRect(
                x: originX + previewInset,
                y: previewY + 18,
                width: max(160, width - (previewInset * 2)),
                height: previewHeight - 70
            ))

            let layoutCardHeight: CGFloat = stacksCards ? 218 : 218
            let timestampCardHeight: CGFloat = layoutCardHeight
            let layoutCardY = previewY - cardGap - layoutCardHeight
            let timestampCardY = stacksCards
                ? layoutCardY - cardGap - timestampCardHeight
                : layoutCardY
            appearanceLayoutCard?.frame = NSIntegralRect(NSRect(
                x: originX,
                y: layoutCardY,
                width: halfWidth,
                height: layoutCardHeight
            ))
            appearanceTimestampCard?.frame = NSIntegralRect(NSRect(
                x: rightX,
                y: timestampCardY,
                width: halfWidth,
                height: timestampCardHeight
            ))
            appearanceLayoutCard?.needsLayout = true
            appearanceTimestampCard?.needsLayout = true

            let layoutX = originX + cardInset
            let layoutWidth = halfWidth - (cardInset * 2)
            rowNumbersButton?.frame = NSIntegralRect(NSRect(
                x: layoutX,
                y: layoutCardY + layoutCardHeight - 80,
                width: layoutWidth,
                height: 20
            ))
            placeLabeledRow(
                label: uiStyleLabel,
                control: uiStylePopup,
                originX: layoutX,
                originY: layoutCardY + layoutCardHeight - 120,
                width: layoutWidth,
                labelWidth: compactLabelWidth
            )
            let textScaleY = layoutCardY + layoutCardHeight - 162
            itemTextScaleLabel?.frame = NSIntegralRect(NSRect(
                x: layoutX,
                y: textScaleY + 7,
                width: compactLabelWidth,
                height: 16
            ))
            let textScaleControlX = layoutX + compactLabelWidth + 12
            let textScaleValueWidth: CGFloat = max(52, min(58, layoutWidth - compactLabelWidth - 94))
            itemTextScaleDecreaseButton?.frame = NSIntegralRect(NSRect(
                x: textScaleControlX,
                y: textScaleY,
                width: 28,
                height: rowH
            ))
            itemTextScaleField?.frame = NSIntegralRect(NSRect(
                x: textScaleControlX + 34,
                y: textScaleY,
                width: textScaleValueWidth,
                height: rowH
            ))
            itemTextScaleIncreaseButton?.frame = NSIntegralRect(NSRect(
                x: textScaleControlX + 40 + textScaleValueWidth,
                y: textScaleY,
                width: 28,
                height: rowH
            ))
            heightControlLabel?.frame = NSIntegralRect(NSRect(
                x: layoutX,
                y: layoutCardY + 11,
                width: compactLabelWidth,
                height: 16
            ))
            let heightControlX = layoutX + compactLabelWidth + 12
            let heightValueWidth: CGFloat = max(52, min(68, layoutWidth - compactLabelWidth - 94))
            heightDecreaseButton?.frame = NSIntegralRect(NSRect(x: heightControlX, y: layoutCardY + 4, width: 28, height: rowH))
            heightLabel?.frame = NSIntegralRect(NSRect(x: heightControlX + 34, y: layoutCardY + 4, width: heightValueWidth, height: rowH))
            heightIncreaseButton?.frame = NSIntegralRect(NSRect(x: heightControlX + 40 + heightValueWidth, y: layoutCardY + 4, width: 28, height: rowH))

            let timestampX = rightX + cardInset
            let timestampWidth = halfWidth - (cardInset * 2)
            placeLabeledRow(
                label: timestampLabel,
                control: timestampPopup,
                originX: timestampX,
                originY: timestampCardY + timestampCardHeight - 94,
                width: timestampWidth,
                labelWidth: compactLabelWidth
            )
            placeLabeledRow(
                label: timestampPositionLabel,
                control: timestampPositionPopup,
                originX: timestampX,
                originY: timestampCardY + timestampCardHeight - 134,
                width: timestampWidth,
                labelWidth: compactLabelWidth
            )

            let usageCardHeight: CGFloat = 292
            let themeCardHeight: CGFloat = 292
            let usageCardY = (stacksCards ? timestampCardY : layoutCardY) - cardGap - usageCardHeight
            let themeCardY = stacksCards
                ? usageCardY - cardGap - themeCardHeight
                : usageCardY
            appearanceUsageCard?.frame = NSIntegralRect(NSRect(
                x: originX,
                y: usageCardY,
                width: halfWidth,
                height: usageCardHeight
            ))
            appearanceThemeCard?.frame = NSIntegralRect(NSRect(
                x: rightX,
                y: themeCardY,
                width: halfWidth,
                height: themeCardHeight
            ))
            appearanceUsageCard?.needsLayout = true
            appearanceThemeCard?.needsLayout = true

            let usageX = originX + cardInset
            let usageWidth = halfWidth - (cardInset * 2)
            usageCountButton?.frame = NSIntegralRect(NSRect(
                x: usageX,
                y: usageCardY + usageCardHeight - 82,
                width: usageWidth,
                height: 20
            ))
            placeLabeledRow(
                label: usageStyleLabel,
                control: usageStylePopup,
                originX: usageX,
                originY: usageCardY + usageCardHeight - 124,
                width: usageWidth,
                labelWidth: compactLabelWidth
            )
            placeLabeledRow(
                label: usedItemStyleLabel,
                control: usedItemStylePopup,
                originX: usageX,
                originY: usageCardY + usageCardHeight - 164,
                width: usageWidth,
                labelWidth: compactLabelWidth
            )
            placeLabeledRow(
                label: pinLabelStyleLabel,
                control: pinLabelStylePopup,
                originX: usageX,
                originY: usageCardY + usageCardHeight - 204,
                width: usageWidth,
                labelWidth: compactLabelWidth
            )
            showInlineImagesButton?.frame = NSIntegralRect(NSRect(
                x: usageX,
                y: usageCardY + usageCardHeight - 236,
                width: usageWidth,
                height: 20
            ))
            placeLabeledRow(
                label: inlineImagePositionLabel,
                control: inlineImagePositionPopup,
                originX: usageX,
                originY: usageCardY + 10,
                width: usageWidth,
                labelWidth: compactLabelWidth
            )
            inlineImagePositionPopup?.isEnabled = showInlineImagesButton?.state == .on

            let themeX = rightX + cardInset
            let themeWidth = halfWidth - (cardInset * 2)
            placeLabeledRow(
                label: themePresetLabel,
                control: themePresetPopup,
                originX: themeX,
                originY: themeCardY + themeCardHeight - 86,
                width: themeWidth,
                labelWidth: compactLabelWidth
            )
            placeLabeledRow(
                label: appearanceModeLabel,
                control: appearanceModePopup,
                originX: themeX,
                originY: themeCardY + themeCardHeight - 126,
                width: themeWidth,
                labelWidth: compactLabelWidth
            )
            placeLabeledRow(
                label: fontChoiceLabel,
                control: fontChoicePopup,
                originX: themeX,
                originY: themeCardY + themeCardHeight - 166,
                width: themeWidth,
                labelWidth: compactLabelWidth
            )
            themeLightenButton?.frame = NSIntegralRect(NSRect(
                x: themeX,
                y: themeCardY + 7,
                width: themeWidth,
                height: 20
            ))

            let toggleY = (stacksCards ? themeCardY : usageCardY) - 36
            appearanceAdvancedButton?.frame = NSIntegralRect(NSRect(x: originX, y: toggleY, width: min(210, width), height: 26))
            appearanceAdvancedButton?.title = boardManText(
                appearanceAdvancedExpanded ? "Hide advanced settings" : "Show advanced settings"
            )
            appearanceAdvancedButton?.image = NSImage(
                systemSymbolName: appearanceAdvancedExpanded ? "chevron.down" : "chevron.right",
                accessibilityDescription: nil
            )

            guard appearanceAdvancedExpanded else {
                appearanceAdvancedCard?.isHidden = true
                advancedControls.forEach { $0?.isHidden = true }
                refreshAppearancePreview()
                return
            }

            appearanceAdvancedCard?.isHidden = false
            advancedControls.forEach { $0?.isHidden = false }
            let advancedHeight: CGFloat = 350
            let advancedY = toggleY - cardGap - advancedHeight
            appearanceAdvancedCard?.frame = NSIntegralRect(NSRect(x: originX, y: advancedY, width: width, height: advancedHeight))
            appearanceAdvancedCard?.needsLayout = true

            let advancedX = originX + cardInset
            let advancedWidth = width - (cardInset * 2)
            let advancedHalfWidth = max(180, floor((advancedWidth - columnGap) / 2))
            let advancedRightX = advancedX + advancedHalfWidth + columnGap
            placeLabeledRow(label: relativeNumberLabel, control: relativeNumberPopup,
                            originX: advancedX, originY: advancedY + advancedHeight - 92,
                            width: advancedHalfWidth, labelWidth: compactLabelWidth)
            placeLabeledRow(label: relativeUnitLabel, control: relativeUnitPopup,
                            originX: advancedRightX, originY: advancedY + advancedHeight - 92,
                            width: advancedHalfWidth, labelWidth: compactLabelWidth)
            placeLabeledRow(label: relativeSuffixLabel, control: relativeSuffixPopup,
                            originX: advancedX, originY: advancedY + advancedHeight - 132,
                            width: advancedHalfWidth, labelWidth: compactLabelWidth)
            placeLabeledRow(label: relativeNowLabel, control: relativeNowPopup,
                            originX: advancedRightX, originY: advancedY + advancedHeight - 132,
                            width: advancedHalfWidth, labelWidth: compactLabelWidth)

            func placeColorRow(label: NSTextField?, well: NSColorWell?, slider: NSSlider?, originX: CGFloat, originY: CGFloat, rowWidth: CGFloat) {
                let labelWidth: CGFloat = min(78, max(58, floor(rowWidth * 0.27)))
                let wellWidth: CGFloat = 40
                label?.frame = NSIntegralRect(NSRect(x: originX, y: originY + 6, width: labelWidth, height: 16))
                well?.frame = NSIntegralRect(NSRect(x: originX + labelWidth + 8, y: originY, width: wellWidth, height: rowH))
                slider?.frame = NSIntegralRect(NSRect(
                    x: originX + labelWidth + wellWidth + 18,
                    y: originY + 3,
                    width: max(42, rowWidth - labelWidth - wellWidth - 18),
                    height: 24
                ))
            }
            placeColorRow(label: customAccentLabel, well: customAccentColorWell, slider: customAccentOpacitySlider,
                          originX: advancedX, originY: advancedY + advancedHeight - 180, rowWidth: advancedHalfWidth)
            placeColorRow(label: customPanelLabel, well: customPanelColorWell, slider: customPanelOpacitySlider,
                          originX: advancedRightX, originY: advancedY + advancedHeight - 180, rowWidth: advancedHalfWidth)
            placeColorRow(label: customUsedColorLabel, well: customUsedColorWell, slider: customUsedOpacitySlider,
                          originX: advancedX, originY: advancedY + advancedHeight - 220, rowWidth: advancedHalfWidth)
            resetCustomColorsButton?.frame = NSIntegralRect(NSRect(
                x: advancedRightX,
                y: advancedY + advancedHeight - 222,
                width: min(150, advancedHalfWidth),
                height: LayoutMetrics.actionButtonHeight
            ))

            func placePreviewScaleRow(label: NSTextField?, slider: NSSlider?, value: NSTextField?, rowY: CGFloat) {
                label?.frame = NSIntegralRect(NSRect(x: advancedX, y: rowY + 7, width: 104, height: 16))
                slider?.frame = NSIntegralRect(NSRect(x: advancedX + 116, y: rowY + 3, width: max(120, advancedWidth - 192), height: 24))
                value?.frame = NSIntegralRect(NSRect(x: advancedX + advancedWidth - 64, y: rowY, width: 64, height: rowH))
            }
            placePreviewScaleRow(label: textPreviewScaleLabel, slider: textPreviewScaleSlider,
                                 value: textPreviewScaleValueLabel, rowY: advancedY + 74)
            placePreviewScaleRow(label: imagePreviewScaleLabel, slider: imagePreviewScaleSlider,
                                 value: imagePreviewScaleValueLabel, rowY: advancedY + 34)
            previewScaleProNoteLabel?.frame = NSIntegralRect(NSRect(x: advancedX, y: advancedY + 4, width: advancedWidth, height: 28))
            refreshAppearancePreview()
        }

        func placeHistorySection(originX: CGFloat, originY: CGFloat, width: CGFloat) {
            placeHeader(historySectionLabel, originX: originX, originY: originY, width: width)
            dedupeButton?.frame = NSRect(x: originX, y: originY - 42, width: width, height: 20)
            reuseTopButton?.frame = NSRect(x: originX, y: originY - 78, width: width, height: 20)
            overwriteSameHistoryButton?.frame = NSRect(x: originX, y: originY - 114, width: width, height: 20)
            skipPinnedNavigationButton?.frame = NSRect(x: originX, y: originY - 150, width: width, height: 20)

            let compactLabelWidth: CGFloat = min(104, max(78, floor(width * 0.24)))
            placeLabeledRow(
                label: longPressActionLabel,
                control: longPressActionPopup,
                originX: originX,
                originY: originY - 198,
                width: width,
                labelWidth: compactLabelWidth
            )
            placeLabeledRow(
                label: timestampInteractionLabel,
                control: timestampInteractionPopup,
                originX: originX,
                originY: originY - 240,
                width: width,
                labelWidth: compactLabelWidth
            )
            timestampShortcutEnabledButton?.frame = NSRect(
                x: originX,
                y: originY - 282,
                width: width,
                height: 20
            )

            let stacksShortcut = Self.usesStackedHistorySettingsLayout(width: width)
            let shortcutRecordY: CGFloat
            let delayRowY: CGFloat
            let pinLabelY: CGFloat
            if stacksShortcut {
                timestampShortcutLabel?.frame = NSIntegralRect(NSRect(
                    x: originX,
                    y: originY - 302,
                    width: width,
                    height: 16
                ))
                shortcutRecordY = originY - 336
                timestampShortcutRecordView?.frame = NSIntegralRect(NSRect(
                    x: originX,
                    y: shortcutRecordY,
                    width: width,
                    height: rowH
                ))
                delayRowY = originY - 370
                pinLabelY = originY - 392
            } else {
                timestampShortcutLabel?.frame = NSIntegralRect(NSRect(
                    x: originX,
                    y: originY - 324,
                    width: compactLabelWidth,
                    height: 16
                ))
                shortcutRecordY = originY - 331
                timestampShortcutRecordView?.frame = NSIntegralRect(NSRect(
                    x: originX + compactLabelWidth + 12,
                    y: shortcutRecordY,
                    width: max(128, width - compactLabelWidth - 12),
                    height: rowH
                ))
                delayRowY = originY - 373
                pinLabelY = originY - 396
            }

            let delayLabelWidth: CGFloat = stacksShortcut ? 48 : compactLabelWidth
            timestampShortcutDelayLabel?.frame = NSIntegralRect(NSRect(
                x: originX,
                y: delayRowY + 7,
                width: delayLabelWidth,
                height: 16
            ))
            let shortcutDelayX = originX + delayLabelWidth + 12
            let secondsWidth: CGFloat = 44
            let adjustmentWidth: CGFloat = 30
            let delayFieldWidth: CGFloat = min(82, max(58, floor(width * 0.18)))
            timestampShortcutDelayDecreaseButton?.frame = NSIntegralRect(NSRect(
                x: shortcutDelayX,
                y: delayRowY,
                width: adjustmentWidth,
                height: rowH
            ))
            timestampShortcutDelayField?.frame = NSIntegralRect(NSRect(
                x: shortcutDelayX + adjustmentWidth + 6,
                y: delayRowY,
                width: delayFieldWidth,
                height: rowH
            ))
            timestampShortcutDelayIncreaseButton?.frame = NSIntegralRect(NSRect(
                x: shortcutDelayX + adjustmentWidth + delayFieldWidth + 12,
                y: delayRowY,
                width: adjustmentWidth,
                height: rowH
            ))
            timestampShortcutSecondsLabel?.frame = NSIntegralRect(NSRect(
                x: shortcutDelayX + (adjustmentWidth * 2) + delayFieldWidth + 24,
                y: delayRowY + 7,
                width: secondsWidth,
                height: 16
            ))

            timedPinDurationLabel?.frame = NSIntegralRect(NSRect(
                x: originX,
                y: pinLabelY,
                width: width,
                height: 16
            ))
            let presetRowY = pinLabelY - 34
            let presetButtonWidth: CGFloat = 34
            let presetGap: CGFloat = 6
            let presetWidth = max(
                112,
                width - (presetButtonWidth * 2) - (presetGap * 2)
            )
            timedPinPresetPopup?.frame = NSIntegralRect(NSRect(
                x: originX,
                y: presetRowY,
                width: presetWidth,
                height: rowH
            ))
            timedPinPresetAddButton?.frame = NSIntegralRect(NSRect(
                x: originX + presetWidth + presetGap,
                y: presetRowY,
                width: presetButtonWidth,
                height: rowH
            ))
            timedPinPresetRemoveButton?.frame = NSIntegralRect(NSRect(
                x: originX + presetWidth + presetGap + presetButtonWidth + presetGap,
                y: presetRowY,
                width: presetButtonWidth,
                height: rowH
            ))

            let durationRowY = presetRowY - 36
            let durationValueWidth: CGFloat = min(96, max(72, floor(width * 0.22)))
            timedPinDurationDecreaseButton?.frame = NSIntegralRect(NSRect(
                x: originX,
                y: durationRowY,
                width: 30,
                height: rowH
            ))
            timedPinDurationValueLabel?.frame = NSIntegralRect(NSRect(
                x: originX + 36,
                y: durationRowY,
                width: durationValueWidth,
                height: rowH
            ))
            timedPinDurationIncreaseButton?.frame = NSIntegralRect(NSRect(
                x: originX + durationValueWidth + 42,
                y: durationRowY,
                width: 30,
                height: rowH
            ))
            let unitX = originX + durationValueWidth + 84
            timedPinDurationUnitPopup?.frame = NSIntegralRect(NSRect(
                x: unitX,
                y: durationRowY,
                width: max(92, width - (unitX - originX)),
                height: rowH
            ))

            let actionY = durationRowY - 50
            let exportWidth = min(176, max(132, floor(width * 0.42)))
            exportHistoryCSVButton?.frame = NSRect(
                x: originX,
                y: actionY,
                width: exportWidth,
                height: LayoutMetrics.actionButtonHeight
            )
            clearHistoryButton?.frame = NSRect(
                x: originX + exportWidth + 10,
                y: actionY,
                width: min(104, max(84, width - exportWidth - 10)),
                height: LayoutMetrics.actionButtonHeight
            )
        }

        func layoutSnippetShortcutRows(width: CGFloat) {
            let rowHeight: CGFloat = 42
            let documentHeight = max(CGFloat(snippetShortcutRows.count) * rowHeight, snippetShortcutScrollView?.bounds.height ?? 0)
            snippetShortcutDocumentView?.frame = NSRect(x: 0, y: 0, width: width, height: documentHeight)

            for (index, row) in snippetShortcutRows.enumerated() {
                let rowOriginY = documentHeight - CGFloat(index + 1) * rowHeight
                let clearWidth: CGFloat = 52
                let recordWidth: CGFloat = min(150, max(112, width * 0.32))
                let textWidth = max(80, width - recordWidth - clearWidth - 20)
                row.titleLabel.frame = NSRect(x: 0, y: rowOriginY + 22, width: textWidth, height: 15)
                row.detailLabel.frame = NSRect(x: 0, y: rowOriginY + 6, width: textWidth, height: 14)
                row.recordView.frame = NSRect(x: textWidth + 8, y: rowOriginY + 7, width: recordWidth, height: 28)
                row.clearButton.frame = NSRect(x: textWidth + recordWidth + 16, y: rowOriginY + 7, width: clearWidth, height: 28)
            }
        }

        func placeSnippetSettingsSection(originX: CGFloat, originY: CGFloat, width: CGFloat, scrollHeight: CGFloat) {
            let minimumBottomInset: CGFloat = 28
            let contentHeight = max(80, CGFloat(max(1, snippetShortcutRows.count)) * 42 + 8)
            let availableHeight = max(80, originY - 286 - minimumBottomInset)
            let safeScrollHeight = max(80, min(scrollHeight, min(280, min(contentHeight, availableHeight))))
            placeHeader(snippetSettingsSectionLabel, originX: originX, originY: originY, width: width)
            snippetSummaryLabel?.frame = NSRect(x: originX, y: originY - 42, width: width, height: 20)
            snippetFoldersLabel?.frame = NSRect(x: originX, y: originY - 74, width: width, height: 20)
            snippetGroupProNoteLabel?.frame = NSRect(x: originX, y: originY - 106, width: width, height: 30)
            let moveButtonWidth: CGFloat = 92
            let moveGap: CGFloat = 8
            let orderPopupWidth = max(120, width - (moveButtonWidth * 2) - (moveGap * 2))
            snippetGroupOrderPopup?.frame = NSRect(x: originX, y: originY - 146, width: orderPopupWidth, height: rowH)
            snippetGroupMoveUpButton?.frame = NSRect(x: originX + orderPopupWidth + moveGap, y: originY - 146, width: moveButtonWidth, height: rowH)
            snippetGroupMoveDownButton?.frame = NSRect(x: originX + orderPopupWidth + moveGap + moveButtonWidth + moveGap, y: originY - 146, width: moveButtonWidth, height: rowH)
            snippetShortcutsLabel?.frame = NSRect(x: originX, y: originY - 184, width: width, height: 20)
            snippetShortcutScrollView?.frame = NSRect(x: originX, y: originY - 196 - safeScrollHeight, width: width, height: safeScrollHeight)
            layoutSnippetShortcutRows(width: width)
            let manageButtonY = originY - 196 - safeScrollHeight - LayoutMetrics.actionButtonHeight - 14
            manageSnippetsButton?.frame = NSRect(x: originX, y: manageButtonY, width: min(156, width), height: LayoutMetrics.actionButtonHeight)
        }

        func placePrivacySection(originX: CGFloat, originY: CGFloat, width: CGFloat) {
            placeHeader(privacySectionLabel, originX: originX, originY: originY, width: width)
            hideMaskedPreviewButton?.frame = NSRect(x: originX, y: originY - 38, width: width, height: 20)
            hideMaskedTitleButton?.frame = NSRect(x: originX, y: originY - 68, width: width, height: 20)
            excludedAppsSummaryLabel?.frame = NSRect(x: originX, y: originY - 104, width: width, height: 18)
            excludedAppsButton?.frame = NSRect(x: originX, y: originY - 144, width: min(178, width), height: rowH)
        }

        func placeStoredTypesSection(originX: CGFloat, originY: CGFloat, width: CGFloat) {
            placeHeader(storedTypesSectionLabel, originX: originX, originY: originY, width: width)
            let buttonWidth = max(72, floor((width - 8) / 2))
            for (index, button) in storedTypeButtons.enumerated() {
                let column = index % 2
                let row = index / 2
                button.frame = NSRect(x: originX + CGFloat(column) * (buttonWidth + 8),
                                      y: originY - rowGap - CGFloat(row * 24),
                                      width: buttonWidth,
                                      height: 18)
            }
        }

        func placeFiltersSection(originX: CGFloat, originY: CGFloat, width: CGFloat) {
            placeHeader(filterSectionLabel, originX: originX, originY: originY, width: width)
            let addWidth: CGFloat = 52
            let modeWidth = min(112, max(92, floor(width * 0.34)))
            let textWidth = max(96, width - modeWidth - addWidth - 16)
            hideRuleModePopup?.frame = NSRect(x: originX, y: originY - rowGap - 6, width: modeWidth, height: rowH)
            hideRuleTextField?.frame = NSRect(x: originX + modeWidth + 8, y: originY - rowGap - 4, width: textWidth, height: rowH)
            addHideRuleButton?.frame = NSRect(x: originX + modeWidth + textWidth + 16, y: originY - rowGap - 6, width: addWidth, height: rowH)
            removeLastHideRuleButton?.frame = NSRect(x: originX, y: originY - (rowGap * 2) - 8, width: 100, height: rowH)
            clearHideRulesButton?.frame = NSRect(x: originX + 108, y: originY - (rowGap * 2) - 8, width: 64, height: rowH)
            hideRulesSummaryLabel?.frame = NSRect(x: originX, y: originY - (rowGap * 3) - 2, width: width, height: 18)
            hideRulesExamplesLabel?.frame = NSRect(x: originX, y: originY - (rowGap * 3) - 22, width: width, height: 18)
            hideRulesNoteLabel?.frame = NSRect(x: originX, y: originY - (rowGap * 3) - 42, width: width, height: 18)
        }

        func placeLabsSection(originX: CGFloat, originY: CGFloat, width: CGFloat) {
            placeHeader(labsSectionLabel, originX: originX, originY: originY, width: width)
            labsNoteLabel?.frame = NSRect(x: originX, y: originY - 30, width: width, height: 18)
        }

        func placeLicenseSection(originX: CGFloat, originY: CGFloat, width: CGFloat) {
            placeHeader(licenseSectionLabel, originX: originX, originY: originY, width: width)
            licensePlanLabel?.frame = NSRect(x: originX, y: originY - 34, width: width, height: 18)
            licenseStateLabel?.frame = NSRect(x: originX, y: originY - 58, width: width, height: 18)
            licenseLimitsLabel?.frame = NSRect(x: originX, y: originY - 82, width: width, height: 18)
            let buttonWidth: CGFloat = 106
            let upgradeWidth: CGFloat = min(126, width)
            let fieldWidth = max(120, width - buttonWidth - 12)
            licenseKeyField?.frame = NSRect(x: originX, y: originY - 124, width: fieldWidth, height: rowH)
            licenseActivateButton?.frame = NSRect(x: originX + fieldWidth + 12, y: originY - 126, width: buttonWidth, height: rowH)
            licenseActivationStatusLabel?.frame = NSRect(x: originX, y: originY - 166, width: width, height: 34)
            licenseUpgradeButton?.frame = NSRect(x: originX, y: originY - 208, width: upgradeWidth, height: rowH)
            licenseProLockedControlView?.frame = NSRect(x: originX, y: originY - 352, width: width, height: 126)
            licenseMockNoteLabel?.frame = NSRect(x: originX, y: originY - 400, width: width, height: 42)
            licenseStateExamplesLabel?.frame = NSRect(x: originX, y: originY - 436, width: width, height: 28)
        }

        func placeUpdatesSection(originX: CGFloat, originY: CGFloat, width: CGFloat) {
            let updatesWidth = min(width, updatesPreferenceView?.frame.width ?? width)
            updatesPreferenceView?.frame = NSRect(x: originX + floor((width - updatesWidth) / 2),
                                                  y: originY - 174,
                                                  width: updatesWidth,
                                                  height: 174)
        }

        refreshLicenseSummary()
        updateSettingsSidebarSelection()
        switch activeSettingsCategory {
        case .general:
            show(generalControls)
            placeGeneralSection(originX: leftX, originY: firstY, width: columnWidth)
            placeShortcutSection(originX: leftX, originY: firstY - 240, width: columnWidth)
        case .view:
            show(viewControls)
            placeViewSection(originX: leftX, originY: firstY, width: columnWidth)
        case .history:
            show(historyControls)
            placeHistorySection(originX: leftX, originY: firstY, width: columnWidth)
        case .snippets:
            show(snippetControls)
            placeSnippetSettingsSection(originX: leftX, originY: firstY, width: columnWidth, scrollHeight: max(160, topY - 300))
        case .privacy:
            show(privacyControls)
            storedTypeButtons.forEach { $0.isHidden = false }
            placePrivacySection(originX: leftX, originY: firstY, width: columnWidth)
            placeStoredTypesSection(originX: leftX, originY: firstY - 190, width: columnWidth)
            placeFiltersSection(originX: leftX, originY: firstY - 364, width: columnWidth)
        case .updates:
            show(updatesControls)
            placeUpdatesSection(originX: leftX, originY: firstY, width: columnWidth)
        case .license:
            show(licenseControls)
            placeLicenseSection(originX: leftX, originY: firstY, width: columnWidth)
        }
        refreshProFeatureAvailability()
    }

    fileprivate func reloadHistoryItems(_ items: [BoardManHistoryItem]) {
        allItems = items
        reloadSnippetCategoryPopup()
        applyCurrentFilter()
        if let table = placeholderList {
            makeFirstResponder(table)
        }
    }

    private var skipsPinnedKeyboardNavigation: Bool {
        return AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.boardManSkipPinnedInKeyboardNavigation)
    }

    private func keyboardNavigableRows() -> [Int] {
        let allRows = Array(historyItems.indices)
        guard skipsPinnedKeyboardNavigation else { return allRows }
        return allRows.filter { !historyItems[$0].isPinned }
    }

    fileprivate func focusTableForKeyboard() {
        guard activeTab != .settings else {
            makeFirstResponder(self)
            return
        }
        guard let table = placeholderList else { return }
        makeFirstResponder(table)
        if !historyItems.isEmpty, selectedIndex < 0 {
            selectedIndex = keyboardNavigableRows().first ?? -1
        }
        syncNativeSelection()
        makeFirstResponder(table)
        DispatchQueue.main.async { [weak self, weak table] in
            guard let self, let table else { return }
            self.makeFirstResponder(table)
        }
    }

    fileprivate func prepareForFirstVisibleOrder(frame finalFrame: NSRect) {
        alphaValue = 0
        setFrame(finalFrame, display: false, animate: false)
        layoutPanelSubviews()
    }

#if DEBUG
    private var benchmarkIsolationForTesting = false

    func setBenchmarkIsolationForTesting(_ enabled: Bool) {
        benchmarkIsolationForTesting = enabled
    }

    func loadItemsForTesting(_ items: [BoardManHistoryItem]) {
        reloadHistoryItems(items)
    }

    func setSearchQueryForTesting(_ query: String) {
        searchField?.stringValue = query
        selectedIndex = -1
        applyCurrentFilter()
    }

    var visibleItemCountForTesting: Int {
        return historyItems.count
    }

    @discardableResult
    func moveVerticalSelectionForTesting(delta: Int) -> Bool {
        return selectRowByKeyboard(delta: delta)
    }

    var selectedIndexForTesting: Int {
        return selectedIndex
    }

    func selectItem(at index: Int) {
        setSelectedIndex(index)
    }

    func selectItemForTesting(at index: Int) {
        selectItem(at: index)
    }

    func setSnippetGroupIdentifiersForTesting(_ identifiers: Set<String>) {
        setActiveSnippetGroupIdentifiers(identifiers)
        reloadSnippetCategoryPopup()
        applyCurrentFilter()
    }

    func reloadSnippetGroupsForTesting() {
        reloadSnippetCategoryPopup()
        applyCurrentFilter()
    }

    var activeSnippetGroupIdentifiersForTesting: Set<String> {
        return activeSnippetGroupIdentifiers
    }

    var activePanelTabForTesting: String {
        switch activeTab {
        case .history: return "history"
        case .snippets: return "snippets"
        case .settings: return "settings"
        }
    }

    func moveHorizontalNavigationForTesting(delta: Int) {
        moveHorizontalNavigation(delta: delta)
    }

    var visibleItemHashesForTesting: [String] {
        return historyItems.map(\.dataHash)
    }

#endif

    private var configuredTimestampInteraction: BoardManTimestampInteraction {
        return BoardManTimestampInteraction.allowed(
            AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManTimestampInteraction)
        )
    }

    private var configuredTimestampShortcut: KeyCombo {
        return BoardManTimestampShortcutStore.keyCombo()
    }

    private var configuredTimestampShortcutEnabled: Bool {
        return AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.boardManTimestampShortcutEnabled)
    }

    private var configuredTimestampShortcutDelay: TimeInterval {
        return BoardManPanel.clampedTimestampShortcutDelay(
            AppEnvironment.current.defaults.double(forKey: Constants.UserDefaults.boardManTimestampShortcutDelay)
        )
    }

    private var configuredLongPressAction: BoardManLongPressAction {
        return BoardManLongPressAction.allowed(
            AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManLongPressAction)
        )
    }

    private var configuredTimedPinDurationValue: Int {
        return BoardManTimedPinPresetStore.selectedPreset().value
    }

    private var configuredTimedPinUnit: BoardManTimedPinUnit {
        return BoardManTimedPinPresetStore.selectedPreset().unit
    }

    private func refreshTimedPinSettingsControls() {
        let presets = BoardManTimedPinPresetStore.presets()
        let selected = BoardManTimedPinPresetStore.selectedPreset()
        timedPinPresetPopup?.removeAllItems()
        presets.forEach { preset in
            timedPinPresetPopup?.addItem(withTitle: preset.title)
            timedPinPresetPopup?.lastItem?.representedObject = preset.id
        }
        if let item = timedPinPresetPopup?.itemArray.first(where: {
            ($0.representedObject as? String) == selected.id
        }) {
            timedPinPresetPopup?.select(item)
        }
        timedPinPresetRemoveButton?.isEnabled = presets.count > 1
        timedPinDurationStepper?.integerValue = selected.value
        timedPinDurationValueLabel?.stringValue = "\(selected.value)"
        if let item = timedPinDurationUnitPopup?.itemArray.first(where: {
            ($0.representedObject as? String) == selected.unit.rawValue
        }) {
            timedPinDurationUnitPopup?.select(item)
        }
        timedPinDurationLabel?.textColor = .labelColor
        timedPinPresetPopup?.isEnabled = true
        timedPinPresetAddButton?.isEnabled = true
        timedPinDurationStepper?.isEnabled = true
        timedPinDurationUnitPopup?.isEnabled = true
        timedPinDurationValueLabel?.isEnabled = true
        timedPinDurationValueLabel?.textColor = .labelColor
    }

    private func refreshTimestampShortcutControls() {
        let enabled = configuredTimestampShortcutEnabled
        timestampShortcutEnabledButton?.state = enabled ? .on : .off
        let delay = configuredTimestampShortcutDelay
        timestampShortcutDelayField?.doubleValue = delay
        timestampShortcutDelayStepper?.doubleValue = delay
        timestampShortcutRecordView?.alphaValue = 1
        timestampShortcutLabel?.textColor = .labelColor
        timestampShortcutDelayLabel?.textColor = .labelColor
        timestampShortcutSecondsLabel?.textColor = .secondaryLabelColor
        timestampShortcutDelayField?.isEnabled = true
        timestampShortcutDelayStepper?.isEnabled = true
    }

    @objc private func skipPinnedNavigationChanged(_ sender: NSButton) {
        AppEnvironment.current.defaults.set(
            sender.state == .on,
            forKey: Constants.UserDefaults.boardManSkipPinnedInKeyboardNavigation
        )
        selectedIndex = -1
        placeholderList?.deselectAll(nil)
        focusTableForKeyboard()
    }

    @objc private func longPressActionChanged(_ sender: NSPopUpButton) {
        let rawValue = sender.selectedItem?.representedObject as? String
        let action = BoardManLongPressAction.allowed(rawValue)
        AppEnvironment.current.defaults.set(action.rawValue, forKey: Constants.UserDefaults.boardManLongPressAction)
        refreshTimedPinSettingsControls()
        updateSnippetModeUI()
    }

    @objc private func timedPinPresetChanged(_ sender: NSPopUpButton) {
        guard let id = sender.selectedItem?.representedObject as? String else { return }
        BoardManTimedPinPresetStore.select(id)
        refreshTimedPinSettingsControls()
        updateSnippetModeUI()
    }

    @objc private func addTimedPinPreset(_ sender: Any?) {
        _ = BoardManTimedPinPresetStore.add()
        refreshTimedPinSettingsControls()
        layoutPanelSubviews()
    }

    @objc private func removeTimedPinPreset(_ sender: Any?) {
        guard BoardManTimedPinPresetStore.removeSelected() else {
            NSSound.beep()
            return
        }
        refreshTimedPinSettingsControls()
        layoutPanelSubviews()
    }

    @objc private func timedPinDurationChanged(_ sender: NSStepper) {
        let selected = BoardManTimedPinPresetStore.updateSelected(value: sender.integerValue)
        sender.integerValue = selected.value
        refreshTimedPinSettingsControls()
        updateSnippetModeUI()
    }

    @objc private func timedPinDurationFieldChanged(_ sender: NSTextField) {
        let selected = BoardManTimedPinPresetStore.updateSelected(value: sender.integerValue)
        sender.integerValue = selected.value
        refreshTimedPinSettingsControls()
        updateSnippetModeUI()
    }

    @objc private func adjustTimedPinDuration(_ sender: NSButton) {
        let current = timedPinDurationValueLabel?.integerValue ?? configuredTimedPinDurationValue
        _ = BoardManTimedPinPresetStore.updateSelected(value: current + sender.tag)
        refreshTimedPinSettingsControls()
        updateSnippetModeUI()
    }

    @objc private func timedPinDurationUnitChanged(_ sender: NSPopUpButton) {
        let rawValue = sender.selectedItem?.representedObject as? String
        _ = BoardManTimedPinPresetStore.updateSelected(unit: BoardManTimedPinUnit.allowed(rawValue))
        refreshTimedPinSettingsControls()
        updateSnippetModeUI()
    }

    @objc private func exportHistoryCSV(_ sender: Any?) {
        let clips = BoardManStores.authoritative.clipsSortedByCreatedTimeDescending()
        let counts = PasteCountStore.shared.countsSnapshot()
        let displayNames = HistoryDisplayNameStore.shared
        let permanentPins = PinnedSnippetStore.shared
        let timedPins = BoardManTimedPinStore.shared
        let rows = clips.map { clip in
            BoardManHistoryCSVRow(
                copiedAt: Date(timeIntervalSince1970: TimeInterval(clip.createdTime)),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(clip.updateTime)),
                displayName: displayNames.name(for: clip.dataHash) ?? "",
                content: clip.title,
                pasteCount: PasteCountStore.shared.count(for: clip, in: counts),
                isPinned: permanentPins.isPinned(clip.dataHash) || timedPins.isPinned(clip.dataHash),
                primaryType: clip.primaryType
            )
        }

        let panel = NSSavePanel()
        panel.title = boardManText("Export History CSV")
        panel.prompt = boardManText("Save")
        panel.allowedFileTypes = ["csv"]
        panel.canCreateDirectories = true
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        panel.nameFieldStringValue = "Board-Man-History-\(formatter.string(from: Date())).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try BoardManHistoryCSVExporter.csv(rows: Array(rows)).write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = boardManText("CSV export failed")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: boardManText("OK"))
            alert.runModal()
        }
    }

    @objc private func toggleAppearanceAdvancedSettings(_ sender: NSButton) {
        appearanceAdvancedExpanded.toggle()
        shouldScrollSettingsToTop = false
        sender.title = boardManText(appearanceAdvancedExpanded ? "Hide advanced settings" : "Show advanced settings")
        sender.image = NSImage(
            systemSymbolName: appearanceAdvancedExpanded ? "chevron.down" : "chevron.right",
            accessibilityDescription: nil
        )
        layoutPanelSubviews()
    }

    @objc private func previewScaleChanged(_ sender: NSSlider) {
        let value = Self.clampedPreviewScale(sender.integerValue)
        sender.integerValue = value
        let key = sender.tag == 1
            ? Constants.UserDefaults.boardManImagePreviewScale
            : Constants.UserDefaults.boardManTextPreviewScale
        AppEnvironment.current.defaults.set(value, forKey: key)
        if sender.tag == 1 {
            imagePreviewScaleValueLabel?.stringValue = "\(value)%"
        } else {
            textPreviewScaleValueLabel?.stringValue = "\(value)%"
        }
        hidePreviewBubble()
        refreshAppearancePreview()
    }

    @objc private func rowNumbersChanged(_ sender: NSButton) {
        AppEnvironment.current.defaults.set(sender.state == .on, forKey: Constants.UserDefaults.boardManShowRowNumbers)
        onRefreshRequested?()
        refreshAppearancePreview()
    }

    @objc private func timestampFormatChanged(_ sender: NSPopUpButton) {
        let selectedRaw = sender.selectedItem?.representedObject as? String ?? sender.titleOfSelectedItem
        let value = BoardManPanel.timestampFormat(forMenuTitle: selectedRaw)
        AppEnvironment.current.defaults.set(value, forKey: Constants.UserDefaults.boardManTimestampFormat)
        onRefreshRequested?()
        refreshAppearancePreview()
    }

    @objc private func relativeNumberStyleChanged(_ sender: NSPopUpButton) {
        let style = BoardManRelativeNumberStyle.allowed(sender.selectedItem?.representedObject as? String)
        AppEnvironment.current.defaults.set(style.rawValue, forKey: Constants.UserDefaults.boardManRelativeNumberStyle)
        onRefreshRequested?()
        refreshAppearancePreview()
    }

    @objc private func relativeUnitStyleChanged(_ sender: NSPopUpButton) {
        let style = BoardManRelativeUnitStyle.allowed(sender.selectedItem?.representedObject as? String)
        AppEnvironment.current.defaults.set(style.rawValue, forKey: Constants.UserDefaults.boardManRelativeUnitStyle)
        onRefreshRequested?()
        refreshAppearancePreview()
    }

    @objc private func relativeSuffixStyleChanged(_ sender: NSPopUpButton) {
        let style = BoardManRelativeSuffixStyle.allowed(sender.selectedItem?.representedObject as? String)
        AppEnvironment.current.defaults.set(style.rawValue, forKey: Constants.UserDefaults.boardManRelativeSuffixStyle)
        onRefreshRequested?()
        refreshAppearancePreview()
    }

    @objc private func relativeNowStyleChanged(_ sender: NSPopUpButton) {
        let style = BoardManRelativeNowStyle.allowed(sender.selectedItem?.representedObject as? String)
        AppEnvironment.current.defaults.set(style.rawValue, forKey: Constants.UserDefaults.boardManRelativeNowStyle)
        onRefreshRequested?()
        refreshAppearancePreview()
    }

    @objc private func timestampShortcutEnabledChanged(_ sender: NSButton) {
        AppEnvironment.current.defaults.set(
            sender.state == .on,
            forKey: Constants.UserDefaults.boardManTimestampShortcutEnabled
        )
        refreshTimestampShortcutControls()
    }

    @objc private func timestampShortcutDelayChanged(_ sender: NSStepper) {
        let value = BoardManPanel.clampedTimestampShortcutDelay(sender.doubleValue)
        sender.doubleValue = value
        AppEnvironment.current.defaults.set(value, forKey: Constants.UserDefaults.boardManTimestampShortcutDelay)
        refreshTimestampShortcutControls()
    }

    @objc private func timestampShortcutDelayFieldChanged(_ sender: NSTextField) {
        let value = BoardManPanel.clampedTimestampShortcutDelay(sender.doubleValue)
        sender.doubleValue = value
        AppEnvironment.current.defaults.set(value, forKey: Constants.UserDefaults.boardManTimestampShortcutDelay)
        refreshTimestampShortcutControls()
    }

    @objc private func adjustTimestampShortcutDelay(_ sender: NSButton) {
        let current = timestampShortcutDelayField?.doubleValue ?? configuredTimestampShortcutDelay
        let value = BoardManPanel.clampedTimestampShortcutDelay(current + (Double(sender.tag) * 0.1))
        AppEnvironment.current.defaults.set(value, forKey: Constants.UserDefaults.boardManTimestampShortcutDelay)
        refreshTimestampShortcutControls()
    }

    @objc private func timestampInteractionChanged(_ sender: NSPopUpButton) {
        let rawValue = sender.selectedItem?.representedObject as? String
        let interaction = BoardManTimestampInteraction.allowed(rawValue)
        AppEnvironment.current.defaults.set(
            interaction.rawValue,
            forKey: Constants.UserDefaults.boardManTimestampInteraction
        )
    }

    @objc private func timestampPositionChanged(_ sender: NSPopUpButton) {
        let selectedRaw = sender.selectedItem?.representedObject as? String ?? sender.titleOfSelectedItem
        let position = BoardManTimestampPosition.allowed(selectedRaw)
        AppEnvironment.current.defaults.set(position.rawValue.lowercased(),
                                            forKey: Constants.UserDefaults.boardManTimestampPosition)
        if position != .hidden,
           BoardManPanel.allowedTimestampFormat(AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManTimestampFormat)) == "none" {
            AppEnvironment.current.defaults.set("relative", forKey: Constants.UserDefaults.boardManTimestampFormat)
            if let relativeItem = timestampPopup?.itemArray.first(where: { ($0.representedObject as? String) == "Relative" }) {
                timestampPopup?.select(relativeItem)
            }
        }
        onRefreshRequested?()
        refreshAppearancePreview()
    }

    @objc private func usageCountChanged(_ sender: NSButton) {
        AppEnvironment.current.defaults.set(sender.state == .on, forKey: Constants.UserDefaults.boardManShowUsageCount)
        onRefreshRequested?()
        refreshAppearancePreview()
    }

    @objc private func usageStyleChanged(_ sender: NSPopUpButton) {
        let selectedRaw = sender.selectedItem?.representedObject as? String ?? sender.titleOfSelectedItem
        AppEnvironment.current.defaults.set(BoardManPanel.allowedUsageCountStyle(selectedRaw),
                                            forKey: Constants.UserDefaults.boardManUsageCountStyle)
        onRefreshRequested?()
        refreshAppearancePreview()
    }

    @objc private func usedItemStyleChanged(_ sender: NSPopUpButton) {
        let selectedRaw = sender.selectedItem?.representedObject as? String ?? sender.titleOfSelectedItem
        AppEnvironment.current.defaults.set(BoardManPanel.allowedUsedItemStyle(selectedRaw),
                                            forKey: Constants.UserDefaults.boardManUsedItemStyle)
        placeholderList?.reloadData()
        synchronizeListGeometry()
        refreshAppearancePreview()
    }

    @objc private func pinLabelStyleChanged(_ sender: NSPopUpButton) {
        let rawValue = sender.selectedItem?.representedObject as? String ?? sender.titleOfSelectedItem
        let style = BoardManPinLabelStyle.allowed(rawValue)
        AppEnvironment.current.defaults.set(style.rawValue, forKey: Constants.UserDefaults.boardManPinLabelStyle)
        placeholderList?.reloadData()
        synchronizeListGeometry()
    }

    @objc private func showInlineImagesChanged(_ sender: NSButton) {
        AppEnvironment.current.defaults.set(sender.state == .on, forKey: Constants.UserDefaults.boardManShowInlineImages)
        inlineImagePositionPopup?.isEnabled = sender.state == .on
        placeholderList?.reloadData()
        synchronizeListGeometry()
    }

    @objc private func inlineImagePositionChanged(_ sender: NSPopUpButton) {
        let rawValue = sender.selectedItem?.representedObject as? String ?? sender.titleOfSelectedItem
        let position = BoardManInlineImagePosition.allowed(rawValue)
        AppEnvironment.current.defaults.set(position.rawValue, forKey: Constants.UserDefaults.boardManInlineImagePosition)
        placeholderList?.reloadData()
        synchronizeListGeometry()
    }

    @objc private func themePresetChanged(_ sender: NSPopUpButton) {
        let rawValue = sender.selectedItem?.representedObject as? String
        let preset = BoardManThemePreset.allowed(rawValue)
        AppEnvironment.current.defaults.set(preset.rawValue, forKey: Constants.UserDefaults.boardManThemePreset)
        applyLiquidGlassStyle()
        layoutPanelSubviews()
        placeholderList?.reloadData()
        synchronizeListGeometry()
        contentView?.needsDisplay = true
    }

    @objc private func appearanceModeChanged(_ sender: NSPopUpButton) {
        let selectedRaw = sender.selectedItem?.representedObject as? String ?? sender.titleOfSelectedItem
        let mode = BoardManAppearanceMode.allowed(selectedRaw)
        AppEnvironment.current.defaults.set(mode.rawValue, forKey: Constants.UserDefaults.boardManAppearanceMode)
        applyLiquidGlassStyle()
        layoutPanelSubviews()
        contentView?.needsDisplay = true
    }

    @objc private func uiStyleChanged(_ sender: NSPopUpButton) {
        let selectedRaw = sender.selectedItem?.representedObject as? String ?? sender.titleOfSelectedItem
        let style = BoardManUIStyle.allowed(selectedRaw)
        AppEnvironment.current.defaults.set(style.rawValue, forKey: Constants.UserDefaults.boardManUIStyle)
        applyLiquidGlassStyle()
        layoutPanelSubviews()
        placeholderList?.reloadData()
        synchronizeListGeometry()
        contentView?.needsDisplay = true
    }

    @objc private func fontChoiceChanged(_ sender: NSPopUpButton) {
        let choice = BoardManFontChoice.allowed(sender.titleOfSelectedItem)
        AppEnvironment.current.defaults.set(choice.rawValue, forKey: Constants.UserDefaults.boardManFontChoice)
        applyTypography()
        layoutPanelSubviews()
        placeholderList?.reloadData()
        synchronizeListGeometry()
        refreshAppearancePreview()
        contentView?.needsDisplay = true
    }

    private func applyItemTextScale(_ rawValue: Int) {
        let value = Self.clampedItemTextScale(rawValue)
        itemTextScaleField?.integerValue = value
        AppEnvironment.current.defaults.set(value, forKey: Constants.UserDefaults.boardManItemTextScale)
        placeholderList?.reloadData()
        synchronizeListGeometry()
        refreshAppearancePreview()
    }

    @objc private func itemTextScaleFieldChanged(_ sender: NSTextField) {
        applyItemTextScale(sender.integerValue)
    }

    @objc private func adjustItemTextScale(_ sender: NSButton) {
        let current = itemTextScaleField?.integerValue ?? Self.clampedItemTextScale(
            AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.boardManItemTextScale)
        )
        applyItemTextScale(current + (sender.tag * 5))
    }

    @objc private func themeLightenChanged(_ sender: NSButton) {
        AppEnvironment.current.defaults.set(sender.state == .on, forKey: Constants.UserDefaults.boardManThemeLighten)
        applyLiquidGlassStyle()
        layoutPanelSubviews()
        placeholderList?.reloadData()
        synchronizeListGeometry()
        contentView?.needsDisplay = true
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        let language = BoardManLanguage.allowed(sender.titleOfSelectedItem)
        AppEnvironment.current.defaults.set(language.rawValue, forKey: Constants.UserDefaults.boardManLanguage)
        applyLocalizedStrings()
        layoutPanelSubviews()
        contentView?.needsDisplay = true
    }

    @objc private func customColorChanged(_ sender: NSColorWell) {
        let key: String
        switch sender.tag {
        case 1: key = Constants.UserDefaults.boardManCustomPanelColor
        case 2: key = Constants.UserDefaults.boardManCustomUsedColor
        default: key = Constants.UserDefaults.boardManCustomAccentColor
        }
        BoardManPanel.storeCustomColor(sender.color, forKey: key)
        applyLiquidGlassStyle()
        placeholderList?.reloadData()
        contentView?.needsDisplay = true
    }

    @objc private func customOpacityChanged(_ sender: NSSlider) {
        let key: String
        switch sender.tag {
        case 1: key = Constants.UserDefaults.boardManCustomPanelOpacity
        case 2: key = Constants.UserDefaults.boardManCustomUsedOpacity
        default: key = Constants.UserDefaults.boardManCustomAccentOpacity
        }
        AppEnvironment.current.defaults.set(sender.doubleValue, forKey: key)
        applyLiquidGlassStyle()
        placeholderList?.reloadData()
        contentView?.needsDisplay = true
    }

    @objc private func resetCustomColors(_ sender: Any?) {
        let defaults = AppEnvironment.current.defaults
        [
            Constants.UserDefaults.boardManCustomAccentColor,
            Constants.UserDefaults.boardManCustomPanelColor,
            Constants.UserDefaults.boardManCustomUsedColor
        ].forEach { defaults.removeObject(forKey: $0) }
        defaults.set(1.0, forKey: Constants.UserDefaults.boardManCustomAccentOpacity)
        defaults.set(0.16, forKey: Constants.UserDefaults.boardManCustomPanelOpacity)
        defaults.set(0.18, forKey: Constants.UserDefaults.boardManCustomUsedOpacity)
        customAccentColorWell?.color = selectedThemePreset.accentColor
        customPanelColorWell?.color = selectedThemePreset.tintColor
        customUsedColorWell?.color = .systemGray
        customAccentOpacitySlider?.doubleValue = 1.0
        customPanelOpacitySlider?.doubleValue = 0.16
        customUsedOpacitySlider?.doubleValue = 0.18
        applyLiquidGlassStyle()
        placeholderList?.reloadData()
        contentView?.needsDisplay = true
    }

    private func setControlTree(_ view: NSView?, enabled: Bool, alpha: CGFloat) {
        guard let view else { return }
        if let control = view as? NSControl {
            control.isEnabled = enabled
        }
        view.alphaValue = alpha
        view.subviews.forEach { subview in
            if let control = subview as? NSControl {
                control.isEnabled = enabled
            }
        }
    }

    private func refreshProFeatureAvailability() {
        // All controls in these sections are local Board-Man capabilities and stay available
        // regardless of account or service entitlement. Only connected services are commercial.
        [
            customAccentLabel, customAccentColorWell, customAccentOpacitySlider,
            customPanelLabel, customPanelColorWell, customPanelOpacitySlider,
            customUsedColorLabel, customUsedColorWell, customUsedOpacitySlider,
            resetCustomColorsButton,
            textPreviewScaleLabel, textPreviewScaleSlider, textPreviewScaleValueLabel,
            imagePreviewScaleLabel, imagePreviewScaleSlider, imagePreviewScaleValueLabel
        ].forEach { setControlTree($0, enabled: true, alpha: 1) }

        let storedTextScale = Self.clampedPreviewScale(
            AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.boardManTextPreviewScale)
        )
        let storedImageScale = Self.clampedPreviewScale(
            AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.boardManImagePreviewScale)
        )
        textPreviewScaleSlider?.integerValue = storedTextScale
        imagePreviewScaleSlider?.integerValue = storedImageScale
        textPreviewScaleValueLabel?.stringValue = "\(storedTextScale)%"
        imagePreviewScaleValueLabel?.stringValue = "\(storedImageScale)%"
        previewScaleProNoteLabel?.isHidden = true

        [snippetGroupOrderPopup, snippetGroupMoveUpButton, snippetGroupMoveDownButton].forEach {
            setControlTree($0, enabled: true, alpha: 1)
        }
        snippetShortcutRows.flatMap { $0.views }.forEach { setControlTree($0, enabled: true, alpha: 1) }
        snippetGroupProNoteLabel?.isHidden = true

        [snippetCategoryAddButton, snippetCategoryRenameButton, snippetCategoryDeleteButton, snippetReorderModeButton].forEach {
            setControlTree($0, enabled: true, alpha: 1)
        }
        snippetFolderEnableButton?.alphaValue = 1
    }

    private var selectedSnippetItem: BoardManHistoryItem? {
        guard selectedIndex >= 0,
              let item = historyItems[safe: selectedIndex],
              item.source == .snippet else {
            return nil
        }
        return item
    }

    private func updateSnippetActionButtons() {
        let isSnippetsTab = activeTab == .snippets
        let selectedItem = selectedSnippetItem
        let hasSelection = selectedItem != nil
        let isEditingSelection = isSnippetEditing && editingSnippetIdentifier == selectedItem?.dataHash
        snippetAddButton?.isEnabled = isSnippetsTab && !isSnippetReorderMode
        snippetEditButton?.isEnabled = isSnippetsTab && hasSelection && !isSnippetReorderMode
        snippetDeleteButton?.isEnabled = isSnippetsTab && hasSelection && !isSnippetEditing && !isSnippetReorderMode
        snippetSaveButton?.isEnabled = isSnippetsTab && isEditingSelection
        snippetCancelEditButton?.isEnabled = isSnippetsTab && isEditingSelection
        snippetEnableButton?.isEnabled = isSnippetsTab && isEditingSelection
        let canManageSelectedCategory = isSnippetsTab && selectedCategoryFolder() != nil && !isSnippetEditing
        snippetCategoryRenameButton?.isEnabled = canManageSelectedCategory && !isSnippetReorderMode
        snippetCategoryDeleteButton?.isEnabled = canManageSelectedCategory && !isSnippetReorderMode
        snippetFolderEnableButton?.isEnabled = isSnippetsTab && isEditingSelection && editorFolder() != nil
        updateSnippetModeUI()
        refreshSnippetEditor()
        refreshProFeatureAvailability()
    }

    private func updateSnippetModeUI() {
        guard activeTab == .snippets else { return }
        let presentation = BoardManSnippetPresentation.reorderState(
            hasReorderableCategory: activeSnippetCategoryIdentifier != BoardManPanel.allCategoriesIdentifier,
            snippetCount: historyItems.filter { $0.source == .snippet }.count,
            isEditing: isSnippetEditing,
            requestedReorderMode: isSnippetReorderMode
        )
        isSnippetReorderMode = presentation.isReordering
        itemLongPressGesture?.isEnabled = !presentation.isReordering
        itemLongPressGesture?.delaysPrimaryMouseButtonEvents = !presentation.isReordering
        snippetReorderModeButton?.isEnabled = presentation.buttonEnabled
        snippetReorderModeButton?.state = presentation.isReordering ? .on : .off
        snippetReorderModeButton?.title = presentation.buttonTitle
        snippetReorderModeButton?.toolTip = presentation.toolTip
        snippetInteractionHintLabel?.stringValue = presentation.hint
        snippetInteractionHintLabel?.textColor = presentation.emphasizesHint ? themeAccentColor : .secondaryLabelColor
        if presentation.emphasizesHint {
            snippetInteractionHintLabel?.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        }
    }

    @objc private func toggleSnippetReorderMode(_ sender: NSButton) {
        if activeSnippetCategoryIdentifier == BoardManPanel.allCategoriesIdentifier,
           let categoryIdentifier = selectedSnippetItem?.categoryIdentifier {
            setActiveSnippetGroupIdentifiers([categoryIdentifier])
            reloadSnippetCategoryPopup()
            applyCurrentFilter()
        }
        guard activeSnippetCategoryIdentifier != BoardManPanel.allCategoriesIdentifier else {
            NSSound.beep()
            sender.state = .off
            return
        }
        isSnippetEditing = false
        editingSnippetIdentifier = nil
        isSnippetReorderMode = sender.state == .on
        itemLongPressGesture?.isEnabled = !isSnippetReorderMode
        itemLongPressGesture?.delaysPrimaryMouseButtonEvents = !isSnippetReorderMode
        makeFirstResponder(placeholderList)
        updateSnippetActionButtons()
        placeholderList?.reloadData()
    }

    private func editorFolder() -> BoardManFolder? {
        if let folder = selectedCategoryFolder() {
            return folder
        }
        guard let item = selectedSnippetItem,
              let identifier = item.categoryIdentifier,
              identifier != BoardManPanel.uncategorizedCategoryIdentifier else {
            return nil
        }
        return store.folder(identifier: identifier)
    }

    private func refreshSnippetEditor() {
        guard activeTab == .snippets else { return }
        let folder = editorFolder()
        let presentation: BoardManSnippetEditorState
        var isEditingSelection = false

        if let item = selectedSnippetItem,
           let snippet = store.snippet(identifier: item.dataHash) {
            isEditingSelection = isSnippetEditing && editingSnippetIdentifier == item.dataHash
            if isSnippetEditing && !isEditingSelection {
                isSnippetEditing = false
                editingSnippetIdentifier = nil
            }
            presentation = BoardManSnippetPresentation.editorState(
                selection: BoardManSnippetEditorSelection(
                    title: snippet.title,
                    content: snippet.content,
                    snippetEnabled: snippet.enable,
                    folderEnabled: folder?.enable ?? false
                ),
                isEditingSelection: isEditingSelection,
                isReorderMode: isSnippetReorderMode
            )
        } else {
            isSnippetEditing = false
            editingSnippetIdentifier = nil
            presentation = .empty
        }

        if presentation.shouldRefreshValues {
            snippetEditorTitleField?.stringValue = presentation.title
            snippetEditorTextView?.string = presentation.content
            snippetEnableButton?.state = presentation.snippetEnabled ? .on : .off
            if let folderEnabled = presentation.folderEnabled {
                snippetFolderEnableButton?.state = folderEnabled ? .on : .off
            }
        }
        snippetEditorTitleField?.isEnabled = presentation.titleEnabled
        snippetEditorTitleField?.isEditable = presentation.titleEditable
        snippetEditorTitleField?.isSelectable = presentation.titleSelectable
        snippetEditorTextView?.isEditable = presentation.contentEditable
        snippetEditorTextView?.isSelectable = presentation.contentSelectable
        snippetEditorStatusLabel?.isHidden = true
        snippetEditorStatusLabel?.stringValue = ""
        snippetEditorStatusLabel?.layer?.backgroundColor = NSColor.clear.cgColor
        snippetEditorView?.layer?.borderWidth = 1
        snippetEditorView?.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        if isEditingSelection {
            snippetSaveButton?.title = boardManText("Save Changes")
        }
    }

    private func setActiveSnippetGroupIdentifiers(_ identifiers: Set<String>) {
        activeSnippetGroupIdentifiers = identifiers
        activeSnippetCategoryIdentifier = identifiers.count == 1
            ? (identifiers.first ?? BoardManPanel.allCategoriesIdentifier)
            : BoardManPanel.allCategoriesIdentifier
    }

    private func reloadSnippetCategoryPopup() {
        guard let popup = snippetCategoryPopup else { return }
        let folders = store.foldersSortedByIndex()
        let includesUncategorized = allItems.contains {
            $0.categoryIdentifier == BoardManPanel.uncategorizedCategoryIdentifier
        }
        setActiveSnippetGroupIdentifiers(BoardManSnippetPresentation.validGroupIdentifiers(
            activeIdentifiers: activeSnippetGroupIdentifiers,
            folders: folders,
            includesUncategorized: includesUncategorized,
            uncategorizedIdentifier: BoardManPanel.uncategorizedCategoryIdentifier
        ))

        popup.removeAllItems()
        popup.addItem(withTitle: BoardManSnippetPresentation.groupSummaryTitle(
            activeIdentifiers: activeSnippetGroupIdentifiers,
            folders: folders,
            uncategorizedIdentifier: BoardManPanel.uncategorizedCategoryIdentifier
        ))
        popup.lastItem?.representedObject = "__boardman_group_summary__"
        popup.lastItem?.isEnabled = false
        popup.menu?.addItem(.separator())
        addCategoryMenuItem(
            to: popup,
            title: boardManText("All Groups"),
            identifier: BoardManPanel.allCategoriesIdentifier,
            isSelected: activeSnippetGroupIdentifiers.isEmpty
        )
        folders.forEach { folder in
            let title = folder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? boardManText("Untitled folder")
                : folder.title
            addCategoryMenuItem(
                to: popup,
                title: title,
                identifier: folder.identifier,
                isSelected: activeSnippetGroupIdentifiers.contains(folder.identifier)
            )
        }
        if includesUncategorized {
            addCategoryMenuItem(
                to: popup,
                title: boardManText("Uncategorized"),
                identifier: BoardManPanel.uncategorizedCategoryIdentifier,
                isSelected: activeSnippetGroupIdentifiers.contains(BoardManPanel.uncategorizedCategoryIdentifier)
            )
        }
        if activeSnippetGroupIdentifiers.isEmpty,
           let allItem = popup.itemArray.first(where: {
               ($0.representedObject as? String) == BoardManPanel.allCategoriesIdentifier
           }) {
            popup.select(allItem)
        } else {
            popup.selectItem(at: 0)
        }
        popup.toolTip = activeSnippetGroupIdentifiers.isEmpty
            ? boardManText("All Groups")
            : activeSnippetGroupIdentifiers.sorted().joined(separator: ", ")
        updateSnippetActionButtons()
    }

    private func addCategoryMenuItem(to popup: NSPopUpButton,
                                     title: String,
                                     identifier: String,
                                     isSelected: Bool) {
        popup.addItem(withTitle: title)
        popup.lastItem?.representedObject = identifier
        popup.lastItem?.state = isSelected ? .on : .off
    }

    private func selectedCategoryFolder() -> BoardManFolder? {
        guard activeSnippetCategoryIdentifier != BoardManPanel.allCategoriesIdentifier,
              activeSnippetCategoryIdentifier != BoardManPanel.uncategorizedCategoryIdentifier else {
            return nil
        }
        return store.folder(identifier: activeSnippetCategoryIdentifier)
    }

    @objc private func snippetCategoryFilterChanged(_ sender: NSPopUpButton) {
        guard let identifier = sender.selectedItem?.representedObject as? String else {
            reloadSnippetCategoryPopup()
            return
        }
        var identifiers = activeSnippetGroupIdentifiers
        if identifier == BoardManPanel.allCategoriesIdentifier {
            identifiers.removeAll()
        } else if identifiers.contains(identifier) {
            identifiers.remove(identifier)
        } else {
            identifiers.insert(identifier)
        }
        setActiveSnippetGroupIdentifiers(identifiers)
        isSnippetEditing = false
        editingSnippetIdentifier = nil
        isSnippetReorderMode = false
        selectedIndex = -1
        hoveredRow = -1
        hidePreviewBubble()
        reloadSnippetCategoryPopup()
        applyCurrentFilter()
        updateSnippetActionButtons()
    }

    @objc private func addSnippetCategoryFromPanel(_ sender: Any?) {
        guard let title = BoardManSnippetDialogCoordinator.promptCategoryTitle(
            on: self,
            title: boardManText("Add Group"),
            initialTitle: ""
        ) else { return }
        let folder = BoardManSnippetCatalogService.createFolder(title: title, store: store)
        setActiveSnippetGroupIdentifiers([folder.identifier])
        onRefreshRequested?()
    }

    @objc private func renameSnippetCategoryFromPanel(_ sender: Any?) {
        guard let folder = selectedCategoryFolder(),
              let title = BoardManSnippetDialogCoordinator.promptCategoryTitle(
                on: self,
                title: boardManText("Rename Group"),
                initialTitle: folder.title
              ) else { return }
        BoardManSnippetCatalogService.renameFolder(folder, title: title, store: store)
        onRefreshRequested?()
    }

    @objc private func deleteSnippetCategoryFromPanel(_ sender: Any?) {
        guard let folder = selectedCategoryFolder() else {
            NSSound.beep()
            return
        }
        guard BoardManSnippetDialogCoordinator.confirmDeleteGroup(title: folder.title, on: self) else { return }
        guard let fallbackFolder = BoardManSnippetCatalogService.deleteFolder(
            identifier: folder.identifier,
            store: store
        ) else { return }
        setActiveSnippetGroupIdentifiers([fallbackFolder.identifier])
        selectedIndex = -1
        onRefreshRequested?()
        refreshSnippetEditor()
    }

    @objc private func addSnippetFromPanel(_ sender: Any?) {
        let creation = BoardManSnippetCatalogService.createSnippet(
            preferredFolderIdentifier: activeSnippetCategoryIdentifier,
            allCategoriesIdentifier: BoardManPanel.allCategoriesIdentifier,
            uncategorizedIdentifier: BoardManPanel.uncategorizedCategoryIdentifier,
            store: store
        )
        setActiveSnippetGroupIdentifiers([creation.folder.identifier])
        onRefreshRequested?()
        selectSnippetInCurrentList(identifier: creation.snippet.identifier)
        isSnippetEditing = true
        editingSnippetIdentifier = creation.snippet.identifier
        updateSnippetActionButtons()
        snippetEditorTitleField?.selectText(nil)
    }

    private func showProLockedAlert(message: String) {
        NSSound.beep()
        let alert = NSAlert()
        alert.messageText = boardManText("Pro limit reached")
        alert.informativeText = message
        alert.addButton(withTitle: boardManText("OK"))
        alert.runModal()
    }

    @objc private func editSelectedSnippetFromPanel(_ sender: Any?) {
        beginSnippetEditing()
    }

    @objc private func snippetTitleFieldChanged(_ sender: NSTextField) {
        guard activeTab == .snippets,
              !isSnippetReorderMode,
              !isSnippetEditing,
              let item = selectedSnippetItem else { return }
        guard let snippet = store.snippet(identifier: item.dataHash) else { return }
        let title = normalizedSnippetTitle(sender.stringValue)
        sender.stringValue = title
        snippet.title = title
        store.upsertSnippet(
            snippet,
            folderIdentifier: store.folderIdentifier(forSnippetIdentifier: snippet.identifier)
        )
        syncLinkedHistoryDisplayName(snippetIdentifier: snippet.identifier, title: title)
        onRefreshRequested?()
        selectSnippetInCurrentList(identifier: snippet.identifier)
        snippetEditorStatusLabel?.stringValue = boardManText("Saved")
    }

    @objc private func snippetEditorClicked(_ gesture: NSClickGestureRecognizer) {
        guard gesture.state == .ended,
              activeTab == .snippets,
              !isSnippetEditing,
              selectedSnippetItem != nil else { return }
        beginSnippetEditing()
    }

    private func beginSnippetEditing() {
        pendingSnippetSingleClickWorkItem?.cancel()
        pendingSnippetSingleClickWorkItem = nil
        guard let item = selectedSnippetItem else {
            NSSound.beep()
            return
        }
        isSnippetReorderMode = false
        isSnippetEditing = true
        editingSnippetIdentifier = item.dataHash
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        updateSnippetActionButtons()
    }

    @objc private func cancelSnippetEditing(_ sender: Any?) {
        isSnippetEditing = false
        editingSnippetIdentifier = nil
        makeFirstResponder(placeholderList)
        refreshSnippetEditor()
        updateSnippetActionButtons()
        snippetEditorStatusLabel?.stringValue = boardManText("Changes discarded")
    }

    @objc private func saveSelectedSnippetFromPanel(_ sender: Any?) {
        guard isSnippetEditing,
              let item = selectedSnippetItem,
              editingSnippetIdentifier == item.dataHash else {
            NSSound.beep()
            return
        }
        guard let snippet = store.snippet(identifier: item.dataHash) else {
            NSSound.beep()
            onRefreshRequested?()
            return
        }
        let content = snippetEditorTextView?.string ?? ""
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showSnippetValidationAlert(message: boardManText("Snippet content is required."))
            return
        }
        let savedFolder = editorFolder()
        let savedTitle = normalizedSnippetTitle(snippetEditorTitleField?.stringValue ?? "")
        BoardManSnippetEditingPolicy.persist(
            draft: BoardManSnippetDraft(
                title: savedTitle,
                content: content,
                snippetEnabled: snippetEnableButton?.state == .on,
                folderEnabled: snippetFolderEnableButton?.state == .on,
                canEditFolder: savedFolder != nil
            ),
            snippet: snippet,
            folder: savedFolder,
            store: store
        )
        syncLinkedHistoryDisplayName(snippetIdentifier: snippet.identifier, title: savedTitle)
        isSnippetEditing = false
        editingSnippetIdentifier = nil
        onRefreshRequested?()
        selectSnippetInCurrentList(identifier: snippet.identifier)
        refreshSnippetEditor()
        updateSnippetActionButtons()
        snippetEditorStatusLabel?.stringValue = boardManText("Saved")
    }

    @objc private func snippetFolderEnableChanged(_ sender: NSButton) {
        guard isSnippetEditing, editorFolder() != nil else {
            NSSound.beep()
            sender.state = editorFolder()?.enable == true ? .on : .off
            return
        }
    }

    @objc private func snippetEnableChanged(_ sender: NSButton) {
        guard isSnippetEditing, selectedSnippetItem != nil else {
            NSSound.beep()
            sender.state = selectedSnippetItem?.isEnabled == true ? .on : .off
            return
        }
    }

    @objc private func deleteSelectedSnippetFromPanel(_ sender: Any?) {
        guard let item = selectedSnippetItem else {
            NSSound.beep()
            return
        }
        guard BoardManSnippetDialogCoordinator.confirmDeleteSnippet(title: item.primaryTitle, on: self) else { return }
        guard BoardManSnippetCatalogService.deleteSnippet(identifier: item.dataHash, store: store) else {
            onRefreshRequested?()
            return
        }
        PinnedSnippetStore.shared.remove(item.dataHash)
        BoardManMaskedItemStore.shared.remove([item.dataHash])
        HistorySnippetLinkStore.shared.unlinkSnippet(item.dataHash)
        selectedIndex = -1
        onRefreshRequested?()
        refreshSnippetEditor()
    }

    private func selectSnippetInCurrentList(identifier: String) {
        applyCurrentFilter()
        guard let row = historyItems.firstIndex(where: { $0.source == .snippet && $0.dataHash == identifier }) else { return }
        setSelectedIndex(row)
        refreshSnippetEditor()
    }

    private func normalizedSnippetTitle(_ title: String) -> String {
        BoardManSnippetCatalogService.normalizedSnippetTitle(title)
    }

    private func showSnippetValidationAlert(message: String) {
        BoardManSnippetDialogCoordinator.showValidation(message: message, on: self)
    }

    @discardableResult
    private func runSnippetPanelAlert(
        _ alert: NSAlert,
        initialFirstResponder: NSView? = nil
    ) -> NSApplication.ModalResponse {
        BoardManSnippetDialogCoordinator.run(
            alert,
            on: self,
            initialFirstResponder: initialFirstResponder
        )
    }

    private func populateCategoryPopup(_ popup: NSPopUpButton, selectedIdentifier: String) {
        popup.removeAllItems()
        let folders = store.foldersSortedByIndex()
        let effectiveIdentifier = selectedIdentifier == BoardManPanel.allCategoriesIdentifier
            ? (folders.first?.identifier ?? BoardManPanel.uncategorizedCategoryIdentifier)
            : selectedIdentifier
        folders.forEach { folder in
            let title = folder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "untitled folder" : folder.title
            addCategoryMenuItem(
                to: popup,
                title: title,
                identifier: folder.identifier,
                isSelected: folder.identifier == effectiveIdentifier
            )
        }
        addCategoryMenuItem(
            to: popup,
            title: "Uncategorized",
            identifier: BoardManPanel.uncategorizedCategoryIdentifier,
            isSelected: effectiveIdentifier == BoardManPanel.uncategorizedCategoryIdentifier
        )
        if let item = popup.itemArray.first(where: { ($0.representedObject as? String) == effectiveIdentifier }) {
            popup.select(item)
        }
    }

    private func snippetTargetFolder(preferredIdentifier: String) -> BoardManFolder {
        BoardManSnippetCatalogService.targetFolder(
            preferredIdentifier: preferredIdentifier,
            allCategoriesIdentifier: BoardManPanel.allCategoriesIdentifier,
            uncategorizedIdentifier: BoardManPanel.uncategorizedCategoryIdentifier,
            store: store
        )
    }

    private func defaultSnippetFolder() -> BoardManFolder {
        BoardManSnippetCatalogService.defaultFolder(store: store)
    }

    private func uncategorizedFolder(excluding excludedIdentifier: String? = nil) -> BoardManFolder {
        BoardManSnippetCatalogService.uncategorizedFolder(
            excluding: excludedIdentifier,
            store: store
        )
    }

    private func moveSnippet(_ snippet: BoardManSnippet, toCategoryIdentifier categoryIdentifier: String) {
        BoardManSnippetCatalogService.moveSnippet(
            snippet,
            toCategoryIdentifier: categoryIdentifier,
            allCategoriesIdentifier: BoardManPanel.allCategoriesIdentifier,
            uncategorizedIdentifier: BoardManPanel.uncategorizedCategoryIdentifier,
            store: store
        )
    }

    private func applyPanelHeight(_ rawValue: Int) {
        let height = BoardManPanel.clampedPanelHeight(rawValue)
        heightStepper?.integerValue = height
        heightLabel?.integerValue = height
        AppEnvironment.current.defaults.set(height, forKey: Constants.UserDefaults.boardManPanelHeight)
        var frame = self.frame
        frame.origin.y += frame.height - CGFloat(height)
        frame.size.height = CGFloat(height)
        setFrame(frame, display: true, animate: false)
        layoutPanelSubviews()
    }

    @objc private func panelHeightChanged(_ sender: NSStepper) {
        applyPanelHeight(sender.integerValue)
    }

    @objc private func panelHeightFieldChanged(_ sender: NSTextField) {
        applyPanelHeight(sender.integerValue)
    }

    @objc private func adjustPanelHeight(_ sender: NSButton) {
        let current = heightLabel?.integerValue ?? BoardManPanel.clampedPanelHeight(
            AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.boardManPanelHeight)
        )
        applyPanelHeight(current + (sender.tag * 40))
    }

    @objc private func settingsButtonPressed(_ sender: NSButton) {
        activateTab(.settings)
    }

    private func updateSettingsButtonAppearance() {
        guard let button = settingsButton else { return }
        button.state = activeTab == .settings ? .on : .off
        if #available(macOS 10.14, *) {
            button.contentTintColor = activeTab == .settings ? themeAccentColor : .secondaryLabelColor
        }
    }

    private func activateTab(_ tab: BoardManPanelTab) {
        if tab != .snippets {
            isSnippetEditing = false
            editingSnippetIdentifier = nil
            isSnippetReorderMode = false
            itemLongPressGesture?.isEnabled = true
            itemLongPressGesture?.delaysPrimaryMouseButtonEvents = true
            _ = makeFirstResponder(nil)
        }
        activeTab = tab
        headerTabBar?.setSelectedIndex(tab == .settings ? -1 : tab.rawValue)
        if tab == .settings {
            shouldScrollSettingsToTop = true
        }
        updateSettingsButtonAppearance()
        selectedIndex = -1
        hoveredRow = -1
        hidePreviewBubble()
        if tab == .snippets && !allItems.contains(where: { $0.source == .snippet }) {
            onRefreshRequested?()
        }
        if tab == .settings {
            refreshSnippetSettingsSummary()
            refreshGlobalShortcutRows()
        }
        reloadSnippetCategoryPopup()
        applyCurrentFilter()
        layoutPanelSubviews()
        if tab == .settings {
            makeFirstResponder(self)
        } else {
            focusTableForKeyboard()
        }
    }

    @objc private func settingsCategoryButtonPressed(_ sender: NSButton) {
        activeSettingsCategory = BoardManInlineSettingsCategory(rawValue: sender.tag) ?? .general
        shouldScrollSettingsToTop = true
        _ = makeFirstResponder(nil)
        refreshSnippetSettingsSummary()
        refreshGlobalShortcutRows()
        updateSettingsSidebarSelection()
        layoutPanelSubviews()
    }

    @objc private func clearGlobalShortcut(_ sender: NSButton) {
        guard let kind = BoardManGlobalShortcutKind(rawValue: sender.tag) else { return }
        applyGlobalShortcut(kind, keyCombo: nil)
        refreshGlobalShortcutRows()
        shortcutStatusLabel?.stringValue = "\(kind.title) shortcut cleared."
    }

    private func applyGlobalShortcut(_ kind: BoardManGlobalShortcutKind, keyCombo: KeyCombo?) {
        switch kind {
        case .openBoardMan:
            AppEnvironment.current.hotKeyService.change(with: .main, keyCombo: keyCombo)
        case .quickMode:
            AppEnvironment.current.hotKeyService.changeQuickModeKeyCombo(keyCombo)
        case .history:
            AppEnvironment.current.hotKeyService.change(with: .history, keyCombo: keyCombo)
        case .snippets:
            AppEnvironment.current.hotKeyService.change(with: .snippet, keyCombo: keyCombo)
        case .clearHistory:
            AppEnvironment.current.hotKeyService.changeClearHistoryKeyCombo(keyCombo)
        }
    }

    @objc private func launchOnLoginChanged(_ sender: NSButton) {
        AppEnvironment.current.defaults.set(sender.state == .on, forKey: Constants.UserDefaults.loginItem)
        AppEnvironment.current.defaults.synchronize()
    }

    @objc private func inputPasteCommandChanged(_ sender: NSButton) {
        AppEnvironment.current.defaults.set(sender.state == .on, forKey: Constants.UserDefaults.inputPasteCommand)
    }

    private func applyMaxHistorySize(_ rawValue: Int) {
        let value = min(1000, max(1, rawValue))
        maxHistorySizeStepper?.integerValue = value
        maxHistorySizeValueLabel?.integerValue = value
        AppEnvironment.current.defaults.set(value, forKey: Constants.UserDefaults.maxHistorySize)
        AppEnvironment.current.defaults.synchronize()
        AppEnvironment.current.dataCleanService.cleanDatas()
        onRefreshRequested?()
    }

    @objc private func maxHistorySizeChanged(_ sender: NSStepper) {
        applyMaxHistorySize(sender.integerValue)
    }

    @objc private func maxHistorySizeFieldChanged(_ sender: NSTextField) {
        applyMaxHistorySize(sender.integerValue)
    }

    @objc private func adjustMaxHistorySize(_ sender: NSButton) {
        let current = maxHistorySizeValueLabel?.integerValue
            ?? max(1, AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxHistorySize))
        applyMaxHistorySize(current + (sender.tag * 10))
    }

    @objc private func statusItemChanged(_ sender: NSPopUpButton) {
        let selectedRaw = sender.selectedItem?.representedObject as? String ?? sender.titleOfSelectedItem
        AppEnvironment.current.defaults.set(BoardManPanel.statusItemValue(for: selectedRaw),
                                            forKey: Constants.UserDefaults.showStatusItem)
    }

    @objc private func dedupeChanged(_ sender: NSButton) {
        AppEnvironment.current.defaults.set(sender.state == .off, forKey: Constants.UserDefaults.copySameHistory)
    }

    @objc private func overwriteSameHistoryChanged(_ sender: NSButton) {
        AppEnvironment.current.defaults.set(sender.state == .on, forKey: Constants.UserDefaults.overwriteSameHistory)
    }

    @objc private func reuseTopChanged(_ sender: NSButton) {
        AppEnvironment.current.defaults.set(sender.state == .on, forKey: Constants.UserDefaults.reorderClipsAfterPasting)
        updateHistorySortButton()
        onRefreshRequested?()
    }

    @objc private func clearHistoryRequested(_ sender: NSButton) {
        let alert = NSAlert()
        alert.messageText = boardManText("Clear History")
        alert.informativeText = boardManText("Clear all clipboard history?")
        alert.addButton(withTitle: boardManText("Clear"))
        alert.addButton(withTitle: boardManText("Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let removedIdentifiers = BoardManStores.authoritative
            .clipsSortedByCreatedTimeDescending()
            .map(\.dataHash)
        AppEnvironment.current.clipService.clearAll()
        BoardManMaskedItemStore.shared.remove(removedIdentifiers)
        onRefreshRequested?()
    }

    @objc private func openExcludedAppsSettings(_ sender: NSButton) {
        AppEnvironment.current.menuManager.hideBoardManPanelForPreferences()
        NSApp.activate(ignoringOtherApps: true)
        BoardManPreferencesWindowController.sharedController.showWindow(self)
    }

    @objc private func openSnippetManager(_ sender: NSButton) {
        openSnippetsManagerMode()
    }

    @objc private func openLicensePurchasePage(_ sender: NSButton) {
        guard let url = URL(string: "https://uniplanck.com") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func activateLicenseRequested(_ sender: NSButton) {
        licenseActivationStatusLabel?.stringValue = boardManText("Activation is not connected yet. Free remains the default runtime entitlement.")
        licenseActivationStatusLabel?.textColor = .secondaryLabelColor
        refreshLicenseSummary()
    }

    @objc private func clearSnippetFolderShortcut(_ sender: NSButton) {
        guard let identifier = sender.identifier?.rawValue else { return }
        AppEnvironment.current.hotKeyService.clearSnippetKeyCombo(forFolder: identifier)
        snippetShortcutRows.first { $0.folderIdentifier == identifier }?.recordView.keyCombo = nil
        refreshSnippetSettingsSummary()
        layoutPanelSubviews()
    }

    @objc private func storedTypeChanged(_ sender: NSButton) {
        guard let typeName = sender.identifier?.rawValue else { return }
        var storeTypes = AppEnvironment.current.defaults.dictionary(forKey: Constants.UserDefaults.storeTypes) as? [String: NSNumber] ?? AppDelegate.storeTypesDictinary()
        storeTypes[typeName] = NSNumber(value: sender.state == .on)
        AppEnvironment.current.defaults.set(storeTypes, forKey: Constants.UserDefaults.storeTypes)
        AppEnvironment.current.defaults.synchronize()
    }

    @objc private func maskedContentVisibilityChanged(_ sender: NSButton) {
        let key = sender.tag == 1
            ? Constants.UserDefaults.boardManHideTitleForMaskedItems
            : Constants.UserDefaults.boardManHidePreviewForMaskedItems
        AppEnvironment.current.defaults.set(sender.state == .on, forKey: key)
        hidePreviewBubble()
        placeholderList?.reloadData()
    }

    @objc private func addHideRuleRequested(_ sender: Any?) {
        let title = hideRuleModePopup?.titleOfSelectedItem ?? BoardManHideRuleMode.contains.title
        let mode = BoardManHideRuleMode.allCases.first { $0.title == title } ?? .contains
        BoardManHideRuleStore.shared.add(mode: mode, value: hideRuleTextField?.stringValue ?? "")
        hideRuleTextField?.stringValue = ""
        refreshHideRulesSummary()
        applyCurrentFilter()
    }

    @objc private func removeLastHideRuleRequested(_ sender: NSButton) {
        BoardManHideRuleStore.shared.removeLast()
        refreshHideRulesSummary()
        applyCurrentFilter()
    }

    @objc private func clearHideRulesRequested(_ sender: NSButton) {
        BoardManHideRuleStore.shared.clear()
        refreshHideRulesSummary()
        applyCurrentFilter()
    }

    private func refreshHideRulesSummary() {
        let rules = BoardManHideRuleStore.shared.rules
        let isJapanese = BoardManLanguage.allowed(
            AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManLanguage)
        ).resolved == .japanese
        guard !rules.isEmpty else {
            hideRulesSummaryLabel?.stringValue = isJapanese ? "非表示ルール: 0件" : "0 hide rules"
            hideRulesExamplesLabel?.stringValue = isJapanese ? "例: 「invoice」を含む、完全一致「draft」" : "Examples: contains invoice, exact draft"
            removeLastHideRuleButton?.isEnabled = false
            clearHideRulesButton?.isEnabled = false
            return
        }
        let sample = rules.prefix(2).map { rule -> String in
            let value = rule.value.replacingOccurrences(of: "\n", with: " ")
            let clipped = value.count > 28 ? String(value.prefix(25)) + "..." : value
            return "\(rule.mode.summaryTitle) \"\(clipped)\""
        }.joined(separator: ", ")
        hideRulesSummaryLabel?.stringValue = isJapanese
            ? "有効な非表示ルール: \(rules.count)件"
            : "\(rules.count) hide \(rules.count == 1 ? "rule" : "rules") active"
        hideRulesExamplesLabel?.stringValue = isJapanese ? "例: \(sample)" : "Examples: \(sample)"
        removeLastHideRuleButton?.isEnabled = true
        clearHideRulesButton?.isEnabled = true
    }

    private func refreshLicenseSummary() {
        let snapshot = EntitlementService.shared.currentSnapshot
        let isActive = snapshot.isProEntitled
        let isJapanese = BoardManLanguage.allowed(
            AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManLanguage)
        ).resolved == .japanese
        licensePlanLabel?.stringValue = licensePlanTitle(snapshot.plan)
        licensePlanLabel?.textColor = isActive ? .systemGreen : .labelColor
        licenseStateLabel?.stringValue = "\(licenseStateTitle(snapshot.state)): \(licenseStateDescription(snapshot))"
        licenseStateLabel?.textColor = licenseStateColor(snapshot.state)
        licenseLimitsLabel?.stringValue = isJapanese
            ? "履歴 \(limitText(snapshot.limits.maxHistoryItems))  •  Pin \(limitText(snapshot.limits.maxPinnedItems))  •  スニペット \(limitText(snapshot.limits.maxSnippets))"
            : "History \(limitText(snapshot.limits.maxHistoryItems))  •  Pins \(limitText(snapshot.limits.maxPinnedItems))  •  Snippets \(limitText(snapshot.limits.maxSnippets))"
        licenseKeyField?.placeholderString = isJapanese
            ? (isActive ? "キーチェーンで確認済み" : "安全なローカルライセンス")
            : (isActive ? "Verified in Keychain" : "Secure local license")
        licenseActivateButton?.isHidden = isActive
        licenseUpgradeButton?.isHidden = isActive
        licenseActivationStatusLabel?.stringValue = isJapanese
            ? (isActive ? "ローカルで確認済みです。このMacに紐づき、起動時に自動復元されます。" : "オンライン認証はまだ接続されていません。")
            : (isActive ? "Verified locally. This entitlement is bound to this Mac and restored automatically at launch." : "Online activation is not connected yet.")
        licenseActivationStatusLabel?.textColor = isActive ? .systemGreen : .secondaryLabelColor
        licenseMockNoteLabel?.stringValue = isJapanese
            ? (isActive ? "署名済みライセンストークンはこのMacのBoard-Man用ローカル領域に保存されます。署名用秘密鍵はBoard-Manに含まれません。" : "確認済みライセンスはこのMacのBoard-Man用ローカル領域へ保存されます。商用サービス未設定のビルドではローカル機能をそのまま利用できます。")
            : (isActive ? "The signed license token is stored in Board-Man's private local application state. The signing private key is not embedded in Board-Man." : "Verified licenses are stored in Board-Man's private local application state. Local features remain available when commercial services are not configured.")
        licenseProLockedControlView?.refresh()
        refreshProFeatureAvailability()
    }

    private func licensePlanTitle(_ plan: EntitlementPlan) -> String {
        switch plan {
        case .free: return boardManText("Free")
        case .pro: return "Pro"
        case .ownerLifetime: return boardManText("Owner Lifetime")
        }
    }

    private func licenseStateTitle(_ state: LicenseState) -> String {
        switch state {
        case .free: return boardManText("Free")
        case .trial: return boardManText("Trial")
        case .proActive: return boardManText("Pro Active")
        case .ownerLifetime: return boardManText("Owner Lifetime")
        case .proExpired: return boardManText("Expired")
        case .invalid: return boardManText("Invalid")
        case .offlineGrace: return boardManText("Offline Grace")
        case .locked: return boardManText("Locked")
        }
    }

    private func licenseActivationStatusTitle(_ status: LicenseActivationStatus) -> String {
        switch status {
        case .activated: return "Activated"
        case .notConfigured: return "Not configured"
        case .invalidInput: return "Invalid input"
        case .networkUnavailable: return "Network unavailable"
        case .rejected: return "Rejected"
        case .serverError: return "Server error"
        case .verificationFailed: return "Verification failed"
        case .storageFailed: return "Storage failed"
        }
    }

    private func licenseStateDescription(_ snapshot: EntitlementSnapshot) -> String {
        let isJapanese = BoardManLanguage.allowed(
            AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManLanguage)
        ).resolved == .japanese
        if isJapanese {
            switch snapshot.state {
            case .free: return "主要な履歴・スニペット機能をローカルで利用できます。"
            case .trial: return "一時的なProアクセスが有効です。"
            case .proActive: return "Proライセンスを確認済みです。"
            case .ownerLifetime: return "オーナー永久ライセンスを確認済みです。"
            case .proExpired: return "Proライセンスは現在無効です。"
            case .invalid: return "ライセンス状態を確認できません。"
            case .offlineGrace: return "オフライン猶予期間としてProを利用できます。"
            case .locked: return "現在のライセンスでは機能がロックされています。"
            }
        }
        switch snapshot.state {
        case .free:
            return "Core clipboard history and snippets are available locally."
        case .trial:
            return "Temporary Pro access\(dateSuffix(snapshot.expiresAt, prefix: " until "))."
        case .proActive:
            return "Verified Pro entitlement\(dateSuffix(snapshot.lastVerifiedAt, prefix: ", checked "))."
        case .ownerLifetime:
            return "Verified owner lifetime entitlement\(dateSuffix(snapshot.lastVerifiedAt, prefix: ", checked "))."
        case .proExpired:
            return "Pro entitlement is no longer active."
        case .invalid:
            return "License status cannot be trusted."
        case .offlineGrace:
            return "Pro is temporarily trusted offline\(dateSuffix(snapshot.offlineGraceExpiresAt, prefix: " until "))."
        case .locked:
            return "Feature access is locked by the current entitlement."
        }
    }

    private func licenseStateColor(_ state: LicenseState) -> NSColor {
        switch state {
        case .proActive, .ownerLifetime: return .systemGreen
        case .trial, .offlineGrace: return .systemOrange
        case .invalid, .proExpired, .locked: return .systemRed
        case .free: return .secondaryLabelColor
        }
    }

    private func dateSuffix(_ date: Date?, prefix: String) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return prefix + formatter.string(from: date)
    }

    private func limitText(_ value: Int) -> String {
        let isJapanese = BoardManLanguage.allowed(
            AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManLanguage)
        ).resolved == .japanese
        return value == Int.max ? (isJapanese ? "無制限" : "unlimited") : "\(value)"
    }

    private func refreshExcludedAppsSummary() {
        let apps = AppEnvironment.current.excludeAppService.applications
        let isJapanese = BoardManLanguage.allowed(
            AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManLanguage)
        ).resolved == .japanese
        guard !apps.isEmpty else {
            excludedAppsSummaryLabel?.stringValue = isJapanese ? "除外アプリ: 0件" : "0 excluded apps"
            return
        }
        let names = apps.prefix(3).map { $0.name }.joined(separator: ", ")
        let suffix = apps.count > 3 ? " +\(apps.count - 3)" : ""
        excludedAppsSummaryLabel?.stringValue = isJapanese
            ? "除外 \(apps.count)件: \(names)\(suffix)"
            : "\(apps.count) excluded: \(names)\(suffix)"
    }

    @objc private func searchTextChanged(_ sender: NSSearchField) {
        selectedIndex = -1
        hoveredRow = -1
        hidePreviewBubble()
        applyCurrentFilter()
    }

    private var currentHistoryUsageFilter: BoardManHistoryUsageFilter {
        return BoardManHistoryUsageFilter.allowed(
            AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManHistoryUsageFilter)
        )
    }

    private enum SavedFilterPopupCommand {
        static let summary = "__boardman_saved_filter_summary__"
        static let save = "__boardman_saved_filter_save__"
        static let update = "__boardman_saved_filter_update__"
        static let rename = "__boardman_saved_filter_rename__"
        static let delete = "__boardman_saved_filter_delete__"
        static let clear = "__boardman_saved_filter_clear__"
    }

    private var availableSnippetGroupIdentifiers: Set<String> {
        var identifiers = Set(store.foldersSortedByIndex().map(\.identifier))
        if allItems.contains(where: { $0.categoryIdentifier == BoardManPanel.uncategorizedCategoryIdentifier }) {
            identifiers.insert(BoardManPanel.uncategorizedCategoryIdentifier)
        }
        return identifiers
    }

    private func currentSavedFilterPreset(id: String, name: String) -> BoardManSavedFilterPreset {
        return BoardManSavedFilterPreset(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            usageFilterRawValue: currentHistoryUsageFilter.rawValue,
            condition: BoardManHistoryConditionStore.shared.condition(for: currentHistoryUsageFilter) ?? .empty,
            snippetGroupIdentifiers: activeSnippetGroupIdentifiers.sorted()
        )
    }

    private func reloadSavedFilterPopup() {
        guard let popup = historySavedFilterPopup else { return }
        let store = BoardManSavedFilterStore.shared
        let selectedID = store.selectedPresetID
        popup.removeAllItems()

        popup.addItem(withTitle: boardManText("Saved Filters"))
        popup.lastItem?.representedObject = SavedFilterPopupCommand.summary
        popup.lastItem?.isEnabled = false

        for preset in store.presets {
            popup.addItem(withTitle: preset.name)
            popup.lastItem?.representedObject = preset.id
        }
        if !store.presets.isEmpty {
            popup.menu?.addItem(.separator())
        }
        popup.addItem(withTitle: boardManText("Save Current Filter…"))
        popup.lastItem?.representedObject = SavedFilterPopupCommand.save
        if selectedID != nil {
            popup.addItem(withTitle: boardManText("Update Selected Filter"))
            popup.lastItem?.representedObject = SavedFilterPopupCommand.update
            popup.addItem(withTitle: boardManText("Rename Selected Filter…"))
            popup.lastItem?.representedObject = SavedFilterPopupCommand.rename
            popup.addItem(withTitle: boardManText("Delete Selected Filter"))
            popup.lastItem?.representedObject = SavedFilterPopupCommand.delete
            popup.addItem(withTitle: boardManText("Clear Saved Filter"))
            popup.lastItem?.representedObject = SavedFilterPopupCommand.clear
        }

        if let selectedID,
           let item = popup.itemArray.first(where: { ($0.representedObject as? String) == selectedID }) {
            popup.select(item)
        } else {
            popup.selectItem(at: 0)
        }
        popup.toolTip = store.selectedPreset?.name ?? boardManText("Saved Filters")
    }

    private func promptForSavedFilterName(title: String, initialName: String) -> String? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.addButton(withTitle: boardManText("Save"))
        alert.addButton(withTitle: boardManText("Cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
        field.stringValue = initialName
        field.placeholderString = boardManText("Filter name")
        field.isEditable = true
        field.isSelectable = true
        alert.accessoryView = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private func applySavedFilterPreset(_ preset: BoardManSavedFilterPreset) {
        let usageFilter = preset.usageFilter
        AppEnvironment.current.defaults.set(
            usageFilter.rawValue,
            forKey: Constants.UserDefaults.boardManHistoryUsageFilter
        )
        historyUsageFilterControl?.selectedSegment = BoardManHistoryUsageFilter.allCases.firstIndex(of: usageFilter) ?? 0
        if preset.condition.hasCriteria {
            BoardManHistoryConditionStore.shared.save(preset.condition, for: usageFilter)
        } else {
            BoardManHistoryConditionStore.shared.delete(for: usageFilter)
        }
        let validGroups = Set(preset.validSnippetGroupIdentifiers(
            availableIdentifiers: availableSnippetGroupIdentifiers
        ))
        setActiveSnippetGroupIdentifiers(validGroups)
        BoardManSavedFilterStore.shared.select(preset.id)
        reloadSnippetCategoryPopup()
        reloadSavedFilterPopup()
        updateHistoryConditionButton()
        selectedIndex = -1
        hoveredRow = -1
        hidePreviewBubble()
        applyCurrentFilter()
    }

    @objc private func savedFilterPopupChanged(_ sender: NSPopUpButton) {
        guard let value = sender.selectedItem?.representedObject as? String else {
            reloadSavedFilterPopup()
            return
        }
        let store = BoardManSavedFilterStore.shared
        if let preset = store.presets.first(where: { $0.id == value }) {
            applySavedFilterPreset(preset)
            return
        }
        switch value {
        case SavedFilterPopupCommand.save:
            guard let name = promptForSavedFilterName(title: boardManText("Save Filter"), initialName: "") else {
                reloadSavedFilterPopup()
                return
            }
            let preset = currentSavedFilterPreset(id: UUID().uuidString, name: name)
            _ = store.save(preset)
        case SavedFilterPopupCommand.update:
            guard let selected = store.selectedPreset else { break }
            _ = store.save(currentSavedFilterPreset(id: selected.id, name: selected.name))
        case SavedFilterPopupCommand.rename:
            guard let selected = store.selectedPreset,
                  let name = promptForSavedFilterName(title: boardManText("Rename Filter"), initialName: selected.name) else {
                reloadSavedFilterPopup()
                return
            }
            var renamed = selected
            renamed.name = name
            _ = store.save(renamed)
        case SavedFilterPopupCommand.delete:
            if let selectedID = store.selectedPresetID {
                store.delete(selectedID)
            }
        case SavedFilterPopupCommand.clear:
            store.select(nil)
        default:
            break
        }
        reloadSavedFilterPopup()
    }

    @objc private func historyUsageFilterChanged(_ sender: NSSegmentedControl) {
        guard let filter = BoardManHistoryUsageFilter.allCases[safe: sender.selectedSegment] else { return }
        AppEnvironment.current.defaults.set(filter.rawValue, forKey: Constants.UserDefaults.boardManHistoryUsageFilter)
        selectedIndex = -1
        hoveredRow = -1
        hidePreviewBubble()
        updateHistoryConditionButton()
        applyCurrentFilter()
    }

    @objc private func historyConditionButtonPressed(_ sender: NSButton) {
        editCurrentHistoryCondition(sender)
    }

    @objc private func editCurrentHistoryCondition(_ sender: Any?) {
        let filter = currentHistoryUsageFilter
        let storedCondition = BoardManHistoryConditionStore.shared.condition(for: filter)
        let existing = storedCondition ?? .empty
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(format: boardManText("Filter %@ history"), boardManText(filter.rawValue))
        alert.informativeText = boardManText("Only matching items remain visible. Empty fields are ignored; clearing every field removes this condition.")
        alert.addButton(withTitle: boardManText("Save"))
        alert.addButton(withTitle: boardManText("Cancel"))
        if storedCondition != nil {
            alert.addButton(withTitle: boardManText("Delete"))
        }

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 246))
        func label(_ title: String, originY: CGFloat) -> NSTextField {
            let field = NSTextField(labelWithString: title)
            field.frame = NSRect(x: 0, y: originY, width: 118, height: 18)
            field.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            accessory.addSubview(field)
            return field
        }
        func hint(_ title: String, originX: CGFloat, originY: CGFloat, width: CGFloat) {
            let field = NSTextField(labelWithString: title)
            field.frame = NSRect(x: originX, y: originY, width: width, height: 16)
            field.font = NSFont.systemFont(ofSize: 9.5)
            field.textColor = .secondaryLabelColor
            accessory.addSubview(field)
        }

        let enabledButton = NSButton(checkboxWithTitle: boardManText("Enable this condition"), target: nil, action: nil)
        enabledButton.frame = NSRect(x: 0, y: 218, width: 220, height: 20)
        enabledButton.state = existing.isEnabled ? .on : .off
        accessory.addSubview(enabledButton)
        let scopeLabel = NSTextField(labelWithString: String(format: boardManText("Applies only to the %@ tab"), boardManText(filter.rawValue)))
        scopeLabel.frame = NSRect(x: 276, y: 219, width: 244, height: 18)
        scopeLabel.alignment = .right
        scopeLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        scopeLabel.textColor = .secondaryLabelColor
        accessory.addSubview(scopeLabel)

        _ = label(boardManText("Minimum characters"), originY: 181)
        let minimumField = NSTextField(frame: NSRect(x: 132, y: 176, width: 82, height: 26))
        minimumField.stringValue = existing.minimumLength > 0 ? "\(existing.minimumLength)" : ""
        minimumField.placeholderString = boardManText("No limit")
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 0
        minimumField.formatter = formatter
        accessory.addSubview(minimumField)
        hint("Example: 100 keeps text with 100 characters or more.", originX: 228, originY: 181, width: 292)

        _ = label(boardManText("Must contain"), originY: 137)
        let includedField = NSTextField(frame: NSRect(x: 132, y: 132, width: 280, height: 26))
        includedField.stringValue = existing.includedTerms.joined(separator: ", ")
        includedField.placeholderString = "git, deploy, Cloudflare"
        accessory.addSubview(includedField)
        let matchPopup = NSPopUpButton(frame: NSRect(x: 422, y: 132, width: 98, height: 26), pullsDown: false)
        matchPopup.addItems(withTitles: ["ALL", "ANY"])
        matchPopup.selectItem(at: existing.matchesAllIncludedTerms ? 0 : 1)
        accessory.addSubview(matchPopup)
        hint("Separate words with commas. ALL requires every word; ANY requires one.", originX: 132, originY: 113, width: 388)

        _ = label(boardManText("Must not contain"), originY: 78)
        let excludedField = NSTextField(frame: NSRect(x: 132, y: 73, width: 388, height: 26))
        excludedField.stringValue = existing.excludedTerms.joined(separator: ", ")
        excludedField.placeholderString = "draft, temporary, ignore"
        accessory.addSubview(excludedField)
        hint("Any matching excluded word hides the item.", originX: 132, originY: 54, width: 388)

        let shellButton = NSButton(checkboxWithTitle: boardManText("Shell-script-like text only"), target: nil, action: nil)
        shellButton.frame = NSRect(x: 0, y: 19, width: 210, height: 20)
        shellButton.state = existing.shellLikeOnly ? .on : .off
        shellButton.toolTip = "Detects shebangs, common shell commands, pipes, &&, ||, and command substitution without executing anything."
        accessory.addSubview(shellButton)
        hint("Detection only. Board-Man never executes the text.", originX: 228, originY: 21, width: 292)
        alert.accessoryView = accessory

        NSApp.activate(ignoringOtherApps: true)
        alert.beginSheetModal(for: self) { [weak self] response in
            guard let self else { return }
            if response == .alertThirdButtonReturn {
                BoardManHistoryConditionStore.shared.delete(for: filter)
            } else if response == .alertFirstButtonReturn {
                let minimumLength = max(0, Int(minimumField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0)
                let condition = BoardManHistoryCondition(
                    isEnabled: enabledButton.state == .on,
                    minimumLength: minimumLength,
                    includedTerms: BoardManHistoryCondition.parsedTerms(includedField.stringValue),
                    excludedTerms: BoardManHistoryCondition.parsedTerms(excludedField.stringValue),
                    matchesAllIncludedTerms: matchPopup.indexOfSelectedItem == 0,
                    shellLikeOnly: shellButton.state == .on
                )
                if condition.hasCriteria {
                    BoardManHistoryConditionStore.shared.save(condition, for: filter)
                } else {
                    BoardManHistoryConditionStore.shared.delete(for: filter)
                }
            } else {
                return
            }
            self.updateHistoryConditionButton()
            self.applyCurrentFilter()
        }
        DispatchQueue.main.async {
            alert.window.makeFirstResponder(includedField)
        }
    }

    @objc private func toggleCurrentHistoryCondition(_ sender: Any?) {
        let filter = currentHistoryUsageFilter
        guard let condition = BoardManHistoryConditionStore.shared.condition(for: filter) else { return }
        BoardManHistoryConditionStore.shared.setEnabled(!condition.isEnabled, for: filter)
        updateHistoryConditionButton()
        applyCurrentFilter()
    }

    @objc private func deleteCurrentHistoryCondition(_ sender: Any?) {
        BoardManHistoryConditionStore.shared.delete(for: currentHistoryUsageFilter)
        updateHistoryConditionButton()
        applyCurrentFilter()
    }

    private func updateHistoryConditionButton() {
        guard let button = historyConditionButton else { return }
        let filter = currentHistoryUsageFilter
        let condition = BoardManHistoryConditionStore.shared.condition(for: filter)
        let isEnabled = condition?.isEnabled == true
        button.toolTip = condition == nil
            ? "Add a condition for \(filter.rawValue)."
            : (isEnabled ? "Condition enabled for \(filter.rawValue)." : "Condition saved but disabled for \(filter.rawValue).")
        if #available(macOS 11.0, *) {
            let symbol = isEnabled ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease"
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: boardManText("Condition"))
            button.title = ""
            button.imagePosition = .imageOnly
        } else {
            button.image = nil
            button.title = "≡"
            button.imagePosition = .noImage
        }
        button.state = isEnabled ? .on : .off
        if #available(macOS 10.14, *) {
            button.contentTintColor = isEnabled ? themeAccentColor : .secondaryLabelColor
        }
    }

    @objc private func historySortOrderChanged(_ sender: NSButton) {
        let usesRecentOrder = sender.state == .on
        AppEnvironment.current.defaults.set(usesRecentOrder, forKey: Constants.UserDefaults.reorderClipsAfterPasting)
        reuseTopButton?.state = usesRecentOrder ? .on : .off
        selectedIndex = -1
        hoveredRow = -1
        hidePreviewBubble()
        updateHistorySortButton()
        onRefreshRequested?()
    }

    private func updateHistorySortButton() {
        guard let button = historySortButton else { return }
        let usesRecentOrder = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.reorderClipsAfterPasting)
        button.state = usesRecentOrder ? .on : .off
        button.toolTip = usesRecentOrder
            ? "Recent Use — move pasted items to the top; newly copied items still appear first."
            : "Copy Order — keep history fixed in the order items were copied."
        if #available(macOS 11.0, *) {
            let symbolName = usesRecentOrder ? "arrow.counterclockwise" : "doc.on.doc"
            let description = usesRecentOrder ? boardManText("Recent Use") : boardManText("Copy Order")
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
            button.title = ""
            button.imagePosition = .imageOnly
        } else {
            button.image = nil
            button.title = usesRecentOrder ? "Use" : "Copy"
            button.imagePosition = .noImage
        }
        if #available(macOS 10.14, *) {
            button.contentTintColor = usesRecentOrder ? themeAccentColor : .secondaryLabelColor
        }
    }

    private func applyCurrentFilter() {
        let rawQuery = (searchField?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultSearchScope: BoardManSearchScope = activeTab == .snippets ? .snippets : .all
        let parsedSearch = BoardManSearchQueryParser.parse(rawQuery, defaultScope: defaultSearchScope)
        let searchRequest = parsedSearch.request
        if searchRequest.scope != defaultSearchScope {
            switch searchRequest.scope {
            case .history where activeTab != .history:
                activateTab(.history)
                return
            case .snippets where activeTab != .snippets:
                activateTab(.snippets)
                return
            case .all, .history, .snippets:
                break
            }
        }
        let tabbedItems: [BoardManHistoryItem]
        switch activeTab {
        case .history:
            #if DEBUG
            let usageFilter: BoardManHistoryUsageFilter = benchmarkIsolationForTesting ? .all : currentHistoryUsageFilter
            let condition = benchmarkIsolationForTesting
                ? nil
                : BoardManHistoryConditionStore.shared.condition(for: usageFilter)
            #else
            let usageFilter = currentHistoryUsageFilter
            let condition = BoardManHistoryConditionStore.shared.condition(for: usageFilter)
            #endif
            let filteredClips = allItems.filter { item in
                guard item.source == .clip, item.isEnabled, usageFilter.includes(item) else { return false }
                guard let condition, condition.isEnabled else { return true }
                return condition.matches(item.previewTitle)
            }
            let pinnedClips = filteredClips.filter { $0.isPinned }
            let regularHistory = filteredClips.filter { !$0.isPinned }
            let pinnedNonHistoryItems = usageFilter == .all
                ? allItems.filter { $0.source != .clip && $0.isPinned && $0.isEnabled }
                : []
            tabbedItems = pinnedClips + pinnedNonHistoryItems + regularHistory
        case .snippets:
            let snippetItems = allItems.filter { $0.source == .snippet }
            if activeSnippetGroupIdentifiers.isEmpty {
                tabbedItems = snippetItems
            } else {
                tabbedItems = snippetItems.filter { item in
                    guard let identifier = item.categoryIdentifier else { return false }
                    return activeSnippetGroupIdentifiers.contains(identifier)
                }
            }
        case .settings:
            tabbedItems = []
        }

        #if DEBUG
        let hideRules = benchmarkIsolationForTesting ? [] : BoardManHideRuleStore.shared.rules
        #else
        let hideRules = BoardManHideRuleStore.shared.rules
        #endif
        let visibleItems = hideRules.isEmpty ? tabbedItems : tabbedItems.filter { item in
            let searchableText = [item.primaryTitle, item.title, item.previewTitle]
                .joined(separator: "\n")
            return !hideRules.contains { $0.matches(searchableText) }
        }
        let startedAt = CFAbsoluteTimeGetCurrent()
        #if DEBUG
        let searchResolution = searchCoordinator.resolve(
            parsedSearch: parsedSearch,
            defaultScope: defaultSearchScope,
            visibleItems: visibleItems,
            totalItemCount: allItems.count,
            includeHistoryDisplayNames: activeTab == .history,
            benchmarkIsolation: benchmarkIsolationForTesting
        )
        #else
        let searchResolution = searchCoordinator.resolve(
            parsedSearch: parsedSearch,
            defaultScope: defaultSearchScope,
            visibleItems: visibleItems,
            totalItemCount: allItems.count,
            includeHistoryDisplayNames: activeTab == .history
        )
        #endif
        let searchedItems = searchResolution.items
        if searchResolution.performedSearch {
            PasteCountInputService.shared.logBoardManPerformance(
                "search_query",
                startedAt: startedAt,
                details: "chars=\(searchResolution.query.count) filters=\(searchResolution.hasStoreFilters ? 1 : 0) indexed_hits=\(searchResolution.indexedHitCount) visible_hits=\(searchedItems.count)"
            )
        }
        historyItems = isQuickMode ? Array(searchedItems.prefix(Self.quickItemLimit)) : searchedItems
        if historyItems.isEmpty {
            selectedIndex = -1
        } else if selectedIndex >= historyItems.count {
            selectedIndex = historyItems.count - 1
        }
        if skipsPinnedKeyboardNavigation, selectedIndex < 0 {
            selectedIndex = keyboardNavigableRows().first ?? -1
        }
        if skipsPinnedKeyboardNavigation,
           selectedIndex >= 0,
           historyItems[safe: selectedIndex]?.isPinned == true {
            selectedIndex = keyboardNavigableRows().first ?? -1
        }
        placeholderList?.rowHeight = activeTab == .history && timestampPosition != .below
            ? LayoutMetrics.compactHistoryRowHeight
            : LayoutMetrics.historyRowHeight
        layoutPanelSubviews()
        placeholderList?.reloadData()
        synchronizeListGeometry()
        syncNativeSelection()
        updateSnippetActionButtons()
        updateHistoryConditionButton()
    }

    private func isTimestampHit(row: Int, tablePoint: NSPoint, table: NSTableView) -> Bool {
        guard let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? BoardManHistoryCellView else {
            return false
        }
        cell.layoutSubtreeIfNeeded()
        return cell.containsTimestamp(at: cell.convert(tablePoint, from: table))
    }

    private func isTimestampHitAtCurrentPointer(row: Int, table: NSTableView) -> Bool {
        guard let window = table.window,
              let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? BoardManHistoryCellView else {
            return false
        }
        cell.layoutSubtreeIfNeeded()
        return cell.containsTimestamp(windowPoint: window.mouseLocationOutsideOfEventStream)
    }

    private func performTimestampShortcut(item: BoardManHistoryItem, startedAt: CFAbsoluteTime?) {
        guard configuredTimestampShortcutEnabled, item.isEnabled else {
            NSSound.beep()
            return
        }
        hidePreviewBubble()
        onTimestampActionRequested?(
            item,
            configuredTimestampShortcut,
            configuredTimestampShortcutDelay,
            startedAt
        )
    }

    // Use NSTableView's native target/action path for reliable single-click delivery.
    // Snippet long-press and drag remain separate gesture paths.
    @objc private func handleTableSingleClick(_ sender: NSTableView) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        guard startedAt >= suppressSingleClickUntil else { return }

        let row = sender.clickedRow >= 0 ? sender.clickedRow : sender.selectedRow
        guard row >= 0, let item = historyItems[safe: row] else { return }
        let tablePoint = NSApp.currentEvent.map { sender.convert($0.locationInWindow, from: nil) }
        let eventTimestampHit = tablePoint.map { isTimestampHit(row: row, tablePoint: $0, table: sender) } ?? false
        let timestampWasHit = eventTimestampHit || isTimestampHitAtCurrentPointer(row: row, table: sender)

        PasteCountInputService.shared.logBoardManPerformance(
            "panel_row_click",
            startedAt: startedAt,
            details: "row=\(row) source=\(item.source) timestampHit=\(timestampWasHit)"
        )

        let wasEditing = isSnippetEditing
        setSelectedIndex(row)
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            _ = togglePin(identifier: item.dataHash)
            return
        }
        if activeTab == .snippets && (isSnippetReorderMode || wasEditing) {
            return
        }
        if timestampWasHit {
            if configuredTimestampInteraction.runsShortcutOnClick {
                performTimestampShortcut(item: item, startedAt: startedAt)
                return
            }
            if configuredTimestampInteraction.togglesMaskOnClick {
                _ = toggleMask(identifier: item.dataHash)
                return
            }
        }
        guard item.isEnabled else {
            NSSound.beep()
            return
        }
        if activeTab == .snippets {
            scheduleSnippetSingleClickPaste(item: item, startedAt: startedAt)
            return
        }
        hidePreviewBubble()
        onPasteRequested?(item, startedAt)
    }

    private func scheduleSnippetSingleClickPaste(item: BoardManHistoryItem, startedAt: CFAbsoluteTime) {
        pendingSnippetSingleClickWorkItem?.cancel()
        let identifier = item.dataHash
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingSnippetSingleClickWorkItem = nil
            guard self.isVisible,
                  self.activeTab == .snippets,
                  !self.isSnippetEditing,
                  !self.isSnippetReorderMode,
                  let currentItem = self.historyItems.first(where: { $0.dataHash == identifier }),
                  currentItem.isEnabled else { return }
            self.hidePreviewBubble()
            self.onPasteRequested?(currentItem, startedAt)
        }
        pendingSnippetSingleClickWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: workItem)
    }

    @objc private func handleTableDoubleClick(_ sender: NSTableView) {
        guard activeTab == .snippets, !isSnippetReorderMode else { return }
        pendingSnippetSingleClickWorkItem?.cancel()
        pendingSnippetSingleClickWorkItem = nil
        let row = sender.clickedRow >= 0 ? sender.clickedRow : sender.selectedRow
        guard row >= 0,
              let item = historyItems[safe: row],
              item.source == .snippet else { return }
        setSelectedIndex(row)
        beginSnippetEditing()
        snippetEditorTitleField?.selectText(nil)
    }

    @objc private func handleItemLongPress(_ gesture: NSPressGestureRecognizer) {
        guard gesture.state == .began,
              activeTab != .settings,
              !(activeTab == .snippets && isSnippetReorderMode),
              let table = placeholderList else { return }
        let tablePoint = gesture.location(in: table)
        let row = table.row(at: tablePoint)
        guard row >= 0, let item = historyItems[safe: row] else { return }
        let timestampWasHit = isTimestampHit(row: row, tablePoint: tablePoint, table: table)
        suppressSingleClickUntil = CFAbsoluteTimeGetCurrent() + 1.0
        setSelectedIndex(row)
        if timestampWasHit {
            if configuredTimestampInteraction.runsShortcutOnLongPress {
                performTimestampShortcut(item: item, startedAt: CFAbsoluteTimeGetCurrent())
                return
            }
            if configuredTimestampInteraction.togglesMaskOnLongPress {
                _ = toggleMask(identifier: item.dataHash)
                return
            }
        }
        switch configuredLongPressAction {
        case .togglePin:
            _ = togglePin(identifier: item.dataHash)
        case .timedPin:
            _ = toggleTimedPin(identifier: item.dataHash)
        case .toggleMask:
            _ = toggleMask(identifier: item.dataHash)
        case .none:
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    // Right-click row actions. History deletion requires confirmation and is disabled for pinned items.
    @objc private func handleRightClick(_ gesture: NSClickGestureRecognizer) {
        guard let table = placeholderList else { return }
        let location = gesture.location(in: table)
        let row = table.row(at: location)
        guard row >= 0, historyItems[safe: row] != nil else { return }
        setSelectedIndex(row)
        let menu = createContextMenu(forRow: row)
        menu.popUp(positioning: nil, at: location, in: table)
    }

    private func createContextMenu(forRow row: Int) -> NSMenu {
        let menu = NSMenu(title: boardManText("Row Actions"))
        let pasteItem = NSMenuItem(title: boardManText("Paste"), action: #selector(performPasteFromMenu(_:)), keyEquivalent: "")
        pasteItem.target = self
        pasteItem.representedObject = row
        menu.addItem(pasteItem)

        if let item = historyItems[safe: row] {
            let pinStore = PinnedSnippetStore.shared
            let isPinnedCurrently = pinStore.isPinned(item.dataHash)
            let pinTitle = boardManText(isPinnedCurrently ? "Unpin" : "Pin")
            let pinItem = NSMenuItem(title: pinTitle, action: #selector(togglePinFromMenu(_:)), keyEquivalent: "p")
            pinItem.keyEquivalentModifierMask = [.command]
            pinItem.target = self
            pinItem.representedObject = item.dataHash
            menu.addItem(pinItem)

            let timedPinStore = BoardManTimedPinStore.shared
            if timedPinStore.isPinned(item.dataHash) {
                let timedPinItem = NSMenuItem(title: boardManText("Remove Timed Pin"), action: #selector(toggleTimedPinFromMenu(_:)), keyEquivalent: "")
                timedPinItem.target = self
                timedPinItem.representedObject = item.dataHash
                menu.addItem(timedPinItem)
            } else {
                let timedPinItem = NSMenuItem(title: boardManText("Timed Pin"), action: nil, keyEquivalent: "")
                let presetMenu = NSMenu(title: boardManText("Timed Pin"))
                BoardManTimedPinPresetStore.presets().forEach { preset in
                    let presetItem = NSMenuItem(title: preset.title, action: #selector(applyTimedPinPresetFromMenu(_:)), keyEquivalent: "")
                    presetItem.target = self
                    presetItem.representedObject = ["identifier": item.dataHash, "presetID": preset.id]
                    presetMenu.addItem(presetItem)
                }
                timedPinItem.submenu = presetMenu
                menu.addItem(timedPinItem)
            }

            let maskTitle = item.isMasked ? boardManText("Show Content") : boardManText("Hide Content")
            let maskItem = NSMenuItem(title: maskTitle, action: #selector(toggleMaskFromMenu(_:)), keyEquivalent: "")
            maskItem.target = self
            maskItem.representedObject = item.dataHash
            menu.addItem(maskItem)

            let highlightItem = NSMenuItem(title: boardManText("Highlight"), action: nil, keyEquivalent: "")
            let highlightMenu = NSMenu(title: boardManText("Highlight"))
            BoardManItemHighlight.allCases.forEach { highlight in
                let colorItem = NSMenuItem(title: highlight.title, action: #selector(setItemHighlightFromMenu(_:)), keyEquivalent: "")
                colorItem.target = self
                colorItem.representedObject = ["identifier": item.dataHash, "highlight": highlight.rawValue]
                colorItem.state = BoardManItemHighlightStore.shared.highlight(for: item.dataHash) == highlight ? .on : .off
                highlightMenu.addItem(colorItem)
            }
            highlightMenu.addItem(.separator())
            let clearHighlight = NSMenuItem(title: boardManText("Remove Highlight"), action: #selector(clearItemHighlightFromMenu(_:)), keyEquivalent: "")
            clearHighlight.target = self
            clearHighlight.representedObject = item.dataHash
            clearHighlight.isEnabled = BoardManItemHighlightStore.shared.highlight(for: item.dataHash) != nil
            highlightMenu.addItem(clearHighlight)
            highlightItem.submenu = highlightMenu
            menu.addItem(highlightItem)

            if item.source == .clip {
                let displayNameStore = HistoryDisplayNameStore.shared
                let currentName = displayNameStore.name(for: item.dataHash)
                menu.addItem(NSMenuItem.separator())

                let setNameItem = NSMenuItem(title: boardManText("Set Display Name…"), action: #selector(setHistoryDisplayNameFromMenu(_:)), keyEquivalent: "")
                setNameItem.target = self
                setNameItem.representedObject = item.dataHash
                menu.addItem(setNameItem)

                let nameOnlyItem = NSMenuItem(title: boardManText("Show Name Only"), action: #selector(toggleHistoryNameOnlyFromMenu(_:)), keyEquivalent: "")
                nameOnlyItem.target = self
                nameOnlyItem.representedObject = item.dataHash
                nameOnlyItem.state = displayNameStore.isNameOnly(item.dataHash) ? .on : .off
                nameOnlyItem.isEnabled = currentName != nil
                menu.addItem(nameOnlyItem)

                let clearNameItem = NSMenuItem(title: boardManText("Remove Display Name"), action: #selector(removeHistoryDisplayNameFromMenu(_:)), keyEquivalent: "")
                clearNameItem.target = self
                clearNameItem.representedObject = item.dataHash
                clearNameItem.isEnabled = currentName != nil
                menu.addItem(clearNameItem)
                menu.addItem(NSMenuItem.separator())

                let addToSnippetsItem = NSMenuItem(title: boardManText("Add to Snippets"), action: nil, keyEquivalent: "")
                let groupMenu = NSMenu(title: boardManText("Add to Snippets"))
                let folders = store.foldersSortedByIndex()
                folders.forEach { folder in
                    let title = folder.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let groupItem = NSMenuItem(title: title.isEmpty ? boardManText("Untitled folder") : title, action: #selector(addHistoryItemToSnippetGroup(_:)), keyEquivalent: "")
                    groupItem.target = self
                    groupItem.representedObject = [
                        "content": item.previewTitle,
                        "folder": folder.identifier,
                        "history": item.dataHash
                    ]
                    groupMenu.addItem(groupItem)
                }
                if !folders.isEmpty {
                    groupMenu.addItem(NSMenuItem.separator())
                }
                let uncategorizedItem = NSMenuItem(title: boardManText("Uncategorized"), action: #selector(addHistoryItemToSnippetGroup(_:)), keyEquivalent: "")
                uncategorizedItem.target = self
                uncategorizedItem.representedObject = [
                    "content": item.previewTitle,
                    "folder": BoardManPanel.uncategorizedCategoryIdentifier,
                    "history": item.dataHash
                ]
                groupMenu.addItem(uncategorizedItem)
                addToSnippetsItem.submenu = groupMenu
                menu.addItem(addToSnippetsItem)

                menu.addItem(NSMenuItem.separator())
                let deleteHistoryItem = NSMenuItem(
                    title: boardManText("Delete History Item"),
                    action: #selector(deleteHistoryItemFromMenu(_:)),
                    keyEquivalent: ""
                )
                deleteHistoryItem.target = self
                deleteHistoryItem.representedObject = item.dataHash
                deleteHistoryItem.isEnabled = !item.isPinned
                deleteHistoryItem.toolTip = item.isPinned
                    ? boardManText("Pinned items must be unpinned before deletion.")
                    : nil
                menu.addItem(deleteHistoryItem)
            }

            if item.source == .snippet {
                let renameSnippetItem = NSMenuItem(title: boardManText("Rename Snippet…"), action: #selector(renameSnippetFromMenu(_:)), keyEquivalent: "")
                renameSnippetItem.target = self
                renameSnippetItem.representedObject = item.dataHash
                menu.addItem(renameSnippetItem)

                let editSnippetItem = NSMenuItem(title: boardManText("Edit Snippet"), action: #selector(editSnippetFromMenu(_:)), keyEquivalent: "")
                editSnippetItem.target = self
                editSnippetItem.representedObject = item.dataHash
                menu.addItem(editSnippetItem)

                let deleteSnippetItem = NSMenuItem(title: boardManText("Delete Snippet"), action: #selector(deleteSnippetFromMenu(_:)), keyEquivalent: "")
                deleteSnippetItem.target = self
                deleteSnippetItem.representedObject = item.dataHash
                menu.addItem(deleteSnippetItem)
            }
        } else {
            let disabledPin = NSMenuItem(title: boardManText("Pin / Unpin"), action: nil, keyEquivalent: "")
            disabledPin.isEnabled = false
            menu.addItem(disabledPin)
        }

        menu.addItem(NSMenuItem.separator())

        if activeTab == .snippets {
            let addSnippetItem = NSMenuItem(title: boardManText("Add Snippet"), action: #selector(addSnippetFromPanel(_:)), keyEquivalent: "")
            addSnippetItem.target = self
            menu.addItem(addSnippetItem)
        }

        let copyItem = NSMenuItem(title: boardManText("Copy"), action: #selector(copyFromMenu(_:)), keyEquivalent: "c")
        copyItem.keyEquivalentModifierMask = [.command]
        copyItem.target = self
        copyItem.representedObject = row
        menu.addItem(copyItem)

        return menu
    }

    @objc private func performPasteFromMenu(_ sender: NSMenuItem) {
        guard let row = sender.representedObject as? Int,
              let item = historyItems[safe: row] else { return }
        guard item.isEnabled else {
            NSSound.beep()
            return
        }
        hidePreviewBubble()
        onPasteRequested?(item, nil)
    }

    @objc private func togglePinFromMenu(_ sender: NSMenuItem) {
        guard let dataHash = sender.representedObject as? String else { return }
        _ = togglePin(identifier: dataHash)
    }

    @objc private func toggleTimedPinFromMenu(_ sender: NSMenuItem) {
        guard let dataHash = sender.representedObject as? String else { return }
        _ = toggleTimedPin(identifier: dataHash)
    }

    @objc private func toggleMaskFromMenu(_ sender: NSMenuItem) {
        guard let dataHash = sender.representedObject as? String else { return }
        _ = toggleMask(identifier: dataHash)
    }

    @objc private func applyTimedPinPresetFromMenu(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? [String: String],
              let identifier = context["identifier"],
              let presetID = context["presetID"],
              let preset = BoardManTimedPinPresetStore.presets().first(where: { $0.id == presetID }) else { return }
        BoardManTimedPinPresetStore.select(preset.id)
        refreshTimedPinSettingsControls()
        _ = toggleTimedPin(identifier: identifier, preset: preset)
    }

    @objc private func setItemHighlightFromMenu(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? [String: String],
              let identifier = context["identifier"],
              let rawValue = context["highlight"],
              let highlight = BoardManItemHighlight(rawValue: rawValue) else { return }
        BoardManItemHighlightStore.shared.set(highlight, for: identifier)
        placeholderList?.reloadData()
    }

    @objc private func clearItemHighlightFromMenu(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else { return }
        BoardManItemHighlightStore.shared.set(nil, for: identifier)
        placeholderList?.reloadData()
    }

    @objc private func copyFromMenu(_ sender: NSMenuItem) {
        guard let row = sender.representedObject as? Int,
              let item = historyItems[safe: row] else { return }
        _ = copyItemToClipboard(item)
    }

    private func syncLinkedSnippetTitles(historyIdentifier: String, title: String) {
        let linkedSnippetIdentifiers = HistorySnippetLinkStore.shared.snippetIdentifiers(forHistory: historyIdentifier)
        guard !linkedSnippetIdentifiers.isEmpty else { return }
        let normalizedTitle = normalizedSnippetTitle(title)
        linkedSnippetIdentifiers.forEach { identifier in
            guard let snippet = store.snippet(identifier: identifier) else { return }
            snippet.title = normalizedTitle
            store.upsertSnippet(
                snippet,
                folderIdentifier: store.folderIdentifier(forSnippetIdentifier: identifier)
            )
        }
    }

    private func syncLinkedHistoryDisplayName(snippetIdentifier: String, title: String) {
        guard let historyIdentifier = HistorySnippetLinkStore.shared.historyIdentifier(forSnippet: snippetIdentifier) else {
            return
        }
        HistoryDisplayNameStore.shared.setName(title, for: historyIdentifier)
        syncLinkedSnippetTitles(historyIdentifier: historyIdentifier, title: title)
    }

    private func defaultSnippetTitle(forHistoryIdentifier identifier: String) -> String? {
        guard let clip = BoardManStores.authoritative.clip(identifier: identifier) else { return nil }
        let rawTitle = clip.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTitle.isEmpty else { return nil }
        let firstLine = rawTitle.components(separatedBy: .newlines).first ?? rawTitle
        return normalizedSnippetTitle(String(firstLine.prefix(80)))
    }

    @objc private func setHistoryDisplayNameFromMenu(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else { return }
        let currentName = HistoryDisplayNameStore.shared.name(for: identifier) ?? ""
        let alert = NSAlert()
        alert.messageText = boardManText("Set Display Name…")
        alert.informativeText = boardManText("The original clipboard content is preserved for paste and preview.")
        alert.addButton(withTitle: boardManText("Save Changes"))
        alert.addButton(withTitle: boardManText("Cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = currentName
        field.placeholderString = boardManText("Display name")
        alert.accessoryView = field
        guard runSnippetPanelAlert(alert, initialFirstResponder: field) == .alertFirstButtonReturn else { return }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            NSSound.beep()
            return
        }
        HistoryDisplayNameStore.shared.setName(trimmed, for: identifier)
        syncLinkedSnippetTitles(historyIdentifier: identifier, title: trimmed)
        onRefreshRequested?()
    }

    @objc private func toggleHistoryNameOnlyFromMenu(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else { return }
        let store = HistoryDisplayNameStore.shared
        store.setNameOnly(!store.isNameOnly(identifier), for: identifier)
        onRefreshRequested?()
    }

    @objc private func removeHistoryDisplayNameFromMenu(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else { return }
        HistoryDisplayNameStore.shared.setName("", for: identifier)
        if let fallbackTitle = defaultSnippetTitle(forHistoryIdentifier: identifier) {
            syncLinkedSnippetTitles(historyIdentifier: identifier, title: fallbackTitle)
        }
        onRefreshRequested?()
    }

    @objc private func addHistoryItemToSnippetGroup(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? [String: String],
              let content = context["content"],
              let folderIdentifier = context["folder"],
              let historyIdentifier = context["history"],
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            return
        }
        let firstLine = content.components(separatedBy: .newlines).first ?? ""
        let snippet = BoardManSnippet()
        let existingDisplayName = HistoryDisplayNameStore.shared.name(for: historyIdentifier)
        snippet.title = normalizedSnippetTitle(existingDisplayName ?? String(firstLine.prefix(80)))
        snippet.content = content
        snippet.enable = true
        let folder = snippetTargetFolder(preferredIdentifier: folderIdentifier)
        snippet.index = folder.snippets.count
        store.upsertSnippet(snippet, folderIdentifier: folder.identifier)
        setActiveSnippetGroupIdentifiers([folder.identifier])
        HistorySnippetLinkStore.shared.link(
            snippetIdentifier: snippet.identifier,
            historyIdentifier: historyIdentifier
        )
        onRefreshRequested?()
    }

    @objc private func deleteHistoryItemFromMenu(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else { return }
        guard BoardManStores.authoritative.clip(identifier: identifier) != nil else {
            onRefreshRequested?()
            return
        }
        guard !PinnedSnippetStore.shared.isPinned(identifier),
              !BoardManTimedPinStore.shared.isPinned(identifier) else {
            NSSound.beep()
            return
        }

        let alert = NSAlert()
        alert.messageText = boardManText("Delete History Item")
        alert.informativeText = boardManText("Delete this item from clipboard history?")
        alert.alertStyle = .warning
        alert.addButton(withTitle: boardManText("Delete"))
        alert.addButton(withTitle: boardManText("Cancel"))
        guard runSnippetPanelAlert(alert) == .alertFirstButtonReturn else { return }
        guard let currentClip = BoardManStores.authoritative.clip(identifier: identifier) else {
            onRefreshRequested?()
            return
        }

        AppEnvironment.current.clipService.delete(with: currentClip)
        BoardManMaskedItemStore.shared.remove([identifier])
        BoardManItemHighlightStore.shared.remove([identifier])
        HistoryDisplayNameStore.shared.remove([identifier])
        HistorySnippetLinkStore.shared.unlinkHistory(identifier)
        selectedIndex = -1
        hidePreviewBubble()
        onRefreshRequested?()
    }

    @objc private func renameSnippetFromMenu(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else { return }
        guard let snippet = store.snippet(identifier: identifier) else {
            NSSound.beep()
            return
        }
        let alert = NSAlert()
        alert.messageText = boardManText("Rename Snippet…")
        alert.informativeText = boardManText("This changes the name shown in the snippet list.")
        alert.addButton(withTitle: boardManText("Save Changes"))
        alert.addButton(withTitle: boardManText("Cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = snippet.title
        field.placeholderString = boardManText("Untitled snippet")
        alert.accessoryView = field
        guard runSnippetPanelAlert(alert, initialFirstResponder: field) == .alertFirstButtonReturn else { return }
        let title = normalizedSnippetTitle(field.stringValue)
        BoardManSnippetEditingPolicy.persistTitle(title, snippet: snippet, store: store)
        syncLinkedHistoryDisplayName(snippetIdentifier: identifier, title: title)
        onRefreshRequested?()
        selectSnippetInCurrentList(identifier: identifier)
    }

    @objc private func editSnippetFromMenu(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String,
              let row = historyItems.firstIndex(where: { $0.dataHash == identifier && $0.source == .snippet }) else {
            NSSound.beep()
            return
        }
        setSelectedIndex(row)
        editSelectedSnippetFromPanel(sender)
    }

    @objc private func deleteSnippetFromMenu(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String,
              let row = historyItems.firstIndex(where: { $0.dataHash == identifier && $0.source == .snippet }) else {
            NSSound.beep()
            return
        }
        setSelectedIndex(row)
        deleteSelectedSnippetFromPanel(sender)
    }

    override func cancelOperation(_ sender: Any?) {
        hidePreviewBubble()
        self.orderOut(nil)  // Esc: hide/orderOut only (avoids V4B-6 crash, no terminate)
    }

    override func becomeKey() {
        super.becomeKey()
        installLocalKeyMonitorIfNeeded()
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        let previousAlpha = alphaValue
        layoutPanelSubviews()
        super.makeKeyAndOrderFront(sender)
        installLocalKeyMonitorIfNeeded()
        DispatchQueue.main.async { [weak self] in
            self?.alphaValue = previousAlpha == 0 ? 1 : previousAlpha
        }
    }

    override func orderOut(_ sender: Any?) {
        hidePreviewBubble()
        removeLocalKeyMonitor()
        super.orderOut(sender)
    }

    override func close() {
        hidePreviewBubble()
        removeLocalKeyMonitor()
        super.close()
    }

    override func resignKey() {
        hidePreviewBubble()
        super.resignKey()
    }

    override func resignMain() {
        hidePreviewBubble()
        super.resignMain()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        schedulePanelLayout()
    }

    private func schedulePanelLayout() {
        guard !isPanelLayoutScheduled else { return }
        isPanelLayoutScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isPanelLayoutScheduled = false
            self.layoutPanelSubviews()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if activeTab == .settings {
            super.scrollWheel(with: event)
            return
        }
        let horizontalDelta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.deltaX * 10
        let verticalDelta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 10
        guard let delta = Self.tabDelta(horizontalDelta: horizontalDelta, verticalDelta: verticalDelta),
              !isSnippetEditing,
              !isSearchFieldEditorActive,
              !(firstResponder is NSTextView) else {
            super.scrollWheel(with: event)
            return
        }

        horizontalScrollAccumulator += horizontalDelta
        horizontalScrollResetWorkItem?.cancel()
        let reset = DispatchWorkItem { [weak self] in self?.horizontalScrollAccumulator = 0 }
        horizontalScrollResetWorkItem = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: reset)
        guard abs(horizontalScrollAccumulator) >= 26 else { return }
        horizontalScrollAccumulator = 0
        let nextRaw = min(BoardManPanelTab.snippets.rawValue, max(BoardManPanelTab.history.rawValue, activeTab.rawValue + delta))
        guard let nextTab = BoardManPanelTab(rawValue: nextRaw), nextTab != activeTab else { return }
        activateTab(nextTab)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, activeTab == .settings {
            endSettingsEditingIfNeeded(for: event)
        }
        if event.type == .keyDown,
           (isUpArrow(event) || isDownArrow(event)) {
            if selectRowByKeyboard(delta: isDownArrow(event) ? 1 : -1) {
                return
            }
        }
        if event.type == .keyDown, shouldHandlePanelKey(event), handlePanelKey(event) {
            return
        }
        super.sendEvent(event)
    }

    private func endSettingsEditingIfNeeded(for event: NSEvent) {
        guard let editor = firstResponder as? NSTextView,
              let activeField = [
                maxHistorySizeValueLabel,
                timestampShortcutDelayField,
                timedPinDurationValueLabel,
                heightLabel,
                hideRuleTextField
              ].compactMap({ $0 }).first(where: { $0.currentEditor() === editor }),
              let contentView else { return }
        let point = contentView.convert(event.locationInWindow, from: nil)
        guard let hitView = contentView.hitTest(point) else { return }
        if hitView === activeField || hitView.isDescendant(of: activeField) { return }
        _ = makeFirstResponder(nil)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if shouldHandlePanelKey(event), handlePanelKey(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func shouldHandlePanelKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        if event.keyCode == 53 { return true }
        guard activeTab != .settings else { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command), [3, 8, 18, 19, 20, 35, 43].contains(Int(event.keyCode)) {
            if event.keyCode == 8 && isSearchFieldEditorActive { return false }
            return true
        }
        if event.keyCode == 49 && !isSearchFieldEditorActive { return true }
        if isUpArrow(event) || isDownArrow(event) { return true }
        guard let textView = firstResponder as? NSTextView else { return true }
        if searchField?.currentEditor() === textView {
            return event.keyCode == 36 || event.keyCode == 76 || isUpArrow(event) || isDownArrow(event)
        }
        return false
    }

    private var isSearchFieldEditorActive: Bool {
        guard let textView = firstResponder as? NSTextView else { return false }
        return searchField?.currentEditor() === textView
    }

    fileprivate func handlePanelKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if activeTab != .settings && modifiers.contains(.command) {
            switch event.keyCode {
            case 18:
                activateTab(.history)
                return true
            case 19:
                activateTab(.snippets)
                return true
            case 20, 43:
                activateTab(.settings)
                return true
            case 3:
                makeFirstResponder(searchField)
                searchField?.selectText(nil)
                return true
            case 8:
                guard !isSearchFieldEditorActive else { return false }
                return copySelectedItemToClipboard()
            case 35:
                return togglePinForSelectedItem()
            default:
                break
            }
        }
        if isDownArrow(event) {
            return selectRowByKeyboard(delta: 1)
        }
        if isUpArrow(event) {
            return selectRowByKeyboard(delta: -1)
        }

        switch event.keyCode {
        case 53:
            hidePreviewBubble()
            orderOut(nil)
            return true
        case 123:
            moveHorizontalNavigation(delta: -1)
            return true
        case 124:
            moveHorizontalNavigation(delta: 1)
            return true
        case 125:
            return selectRowByKeyboard(delta: 1)
        case 126:
            return selectRowByKeyboard(delta: -1)
        case 36, 76:
            guard activeTab != .settings else { return false }
            pasteSelectedRow()
            return true
        case 49:
            togglePreviewForSelectedRow()
            return true
        default:
            return false
        }
    }

    private func isUpArrow(_ event: NSEvent) -> Bool {
        return event.keyCode == 126 || eventContainsFunctionKey(event, UInt32(NSUpArrowFunctionKey))
    }

    private func isDownArrow(_ event: NSEvent) -> Bool {
        return event.keyCode == 125 || eventContainsFunctionKey(event, UInt32(NSDownArrowFunctionKey))
    }

    private func eventContainsFunctionKey(_ event: NSEvent, _ functionKey: UInt32) -> Bool {
        guard let characters = event.charactersIgnoringModifiers else { return false }
        return characters.unicodeScalars.contains { $0.value == functionKey }
    }

    private func exitSearchToSelectionIfNeeded() {
        guard isSearchFieldEditorActive else { return }
        makeFirstResponder(placeholderList)
    }

    private func moveHorizontalNavigation(delta: Int) {
        let target = BoardManPanelNavigationPolicy.target(
            activeTab: activeTab,
            activeSnippetGroupIdentifiers: activeSnippetGroupIdentifiers,
            snippetCategoryIdentifiers: horizontalSnippetCategoryIdentifiers(),
            delta: delta
        )
        switch target {
        case .history:
            activateTab(.history)
        case .snippets(let categoryIdentifier):
            openSnippetsManagerMode(categoryIdentifier: categoryIdentifier)
        case nil:
            break
        }
    }

    private func horizontalSnippetCategoryIdentifiers() -> [String] {
        let folders = store.foldersSortedByIndex()
        var identifiers = [BoardManPanel.allCategoriesIdentifier]
        identifiers.append(contentsOf: folders.map(\.identifier))
        if allItems.contains(where: {
            $0.source == .snippet && $0.categoryIdentifier == BoardManPanel.uncategorizedCategoryIdentifier
        }) {
            identifiers.append(BoardManPanel.uncategorizedCategoryIdentifier)
        }
        return identifiers
    }

    @discardableResult
    private func selectRowByKeyboard(delta: Int) -> Bool {
        guard activeTab != .settings,
              let table = placeholderList,
              !historyItems.isEmpty else {
            return false
        }
        let candidates = keyboardNavigableRows()
        guard !candidates.isEmpty else {
            selectedIndex = -1
            table.deselectAll(nil)
            return false
        }

        let tableRow = table.selectedRow
        let previous = historyItems.indices.contains(tableRow) ? tableRow : selectedIndex
        let next: Int
        if let candidateIndex = candidates.firstIndex(of: previous) {
            let nextCandidateIndex = max(0, min(candidates.count - 1, candidateIndex + delta))
            next = candidates[nextCandidateIndex]
        } else {
            next = delta < 0 ? candidates.last! : candidates.first!
        }

        if isSearchFieldEditorActive {
            searchField?.abortEditing()
        }
        makeFirstResponder(table)

        hoveredRow = -1
        keyboardPreviewLockUntil = CFAbsoluteTimeGetCurrent() + 0.35
        setSelectedIndex(next)
        table.scrollRowToVisible(next)
        showPreviewBubble(for: next)

        return true
    }

    private func configureHistoryCell(_ cell: BoardManHistoryCellView,
                                      item: BoardManHistoryItem,
                                      row: Int) {
        cell.toolTip = item.isPinned
            ? "Pinned • Hold or ⌥-click to unpin • ⌘C Copy • Space Preview"
            : "Hold or ⌥-click to pin • ⌘C Copy • ⌘P Pin • Space Preview"
        cell.configure(
            item: item,
            isSelected: selectedIndex == row,
            usageStyle: BoardManPanel.allowedUsageCountStyle(
                AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManUsageCountStyle)
            ),
            useLiquidGlass: isLiquidGlassEnabled,
            lightenTheme: isThemeLightenEnabled,
            themePreset: themePreset,
            timestampPosition: activeTab == .history ? timestampPosition : .below
        )
        cell.setSnippetInteractionMode(
            reorderMode: activeTab == .snippets && isSnippetReorderMode,
            accentColor: themeAccentColor
        )
    }

    private func refreshRowsInPlace(_ rows: IndexSet) {
        guard let table = placeholderList, !rows.isEmpty else { return }
        for row in rows where row >= 0 && row < historyItems.count {
            table.rowView(atRow: row, makeIfNecessary: false)?.needsDisplay = true
            guard let item = historyItems[safe: row],
                  let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? BoardManHistoryCellView else {
                continue
            }
            let existingFrame = cell.frame
            configureHistoryCell(cell, item: item, row: row)
            cell.frame = existingFrame
            cell.needsLayout = true
            cell.needsDisplay = true
        }
        table.needsDisplay = true
    }

    private func refreshSelectionRows(oldIndex: Int, newIndex: Int) {
        var rows = IndexSet()
        [oldIndex, newIndex].forEach { row in
            guard row >= 0, row < historyItems.count else { return }
            rows.insert(row)
        }
        refreshRowsInPlace(rows)
    }

    private func installLocalKeyMonitorIfNeeded() {
        guard localKeyMonitor == nil else { return }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.isVisible,
                  self.activeTab != .settings,
                  event.window === self || self.isKeyWindow || self.isMainWindow,
                  self.isUpArrow(event) || self.isDownArrow(event) else {
                return event
            }
            return self.selectRowByKeyboard(delta: self.isDownArrow(event) ? 1 : -1) ? nil : event
        }
    }

    private func removeLocalKeyMonitor() {
        guard let localKeyMonitor else { return }
        NSEvent.removeMonitor(localKeyMonitor)
        self.localKeyMonitor = nil
    }

    private func rowForCurrentSelection() -> Int {
        guard !historyItems.isEmpty else { return -1 }
        let tableRow = placeholderList?.selectedRow ?? -1
        if tableRow >= 0 && tableRow < historyItems.count {
            return tableRow
        }
        if selectedIndex >= 0 && selectedIndex < historyItems.count {
            return selectedIndex
        }
        return keyboardNavigableRows().first ?? 0
    }

    private func moveSelection(delta: Int) {
        _ = selectRowByKeyboard(delta: delta)
    }

    @discardableResult
    private func togglePin(identifier: String) -> Bool {
        let store = PinnedSnippetStore.shared
        if store.isPinned(identifier) {
            store.remove(identifier)
        } else {
            _ = store.add(identifier)
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        onRefreshRequested?()
        selectItemInCurrentList(identifier: identifier)
        return true
    }

    @discardableResult
    private func toggleTimedPin(identifier: String, preset: BoardManTimedPinPreset? = nil) -> Bool {
        let store = BoardManTimedPinStore.shared
        if store.isPinned(identifier) {
            store.remove(identifier)
        } else {
            let permanentStore = PinnedSnippetStore.shared
            permanentStore.remove(identifier)
            let selectedPreset = preset ?? BoardManTimedPinPresetStore.selectedPreset()
            guard store.setPin(
                identifier,
                durationValue: selectedPreset.value,
                unit: selectedPreset.unit,
                maximumActiveCount: nil
            ) else { return false }
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        onRefreshRequested?()
        selectItemInCurrentList(identifier: identifier)
        return true
    }

    @discardableResult
    private func toggleMask(identifier: String) -> Bool {
        _ = BoardManMaskedItemStore.shared.toggle(identifier)
        hidePreviewBubble()
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        onRefreshRequested?()
        selectItemInCurrentList(identifier: identifier)
        return true
    }

    @discardableResult
    private func togglePinForSelectedItem() -> Bool {
        let row = rowForCurrentSelection()
        guard let item = historyItems[safe: row] else { return false }
        setSelectedIndex(row)
        return togglePin(identifier: item.dataHash)
    }

    @discardableResult
    private func copySelectedItemToClipboard() -> Bool {
        let row = rowForCurrentSelection()
        guard let item = historyItems[safe: row] else { return false }
        setSelectedIndex(row)
        return copyItemToClipboard(item)
    }

    @discardableResult
    private func copyItemToClipboard(_ item: BoardManHistoryItem) -> Bool {
        switch item.source {
        case .clip:
            guard let clip = BoardManStores.authoritative.clip(identifier: item.dataHash) else {
                NSSound.beep()
                return false
            }
            AppEnvironment.current.pasteService.copyToPasteboard(with: clip)
        case .snippet:
            AppEnvironment.current.pasteService.copyToPasteboard(with: item.previewTitle)
        case .favorite:
            return false
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        return true
    }

    private func togglePreviewForSelectedRow() {
        let row = rowForCurrentSelection()
        guard row >= 0, historyItems[safe: row] != nil else { return }
        if previewBubblePanel?.isVisible == true {
            hidePreviewBubble()
        } else {
            setSelectedIndex(row)
            showPreviewBubble(for: row)
        }
    }

    private func selectItemInCurrentList(identifier: String) {
        applyCurrentFilter()
        guard let row = historyItems.firstIndex(where: { $0.dataHash == identifier }) else { return }
        setSelectedIndex(row)
        if historyItems[safe: row]?.source == .snippet {
            refreshSnippetEditor()
        }
    }

    private func pasteSelectedRow() {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let row = rowForCurrentSelection()
        guard let item = historyItems[safe: row] else { return }
        setSelectedIndex(row)
        guard item.isEnabled else {
            NSSound.beep()
            return
        }
        hidePreviewBubble()
        onPasteRequested?(item, startedAt)
    }

    fileprivate func setHoveredRow(_ row: Int) {
        guard row >= 0, historyItems[safe: row] != nil else { return }
        hoveredRow = row
        if activeTab == .snippets && !isSnippetEditing && !isSnippetReorderMode {
            setSelectedIndex(row)
        }
        refreshRowsInPlace(IndexSet(integer: row))
        if CFAbsoluteTimeGetCurrent() >= keyboardPreviewLockUntil {
            showPreviewBubble(for: row)
        }
    }

    fileprivate func clearHoveredRow(_ row: Int) {
        if hoveredRow == row {
            hoveredRow = -1
            hidePreviewBubble()
        }
        if row >= 0 {
            refreshRowsInPlace(IndexSet(integer: row))
        }
    }

    fileprivate func isSelectedRow(_ row: Int) -> Bool {
        return row >= 0 && row == selectedIndex
    }

    fileprivate func isHoveredRow(_ row: Int) -> Bool {
        return row >= 0 && row == hoveredRow
    }

    private func previewBubbleOrigin(width bubbleWidth: CGFloat, height bubbleHeight: CGFloat, preferOppositeSide: Bool) -> NSPoint {
        let panelFrame = frame
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panelFrame.insetBy(dx: -bubbleWidth, dy: -bubbleHeight)
        let gap: CGFloat = 12
        let panelIsLeftOfCenter = panelFrame.midX <= visibleFrame.midX
        let preferredRight = preferOppositeSide ? panelIsLeftOfCenter : true
        let rightX = panelFrame.maxX + gap
        let leftX = panelFrame.minX - bubbleWidth - gap
        let preferredX = preferredRight ? rightX : leftX
        let fallbackX = preferredRight ? leftX : rightX
        let bubbleX: CGFloat
        if preferredX >= visibleFrame.minX + gap && preferredX + bubbleWidth <= visibleFrame.maxX - gap {
            bubbleX = preferredX
        } else if fallbackX >= visibleFrame.minX + gap && fallbackX + bubbleWidth <= visibleFrame.maxX - gap {
            bubbleX = fallbackX
        } else {
            bubbleX = min(max(visibleFrame.minX + gap, preferredX), visibleFrame.maxX - bubbleWidth - gap)
        }
        let desiredY = panelFrame.maxY - bubbleHeight - 54
        let bubbleY = min(max(visibleFrame.minY + gap, desiredY), visibleFrame.maxY - bubbleHeight - gap)
        return NSPoint(x: bubbleX, y: bubbleY)
    }

    fileprivate func itemHighlightAppearance(for row: Int) -> (background: NSColor, border: NSColor, borderWidth: CGFloat)? {
        guard row >= 0,
              let item = historyItems[safe: row],
              let highlight = BoardManItemHighlightStore.shared.highlight(for: item.dataHash) else { return nil }
        let base = highlight.color
        let backgroundAlpha: CGFloat = isThemeLightenEnabled ? 0.10 : (isLiquidGlassEnabled ? 0.22 : 0.18)
        let borderAlpha: CGFloat = isThemeLightenEnabled ? 0.34 : 0.58
        return (base.withAlphaComponent(backgroundAlpha), base.withAlphaComponent(borderAlpha), 1.25)
    }

    fileprivate func isPinnedRow(_ row: Int) -> Bool {
        return row >= 0 && historyItems[safe: row]?.isPinned == true
    }

    fileprivate func usedItemAppearance(for row: Int) -> (background: NSColor, border: NSColor, borderWidth: CGFloat)? {
        guard row >= 0,
              let item = historyItems[safe: row],
              item.pasteCount >= 1,
              !item.isPinned else { return nil }
        if AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManCustomUsedColor) != nil {
            let base = BoardManPanel.customColor(
                forKey: Constants.UserDefaults.boardManCustomUsedColor,
                fallback: .systemGray
            )
            return (customUsedTintColor, base.withAlphaComponent(max(0.28, customUsedTintColor.alphaComponent * 1.8)), 1)
        }
        let storedStyle = BoardManPanel.allowedUsedItemStyle(AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManUsedItemStyle))
        let style = uiStyle == .monochrome ? "Monochrome" : storedStyle
        let alpha: CGFloat
        if uiStyle == .simple {
            alpha = isThemeLightenEnabled ? 0.05 : 0.09
        } else {
            alpha = isThemeLightenEnabled ? 0.09 : (isLiquidGlassEnabled ? 0.16 : 0.20)
        }
        let borderAlpha: CGFloat = uiStyle == .simple ? 0.24 : (isThemeLightenEnabled ? 0.24 : 0.42)
        switch style {
        case "Subtle Red":
            return (NSColor.systemRed.withAlphaComponent(alpha), NSColor.systemRed.withAlphaComponent(borderAlpha), 1)
        case "Amber":
            return (NSColor.systemOrange.withAlphaComponent(alpha), NSColor.systemOrange.withAlphaComponent(borderAlpha), 1)
        case "Blue":
            return (NSColor.systemBlue.withAlphaComponent(alpha), NSColor.systemBlue.withAlphaComponent(borderAlpha), 1)
        case "Teal":
            return (NSColor.systemTeal.withAlphaComponent(alpha), NSColor.systemTeal.withAlphaComponent(borderAlpha), 1)
        case "Green":
            return (NSColor.systemGreen.withAlphaComponent(alpha), NSColor.systemGreen.withAlphaComponent(borderAlpha), 1)
        case "Purple":
            return (NSColor.systemPurple.withAlphaComponent(alpha), NSColor.systemPurple.withAlphaComponent(borderAlpha), 1)
        case "Indigo":
            return (NSColor.systemIndigo.withAlphaComponent(alpha), NSColor.systemIndigo.withAlphaComponent(borderAlpha), 1)
        case "Gray":
            return (NSColor.systemGray.withAlphaComponent(alpha), NSColor.systemGray.withAlphaComponent(borderAlpha), 1)
        case "Monochrome":
            return (NSColor.labelColor.withAlphaComponent(isLiquidGlassEnabled ? 0.10 : 0.08), NSColor.separatorColor.withAlphaComponent(0.70), 1)
        default:
            return nil
        }
    }

    private func setSelectedIndex(_ row: Int) {
        guard row >= 0, row < historyItems.count else { return }
        let oldIndex = selectedIndex
        let nextIdentifier = historyItems[safe: row]?.dataHash
        if isSnippetEditing, editingSnippetIdentifier != nextIdentifier {
            isSnippetEditing = false
            editingSnippetIdentifier = nil
            _ = makeFirstResponder(nil)
        }
        selectedIndex = row
        updateSnippetActionButtons()
        syncNativeSelection()
        refreshSelectionRows(oldIndex: oldIndex, newIndex: row)
        refreshSnippetEditor()
        if !isSnippetEditing,
           !isSnippetReorderMode,
           CFAbsoluteTimeGetCurrent() >= keyboardPreviewLockUntil {
            showPreviewBubble(for: row)
        } else {
            hidePreviewBubble()
        }
    }

    private func syncNativeSelection() {
        guard let table = placeholderList else { return }
        if selectedIndex >= 0, selectedIndex < historyItems.count {
            table.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        } else {
            table.deselectAll(nil)
            hidePreviewBubble()
        }
    }

    fileprivate func showPreviewBubble(for row: Int) {
        guard row >= 0,
              let item = historyItems[safe: row],
              let bubble = previewBubblePanel,
              let label = previewBubbleLabel,
              let imageView = previewBubbleImageView else {
            hidePreviewBubble()
            return
        }
        if item.isMasked && AppEnvironment.current.defaults.bool(
            forKey: Constants.UserDefaults.boardManHidePreviewForMaskedItems
        ) {
            hidePreviewBubble()
            return
        }
        if let image = previewImage(for: item) {
            showImagePreview(image, in: bubble, imageView: imageView, label: label)
            return
        }
        imageView.isHidden = true
        imageView.image = nil
        label.isHidden = false
        let previewText = item.isMasked ? "＊＊＊＊＊" : item.previewTitle
        label.stringValue = previewText
        let previewScale = effectiveTextPreviewScale
        label.font = fontChoice.font(ofSize: 12 * previewScale)
        let maxWidth: CGFloat = 340 * previewScale
        let padding: CGFloat = 12 * previewScale
        let maxLabelSize = NSSize(width: maxWidth - (padding * 2), height: 150 * previewScale)
        let textSize = (previewText as NSString).boundingRect(
            with: maxLabelSize,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: label.font ?? NSFont.systemFont(ofSize: 12)]
        ).size
        let bubbleWidth = min(maxWidth, max(180 * previewScale, ceil(textSize.width) + (padding * 2)))
        let bubbleHeight = min(174 * previewScale, max(48 * previewScale, ceil(textSize.height) + (padding * 2)))
        label.frame = NSRect(x: padding, y: padding, width: bubbleWidth - (padding * 2), height: bubbleHeight - (padding * 2))
        bubble.contentView?.frame = NSRect(x: 0, y: 0, width: bubbleWidth, height: bubbleHeight)
        let useGlass = isLiquidGlassEnabled
        let lightenTheme = isThemeLightenEnabled
        if let effectView = bubble.contentView as? NSVisualEffectView {
            effectView.material = useGlass ? themePreset.glassMaterial : .popover
            effectView.blendingMode = useGlass ? .behindWindow : .withinWindow
        }
        bubble.contentView?.layer?.backgroundColor = themePreset.surfaceTintColor(useLiquidGlass: useGlass, lighten: lightenTheme).withAlphaComponent(useGlass ? 0.42 : 0.94).cgColor
        bubble.contentView?.layer?.borderColor = themeAccentColor.withAlphaComponent(lightenTheme ? 0.18 : (useGlass ? 0.46 : 0.42)).cgColor
        bubble.contentView?.layer?.borderWidth = 1
        bubble.contentView?.layer?.shadowColor = themePreset.shadowColor(useLiquidGlass: useGlass, lighten: lightenTheme).cgColor
        bubble.contentView?.layer?.shadowOpacity = Float(lightenTheme ? 0.05 : (useGlass ? 0.22 : 0.10))
        label.textColor = useGlass ? .labelColor : .labelColor

        let origin = previewBubbleOrigin(width: bubbleWidth, height: bubbleHeight, preferOppositeSide: true)
        bubble.setFrame(NSRect(x: origin.x, y: origin.y, width: bubbleWidth, height: bubbleHeight), display: true)
        bubble.orderFront(nil)
    }

    private func previewImage(for item: BoardManHistoryItem) -> NSImage? {
        guard !item.isMasked, item.source == .clip, !item.imageDataPath.isEmpty,
              let data = NSKeyedUnarchiver.unarchiveObject(withFile: item.imageDataPath) as? BoardManClipData else {
            return nil
        }
        if let image = data.image {
            return image
        }
        if let fileName = data.fileNames.first {
            return NSImage(contentsOfFile: fileName)
        }
        return nil
    }

    private func showImagePreview(_ image: NSImage, in bubble: NSPanel, imageView: NSImageView, label: NSTextField) {
        label.isHidden = true
        imageView.isHidden = false
        imageView.image = image

        let panelFrame = frame
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panelFrame.insetBy(dx: -420, dy: -320)
        let previewScale = effectiveImagePreviewScale
        let maxImageSize = NSSize(width: min(840, max(130, min(420, max(260, visibleFrame.width * 0.46)) * previewScale)),
                                  height: min(640, max(100, min(320, max(200, visibleFrame.height * 0.50)) * previewScale)))
        let imageSize = image.size
        let scale: CGFloat
        if imageSize.width <= 0 || imageSize.height <= 0 {
            scale = 1
        } else {
            scale = min(
                maxImageSize.width / imageSize.width,
                maxImageSize.height / imageSize.height,
                max(1, previewScale)
            )
        }
        let displayWidth = max(90, min(maxImageSize.width, ceil(imageSize.width * scale)))
        let displayHeight = max(60, min(maxImageSize.height, ceil(imageSize.height * scale)))
        let padding: CGFloat = 14 * previewScale
        let bubbleWidth = displayWidth + (padding * 2)
        let bubbleHeight = displayHeight + (padding * 2)
        imageView.frame = NSRect(x: padding, y: padding, width: displayWidth, height: displayHeight)
        bubble.contentView?.frame = NSRect(x: 0, y: 0, width: bubbleWidth, height: bubbleHeight)

        let useGlass = isLiquidGlassEnabled
        let lightenTheme = isThemeLightenEnabled
        if let effectView = bubble.contentView as? NSVisualEffectView {
            effectView.material = useGlass ? themePreset.glassMaterial : .popover
            effectView.blendingMode = useGlass ? .behindWindow : .withinWindow
        }
        bubble.contentView?.layer?.backgroundColor = themePreset.surfaceTintColor(useLiquidGlass: useGlass, lighten: lightenTheme).withAlphaComponent(useGlass ? 0.42 : 0.94).cgColor
        bubble.contentView?.layer?.borderColor = themeAccentColor.withAlphaComponent(lightenTheme ? 0.18 : (useGlass ? 0.46 : 0.42)).cgColor
        bubble.contentView?.layer?.borderWidth = 1
        bubble.contentView?.layer?.shadowColor = themePreset.shadowColor(useLiquidGlass: useGlass, lighten: lightenTheme).cgColor
        bubble.contentView?.layer?.shadowOpacity = Float(lightenTheme ? 0.05 : (useGlass ? 0.22 : 0.10))

        let origin = previewBubbleOrigin(width: bubbleWidth, height: bubbleHeight, preferOppositeSide: true)
        bubble.setFrame(NSRect(x: origin.x, y: origin.y, width: bubbleWidth, height: bubbleHeight), display: true)
        bubble.orderFront(nil)
    }

    fileprivate func hidePreviewBubble() {
        previewBubbleImageView?.image = nil
        previewBubbleImageView?.isHidden = true
        previewBubbleLabel?.isHidden = false
        previewBubblePanel?.orderOut(nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {  // Escape
            hidePreviewBubble()
            self.orderOut(nil)
            return
        }
        if handlePanelKey(event) {
            return
        }
        super.keyDown(with: event)
    }

    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return true
    }
}

extension BoardManPanel: NSSearchFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let search = searchField, control === search, activeTab != .settings else { return false }
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            _ = selectRowByKeyboard(delta: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            _ = selectRowByKeyboard(delta: -1)
            return true
        case #selector(NSResponder.insertNewline(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            pasteSelectedRow()
            return true
        default:
            return false
        }
    }
}

extension BoardManPanel: RecordViewDelegate {
    func recordViewShouldBeginRecording(_ recordView: RecordView) -> Bool {
        return recordView === timestampShortcutRecordView
            || globalShortcutRows.contains { $0.recordView === recordView }
            || snippetShortcutRows.contains { $0.recordView === recordView }
    }

    func recordView(_ recordView: RecordView, canRecordKeyCombo keyCombo: KeyCombo) -> Bool {
        guard recordViewShouldBeginRecording(recordView) else { return false }
        if recordView === timestampShortcutRecordView {
            guard !keyCombo.doubledModifiers else {
                NSSound.beep()
                return false
            }
            return true
        }
        let candidate = BoardManPanel.shortcutText(keyCombo)
        let globalConflict = globalShortcutRows.contains {
            $0.recordView !== recordView && BoardManPanel.shortcutText($0.recordView.keyCombo) == candidate
        }
        let folderConflict = snippetShortcutRows.contains {
            $0.recordView !== recordView && BoardManPanel.shortcutText($0.recordView.keyCombo) == candidate
        }
        guard !globalConflict && !folderConflict else {
            shortcutStatusLabel?.stringValue = "That shortcut is already assigned. Choose another combination."
            NSSound.beep()
            return false
        }
        return true
    }

    func recordView(_ recordView: RecordView, didChangeKeyCombo keyCombo: KeyCombo?) {
        if recordView === timestampShortcutRecordView {
            let saved = keyCombo ?? BoardManTimestampShortcutStore.defaultKeyCombo
            BoardManTimestampShortcutStore.save(saved)
            recordView.keyCombo = saved
            return
        }
        if let row = globalShortcutRows.first(where: { $0.recordView === recordView }) {
            applyGlobalShortcut(row.kind, keyCombo: keyCombo)
            shortcutStatusLabel?.stringValue = keyCombo == nil
                ? "\(row.kind.title) shortcut cleared."
                : "\(row.kind.title) updated to \(BoardManPanel.shortcutText(keyCombo))."
            refreshGlobalShortcutRows()
            return
        }
        guard let row = snippetShortcutRows.first(where: { $0.recordView === recordView }) else { return }
        AppEnvironment.current.hotKeyService.setSnippetKeyCombo(keyCombo, forFolder: row.folderIdentifier)
        refreshSnippetSettingsSummary()
        layoutPanelSubviews()
    }

    func recordViewDidEndRecording(_ recordView: RecordView) {}
}

extension BoardManPanel: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === maxHistorySizeValueLabel {
            maxHistorySizeFieldChanged(field)
        } else if field === timedPinDurationValueLabel {
            timedPinDurationFieldChanged(field)
        } else if field === timestampShortcutDelayField {
            timestampShortcutDelayFieldChanged(field)
        } else if field === heightLabel {
            panelHeightFieldChanged(field)
        } else if field === snippetEditorTitleField, !isSnippetEditing {
            snippetTitleFieldChanged(field)
        }
    }
}

extension BoardManPanel: NSGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
        if gestureRecognizer === snippetEditorClickGesture {
            if let editorView = snippetEditorView,
               let titleField = snippetEditorTitleField,
               titleField.frame.insetBy(dx: -4, dy: -4).contains(gestureRecognizer.location(in: editorView)) {
                return false
            }
            return BoardManSnippetEditingPolicy.shouldBeginEditorContainerClick(
                isSnippetTab: activeTab == .snippets,
                isEditing: isSnippetEditing,
                hasSelection: selectedSnippetItem != nil
            )
        }
        if gestureRecognizer is NSPressGestureRecognizer {
            return activeTab != .settings && !(activeTab == .snippets && isSnippetReorderMode)
        }
        if let click = gestureRecognizer as? NSClickGestureRecognizer,
           click.buttonMask == 0x1,
           activeTab == .snippets,
           isSnippetReorderMode {
            return false
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer) -> Bool {
        let includesPress = gestureRecognizer is NSPressGestureRecognizer || otherGestureRecognizer is NSPressGestureRecognizer
        let includesClick = gestureRecognizer is NSClickGestureRecognizer || otherGestureRecognizer is NSClickGestureRecognizer
        return includesPress && includesClick
    }
}

// Basic data source for placeholder list (embedded to avoid extra files)
extension BoardManPanel: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        return max(historyItems.count, 1)
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard activeTab == .snippets,
              isSnippetReorderMode,
              activeSnippetCategoryIdentifier != BoardManPanel.allCategoriesIdentifier,
              let item = historyItems[safe: row],
              item.source == .snippet,
              item.categoryIdentifier == activeSnippetCategoryIdentifier else { return nil }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(item.dataHash, forType: BoardManPanel.snippetDragType)
        return pasteboardItem
    }

    func tableView(_ tableView: NSTableView,
                   validateDrop info: NSDraggingInfo,
                   proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard activeTab == .snippets,
              isSnippetReorderMode,
              activeSnippetCategoryIdentifier != BoardManPanel.allCategoriesIdentifier,
              info.draggingPasteboard.string(forType: BoardManPanel.snippetDragType) != nil else { return [] }
        tableView.setDropRow(max(0, min(row, historyItems.count)), dropOperation: .above)
        return .move
    }

    func tableView(_ tableView: NSTableView,
                   acceptDrop info: NSDraggingInfo,
                   row destinationRow: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard activeTab == .snippets,
              isSnippetReorderMode,
              activeSnippetCategoryIdentifier != BoardManPanel.allCategoriesIdentifier,
              let identifier = info.draggingPasteboard.string(forType: BoardManPanel.snippetDragType) else { return false }
        let visibleIdentifiers = historyItems.compactMap { item -> String? in
            guard item.source == .snippet,
                  item.categoryIdentifier == activeSnippetCategoryIdentifier else { return nil }
            return item.dataHash
        }
        let reorderedIdentifiers = BoardManSnippetEditingPolicy.reorderedIdentifiers(
            visibleIdentifiers,
            moving: identifier,
            to: destinationRow
        )
        guard reorderedIdentifiers != visibleIdentifiers else { return false }

        let folderIdentifier = activeSnippetCategoryIdentifier == BoardManPanel.uncategorizedCategoryIdentifier
            ? nil
            : activeSnippetCategoryIdentifier
        store.reorderSnippets(reorderedIdentifiers, folderIdentifier: folderIdentifier)
        onRefreshRequested?()
        selectSnippetInCurrentList(identifier: identifier)
        return true
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let identifier = NSUserInterfaceItemIdentifier("BoardManHistoryRowView")
        let rowView = tableView.makeView(withIdentifier: identifier, owner: self) as? BoardManHistoryRowView ?? BoardManHistoryRowView()
        rowView.identifier = identifier
        rowView.previewOwner = self
        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if historyItems.isEmpty {
            let identifier = NSUserInterfaceItemIdentifier("emptyCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField ?? NSTextField(labelWithString: "")
            cell.identifier = identifier
            cell.stringValue = activeTab.emptyMessage
            cell.toolTip = nil
            cell.textColor = .secondaryLabelColor
            cell.backgroundColor = .clear
            cell.drawsBackground = false
            cell.alignment = .center
            cell.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            return cell
        }

        guard let item = historyItems[safe: row] else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("BoardManHistoryCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? BoardManHistoryCellView ?? BoardManHistoryCellView(frame: .zero)
        cell.identifier = identifier
        configureHistoryCell(cell, item: item, row: row)
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if activeTab == .history, timestampPosition != .below {
            return LayoutMetrics.compactHistoryRowHeight
        }
        return LayoutMetrics.historyRowHeight
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let oldIndex = selectedIndex
        if let row = placeholderList?.selectedRow, row >= 0, row < historyItems.count {
            let nextIdentifier = historyItems[safe: row]?.dataHash
            if isSnippetEditing, editingSnippetIdentifier != nextIdentifier {
                isSnippetEditing = false
                editingSnippetIdentifier = nil
                _ = makeFirstResponder(nil)
            }
            selectedIndex = row
            refreshSelectionRows(oldIndex: oldIndex, newIndex: row)
            if isSnippetEditing || isSnippetReorderMode {
                hidePreviewBubble()
            } else {
                showPreviewBubble(for: row)
            }
            refreshSnippetEditor()
        }
        updateSnippetActionButtons()
    }
}
