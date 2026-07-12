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
import KeyHolder
import Magnet
import PINCache
import RealmSwift
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
    fileprivate var previousFrontmostApplication: NSRunningApplication?
    // Icon Cache
    fileprivate let folderIcon = NSImage(resource: .iconFolder)
    fileprivate let snippetIcon = NSImage(resource: .iconText)
    // Other
    fileprivate let disposeBag = DisposeBag()
    fileprivate let notificationCenter = NotificationCenter.default
    fileprivate let kMaxKeyEquivalents = 10
    fileprivate let shortenSymbol = "..."
    // Realm
    fileprivate let realm = try! Realm()
    fileprivate var clipToken: NotificationToken?
    fileprivate var snippetToken: NotificationToken?

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
        previousFrontmostApplication = nil
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

    func popUpSnippetFolder(_ folder: CPYFolder) {
        showBoardManSnippetsPanel(folderIdentifier: folder.identifier)
    }

    fileprivate func showBoardManPanel(anchorPoint: NSPoint? = nil) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        previousFrontmostApplication = NSWorkspace.shared.frontmostApplication
        if boardManPanel == nil {
            boardManPanel = BoardManPanel()
            boardManPanel?.onPasteRequested = { [weak self] item, clickStartedAt in
                switch item.source {
                case .clip:
                    self?.handlePanelPaste(dataHash: item.dataHash, clickStartedAt: clickStartedAt)
                case .snippet:
                    self?.handlePanelSnippetPaste(identifier: item.dataHash, clickStartedAt: clickStartedAt)
                case .favorite:
                    NSSound.beep()
                }
            }
            boardManPanel?.onRefreshRequested = { [weak self] in
                guard let strongSelf = self, let panel = strongSelf.boardManPanel else { return }
                panel.reloadHistoryItems(strongSelf.boardManPanelItems())
            }
        }
        if let panel = boardManPanel {
            // V4B-13: position and show first. Heavy Realm/defaults reload happens after first paint.
            let panelSize = NSSize(width: BoardManPanel.preferredPanelWidth(), height: BoardManPanel.preferredPanelHeight())
            let finalFrame = BoardManPanel.cursorRelativeFrame(size: panelSize, anchorPoint: anchorPoint)
            panel.prepareForFirstVisibleOrder(frame: finalFrame)
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            panel.focusTableForKeyboard()
            PasteCountInputService.shared.logBoardManPerformance("panel_visible_fast", startedAt: startedAt, details: "items=\(panel.itemCount)")

            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) { [weak self, weak panel] in
                guard let self, let panel else { return }
                panel.reloadHistoryItems(self.boardManInitialPanelItems())
                panel.focusTableForKeyboard()
            }
        }
    }

    func showBoardManSettingsPanel() {
        showBoardManPanel()
        boardManPanel?.selectSettingsTab()
    }

    func showBoardManSnippetsPanel(folderIdentifier: String? = nil) {
        showBoardManPanel()
        guard let panel = boardManPanel else { return }
        panel.openSnippetsManagerMode(categoryIdentifier: folderIdentifier)
        panel.reloadHistoryItems(boardManPanelItems())
        panel.focusTableForKeyboard()
    }

    fileprivate func handlePanelPaste(dataHash: String, clickStartedAt: CFAbsoluteTime?) {
        guard let panel = boardManPanel else { return }

        // V4B-15: close panel first, restore target app, then paste directly.
        // Avoid dummy NSMenuItem + AppDelegate.selectClipMenuItem indirection.
        panel.orderOut(nil)

        if let prevApp = previousFrontmostApplication {
            prevApp.activate(options: [.activateIgnoringOtherApps])
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            guard let self else { return }

            if let clickStartedAt {
                PasteCountInputService.shared.logBoardManPerformance("panel_direct_paste_dispatch", startedAt: clickStartedAt)
            }

            let realm = try! Realm()
            guard let clip = realm.object(ofType: CPYClip.self, forPrimaryKey: dataHash) else {
                CPYUtilities.sendCustomLog(with: "BoardMan direct paste: cannot fetch clip")
                NSSound.beep()
                self.previousFrontmostApplication = nil
                return
            }

            let didPaste = AppEnvironment.current.pasteService.paste(with: clip)

            if didPaste {
                let pasteCountKey = PasteCountStore.shared.key(for: clip)
                PasteCountStore.shared.markUsed(clip: clip, in: realm)
                PasteCountStore.shared.increment(forKey: pasteCountKey)
            }

            self.previousFrontmostApplication = nil
        }
    }

    fileprivate func handlePanelSnippetPaste(identifier: String, clickStartedAt: CFAbsoluteTime?) {
        guard let panel = boardManPanel else { return }
        panel.orderOut(nil)

        if let prevApp = previousFrontmostApplication {
            prevApp.activate(options: [.activateIgnoringOtherApps])
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            guard let self else { return }

            if let clickStartedAt {
                PasteCountInputService.shared.logBoardManPerformance("panel_snippet_paste_dispatch", startedAt: clickStartedAt)
            }

            let realm = try! Realm()
            guard let snippet = realm.object(ofType: CPYSnippet.self, forPrimaryKey: identifier) else {
                CPYUtilities.sendCustomLog(with: "BoardMan direct paste: cannot fetch snippet")
                NSSound.beep()
                self.previousFrontmostApplication = nil
                return
            }
            guard snippet.enable, snippet.folder?.enable ?? true else {
                NSSound.beep()
                self.previousFrontmostApplication = nil
                return
            }

            AppEnvironment.current.pasteService.copyToPasteboard(with: snippet.content)
            AppEnvironment.current.pasteService.paste()
            self.previousFrontmostApplication = nil
        }
    }

    fileprivate func boardManPanelItems() -> [BoardManHistoryItem] {
        return boardManHistoryItems() + boardManSnippetItems()
    }

    fileprivate func boardManInitialPanelItems() -> [BoardManHistoryItem] {
        return boardManHistoryItems()
    }

    fileprivate func boardManHistoryItems() -> [BoardManHistoryItem] {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let maxHistory = max(1, AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxHistorySize))
        let ascending = !AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.reorderClipsAfterPasting)
        let clipResults = realm.objects(CPYClip.self).sorted(byKeyPath: #keyPath(CPYClip.updateTime), ascending: ascending)
        let defaults = AppEnvironment.current.defaults
        let showRowNumbers = defaults.object(forKey: Constants.UserDefaults.boardManShowRowNumbers) as? Bool ?? true
        let timestampFormat = BoardManPanel.allowedTimestampFormat(defaults.string(forKey: Constants.UserDefaults.boardManTimestampFormat))
        let showUsageCount = defaults.object(forKey: Constants.UserDefaults.boardManShowUsageCount) as? Bool ?? true

        let pinStore = PinnedSnippetStore.shared
        let panelHistoryLimit = min(maxHistory, 120)  // Keep panel launch fast; full history remains in Realm.
        let items = Array(clipResults.prefix(panelHistoryLimit)).enumerated().map { index, clip in
            let rawTitle = clip.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let isImageClip = BoardManPanel.isImageClip(clip)
            let title = rawTitle.isEmpty ? (isImageClip ? BoardManPanel.imageClipTitle(for: clip) : "(empty clipboard item)") : rawTitle
            let firstLine = title.components(separatedBy: .newlines).first ?? title
            let clipped = firstLine.count > 120 ? String(firstLine.prefix(117)) + "..." : firstLine
            let pasteCount = PasteCountStore.shared.count(for: clip)
            let isPinned = pinStore.isPinned(clip.dataHash)
            var parts: [String] = []
            if showRowNumbers {
                parts.append("\(index + 1).")
            }
            let timestamp = BoardManPanel.timestampText(for: clip.updateTime, format: timestampFormat)
            if !timestamp.isEmpty {
                parts.append(timestamp)
            }
            if isPinned {
                parts.append("[PIN]")
            }
            if isImageClip {
                parts.append("Image")
            }
            let countText = showUsageCount && pasteCount > 0 ? "\(pasteCount)" : ""
            let displayTitle = (parts + [clipped]).joined(separator: " ")
            return BoardManHistoryItem(title: displayTitle,
                                       primaryTitle: clipped,
                                       metadataText: parts.joined(separator: "   "),
                                       countText: countText,
                                       previewTitle: title,
                                       dataHash: clip.dataHash,
                                       imageDataPath: clip.dataPath,
                                       inlineThumbnail: isImageClip ? PINCache.shared.object(forKey: clip.thumbnailPath) as? NSImage : nil,
                                       pasteCount: pasteCount,
                                       isPinned: isPinned,
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
        let folderResults = realm.objects(CPYFolder.self).sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)
        let folderItems = Array(folderResults
            .flatMap { folder -> [BoardManHistoryItem] in
                folder.snippets
                    .sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true)
                    .map { snippet in
                        let rawTitle = snippet.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let title = rawTitle.isEmpty ? "(untitled snippet)" : rawTitle
                        let folderTitle = folder.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let prefix = folderTitle.isEmpty ? "Snippet" : folderTitle
                        let isPinned = pinStore.isPinned(snippet.identifier)
                        let pin = isPinned ? "[PIN] " : ""
                        let disabled = folder.enable && snippet.enable ? "" : " [OFF]"
                        return BoardManHistoryItem(title: "\(pin)\(prefix) / \(title)",
                                                   primaryTitle: title,
                                                   metadataText: "\(pin)\(prefix)\(disabled)",
                                                   countText: "",
                                                   previewTitle: snippet.content,
                                                   dataHash: snippet.identifier,
                                                   imageDataPath: "",
                                                   inlineThumbnail: nil,
                                                   pasteCount: 0,
                                                   isPinned: isPinned,
                                                   isEnabled: folder.enable && snippet.enable,
                                                   source: .snippet,
                                                   categoryIdentifier: folder.identifier,
                                                   categoryTitle: prefix)
                    }
            })
        var folderSnippetIdentifiers = Set<String>()
        folderResults.forEach { folder in
            folder.snippets.forEach { snippet in
                folderSnippetIdentifiers.insert(snippet.identifier)
            }
        }
        let uncategorizedItems = Array(realm.objects(CPYSnippet.self)
            .filter { !folderSnippetIdentifiers.contains($0.identifier) }
            .map { snippet -> BoardManHistoryItem in
                let rawTitle = snippet.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = rawTitle.isEmpty ? "(untitled snippet)" : rawTitle
                let isPinned = pinStore.isPinned(snippet.identifier)
                let pin = isPinned ? "[PIN] " : ""
                let disabled = snippet.enable ? "" : " [OFF]"
                return BoardManHistoryItem(title: "\(pin)Uncategorized / \(title)",
                                           primaryTitle: title,
                                           metadataText: "\(pin)Uncategorized\(disabled)",
                                           countText: "",
                                           previewTitle: snippet.content,
                                           dataHash: snippet.identifier,
                                           imageDataPath: "",
                                           inlineThumbnail: nil,
                                           pasteCount: 0,
                                           isPinned: isPinned,
                                           isEnabled: snippet.enable,
                                           source: .snippet,
                                           categoryIdentifier: BoardManPanel.uncategorizedCategoryIdentifier,
                                           categoryTitle: "Uncategorized")
            })
        return (folderItems + uncategorizedItems)
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

}

// MARK: - Binding
private extension MenuManager {
    func bind() {
        // Realm Notification
        clipToken = realm.objects(CPYClip.self)
                        .observe { [weak self] _ in
                            DispatchQueue.main.async { [weak self] in
                                self?.createClipMenu()
                            }
                        }
        snippetToken = realm.objects(CPYFolder.self)
                        .observe { [weak self] _ in
                            DispatchQueue.main.async { [weak self] in
                                self?.createClipMenu()
                            }
                        }
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
                guard let wSelf = self else { return }
                wSelf.createClipMenu()
            })
            .disposed(by: disposeBag)
        // Edit snippets
        notificationCenter.rx.notification(Notification.Name(rawValue: Constants.Notification.closeSnippetEditor))
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] _ in
                self?.createClipMenu()
            })
            .disposed(by: disposeBag)
        notificationCenter.rx.notification(Notification.Name(rawValue: Constants.Notification.pasteCountDidChange))
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] _ in
                self?.createClipMenu()
            })
            .disposed(by: disposeBag)
        // Observe change preference settings
        let defaults = AppEnvironment.current.defaults
        var menuChangedObservables = [Observable<Void>]()
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.addClearHistoryMenuItem, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.maxHistorySize, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.showIconInTheMenu, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.numberOfItemsPlaceInline, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.numberOfItemsPlaceInsideFolder, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.maxMenuItemTitleLength, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.menuItemsTitleStartWithZero, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.menuItemsAreMarkedWithNumbers, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.showToolTipOnMenuItem, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.showImageInTheMenu, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.addNumericKeyEquivalents, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Int.self, Constants.UserDefaults.maxLengthOfToolTip, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        menuChangedObservables.append(defaults.rx.observe(Bool.self, Constants.UserDefaults.showColorPreviewInTheMenu, options: [.new], retainSelf: false)
                                        .compactMap { $0 }.distinctUntilChanged().map { _ in })
        Observable.merge(menuChangedObservables)
            .throttle(.seconds(1), scheduler: MainScheduler.instance)
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] in
                self?.createClipMenu()
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
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Quit Board-Man"), action: #selector(AppDelegate.terminate)))

        clipMenu = menu
        historyMenu = NSMenu(title: Constants.Menu.history)
        snippetMenu = NSMenu(title: Constants.Menu.snippet)
        statusItem?.menu = nil
    }

    func createClipMenu() {
        createBoardManLiteMenu()
    }

    func menuItemTitle(_ title: String, listNumber: NSInteger, isMarkWithNumber: Bool) -> String {
        return (isMarkWithNumber) ? "\(listNumber). \(title)" : title
    }

    func clipMenuItemTitle(_ title: String, clip: CPYClip, listNumber: NSInteger, isMarkWithNumber: Bool) -> String {
        return PasteCountStore.shared.label(for: clip) + menuItemTitle(title, listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)
    }

    func applyPasteCountStyle(to menuItem: NSMenuItem, clip: CPYClip) {
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

        let ascending = !AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.reorderClipsAfterPasting)
        let clipResults = realm.objects(CPYClip.self).sorted(byKeyPath: #keyPath(CPYClip.updateTime), ascending: ascending)
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

    func makeClipMenuItem(_ clip: CPYClip, index: Int, listNumber: Int) -> NSMenuItem {
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

        let snippetResults = realm.objects(CPYSnippet.self)
        let snippets = pinnedIdentifiers.compactMap { identifier in
            snippetResults.first(where: { snippet in
                snippet.identifier == identifier && snippet.enable && (snippet.folder?.enable ?? true)
            })
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
            let pinnedTitle = "[PIN] " + menuItem.title
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
        let folderResults = realm.objects(CPYFolder.self).sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)
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
                folder.snippets
                    .sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true)
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

    func makeSnippetMenuItem(_ snippet: CPYSnippet, listNumber: Int) -> NSMenuItem {
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
    private let key = "com.uniplanck.BoardMan.pinnedSnippetIdentifiers"

    init(defaults: UserDefaults = AppEnvironment.current.defaults) {
        self.defaults = defaults
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
        guard EntitlementGate.canPinItem(currentPinnedCount: values.count) else {
            return false
        }
        values.append(identifier)
        save(values)
        return true
    }

    func remove(_ identifier: String) {
        save(identifiers.filter { $0 != identifier })
    }

    private func save(_ values: [String]) {
        defaults.set(values, forKey: key)
        defaults.synchronize()
        NotificationCenter.default.post(name: Notification.Name(rawValue: Constants.Notification.closeSnippetEditor), object: nil)
    }
}

// MARK: - BoardMan History Item (lightweight for panel)
fileprivate enum BoardManPanelTab: Int, CaseIterable {
    case history = 0
    case snippets
    case settings

    var title: String {
        switch self {
        case .history: return "History"
        case .snippets: return "Snippets"
        case .settings: return "Settings"
        }
    }

    var emptyMessage: String {
        switch self {
        case .history: return "No clipboard history yet"
        case .snippets: return "No snippets yet"
        case .settings: return ""
        }
    }
}

fileprivate enum BoardManInlineSettingsCategory: Int, CaseIterable {
    case general, view, history, snippets, privacy, updates, license

    var title: String {
        switch self {
        case .general: return "General"
        case .view: return "Appearance"
        case .history: return "History"
        case .snippets: return "Snippets"
        case .privacy: return "Privacy"
        case .updates: return "Updates"
        case .license: return "License"
        }
    }

    var detail: String {
        switch self {
        case .general: return "Startup, menu bar, and keyboard shortcuts"
        case .view: return "Layout, timestamps, counts, and theme"
        case .history: return "Retention, duplicate handling, and cleanup"
        case .snippets: return "Folders, snippets, and folder shortcuts"
        case .privacy: return "Excluded apps, stored data, and filters"
        case .updates: return "Version and update channel"
        case .license: return "Plan, activation, and usage limits"
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
    case openBoardMan, history, snippets, clearHistory

    var title: String {
        switch self {
        case .openBoardMan: return "Open Board-Man"
        case .history: return "Open History"
        case .snippets: return "Open Snippets"
        case .clearHistory: return "Clear History"
        }
    }

    var detail: String {
        switch self {
        case .openBoardMan: return "Show the main clipboard panel"
        case .history: return "Jump directly to clipboard history"
        case .snippets: return "Jump directly to snippets"
        case .clearHistory: return "Clear history after confirmation"
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

        clearButton = NSButton(title: "Clear", target: nil, action: nil)
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

    init(folder: CPYFolder, keyCombo: KeyCombo?) {
        folderIdentifier = folder.identifier

        let title = folder.title.trimmingCharacters(in: .whitespacesAndNewlines)
        titleLabel = NSTextField(labelWithString: title.isEmpty ? "untitled folder" : title)
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        let enabledText = folder.enable ? "Enabled" : "Disabled"
        detailLabel = NSTextField(labelWithString: "\(enabledText) / \(folder.snippets.count) snippets")
        detailLabel.font = NSFont.systemFont(ofSize: 10)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail

        recordView = RecordView(frame: .zero)
        recordView.keyCombo = keyCombo

        clearButton = NSButton(title: "Clear", target: nil, action: nil)
        clearButton.font = NSFont.systemFont(ofSize: 10)
        clearButton.bezelStyle = .rounded
        clearButton.identifier = NSUserInterfaceItemIdentifier(folder.identifier)
    }

    var views: [NSView] {
        return [titleLabel, detailLabel, recordView, clearButton]
    }
}

fileprivate enum BoardManThemePreset: String, CaseIterable {
    case defaultPreset = "Default"
    case graphite = "Graphite"
    case ocean = "Ocean"
    case amber = "Amber"
    case rose = "Rose"

    var title: String {
        return rawValue
    }

    var accentColor: NSColor {
        switch self {
        case .defaultPreset: return NSColor.labelColor.withAlphaComponent(0.70)
        case .graphite: return NSColor(calibratedWhite: 0.52, alpha: 1)
        case .ocean: return .systemTeal
        case .amber: return .systemOrange
        case .rose: return .systemPink
        }
    }

    var tintColor: NSColor {
        switch self {
        case .defaultPreset: return NSColor.controlBackgroundColor.withAlphaComponent(0.10)
        case .graphite: return NSColor.labelColor.withAlphaComponent(0.11)
        case .ocean: return NSColor.systemTeal.withAlphaComponent(0.16)
        case .amber: return NSColor.systemOrange.withAlphaComponent(0.15)
        case .rose: return NSColor.systemPink.withAlphaComponent(0.15)
        }
    }

    var glassMaterial: NSVisualEffectView.Material {
        switch self {
        case .graphite:
            return .hudWindow
        default:
            return .popover
        }
    }

    private func lightenedAlpha(_ alpha: CGFloat) -> CGFloat {
        switch self {
        case .defaultPreset:
            return min(alpha, 0.06)
        default:
            return alpha * 0.56
        }
    }

    func panelTintColor(useLiquidGlass: Bool, lighten: Bool = false) -> NSColor {
        if useLiquidGlass {
            switch self {
            case .defaultPreset: return NSColor.controlBackgroundColor.withAlphaComponent(lighten ? 0.06 : 0.10)
            case .graphite: return NSColor.labelColor.withAlphaComponent(lighten ? 0.08 : 0.15)
            case .ocean: return NSColor.systemTeal.withAlphaComponent(lighten ? 0.08 : 0.15)
            case .amber: return NSColor.systemOrange.withAlphaComponent(lighten ? 0.08 : 0.14)
            case .rose: return NSColor.systemPink.withAlphaComponent(lighten ? 0.08 : 0.14)
            }
        }
        return lighten ? tintColor.withAlphaComponent(lightenedAlpha(tintColor.alphaComponent)) : tintColor
    }

    func surfaceTintColor(useLiquidGlass: Bool, lighten: Bool = false) -> NSColor {
        let alpha: CGFloat = useLiquidGlass ? 0.52 : 0.18
        return tintColor.withAlphaComponent(lighten ? lightenedAlpha(alpha) : alpha)
    }

    func rowFillColor(useLiquidGlass: Bool, lighten: Bool = false) -> NSColor {
        let alpha: CGFloat = useLiquidGlass ? 0.32 : 0.42
        return tintColor.withAlphaComponent(lighten ? lightenedAlpha(alpha) : alpha)
    }

    func rowHoverColor(useLiquidGlass: Bool, lighten: Bool = false) -> NSColor {
        let alpha: CGFloat = useLiquidGlass ? 0.18 : 0.16
        return accentColor.withAlphaComponent(lighten ? lightenedAlpha(alpha) : alpha)
    }

    func rowSelectedColor(useLiquidGlass: Bool, lighten: Bool = false) -> NSColor {
        let alpha: CGFloat = useLiquidGlass ? 0.34 : 0.28
        return accentColor.withAlphaComponent(lighten ? max(0.12, lightenedAlpha(alpha)) : alpha)
    }

    func edgeColor(useLiquidGlass: Bool, lighten: Bool = false) -> NSColor {
        if self == .defaultPreset && !useLiquidGlass {
            return NSColor.separatorColor.withAlphaComponent(lighten ? 0.18 : 0.28)
        }
        let alpha: CGFloat = useLiquidGlass ? 0.28 : 0.10
        return NSColor.white.withAlphaComponent(lighten ? max(0.08, lightenedAlpha(alpha)) : alpha)
    }

    func shadowColor(useLiquidGlass: Bool, lighten: Bool = false) -> NSColor {
        switch self {
        case .graphite:
            let alpha: CGFloat = useLiquidGlass ? 0.36 : 0.16
            return NSColor.black.withAlphaComponent(lighten ? alpha * 0.55 : alpha)
        default:
            let alpha: CGFloat = useLiquidGlass ? 0.24 : 0.14
            return accentColor.withAlphaComponent(lighten ? lightenedAlpha(alpha) : alpha)
        }
    }

    static func allowed(_ value: String?) -> BoardManThemePreset {
        guard let value,
              let preset = BoardManThemePreset.allCases.first(where: { $0.rawValue == value }) else {
            return .defaultPreset
        }
        return preset
    }
}

fileprivate enum BoardManPanelItemSource {
    case clip
    case snippet
    case favorite
}

fileprivate enum BoardManHideRuleMode: String, Codable, CaseIterable {
    case contains
    case startsWith
    case endsWith
    case exact

    var title: String {
        switch self {
        case .contains: return "Contains text"
        case .startsWith: return "Starts with"
        case .endsWith: return "Ends with"
        case .exact: return "Exact match"
        }
    }

    var summaryTitle: String {
        switch self {
        case .contains: return "contains"
        case .startsWith: return "starts"
        case .endsWith: return "ends"
        case .exact: return "exact"
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
        self.upgradeButton = NSButton(title: "Upgrade", target: upgradeTarget, action: upgradeAction)
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
        titleLabel.lineBreakMode = .byTruncatingTail
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
        explanationLabel.lineBreakMode = .byTruncatingTail
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
        lockImageView?.frame = NSRect(x: inset, y: bounds.height - 25, width: lockSize, height: lockSize)
        badgeLabel.frame = NSRect(x: min(bounds.width - badgeWidth - inset, titleX + 142), y: bounds.height - 26, width: badgeWidth, height: 16)
        titleLabel.frame = NSRect(x: titleX, y: bounds.height - 28, width: max(80, badgeLabel.frame.minX - titleX - 8), height: 18)
        explanationLabel.frame = NSRect(x: inset, y: bounds.height - 50, width: max(80, bounds.width - inset * 2), height: 18)
        lockedControl.frame = NSRect(x: inset, y: 10, width: controlWidth, height: 24)
        upgradeButton.frame = NSRect(x: lockedControl.frame.maxX + controlGap, y: 8, width: buttonWidth, height: 24)
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

fileprivate struct BoardManHistoryItem {
    let title: String
    let primaryTitle: String
    let metadataText: String
    let countText: String
    let previewTitle: String
    let dataHash: String
    let imageDataPath: String
    let inlineThumbnail: NSImage?
    let pasteCount: Int
    let isPinned: Bool
    let isEnabled: Bool
    let source: BoardManPanelItemSource
    let categoryIdentifier: String?
    let categoryTitle: String?
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

private final class BoardManHistoryRowView: NSTableRowView {
    weak var previewOwner: BoardManPanel?
    private var hoverTrackingArea: NSTrackingArea?

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
        let accentColor = preset.accentColor
        let path = NSBezierPath(roundedRect: rowRect, xRadius: 9, yRadius: 9)
        if previewOwner?.isSelectedRow(row) == true {
            preset.rowSelectedColor(useLiquidGlass: useLiquidGlass, lighten: lightenTheme).setFill()
            path.fill()
            accentColor.withAlphaComponent(lightenTheme ? 0.30 : (useLiquidGlass ? 0.54 : 0.46)).setStroke()
            path.lineWidth = 1
            path.stroke()
        } else if previewOwner?.isHoveredRow(row) == true {
            preset.rowHoverColor(useLiquidGlass: useLiquidGlass, lighten: lightenTheme).setFill()
            path.fill()
            preset.edgeColor(useLiquidGlass: useLiquidGlass, lighten: lightenTheme).setStroke()
            path.lineWidth = 1
            path.stroke()
        } else if let appearance = previewOwner?.usedItemAppearance(for: row) {
            appearance.background.setFill()
            path.fill()
            appearance.border.setStroke()
            path.lineWidth = appearance.borderWidth
            path.stroke()
        } else if row >= 0 {
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

    override func drawSelection(in dirtyRect: NSRect) {
        drawBackground(in: dirtyRect)
    }
}

private final class BoardManHistoryCellView: NSTableCellView {
    private let primaryLabel = NSTextField(labelWithString: "")
    private let metadataLabel = NSTextField(labelWithString: "")
    private let countBadge = NSTextField(labelWithString: "")
    private let inlineImageView = NSImageView(frame: .zero)

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

        metadataLabel.lineBreakMode = .byTruncatingTail
        metadataLabel.maximumNumberOfLines = 1
        metadataLabel.backgroundColor = .clear
        metadataLabel.drawsBackground = false
        metadataLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)

        countBadge.alignment = .center
        countBadge.lineBreakMode = .byTruncatingTail
        countBadge.maximumNumberOfLines = 1
        countBadge.isBordered = false
        countBadge.isEditable = false
        countBadge.wantsLayer = true
        countBadge.layer?.cornerRadius = 8
        countBadge.layer?.masksToBounds = true
        countBadge.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)

        inlineImageView.imageScaling = .scaleProportionallyUpOrDown
        inlineImageView.imageAlignment = .alignCenter
        inlineImageView.wantsLayer = true
        inlineImageView.layer?.cornerRadius = 5
        inlineImageView.layer?.masksToBounds = true
        inlineImageView.layer?.borderWidth = 1

        [primaryLabel, metadataLabel, countBadge].forEach {
            $0.cell?.truncatesLastVisibleLine = true
            $0.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        inlineImageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(primaryLabel)
        addSubview(metadataLabel)
        addSubview(inlineImageView)
        addSubview(countBadge)
    }

    func configure(item: BoardManHistoryItem,
                   isSelected: Bool,
                   usageStyle: String,
                   useLiquidGlass: Bool,
                   lightenTheme: Bool,
                   themePreset: BoardManThemePreset) {
        primaryLabel.stringValue = item.primaryTitle
        metadataLabel.stringValue = item.metadataText
        let badgePrefix = usageStyle == "compact" ? "used " : "×"
        let shouldShowCount = item.pasteCount > 0 && !item.countText.isEmpty
        countBadge.stringValue = shouldShowCount ? "\(badgePrefix)\(item.countText)" : ""
        countBadge.isHidden = !shouldShowCount
        inlineImageView.image = item.inlineThumbnail
        inlineImageView.isHidden = item.inlineThumbnail == nil

        if isSelected {
            primaryLabel.textColor = .selectedMenuItemTextColor
            metadataLabel.textColor = NSColor.selectedMenuItemTextColor.withAlphaComponent(0.86)
            countBadge.textColor = .selectedMenuItemTextColor
            countBadge.layer?.backgroundColor = NSColor.selectedMenuItemTextColor.withAlphaComponent(useLiquidGlass ? 0.20 : 0.18).cgColor
            inlineImageView.layer?.backgroundColor = NSColor.selectedMenuItemTextColor.withAlphaComponent(0.10).cgColor
            inlineImageView.layer?.borderColor = NSColor.selectedMenuItemTextColor.withAlphaComponent(0.24).cgColor
        } else {
            let accentColor = themePreset.accentColor
            primaryLabel.textColor = .labelColor
            metadataLabel.textColor = useLiquidGlass ? NSColor.secondaryLabelColor.withAlphaComponent(0.92) : .secondaryLabelColor
            countBadge.textColor = .labelColor
            countBadge.layer?.backgroundColor = accentColor.withAlphaComponent(lightenTheme ? 0.10 : (useLiquidGlass ? 0.22 : 0.18)).cgColor
            inlineImageView.layer?.backgroundColor = themePreset.surfaceTintColor(useLiquidGlass: useLiquidGlass, lighten: lightenTheme).cgColor
            inlineImageView.layer?.borderColor = accentColor.withAlphaComponent(lightenTheme ? 0.18 : (useLiquidGlass ? 0.34 : 0.28)).cgColor
        }
        countBadge.layer?.borderColor = themePreset.edgeColor(useLiquidGlass: useLiquidGlass, lighten: lightenTheme).cgColor
        countBadge.layer?.borderWidth = 0
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let insetX: CGFloat = 16
        let topPadding: CGFloat = 8
        let maxContentWidth = max(0, bounds.width - (insetX * 2))
        let badgeWidth: CGFloat = countBadge.isHidden ? 0 : min(maxContentWidth, min(72, max(34, countBadge.intrinsicContentSize.width + 16)))
        let badgeX = max(insetX, bounds.width - insetX - badgeWidth)
        let imageSize: CGFloat = inlineImageView.isHidden ? 0 : 32
        let imageX = imageSize > 0 ? max(insetX, badgeX - imageSize - 10) : 0
        let textRightLimit = imageSize > 0 ? imageX : (badgeWidth > 0 ? badgeX : bounds.width - insetX)
        let textWidth = max(0, textRightLimit - insetX - 10)
        primaryLabel.frame = NSRect(x: insetX, y: bounds.height - topPadding - 18, width: textWidth, height: 18)
        metadataLabel.frame = NSRect(x: insetX, y: 8, width: textWidth, height: 15)
        if !inlineImageView.isHidden {
            inlineImageView.frame = NSRect(x: imageX, y: floor((bounds.height - imageSize) / 2), width: imageSize, height: imageSize)
        }
        if !countBadge.isHidden {
            countBadge.frame = NSRect(x: badgeX, y: (bounds.height - 20) / 2, width: badgeWidth, height: 20)
        }
    }
}

// MARK: - BoardManPanel MVP Shell (embedded in MenuManager.swift per constraints)
class BoardManPanel: NSPanel {

    private var glassBackgroundView: NSVisualEffectView?
    private var searchField: NSSearchField?
    private var segmentedControl: NSSegmentedControl?
    private var settingsBackgroundView: NSView?
    private var settingsSidebarView: NSView?
    private var settingsCategoryButtons: [NSButton] = []
    private var settingsPageTitleLabel: NSTextField?
    private var settingsPageDescriptionLabel: NSTextField?
    private var scrollView: NSScrollView?
    private var placeholderList: NSTableView?
    private var rowNumbersButton: NSButton?
    private var timestampLabel: NSTextField?
    private var timestampPopup: NSPopUpButton?
    private var usageCountButton: NSButton?
    private var usageStyleLabel: NSTextField?
    private var usageStylePopup: NSPopUpButton?
    private var usedItemStyleLabel: NSTextField?
    private var usedItemStylePopup: NSPopUpButton?
    private var themePresetLabel: NSTextField?
    private var themePresetPopup: NSPopUpButton?
    private var themeLightenButton: NSButton?
    private var generalSectionLabel: NSTextField?
    private var launchOnLoginButton: NSButton?
    private var inputPasteCommandButton: NSButton?
    private var maxHistorySizeLabel: NSTextField?
    private var maxHistorySizeStepper: NSStepper?
    private var maxHistorySizeValueLabel: NSTextField?
    private var statusItemLabel: NSTextField?
    private var statusItemPopup: NSPopUpButton?
    private var shortcutSectionLabel: NSTextField?
    private var globalShortcutRows: [BoardManGlobalShortcutRow] = []
    private var shortcutStatusLabel: NSTextField?
    private var snippetSettingsSectionLabel: NSTextField?
    private var snippetSummaryLabel: NSTextField?
    private var snippetFoldersLabel: NSTextField?
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
    private let updatesPreferenceViewController = CPYUpdatesPreferenceViewController(nibName: "CPYUpdatesPreferenceViewController", bundle: nil)
    private var updatesPreferenceView: NSView?
    private var viewSectionLabel: NSTextField?
    private var historySectionLabel: NSTextField?
    private var privacySectionLabel: NSTextField?
    private var labsSectionLabel: NSTextField?
    private var labsNoteLabel: NSTextField?
    private var heightControlLabel: NSTextField?
    private var heightStepper: NSStepper?
    private var heightLabel: NSTextField?
    private var footerNote: NSTextField?
    private var snippetCategoryLabel: NSTextField?
    private var snippetCategoryPopup: NSPopUpButton?
    private var snippetCategoryAddButton: NSButton?
    private var snippetCategoryRenameButton: NSButton?
    private var snippetCategoryDeleteButton: NSButton?
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
    private var snippetEditorStatusLabel: NSTextField?
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
    private var activeTab: BoardManPanelTab = .history
    private var activeSettingsCategory: BoardManInlineSettingsCategory = .general
    private var activeSnippetCategoryIdentifier: String = BoardManPanel.allCategoriesIdentifier
    fileprivate var onPasteRequested: ((BoardManHistoryItem, CFAbsoluteTime?) -> Void)?
    var onRefreshRequested: (() -> Void)?
    var itemCount: Int {
        return historyItems.count
    }

    func selectHistoryTab() {
        activateTab(.history)
    }

    func selectSettingsTab() {
        activeTab = .settings
        segmentedControl?.selectedSegment = activeTab.rawValue
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
        segmentedControl?.selectedSegment = activeTab.rawValue
        if let categoryIdentifier {
            activeSnippetCategoryIdentifier = categoryIdentifier
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

    fileprivate var themePreset: BoardManThemePreset {
        return BoardManThemePreset.allowed(AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManThemePreset))
    }

    fileprivate var themeAccentColor: NSColor {
        return themePreset.accentColor
    }

    static func preferredPanelHeight() -> CGFloat {
        return CGFloat(clampedPanelHeight(AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.boardManPanelHeight)))
    }

    static let allCategoriesIdentifier = "__boardman_all_categories__"
    static let uncategorizedCategoryIdentifier = "__boardman_uncategorized__"

    static func preferredPanelWidth() -> CGFloat {
        return 720
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
        let allowed = ["relative", "HH:mm", "HH:mm:ss", "h:mm a", "h:mm:ss a", "MMM d HH:mm", "yyyy/MM/dd HH:mm", "none"]
        guard let value, allowed.contains(value) else { return "none" }
        return value
    }

    static func timestampText(for updateTime: Int, format: String) -> String {
        guard format != "none" else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(updateTime))
        if format == "relative" {
            let seconds = max(0, Int(Date().timeIntervalSince(date)))
            if seconds < 60 { return "now" }
            if seconds < 3600 { return "\(seconds / 60)m ago" }
            if seconds < 86_400 { return "\(seconds / 3600)h ago" }
            return "\(seconds / 86_400)d ago"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    static func isImageClip(_ clip: CPYClip) -> Bool {
        if !clip.thumbnailPath.isEmpty && !clip.isColorCode {
            return true
        }
        let type = NSPasteboard.PasteboardType(rawValue: clip.primaryType)
        return type == .png || type == .tiff || type == .deprecatedTIFF
    }

    static func imageClipTitle(for clip: CPYClip) -> String {
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
        switch allowedTimestampFormat(value) {
        case "relative": return "Relative"
        case "HH:mm": return "24-hour"
        case "HH:mm:ss": return "24-hour + seconds"
        case "h:mm a": return "12-hour"
        case "h:mm:ss a": return "12-hour + seconds"
        case "MMM d HH:mm", "yyyy/MM/dd HH:mm": return "Date + time"
        default: return "Hidden"
        }
    }

    private static func timestampFormat(forMenuTitle title: String?) -> String {
        switch title {
        case "Relative": return "relative"
        case "24-hour": return "HH:mm"
        case "24-hour + seconds": return "HH:mm:ss"
        case "12-hour": return "h:mm a"
        case "12-hour + seconds": return "h:mm:ss a"
        case "Date + time": return "MMM d HH:mm"
        default: return "none"
        }
    }

    private static func allowedUsageCountStyle(_ value: String?) -> String {
        return value == "compact" ? "compact" : "badge"
    }

    private static func allowedUsedItemStyle(_ value: String?) -> String {
        let allowed = ["Default", "Subtle Red", "Amber", "Blue", "Monochrome"]
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
        case .history: return AppEnvironment.current.hotKeyService.historyKeyCombo
        case .snippets: return AppEnvironment.current.hotKeyService.snippetKeyCombo
        case .clearHistory: return AppEnvironment.current.hotKeyService.clearHistoryKeyCombo
        }
    }

    private func refreshGlobalShortcutRows() {
        globalShortcutRows.forEach { row in
            row.recordView.keyCombo = globalShortcutKeyCombo(for: row.kind)
        }
        shortcutStatusLabel?.stringValue = "Click a shortcut field, then press the new key combination. Changes apply immediately."
        updateSettingsSidebarSelection()
    }

    private func refreshSnippetSettingsSummary() {
        let realm = try! Realm()
        let folders = Array(realm.objects(CPYFolder.self).sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true))
        let snippetCount = realm.objects(CPYSnippet.self).count
        let enabledSnippetCount = realm.objects(CPYSnippet.self).filter("enable == true").count
        let enabledFolderCount = folders.filter { $0.enable }.count
        let shortcutCount = folders.filter { AppEnvironment.current.hotKeyService.snippetKeyCombo(forIdentifier: $0.identifier) != nil }.count
        let topFolderNames = folders.prefix(4).map { folder -> String in
            let title = folder.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? "untitled folder" : title
        }
        let folderPreview = topFolderNames.isEmpty ? "No folders yet" : topFolderNames.joined(separator: ", ")

        snippetSummaryLabel?.stringValue = "\(snippetCount) snippets, \(folders.count) folders (\(enabledSnippetCount) snippets enabled, \(enabledFolderCount) folders enabled)"
        snippetFoldersLabel?.stringValue = "Folders: \(folderPreview)"
        snippetShortcutsLabel?.stringValue = "Folder shortcuts configured: \(shortcutCount)"
        reloadSnippetShortcutRows(with: folders)
    }

    private func reloadSnippetShortcutRows(with folders: [CPYFolder]) {
        guard let documentView = snippetShortcutDocumentView else { return }
        snippetShortcutRows.flatMap { $0.views }.forEach { $0.removeFromSuperview() }
        snippetShortcutRows = folders.map { folder in
            let keyCombo = AppEnvironment.current.hotKeyService.keyComboForSnippetFolder(identifier: folder.identifier)
            let row = BoardManSnippetShortcutRow(folder: folder, keyCombo: keyCombo)
            row.recordView.delegate = self
            row.clearButton.target = self
            row.clearButton.action = #selector(clearSnippetFolderShortcut(_:))
            row.views.forEach { documentView.addSubview($0) }
            return row
        }
    }

    private static func makeSectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    convenience init() {
        let contentRect = NSRect(x: 0, y: 0, width: BoardManPanel.preferredPanelWidth(), height: BoardManPanel.preferredPanelHeight())
        self.init(contentRect: contentRect,
                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView],  // no .hudWindow = no harsh black footer/band
                  backing: .buffered,
                  defer: false)
        self.minSize = NSSize(width: 560, height: 560)
        self.title = "Board-Man"
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.isFloatingPanel = true
        self.level = .popUpMenu
        self.backgroundColor = NSColor.windowBackgroundColor
        self.hasShadow = true
        self.isRestorable = false
        self.setFrameAutosaveName("")
        setupPanelContainer()
        setupUI()
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
                contentView.layer?.cornerRadius = 16
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
        search.placeholderString = "Search clipboard history and snippets"
        search.target = self
        search.action = #selector(searchTextChanged(_:))
        search.sendsSearchStringImmediately = true
        search.delegate = self
        search.focusRingType = .none
        search.controlSize = .large
        search.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        contentView.addSubview(search)
        searchField = search

        // Primary navigation stays visible and uses native separated segments.
        let tabs = NSSegmentedControl(frame: .zero)
        tabs.segmentCount = 3
        tabs.setLabel("History", forSegment: 0)
        tabs.setLabel("Snippets", forSegment: 1)
        tabs.setLabel("Settings", forSegment: 2)
        if #available(macOS 11.0, *) {
            tabs.setImage(NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "History"), forSegment: 0)
            tabs.setImage(NSImage(systemSymbolName: "text.badge.plus", accessibilityDescription: "Snippets"), forSegment: 1)
            tabs.setImage(NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Settings"), forSegment: 2)
        }
        tabs.selectedSegment = 0
        tabs.target = self
        tabs.action = #selector(tabChanged(_:))
        if #available(macOS 10.10, *) {
            tabs.segmentStyle = .separated
        }
        tabs.controlSize = .large
        tabs.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        contentView.addSubview(tabs)
        segmentedControl = tabs

        let settingsBackground = NSView(frame: .zero)
        settingsBackground.wantsLayer = true
        settingsBackground.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        settingsBackground.layer?.cornerRadius = 12
        contentView.addSubview(settingsBackground)
        settingsBackgroundView = settingsBackground

        let sidebar = NSView(frame: .zero)
        sidebar.wantsLayer = true
        sidebar.layer?.cornerRadius = 12
        sidebar.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor
        sidebar.layer?.borderWidth = 1
        sidebar.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.34).cgColor
        contentView.addSubview(sidebar)
        settingsSidebarView = sidebar

        settingsCategoryButtons = BoardManInlineSettingsCategory.allCases.map { category in
            let button = NSButton(title: category.title, target: self, action: #selector(settingsCategoryButtonPressed(_:)))
            button.tag = category.rawValue
            button.isBordered = false
            button.alignment = .left
            button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.wantsLayer = true
            button.layer?.cornerRadius = 8
            button.toolTip = category.detail
            if #available(macOS 11.0, *) {
                button.image = NSImage(systemSymbolName: category.symbolName, accessibilityDescription: category.title)
            }
            sidebar.addSubview(button)
            return button
        }

        let pageTitle = NSTextField(labelWithString: activeSettingsCategory.title)
        pageTitle.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        pageTitle.textColor = .labelColor
        contentView.addSubview(pageTitle)
        settingsPageTitleLabel = pageTitle

        let pageDescription = NSTextField(labelWithString: activeSettingsCategory.detail)
        pageDescription.font = NSFont.systemFont(ofSize: 11.5)
        pageDescription.textColor = .secondaryLabelColor
        pageDescription.lineBreakMode = .byTruncatingTail
        contentView.addSubview(pageDescription)
        settingsPageDescriptionLabel = pageDescription

        let generalTitle = BoardManPanel.makeSectionLabel("General")
        contentView.addSubview(generalTitle)
        generalSectionLabel = generalTitle

        let launchOnLogin = NSButton(checkboxWithTitle: "Launch on Login", target: self, action: #selector(launchOnLoginChanged(_:)))
        launchOnLogin.state = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.loginItem) ? .on : .off
        launchOnLogin.font = NSFont.systemFont(ofSize: 11)
        if #available(macOS 10.14, *) {
            launchOnLogin.contentTintColor = .labelColor
        }
        contentView.addSubview(launchOnLogin)
        launchOnLoginButton = launchOnLogin

        let pasteCommand = NSButton(checkboxWithTitle: "Send Command+V", target: self, action: #selector(inputPasteCommandChanged(_:)))
        pasteCommand.state = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.inputPasteCommand) ? .on : .off
        pasteCommand.font = NSFont.systemFont(ofSize: 11)
        pasteCommand.toolTip = "Sends Command+V after selecting a clipboard item."
        if #available(macOS 10.14, *) {
            pasteCommand.contentTintColor = .labelColor
        }
        contentView.addSubview(pasteCommand)
        inputPasteCommandButton = pasteCommand

        let maxHistoryLabel = NSTextField(labelWithString: "Max")
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
        contentView.addSubview(maxHistoryStepper)
        maxHistorySizeStepper = maxHistoryStepper

        let maxHistoryValue = NSTextField(labelWithString: "\(maxHistoryStepper.integerValue)")
        maxHistoryValue.alignment = .right
        maxHistoryValue.font = NSFont.systemFont(ofSize: 11)
        maxHistoryValue.textColor = .labelColor
        contentView.addSubview(maxHistoryValue)
        maxHistorySizeValueLabel = maxHistoryValue

        let statusLabel = NSTextField(labelWithString: "Icon")
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

        let shortcutStatus = NSTextField(labelWithString: "Click a shortcut field, then press the new key combination. Changes apply immediately.")
        shortcutStatus.font = NSFont.systemFont(ofSize: 10.5)
        shortcutStatus.textColor = .secondaryLabelColor
        shortcutStatus.lineBreakMode = .byTruncatingTail
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
        contentView.addSubview(shortcutScrollView)
        snippetShortcutDocumentView = shortcutDocument
        snippetShortcutScrollView = shortcutScrollView

        let manageSnippets = NSButton(title: "Manage Snippets", target: self, action: #selector(openSnippetManager(_:)))
        manageSnippets.font = NSFont.systemFont(ofSize: 11)
        manageSnippets.bezelStyle = .rounded
        manageSnippets.toolTip = "Opens the Board-Man Snippets tab. Existing snippet shortcuts are preserved."
        contentView.addSubview(manageSnippets)
        manageSnippetsButton = manageSnippets

        let viewTitle = BoardManPanel.makeSectionLabel("Appearance")
        contentView.addSubview(viewTitle)
        viewSectionLabel = viewTitle

        let numbers = NSButton(checkboxWithTitle: "Rows", target: self, action: #selector(rowNumbersChanged(_:)))
        numbers.state = (AppEnvironment.current.defaults.object(forKey: Constants.UserDefaults.boardManShowRowNumbers) as? Bool ?? true) ? .on : .off
        numbers.font = NSFont.systemFont(ofSize: 11)
        if #available(macOS 10.14, *) {
            numbers.contentTintColor = .labelColor
        }
        contentView.addSubview(numbers)
        rowNumbersButton = numbers

        let timeText = NSTextField(labelWithString: "Time")
        timeText.font = NSFont.systemFont(ofSize: 11)
        timeText.textColor = .labelColor
        contentView.addSubview(timeText)
        timestampLabel = timeText

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: ["Relative", "24-hour", "24-hour + seconds", "12-hour", "12-hour + seconds", "Date + time", "Hidden"])
        popup.selectItem(withTitle: BoardManPanel.timestampMenuTitle(for: AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManTimestampFormat)))
        popup.font = NSFont.systemFont(ofSize: 11)
        popup.target = self
        popup.action = #selector(timestampFormatChanged(_:))
        contentView.addSubview(popup)
        timestampPopup = popup

        let usage = NSButton(checkboxWithTitle: "Count", target: self, action: #selector(usageCountChanged(_:)))
        usage.state = (AppEnvironment.current.defaults.object(forKey: Constants.UserDefaults.boardManShowUsageCount) as? Bool ?? true) ? .on : .off
        usage.font = NSFont.systemFont(ofSize: 11)
        if #available(macOS 10.14, *) {
            usage.contentTintColor = .labelColor
        }
        contentView.addSubview(usage)
        usageCountButton = usage

        let styleText = NSTextField(labelWithString: "Style")
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

        let usedItemText = NSTextField(labelWithString: "Used")
        usedItemText.font = NSFont.systemFont(ofSize: 11)
        usedItemText.textColor = .labelColor
        contentView.addSubview(usedItemText)
        usedItemStyleLabel = usedItemText

        let usedItemStyle = NSPopUpButton(frame: .zero, pullsDown: false)
        usedItemStyle.addItems(withTitles: ["Default", "Subtle Red", "Amber", "Blue", "Monochrome"])
        usedItemStyle.selectItem(withTitle: BoardManPanel.allowedUsedItemStyle(AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManUsedItemStyle)))
        usedItemStyle.font = NSFont.systemFont(ofSize: 11)
        usedItemStyle.target = self
        usedItemStyle.action = #selector(usedItemStyleChanged(_:))
        contentView.addSubview(usedItemStyle)
        usedItemStylePopup = usedItemStyle

        let themeText = NSTextField(labelWithString: "Theme")
        themeText.font = NSFont.systemFont(ofSize: 11)
        themeText.textColor = .labelColor
        contentView.addSubview(themeText)
        themePresetLabel = themeText

        let themePresetControl = NSPopUpButton(frame: .zero, pullsDown: false)
        themePresetControl.addItems(withTitles: BoardManThemePreset.allCases.map { $0.title })
        themePresetControl.selectItem(withTitle: BoardManPanel.allowedThemePresetTitle(AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManThemePreset)))
        themePresetControl.font = NSFont.systemFont(ofSize: 11)
        themePresetControl.target = self
        themePresetControl.action = #selector(themePresetChanged(_:))
        themePresetControl.toolTip = "Changes Board-Man panel accents only."
        contentView.addSubview(themePresetControl)
        themePresetPopup = themePresetControl

        let lighten = NSButton(checkboxWithTitle: "Lighten", target: self, action: #selector(themeLightenChanged(_:)))
        lighten.state = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.boardManThemeLighten) ? .on : .off
        lighten.font = NSFont.systemFont(ofSize: 11)
        lighten.toolTip = "Softens Board-Man theme tint, accent, surface, and glass intensity."
        if #available(macOS 10.14, *) {
            lighten.contentTintColor = .labelColor
        }
        contentView.addSubview(lighten)
        themeLightenButton = lighten

        let historyTitle = BoardManPanel.makeSectionLabel("History")
        contentView.addSubview(historyTitle)
        historySectionLabel = historyTitle

        let dedupe = NSButton(checkboxWithTitle: "Dedupe", target: self, action: #selector(dedupeChanged(_:)))
        dedupe.state = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.copySameHistory) ? .off : .on
        dedupe.font = NSFont.systemFont(ofSize: 11)
        if #available(macOS 10.14, *) {
            dedupe.contentTintColor = .labelColor
        }
        contentView.addSubview(dedupe)
        dedupeButton = dedupe

        let overwrite = NSButton(checkboxWithTitle: "Overwrite same", target: self, action: #selector(overwriteSameHistoryChanged(_:)))
        overwrite.state = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.overwriteSameHistory) ? .on : .off
        overwrite.font = NSFont.systemFont(ofSize: 11)
        overwrite.toolTip = "Uses the same stored history item when duplicate content is allowed."
        if #available(macOS 10.14, *) {
            overwrite.contentTintColor = .labelColor
        }
        contentView.addSubview(overwrite)
        overwriteSameHistoryButton = overwrite

        let reuseTop = NSButton(checkboxWithTitle: "Reuse top", target: self, action: #selector(reuseTopChanged(_:)))
        reuseTop.state = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.reorderClipsAfterPasting) ? .on : .off
        reuseTop.font = NSFont.systemFont(ofSize: 11)
        if #available(macOS 10.14, *) {
            reuseTop.contentTintColor = .labelColor
        }
        contentView.addSubview(reuseTop)
        reuseTopButton = reuseTop

        let clear = NSButton(title: "Clear", target: self, action: #selector(clearHistoryRequested(_:)))
        clear.font = NSFont.systemFont(ofSize: 11)
        clear.bezelStyle = .rounded
        contentView.addSubview(clear)
        clearHistoryButton = clear

        let privacyTitle = BoardManPanel.makeSectionLabel("Privacy")
        contentView.addSubview(privacyTitle)
        privacySectionLabel = privacyTitle

        let typesTitle = BoardManPanel.makeSectionLabel("Stored Types")
        contentView.addSubview(typesTitle)
        storedTypesSectionLabel = typesTitle

        let storedTypes = AppEnvironment.current.defaults.dictionary(forKey: Constants.UserDefaults.storeTypes) as? [String: NSNumber] ?? AppDelegate.storeTypesDictinary()
        storedTypeButtons = CPYClipData.availableTypesString.map { typeName in
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

        let exclude = NSButton(title: "Manage Excluded Apps", target: self, action: #selector(openExcludedAppsSettings(_:)))
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
        hideText.placeholderString = "word or phrase"
        hideText.font = NSFont.systemFont(ofSize: 11)
        hideText.target = self
        hideText.action = #selector(addHideRuleRequested(_:))
        contentView.addSubview(hideText)
        hideRuleTextField = hideText

        let hideMode = NSPopUpButton(frame: .zero, pullsDown: false)
        hideMode.addItems(withTitles: BoardManHideRuleMode.allCases.map { $0.title })
        hideMode.selectItem(withTitle: BoardManHideRuleMode.contains.title)
        hideMode.font = NSFont.systemFont(ofSize: 11)
        contentView.addSubview(hideMode)
        hideRuleModePopup = hideMode

        let addRule = NSButton(title: "Add", target: self, action: #selector(addHideRuleRequested(_:)))
        addRule.font = NSFont.systemFont(ofSize: 11)
        addRule.bezelStyle = .rounded
        contentView.addSubview(addRule)
        addHideRuleButton = addRule

        let removeRule = NSButton(title: "Remove Last", target: self, action: #selector(removeLastHideRuleRequested(_:)))
        removeRule.font = NSFont.systemFont(ofSize: 11)
        removeRule.bezelStyle = .rounded
        contentView.addSubview(removeRule)
        removeLastHideRuleButton = removeRule

        let clearRules = NSButton(title: "Clear", target: self, action: #selector(clearHideRulesRequested(_:)))
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

        let ruleNote = NSTextField(labelWithString: "Hidden only in Board-Man, data is not deleted.")
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
        licenseKey.placeholderString = "Secure local license"
        licenseKey.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        licenseKey.isEnabled = false
        licenseKey.toolTip = "Verified licenses are stored securely in Keychain."
        contentView.addSubview(licenseKey)
        licenseKeyField = licenseKey

        let activate = NSButton(title: "Activate", target: self, action: #selector(activateLicenseRequested(_:)))
        activate.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        activate.bezelStyle = .rounded
        activate.isEnabled = false
        activate.toolTip = "Activation is not connected yet."
        contentView.addSubview(activate)
        licenseActivateButton = activate

        let activationStatus = NSTextField(labelWithString: "Online activation is not connected yet.")
        activationStatus.font = NSFont.systemFont(ofSize: 11)
        activationStatus.textColor = .secondaryLabelColor
        activationStatus.lineBreakMode = .byWordWrapping
        contentView.addSubview(activationStatus)
        licenseActivationStatusLabel = activationStatus

        let upgrade = NSButton(title: "Upgrade to Pro", target: self, action: #selector(openLicensePurchasePage(_:)))
        upgrade.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        upgrade.bezelStyle = .rounded
        upgrade.toolTip = "Opens uniplanck.com for the future purchase flow."
        contentView.addSubview(upgrade)
        licenseUpgradeButton = upgrade

        let proControl = NSPopUpButton(frame: .zero, pullsDown: false)
        proControl.addItems(withTitles: ["Advanced Accent", "Saved Theme"])
        proControl.font = NSFont.systemFont(ofSize: 11)
        proControl.toolTip = "Pro-only advanced appearance control."
        let lockedProControl = BoardManProLockedControlView(
            title: "Advanced appearance",
            explanation: "Unlock Pro to customize advanced visual presets.",
            feature: .appearanceAdvanced,
            control: proControl,
            upgradeTarget: self,
            upgradeAction: #selector(openLicensePurchasePage(_:))
        )
        contentView.addSubview(lockedProControl)
        licenseProLockedControlView = lockedProControl

        let licenseNote = NSTextField(labelWithString: "Verified licenses are stored in Keychain and bound to this Mac. Online purchase activation remains unavailable.")
        licenseNote.font = NSFont.systemFont(ofSize: 11)
        licenseNote.textColor = .secondaryLabelColor
        licenseNote.lineBreakMode = .byWordWrapping
        contentView.addSubview(licenseNote)
        licenseMockNoteLabel = licenseNote

        let examples = NSTextField(labelWithString: "UI states: Free / Trial / Pro Active / Expired / Invalid / Offline Grace / Locked")
        examples.font = NSFont.systemFont(ofSize: 10)
        examples.textColor = .tertiaryLabelColor
        examples.lineBreakMode = .byTruncatingTail
        contentView.addSubview(examples)
        licenseStateExamplesLabel = examples
        refreshLicenseSummary()

        let labsTitle = BoardManPanel.makeSectionLabel("Labs")
        contentView.addSubview(labsTitle)
        labsSectionLabel = labsTitle

        let labsNote = NSTextField(labelWithString: "Glass options are available here.")
        labsNote.font = NSFont.systemFont(ofSize: 11)
        labsNote.textColor = .secondaryLabelColor
        contentView.addSubview(labsNote)
        labsNoteLabel = labsNote

        let heightTitle = NSTextField(labelWithString: "Height")
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

        let heightText = NSTextField(labelWithString: "\(stepper.integerValue)")
        heightText.alignment = .right
        heightText.font = NSFont.systemFont(ofSize: 11)
        heightText.textColor = .labelColor
        contentView.addSubview(heightText)
        heightLabel = heightText

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
        scroll.layer?.cornerRadius = 12
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
        table.rowHeight = 58
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
        table.doubleAction = nil  // disabled per spec: no double-click paste
        // Single left-click on valid row pastes immediately (spec #1); hover/selection makes row feel actionable
        let singleClick = NSClickGestureRecognizer(target: self, action: #selector(handleSingleClickPaste(_:)))
        singleClick.numberOfClicksRequired = 1
        table.addGestureRecognizer(singleClick)
        // Right-click on row shows safe actions menu (Paste + Pin + placeholders)
        let rightClick = NSClickGestureRecognizer(target: self, action: #selector(handleRightClick(_:)))
        rightClick.buttonMask = 0x2
        rightClick.numberOfClicksRequired = 1
        table.addGestureRecognizer(rightClick)

        scroll.documentView = table
        contentView.addSubview(scroll)
        scrollView = scroll
        placeholderList = table

        let categoryLabel = NSTextField(labelWithString: "Category")
        categoryLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        categoryLabel.textColor = .labelColor
        categoryLabel.isHidden = true
        contentView.addSubview(categoryLabel)
        snippetCategoryLabel = categoryLabel

        let categoryPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        categoryPopup.font = NSFont.systemFont(ofSize: 11)
        categoryPopup.target = self
        categoryPopup.action = #selector(snippetCategoryFilterChanged(_:))
        categoryPopup.isHidden = true
        categoryPopup.toolTip = "Filter snippets by category."
        contentView.addSubview(categoryPopup)
        snippetCategoryPopup = categoryPopup

        let addSnippet = NSButton(title: "Add Snippet", target: self, action: #selector(addSnippetFromPanel(_:)))
        addSnippet.font = NSFont.systemFont(ofSize: 11)
        addSnippet.bezelStyle = .rounded
        addSnippet.isHidden = true
        addSnippet.toolTip = "Add a snippet."
        contentView.addSubview(addSnippet)
        snippetAddButton = addSnippet

        let editSnippet = NSButton(title: "Edit", target: self, action: #selector(editSelectedSnippetFromPanel(_:)))
        editSnippet.font = NSFont.systemFont(ofSize: 11)
        editSnippet.bezelStyle = .rounded
        editSnippet.isHidden = true
        editSnippet.toolTip = "Edit the selected snippet."
        contentView.addSubview(editSnippet)
        snippetEditButton = editSnippet

        let deleteSnippet = NSButton(title: "Delete", target: self, action: #selector(deleteSelectedSnippetFromPanel(_:)))
        deleteSnippet.font = NSFont.systemFont(ofSize: 11)
        deleteSnippet.bezelStyle = .rounded
        deleteSnippet.isHidden = true
        deleteSnippet.toolTip = "Delete the selected snippet."
        contentView.addSubview(deleteSnippet)
        snippetDeleteButton = deleteSnippet

        let addCategory = NSButton(title: "Add Group", target: self, action: #selector(addSnippetCategoryFromPanel(_:)))
        addCategory.font = NSFont.systemFont(ofSize: 11)
        addCategory.bezelStyle = .rounded
        addCategory.isHidden = true
        contentView.addSubview(addCategory)
        snippetCategoryAddButton = addCategory

        let renameCategory = NSButton(title: "Rename Group", target: self, action: #selector(renameSnippetCategoryFromPanel(_:)))
        renameCategory.font = NSFont.systemFont(ofSize: 11)
        renameCategory.bezelStyle = .rounded
        renameCategory.isHidden = true
        contentView.addSubview(renameCategory)
        snippetCategoryRenameButton = renameCategory

        let deleteCategory = NSButton(title: "Delete Group", target: self, action: #selector(deleteSnippetCategoryFromPanel(_:)))
        deleteCategory.font = NSFont.systemFont(ofSize: 11)
        deleteCategory.bezelStyle = .rounded
        deleteCategory.isHidden = true
        contentView.addSubview(deleteCategory)
        snippetCategoryDeleteButton = deleteCategory

        let editorView = NSView(frame: .zero)
        editorView.wantsLayer = true
        editorView.layer?.cornerRadius = 8
        editorView.layer?.borderWidth = 1
        editorView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        editorView.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.45).cgColor
        editorView.isHidden = true
        contentView.addSubview(editorView)
        snippetEditorView = editorView

        let editorTitleLabel = NSTextField(labelWithString: "Title")
        editorTitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        editorTitleLabel.textColor = .labelColor
        editorView.addSubview(editorTitleLabel)
        snippetEditorTitleLabel = editorTitleLabel

        let editorTitle = NSTextField(frame: .zero)
        editorTitle.font = NSFont.systemFont(ofSize: 12)
        editorTitle.placeholderString = "untitled snippet"
        editorView.addSubview(editorTitle)
        snippetEditorTitleField = editorTitle

        let editorContentLabel = NSTextField(labelWithString: "Content")
        editorContentLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        editorContentLabel.textColor = .labelColor
        editorView.addSubview(editorContentLabel)
        snippetEditorContentLabel = editorContentLabel

        let editorScroll = NSScrollView(frame: .zero)
        editorScroll.hasVerticalScroller = true
        editorScroll.borderType = .bezelBorder
        editorScroll.autohidesScrollers = true
        let editorText = NSTextView(frame: .zero)
        editorText.font = NSFont.systemFont(ofSize: 12)
        editorText.isRichText = false
        editorText.isAutomaticQuoteSubstitutionEnabled = false
        editorText.enabledTextCheckingTypes = 0
        editorScroll.documentView = editorText
        editorView.addSubview(editorScroll)
        snippetEditorScrollView = editorScroll
        snippetEditorTextView = editorText

        let folderEnable = NSButton(checkboxWithTitle: "Group Enabled", target: self, action: #selector(snippetFolderEnableChanged(_:)))
        folderEnable.font = NSFont.systemFont(ofSize: 11)
        editorView.addSubview(folderEnable)
        snippetFolderEnableButton = folderEnable

        let snippetEnable = NSButton(checkboxWithTitle: "Snippet Enabled", target: self, action: #selector(snippetEnableChanged(_:)))
        snippetEnable.font = NSFont.systemFont(ofSize: 11)
        editorView.addSubview(snippetEnable)
        snippetEnableButton = snippetEnable

        let saveSnippet = NSButton(title: "Save Snippet", target: self, action: #selector(saveSelectedSnippetFromPanel(_:)))
        saveSnippet.font = NSFont.systemFont(ofSize: 11)
        saveSnippet.bezelStyle = .rounded
        editorView.addSubview(saveSnippet)
        snippetSaveButton = saveSnippet

        let editorStatus = NSTextField(labelWithString: "Select a snippet to edit.")
        editorStatus.font = NSFont.systemFont(ofSize: 11)
        editorStatus.textColor = .secondaryLabelColor
        editorStatus.lineBreakMode = .byTruncatingTail
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

        // Load initial data
        layoutPanelSubviews()
        table.reloadData()
        synchronizeListGeometry()
    }

    private func applyLiquidGlassStyle() {
        let useGlass = isLiquidGlassEnabled
        let lightenTheme = isThemeLightenEnabled
        let preset = themePreset
        let accentColor = preset.accentColor
        let tintColor = preset.panelTintColor(useLiquidGlass: useGlass, lighten: lightenTheme)
        let surfaceTint = preset.surfaceTintColor(useLiquidGlass: useGlass, lighten: lightenTheme)
        backgroundColor = useGlass ? .clear : .windowBackgroundColor
        isOpaque = !useGlass
        hasShadow = true
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
        searchField?.wantsLayer = true
        searchField?.layer?.cornerRadius = 10
        searchField?.layer?.backgroundColor = (useGlass
            ? surfaceTint.withAlphaComponent(0.26)
            : NSColor.controlBackgroundColor.withAlphaComponent(0.78)).cgColor
        searchField?.layer?.borderColor = preset.edgeColor(useLiquidGlass: useGlass, lighten: lightenTheme).cgColor
        searchField?.layer?.borderWidth = 1
        segmentedControl?.wantsLayer = true
        segmentedControl?.layer?.cornerRadius = 9
        segmentedControl?.layer?.backgroundColor = NSColor.clear.cgColor
        settingsSidebarView?.layer?.backgroundColor = (useGlass
            ? surfaceTint.withAlphaComponent(0.28)
            : NSColor.controlBackgroundColor.withAlphaComponent(0.72)).cgColor
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
        settingsBackgroundView?.layer?.cornerRadius = 12
        settingsBackgroundView?.layer?.borderColor = preset.edgeColor(useLiquidGlass: useGlass, lighten: lightenTheme).cgColor
        settingsBackgroundView?.layer?.borderWidth = 1
        settingsBackgroundView?.layer?.shadowOpacity = 0
        scrollView?.layer?.backgroundColor = (useGlass
            ? surfaceTint.withAlphaComponent(0.30)
            : tintColor).cgColor
        scrollView?.layer?.cornerRadius = 12
        scrollView?.layer?.borderColor = preset.edgeColor(useLiquidGlass: useGlass, lighten: lightenTheme).cgColor
        scrollView?.layer?.borderWidth = 1
        scrollView?.layer?.shadowOpacity = 0
        scrollView?.drawsBackground = !useGlass
        placeholderList?.backgroundColor = .clear
        ([launchOnLoginButton, inputPasteCommandButton, rowNumbersButton, usageCountButton, themeLightenButton, dedupeButton, overwriteSameHistoryButton, reuseTopButton, snippetFolderEnableButton, snippetEnableButton] + storedTypeButtons.map { Optional($0) }).forEach { button in
            if #available(macOS 10.14, *) {
                button?.contentTintColor = accentColor
            }
        }
        [snippetCategoryAddButton, snippetCategoryRenameButton, snippetCategoryDeleteButton, snippetAddButton, snippetEditButton, snippetDeleteButton, snippetSaveButton, addHideRuleButton, removeLastHideRuleButton, clearHideRulesButton, clearHistoryButton, excludedAppsButton].forEach { button in
            if #available(macOS 10.14, *) {
                button?.contentTintColor = themePreset == .defaultPreset ? .labelColor : accentColor
            }
        }
        [generalSectionLabel, shortcutSectionLabel, viewSectionLabel, historySectionLabel, privacySectionLabel, storedTypesSectionLabel, filterSectionLabel, labsSectionLabel, snippetCategoryLabel, snippetEditorTitleLabel, snippetEditorContentLabel].forEach { label in
            label?.textColor = themePreset == .defaultPreset ? .labelColor : accentColor
        }
        [maxHistorySizeLabel, statusItemLabel, themePresetLabel, timestampLabel, usageStyleLabel, usedItemStyleLabel, heightControlLabel].forEach { label in
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
        snippetEditorView?.layer?.backgroundColor = (useGlass ? surfaceTint.withAlphaComponent(0.30) : tintColor).cgColor
        snippetEditorView?.layer?.borderColor = (useGlass ? preset.edgeColor(useLiquidGlass: true, lighten: lightenTheme) : accentColor.withAlphaComponent(lightenTheme ? 0.18 : 0.42)).cgColor
        previewBubblePanel?.contentView?.layer?.cornerRadius = useGlass ? 11 : 8
        previewBubblePanel?.contentView?.layer?.backgroundColor = surfaceTint.withAlphaComponent(useGlass ? 0.42 : 0.95).cgColor
        previewBubblePanel?.contentView?.layer?.borderColor = accentColor.withAlphaComponent(lightenTheme ? 0.18 : (useGlass ? 0.46 : 0.42)).cgColor
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
                self?.hidePreviewBubble()
            },
            center.addObserver(forName: NSApplication.didHideNotification, object: NSApp, queue: .main) { [weak self] _ in
                self?.hidePreviewBubble()
            }
        ]
    }

    private func layoutPanelSubviews() {
        guard let contentView = contentView else { return }
        let bounds = contentView.bounds
        let margin: CGFloat = bounds.width < 620 ? 18 : 24
        let width = bounds.width - (margin * 2)
        let headerY = bounds.height - 62
        let isSettings = activeTab == .settings
        let tabsWidth = min(300, max(238, floor(width * 0.40)))
        segmentedControl?.frame = NSRect(x: margin, y: headerY, width: tabsWidth, height: 34)
        updateTabWidths(totalWidth: tabsWidth)

        searchField?.isHidden = isSettings
        let showsSnippetButtons = activeTab == .snippets && !isSettings
        let snippetButtonGap: CGFloat = 6
        let snippetButtonWidths: [CGFloat] = [82, 44, 58]
        let snippetButtonsWidth = showsSnippetButtons ? snippetButtonWidths.reduce(0, +) + (snippetButtonGap * 2) : 0
        let rightX = margin + tabsWidth + 12
        let rightWidth = max(0, width - tabsWidth - 12)
        let searchWidth = max(150, rightWidth - snippetButtonsWidth - (showsSnippetButtons ? 12 : 0))
        searchField?.frame = NSRect(x: rightX, y: headerY - 2, width: searchWidth, height: 38)
        snippetAddButton?.isHidden = !showsSnippetButtons
        snippetEditButton?.isHidden = !showsSnippetButtons
        snippetDeleteButton?.isHidden = !showsSnippetButtons
        if showsSnippetButtons {
            let buttonY = headerY + 4
            var buttonX = rightX + searchWidth + 12
            snippetAddButton?.frame = NSRect(x: buttonX, y: buttonY, width: snippetButtonWidths[0], height: 26)
            buttonX += snippetButtonWidths[0] + snippetButtonGap
            snippetEditButton?.frame = NSRect(x: buttonX, y: buttonY, width: snippetButtonWidths[1], height: 26)
            buttonX += snippetButtonWidths[1] + snippetButtonGap
            snippetDeleteButton?.frame = NSRect(x: buttonX, y: buttonY, width: snippetButtonWidths[2], height: 26)
        }
        updateSnippetActionButtons()

        let contentTop = headerY - 18
        let sidebarWidth: CGFloat = min(162, max(144, floor(width * 0.24)))
        let settingsGap: CGFloat = 12
        let settingsContentX = margin + sidebarWidth + settingsGap
        let settingsContentWidth = max(260, width - sidebarWidth - settingsGap)
        settingsSidebarView?.isHidden = !isSettings
        settingsSidebarView?.frame = NSRect(x: margin, y: 24, width: sidebarWidth, height: max(220, contentTop - 24))
        layoutSettingsSidebar(width: sidebarWidth, height: max(220, contentTop - 24))
        settingsBackgroundView?.isHidden = !isSettings
        settingsBackgroundView?.frame = NSRect(x: settingsContentX, y: 24, width: settingsContentWidth, height: max(220, contentTop - 24))
        layoutInlineSettingsControls(margin: settingsContentX, width: settingsContentWidth, topY: contentTop, isVisible: isSettings)
        footerNote?.isHidden = true
        scrollView?.isHidden = isSettings
        let showsSnippetCategories = activeTab == .snippets && !isSettings
        snippetEditorView?.isHidden = !showsSnippetCategories
        let categoryRowY = contentTop - 34
        let listTop = showsSnippetCategories ? categoryRowY - 12 : contentTop
        let listHeight = max(190, listTop - 24)
        [snippetCategoryLabel, snippetCategoryPopup, snippetCategoryAddButton, snippetCategoryRenameButton, snippetCategoryDeleteButton].forEach {
            $0?.isHidden = !showsSnippetCategories
        }
        if showsSnippetCategories {
            snippetCategoryLabel?.frame = NSRect(x: margin, y: categoryRowY + 5, width: 58, height: 16)
            let categoryButtonGap: CGFloat = 6
            let categoryButtonWidths: [CGFloat] = width < 560 ? [78, 76, 76] : [86, 92, 88]
            let actionWidth = categoryButtonWidths.reduce(0, +) + (categoryButtonGap * 2)
            let popupWidth = max(120, width - 58 - 10 - actionWidth - 10)
            snippetCategoryPopup?.frame = NSRect(x: margin + 68, y: categoryRowY, width: popupWidth, height: 24)
            var categoryButtonX = margin + 68 + popupWidth + 10
            snippetCategoryAddButton?.frame = NSRect(x: categoryButtonX, y: categoryRowY, width: categoryButtonWidths[0], height: 24)
            categoryButtonX += categoryButtonWidths[0] + categoryButtonGap
            snippetCategoryRenameButton?.frame = NSRect(x: categoryButtonX, y: categoryRowY, width: categoryButtonWidths[1], height: 24)
            categoryButtonX += categoryButtonWidths[1] + categoryButtonGap
            snippetCategoryDeleteButton?.frame = NSRect(x: categoryButtonX, y: categoryRowY, width: categoryButtonWidths[2], height: 24)
        }
        let listFrameHeight = listHeight + 10
        let editorGap: CGFloat = showsSnippetCategories ? 12 : 0
        let editorWidth = showsSnippetCategories ? min(250, max(220, floor(width * 0.38))) : 0
        let listWidth = max(180, width - editorWidth - editorGap)
        scrollView?.frame = NSRect(x: margin, y: 16, width: listWidth, height: listFrameHeight)
        if showsSnippetCategories {
            snippetEditorView?.frame = NSRect(x: margin + listWidth + editorGap, y: 16, width: editorWidth, height: listFrameHeight)
            layoutSnippetEditorControls(width: editorWidth, height: listFrameHeight)
        }
        synchronizeListGeometry(frameWidth: listWidth, height: listFrameHeight)
        hidePreviewBubble()
    }

    private func layoutSnippetEditorControls(width: CGFloat, height: CGFloat) {
        let inset: CGFloat = 12
        let contentWidth = max(120, width - (inset * 2))
        let topY = height - inset
        snippetEditorStatusLabel?.frame = NSRect(x: inset, y: topY - 18, width: contentWidth, height: 16)
        snippetFolderEnableButton?.frame = NSRect(x: inset, y: topY - 46, width: contentWidth, height: 18)
        snippetEnableButton?.frame = NSRect(x: inset, y: topY - 72, width: contentWidth, height: 18)
        snippetEditorTitleLabel?.frame = NSRect(x: inset, y: topY - 102, width: contentWidth, height: 16)
        snippetEditorTitleField?.frame = NSRect(x: inset, y: topY - 132, width: contentWidth, height: 24)
        snippetEditorContentLabel?.frame = NSRect(x: inset, y: topY - 160, width: contentWidth, height: 16)
        let saveHeight: CGFloat = 28
        let contentBottom = inset + saveHeight + 10
        let contentHeight = max(90, topY - 170 - contentBottom)
        snippetEditorScrollView?.frame = NSRect(x: inset, y: contentBottom, width: contentWidth, height: contentHeight)
        snippetEditorTextView?.minSize = NSSize(width: 0, height: contentHeight)
        snippetEditorTextView?.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        snippetEditorTextView?.isVerticallyResizable = true
        snippetEditorTextView?.isHorizontallyResizable = false
        snippetEditorTextView?.textContainer?.containerSize = NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)
        snippetEditorTextView?.textContainer?.widthTracksTextView = true
        snippetSaveButton?.frame = NSRect(x: inset, y: inset, width: min(112, contentWidth), height: 24)
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
                cellView.frame = NSRect(x: 0, y: cellView.frame.origin.y, width: safeWidth, height: cellView.frame.height)
                cellView.needsLayout = true
                cellView.needsDisplay = true
            }
        }
    }

    private func updateTabWidths(totalWidth: CGFloat) {
        guard let segmentedControl else { return }
        let segmentWidth = max(72, floor(totalWidth / 3))
        for segment in 0..<3 {
            segmentedControl.setWidth(segmentWidth, forSegment: segment)
        }
    }

    private func layoutSettingsSidebar(width: CGFloat, height: CGFloat) {
        guard let sidebar = settingsSidebarView else { return }
        let inset: CGFloat = 10
        let buttonHeight: CGFloat = 38
        let gap: CGFloat = 4
        var currentY = height - inset - buttonHeight
        for button in settingsCategoryButtons {
            button.frame = NSRect(x: inset, y: currentY, width: max(80, width - (inset * 2)), height: buttonHeight)
            currentY -= buttonHeight + gap
        }
        sidebar.needsLayout = true
        updateSettingsSidebarSelection()
    }

    private func updateSettingsSidebarSelection() {
        settingsPageTitleLabel?.stringValue = activeSettingsCategory.title
        settingsPageDescriptionLabel?.stringValue = activeSettingsCategory.detail
        for button in settingsCategoryButtons {
            let isSelected = button.tag == activeSettingsCategory.rawValue
            button.state = isSelected ? .on : .off
            button.layer?.backgroundColor = isSelected
                ? themeAccentColor.withAlphaComponent(isThemeLightenEnabled ? 0.10 : 0.16).cgColor
                : NSColor.clear.cgColor
            button.layer?.borderWidth = isSelected ? 1 : 0
            button.layer?.borderColor = themeAccentColor.withAlphaComponent(0.26).cgColor
        }
    }

    private func layoutInlineSettingsControls(margin: CGFloat, width: CGFloat, topY: CGFloat, isVisible: Bool) {
        let allControls: [NSView?] = [
            settingsPageTitleLabel, settingsPageDescriptionLabel,
            generalSectionLabel, launchOnLoginButton, inputPasteCommandButton, maxHistorySizeLabel, maxHistorySizeStepper, maxHistorySizeValueLabel, statusItemLabel, statusItemPopup, shortcutSectionLabel, shortcutStatusLabel,
            snippetSettingsSectionLabel, snippetSummaryLabel, snippetFoldersLabel, snippetShortcutsLabel, snippetShortcutScrollView, manageSnippetsButton,
            viewSectionLabel, rowNumbersButton, timestampLabel, timestampPopup, usageCountButton, usageStyleLabel, usageStylePopup, usedItemStyleLabel, usedItemStylePopup, themePresetLabel, themePresetPopup, themeLightenButton,
            historySectionLabel, dedupeButton, overwriteSameHistoryButton, reuseTopButton, clearHistoryButton,
            privacySectionLabel, excludedAppsButton, excludedAppsSummaryLabel, storedTypesSectionLabel,
            filterSectionLabel, hideRuleTextField, hideRuleModePopup, addHideRuleButton, removeLastHideRuleButton, clearHideRulesButton, hideRulesSummaryLabel, hideRulesExamplesLabel, hideRulesNoteLabel,
            licenseSectionLabel, licensePlanLabel, licenseStateLabel, licenseLimitsLabel, licenseKeyField, licenseActivateButton, licenseActivationStatusLabel, licenseUpgradeButton, licenseProLockedControlView, licenseMockNoteLabel, licenseStateExamplesLabel,
            labsSectionLabel, labsNoteLabel,
            heightControlLabel, heightLabel, heightStepper
        ]
        allControls.forEach { $0?.isHidden = true }
        globalShortcutRows.flatMap { $0.views }.forEach { $0.isHidden = true }
        updatesPreferenceView?.isHidden = true
        pauseRecordingButton?.isHidden = true
        storedTypeButtons.forEach { $0.isHidden = true }
        guard isVisible else { return }
        refreshSnippetSettingsSummary()
        refreshGlobalShortcutRows()

        let rowH: CGFloat = 24
        let rowGap: CGFloat = 32
        let fieldLabelWidth: CGFloat = 58
        let contentX = margin + 18
        let contentWidth = max(240, width - 36)
        let columnWidth = contentWidth
        let leftX = contentX
        settingsPageTitleLabel?.isHidden = false
        settingsPageDescriptionLabel?.isHidden = false
        settingsPageTitleLabel?.frame = NSRect(x: leftX, y: topY - 44, width: columnWidth, height: 26)
        settingsPageDescriptionLabel?.frame = NSRect(x: leftX, y: topY - 66, width: columnWidth, height: 18)
        let firstY = topY - 102

        var generalControls: [NSView?] = [
            generalSectionLabel, launchOnLoginButton, inputPasteCommandButton,
            maxHistorySizeLabel, maxHistorySizeStepper, maxHistorySizeValueLabel,
            statusItemLabel, statusItemPopup, shortcutSectionLabel, shortcutStatusLabel
        ]
        generalControls.append(contentsOf: globalShortcutRows.flatMap { $0.views }.map { Optional($0) })
        let viewControls: [NSView?] = [
            viewSectionLabel, rowNumbersButton, timestampLabel, timestampPopup,
            usageCountButton, usageStyleLabel, usageStylePopup, usedItemStyleLabel,
            usedItemStylePopup, themePresetLabel, themePresetPopup, themeLightenButton,
            heightControlLabel, heightLabel, heightStepper
        ]
        let historyControls: [NSView?] = [historySectionLabel, dedupeButton, overwriteSameHistoryButton, reuseTopButton, clearHistoryButton]
        let snippetControls: [NSView?] = [snippetSettingsSectionLabel, snippetSummaryLabel, snippetFoldersLabel, snippetShortcutsLabel, snippetShortcutScrollView, manageSnippetsButton]
        let privacyControls: [NSView?] = [
            privacySectionLabel, excludedAppsButton, excludedAppsSummaryLabel,
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
            return max(118, min(220, columnWidth - labelWidth - 12))
        }

        func placeHeader(_ label: NSTextField?, originX: CGFloat, originY: CGFloat, width: CGFloat) {
            label?.frame = NSRect(x: originX, y: originY, width: width, height: 18)
        }

        func placeLabeledRow(label: NSTextField?, control: NSView?, originX: CGFloat, originY: CGFloat, width: CGFloat, labelWidth: CGFloat = fieldLabelWidth) {
            label?.frame = NSRect(x: originX, y: originY + 5, width: labelWidth, height: 14)
            control?.frame = NSRect(x: originX + labelWidth + 12, y: originY, width: popupWidth(in: width, labelWidth: labelWidth), height: rowH)
        }

        func placeGeneralSection(originX: CGFloat, originY: CGFloat, width: CGFloat) {
            placeHeader(generalSectionLabel, originX: originX, originY: originY, width: width)
            launchOnLoginButton?.frame = NSRect(x: originX, y: originY - rowGap, width: 150, height: 18)
            inputPasteCommandButton?.frame = NSRect(x: originX + 162, y: originY - rowGap, width: 150, height: 18)
            maxHistorySizeLabel?.frame = NSRect(x: originX, y: originY - (rowGap * 2) - 5, width: fieldLabelWidth, height: 14)
            maxHistorySizeStepper?.frame = NSRect(x: originX + fieldLabelWidth + 12, y: originY - (rowGap * 2) - 10, width: 72, height: rowH)
            maxHistorySizeValueLabel?.frame = NSRect(x: originX + fieldLabelWidth + 92, y: originY - (rowGap * 2) - 5, width: 52, height: 14)
            placeLabeledRow(label: statusItemLabel, control: statusItemPopup, originX: originX, originY: originY - (rowGap * 3) - 12, width: width, labelWidth: 42)
        }

        func placeShortcutSection(originX: CGFloat, originY: CGFloat, width: CGFloat) {
            placeHeader(shortcutSectionLabel, originX: originX, originY: originY, width: width)
            let shortcutRowHeight: CGFloat = 46
            let clearWidth: CGFloat = 52
            let recordWidth: CGFloat = min(168, max(122, floor(width * 0.34)))
            let textWidth = max(110, width - recordWidth - clearWidth - 24)
            for (index, row) in globalShortcutRows.enumerated() {
                let rowY = originY - 34 - CGFloat(index) * shortcutRowHeight
                row.titleLabel.frame = NSRect(x: originX, y: rowY + 20, width: textWidth, height: 16)
                row.detailLabel.frame = NSRect(x: originX, y: rowY + 4, width: textWidth, height: 14)
                row.recordView.frame = NSRect(x: originX + textWidth + 8, y: rowY + 7, width: recordWidth, height: 26)
                row.clearButton.frame = NSRect(x: originX + textWidth + recordWidth + 16, y: rowY + 7, width: clearWidth, height: 26)
            }
            shortcutStatusLabel?.frame = NSRect(x: originX,
                                                y: originY - 34 - CGFloat(globalShortcutRows.count) * shortcutRowHeight - 2,
                                                width: width,
                                                height: 16)
        }

        func placeViewSection(originX: CGFloat, originY: CGFloat, width: CGFloat) {
            placeHeader(viewSectionLabel, originX: originX, originY: originY, width: width)
            rowNumbersButton?.frame = NSRect(x: originX, y: originY - rowGap, width: 86, height: 18)
            placeLabeledRow(label: timestampLabel, control: timestampPopup, originX: originX, originY: originY - (rowGap * 2) - 4, width: width)
            usageCountButton?.frame = NSRect(x: originX, y: originY - (rowGap * 3) - 2, width: 82, height: 18)
            placeLabeledRow(label: usageStyleLabel, control: usageStylePopup, originX: originX + 104, originY: originY - (rowGap * 3) - 6, width: max(150, width - 104), labelWidth: 38)
            placeLabeledRow(label: usedItemStyleLabel, control: usedItemStylePopup, originX: originX, originY: originY - (rowGap * 4) - 8, width: width)
            placeLabeledRow(label: themePresetLabel, control: themePresetPopup, originX: originX, originY: originY - (rowGap * 5) - 10, width: width)
            themeLightenButton?.frame = NSRect(x: originX, y: originY - (rowGap * 6) - 6, width: 96, height: 18)
            heightControlLabel?.frame = NSRect(x: originX + 104, y: originY - (rowGap * 6) - 7, width: fieldLabelWidth, height: 14)
            heightStepper?.frame = NSRect(x: originX + 104 + fieldLabelWidth + 12, y: originY - (rowGap * 6) - 12, width: 72, height: rowH)
            heightLabel?.frame = NSRect(x: originX + 104 + fieldLabelWidth + 92, y: originY - (rowGap * 6) - 7, width: 42, height: 14)
        }

        func placeHistorySection(originX: CGFloat, originY: CGFloat, width: CGFloat) {
            placeHeader(historySectionLabel, originX: originX, originY: originY, width: width)
            dedupeButton?.frame = NSRect(x: originX, y: originY - rowGap, width: 92, height: 18)
            reuseTopButton?.frame = NSRect(x: originX + 106, y: originY - rowGap, width: 118, height: 18)
            overwriteSameHistoryButton?.frame = NSRect(x: originX, y: originY - (rowGap * 2) - 2, width: 136, height: 18)
            clearHistoryButton?.frame = NSRect(x: originX, y: originY - (rowGap * 3) - 6, width: 86, height: rowH)
        }

        func layoutSnippetShortcutRows(width: CGFloat) {
            let rowHeight: CGFloat = 34
            let documentHeight = max(CGFloat(snippetShortcutRows.count) * rowHeight, snippetShortcutScrollView?.bounds.height ?? 0)
            snippetShortcutDocumentView?.frame = NSRect(x: 0, y: 0, width: width, height: documentHeight)

            for (index, row) in snippetShortcutRows.enumerated() {
                let rowOriginY = documentHeight - CGFloat(index + 1) * rowHeight
                let clearWidth: CGFloat = 52
                let recordWidth: CGFloat = min(150, max(112, width * 0.32))
                let textWidth = max(80, width - recordWidth - clearWidth - 20)
                row.titleLabel.frame = NSRect(x: 0, y: rowOriginY + 17, width: textWidth, height: 14)
                row.detailLabel.frame = NSRect(x: 0, y: rowOriginY + 3, width: textWidth, height: 13)
                row.recordView.frame = NSRect(x: textWidth + 8, y: rowOriginY + 5, width: recordWidth, height: 24)
                row.clearButton.frame = NSRect(x: textWidth + recordWidth + 16, y: rowOriginY + 5, width: clearWidth, height: 24)
            }
        }

        func placeSnippetSettingsSection(originX: CGFloat, originY: CGFloat, width: CGFloat, scrollHeight: CGFloat) {
            placeHeader(snippetSettingsSectionLabel, originX: originX, originY: originY, width: width)
            snippetSummaryLabel?.frame = NSRect(x: originX, y: originY - rowGap + 4, width: width, height: 18)
            snippetFoldersLabel?.frame = NSRect(x: originX, y: originY - (rowGap * 2) + 2, width: width, height: 18)
            snippetShortcutsLabel?.frame = NSRect(x: originX, y: originY - (rowGap * 3), width: width, height: 18)
            snippetShortcutScrollView?.frame = NSRect(x: originX, y: originY - (rowGap * 3) - scrollHeight - 6, width: width, height: scrollHeight)
            layoutSnippetShortcutRows(width: width)
            manageSnippetsButton?.frame = NSRect(x: originX, y: originY - (rowGap * 3) - scrollHeight - 38, width: min(136, width), height: rowH)
        }

        func placePrivacySection(originX: CGFloat, originY: CGFloat, width: CGFloat) {
            placeHeader(privacySectionLabel, originX: originX, originY: originY, width: width)
            excludedAppsSummaryLabel?.frame = NSRect(x: originX, y: originY - rowGap + 3, width: width, height: 18)
            excludedAppsButton?.frame = NSRect(x: originX, y: originY - (rowGap * 2) - 6, width: min(178, width), height: rowH)
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
            licenseProLockedControlView?.frame = NSRect(x: originX, y: originY - 306, width: width, height: 88)
            licenseMockNoteLabel?.frame = NSRect(x: originX, y: originY - 360, width: width, height: 34)
            licenseStateExamplesLabel?.frame = NSRect(x: originX, y: originY - 384, width: width, height: 14)
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
            placeShortcutSection(originX: leftX, originY: firstY - 150, width: columnWidth)
        case .view:
            show(viewControls)
            placeViewSection(originX: leftX, originY: firstY, width: columnWidth)
        case .history:
            show(historyControls)
            placeHistorySection(originX: leftX, originY: firstY, width: columnWidth)
        case .snippets:
            show(snippetControls)
            placeSnippetSettingsSection(originX: leftX, originY: firstY, width: columnWidth, scrollHeight: max(180, topY - 250))
        case .privacy:
            show(privacyControls)
            storedTypeButtons.forEach { $0.isHidden = false }
            placePrivacySection(originX: leftX, originY: firstY, width: columnWidth)
            placeStoredTypesSection(originX: leftX, originY: firstY - 112, width: columnWidth)
            placeFiltersSection(originX: leftX, originY: firstY - 268, width: columnWidth)
        case .updates:
            show(updatesControls)
            placeUpdatesSection(originX: leftX, originY: firstY, width: columnWidth)
        case .license:
            show(licenseControls)
            placeLicenseSection(originX: leftX, originY: firstY, width: columnWidth)
        }
    }

    fileprivate func reloadHistoryItems(_ items: [BoardManHistoryItem]) {
        allItems = items
        reloadSnippetCategoryPopup()
        applyCurrentFilter()
        if let table = placeholderList {
            makeFirstResponder(table)
        }
    }

    fileprivate func focusTableForKeyboard() {
        guard activeTab != .settings else {
            makeFirstResponder(self)
            return
        }
        guard let table = placeholderList else { return }
        makeFirstResponder(table)
        if !historyItems.isEmpty, selectedIndex < 0 {
            selectedIndex = 0
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

    @objc private func rowNumbersChanged(_ sender: NSButton) {
        AppEnvironment.current.defaults.set(sender.state == .on, forKey: Constants.UserDefaults.boardManShowRowNumbers)
        onRefreshRequested?()
    }

    @objc private func timestampFormatChanged(_ sender: NSPopUpButton) {
        let value = BoardManPanel.timestampFormat(forMenuTitle: sender.titleOfSelectedItem)
        AppEnvironment.current.defaults.set(value, forKey: Constants.UserDefaults.boardManTimestampFormat)
        onRefreshRequested?()
    }

    @objc private func usageCountChanged(_ sender: NSButton) {
        AppEnvironment.current.defaults.set(sender.state == .on, forKey: Constants.UserDefaults.boardManShowUsageCount)
        onRefreshRequested?()
    }

    @objc private func usageStyleChanged(_ sender: NSPopUpButton) {
        AppEnvironment.current.defaults.set(BoardManPanel.allowedUsageCountStyle(sender.titleOfSelectedItem),
                                            forKey: Constants.UserDefaults.boardManUsageCountStyle)
        onRefreshRequested?()
    }

    @objc private func usedItemStyleChanged(_ sender: NSPopUpButton) {
        AppEnvironment.current.defaults.set(BoardManPanel.allowedUsedItemStyle(sender.titleOfSelectedItem),
                                            forKey: Constants.UserDefaults.boardManUsedItemStyle)
        placeholderList?.reloadData()
        synchronizeListGeometry()
    }

    @objc private func themePresetChanged(_ sender: NSPopUpButton) {
        let title = sender.titleOfSelectedItem ?? BoardManThemePreset.defaultPreset.title
        let preset = BoardManThemePreset.allCases.first { $0.title == title } ?? .defaultPreset
        AppEnvironment.current.defaults.set(preset.title, forKey: Constants.UserDefaults.boardManThemePreset)
        applyLiquidGlassStyle()
        layoutPanelSubviews()
        placeholderList?.reloadData()
        synchronizeListGeometry()
        contentView?.needsDisplay = true
    }

    @objc private func themeLightenChanged(_ sender: NSButton) {
        AppEnvironment.current.defaults.set(sender.state == .on, forKey: Constants.UserDefaults.boardManThemeLighten)
        applyLiquidGlassStyle()
        layoutPanelSubviews()
        placeholderList?.reloadData()
        synchronizeListGeometry()
        contentView?.needsDisplay = true
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
        let hasSelection = selectedSnippetItem != nil
        snippetAddButton?.isEnabled = isSnippetsTab
        snippetEditButton?.isEnabled = isSnippetsTab && hasSelection
        snippetDeleteButton?.isEnabled = isSnippetsTab && hasSelection
        snippetSaveButton?.isEnabled = isSnippetsTab && hasSelection
        snippetEnableButton?.isEnabled = isSnippetsTab && hasSelection
        let canManageSelectedCategory = isSnippetsTab && selectedCategoryFolder() != nil
        snippetCategoryRenameButton?.isEnabled = canManageSelectedCategory
        snippetCategoryDeleteButton?.isEnabled = canManageSelectedCategory
        snippetFolderEnableButton?.isEnabled = isSnippetsTab && editorFolder() != nil
        refreshSnippetEditor()
    }

    private func editorFolder() -> CPYFolder? {
        if let folder = selectedCategoryFolder() {
            return folder
        }
        guard let item = selectedSnippetItem,
              let identifier = item.categoryIdentifier,
              identifier != BoardManPanel.uncategorizedCategoryIdentifier else {
            return nil
        }
        let realm = try! Realm()
        return realm.object(ofType: CPYFolder.self, forPrimaryKey: identifier)
    }

    private func refreshSnippetEditor() {
        guard activeTab == .snippets else { return }
        let realm = try! Realm()
        let folder = editorFolder()
        snippetFolderEnableButton?.state = (folder?.enable ?? false) ? .on : .off
        if let folder {
            let title = folder.title.trimmingCharacters(in: .whitespacesAndNewlines)
            snippetEditorStatusLabel?.stringValue = title.isEmpty ? "Group: untitled folder" : "Group: \(title)"
        } else {
            snippetEditorStatusLabel?.stringValue = "Group: Uncategorized"
        }

        guard let item = selectedSnippetItem,
              let snippet = realm.object(ofType: CPYSnippet.self, forPrimaryKey: item.dataHash) else {
            snippetEditorTitleField?.stringValue = ""
            snippetEditorTextView?.string = ""
            snippetEnableButton?.state = .off
            snippetEditorTitleField?.isEnabled = false
            snippetEditorTextView?.isEditable = false
            return
        }

        snippetEditorTitleField?.isEnabled = true
        snippetEditorTextView?.isEditable = true
        if snippetEditorTitleField?.currentEditor() == nil {
            snippetEditorTitleField?.stringValue = snippet.title
        }
        if snippetEditorTextView?.window?.firstResponder !== snippetEditorTextView {
            snippetEditorTextView?.string = snippet.content
        }
        snippetEnableButton?.state = snippet.enable ? .on : .off
    }

    private func reloadSnippetCategoryPopup() {
        guard let popup = snippetCategoryPopup else { return }
        let selectedIdentifier = activeSnippetCategoryIdentifier
        popup.removeAllItems()
        addCategoryMenuItem(to: popup, title: "All", identifier: BoardManPanel.allCategoriesIdentifier)

        let realm = try! Realm()
        let folders = realm.objects(CPYFolder.self).sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)
        folders.forEach { folder in
            let title = folder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "untitled folder" : folder.title
            addCategoryMenuItem(to: popup, title: title, identifier: folder.identifier)
        }

        if allItems.contains(where: { $0.categoryIdentifier == BoardManPanel.uncategorizedCategoryIdentifier }) {
            addCategoryMenuItem(to: popup, title: "Uncategorized", identifier: BoardManPanel.uncategorizedCategoryIdentifier)
        }

        let identifiers = popup.itemArray.compactMap { $0.representedObject as? String }
        activeSnippetCategoryIdentifier = identifiers.contains(selectedIdentifier) ? selectedIdentifier : BoardManPanel.allCategoriesIdentifier
        if let item = popup.itemArray.first(where: { ($0.representedObject as? String) == activeSnippetCategoryIdentifier }) {
            popup.select(item)
        }
        updateSnippetActionButtons()
    }

    private func addCategoryMenuItem(to popup: NSPopUpButton, title: String, identifier: String) {
        popup.addItem(withTitle: title)
        popup.lastItem?.representedObject = identifier
    }

    private func selectedCategoryFolder() -> CPYFolder? {
        guard activeSnippetCategoryIdentifier != BoardManPanel.allCategoriesIdentifier,
              activeSnippetCategoryIdentifier != BoardManPanel.uncategorizedCategoryIdentifier else {
            return nil
        }
        let realm = try! Realm()
        return realm.object(ofType: CPYFolder.self, forPrimaryKey: activeSnippetCategoryIdentifier)
    }

    @objc private func snippetCategoryFilterChanged(_ sender: NSPopUpButton) {
        activeSnippetCategoryIdentifier = (sender.selectedItem?.representedObject as? String) ?? BoardManPanel.allCategoriesIdentifier
        selectedIndex = -1
        hoveredRow = -1
        hidePreviewBubble()
        applyCurrentFilter()
        refreshSnippetEditor()
    }

    @objc private func addSnippetCategoryFromPanel(_ sender: Any?) {
        let realm = try! Realm()
        guard canAddSnippetFolder(in: realm) else {
            showProLockedAlert(message: "Free plan includes 1 snippet folder. Upgrade to Pro to add more.")
            return
        }
        guard let title = promptForCategoryTitle(title: "Add Group", initialTitle: "") else { return }
        let folder = CPYFolder()
        folder.title = title
        folder.enable = true
        folder.index = (realm.objects(CPYFolder.self).sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true).last?.index ?? -1) + 1
        realm.transaction {
            realm.add(folder)
        }
        activeSnippetCategoryIdentifier = folder.identifier
        onRefreshRequested?()
    }

    @objc private func renameSnippetCategoryFromPanel(_ sender: Any?) {
        guard let folder = selectedCategoryFolder(),
              let title = promptForCategoryTitle(title: "Rename Group", initialTitle: folder.title) else { return }
        let realm = try! Realm()
        guard let savedFolder = realm.object(ofType: CPYFolder.self, forPrimaryKey: folder.identifier) else { return }
        realm.transaction {
            savedFolder.title = title
        }
        onRefreshRequested?()
    }

    @objc private func deleteSnippetCategoryFromPanel(_ sender: Any?) {
        guard let folder = selectedCategoryFolder() else {
            NSSound.beep()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Delete Group"
        alert.informativeText = "Delete \"\(folder.title)\"? Snippets in this group will be moved to Uncategorized."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete Group")
        alert.addButton(withTitle: "Cancel")
        guard runSnippetPanelAlert(alert) == .alertFirstButtonReturn else { return }

        let realm = try! Realm()
        guard let savedFolder = realm.object(ofType: CPYFolder.self, forPrimaryKey: folder.identifier) else { return }
        let fallbackFolder = uncategorizedFolder(in: realm, excluding: savedFolder.identifier)
        realm.transaction {
            let movedSnippets = Array(savedFolder.snippets)
            savedFolder.snippets.removeAll()
            movedSnippets.forEach { snippet in
                snippet.index = fallbackFolder.snippets.count
                fallbackFolder.snippets.append(snippet)
            }
            realm.delete(savedFolder)
        }
        activeSnippetCategoryIdentifier = fallbackFolder.identifier
        selectedIndex = -1
        onRefreshRequested?()
        refreshSnippetEditor()
    }

    private func promptForCategoryTitle(title: String, initialTitle: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Enter a group name."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = initialTitle
        alert.accessoryView = field
        guard runSnippetPanelAlert(alert, initialFirstResponder: field) == .alertFirstButtonReturn else { return nil }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showSnippetValidationAlert(message: "Group name is required.")
            return nil
        }
        return trimmed
    }

    @objc private func addSnippetFromPanel(_ sender: Any?) {
        let realm = try! Realm()
        guard canAddSnippet(in: realm) else {
            showProLockedAlert(message: "Free plan includes 5 snippets. Upgrade or activate Founder Lifetime to add more.")
            return
        }
        let folder = snippetTargetFolder(in: realm, preferredIdentifier: activeSnippetCategoryIdentifier)
        let snippet = CPYSnippet()
        snippet.title = "untitled snippet"
        snippet.content = ""
        snippet.enable = true
        snippet.index = folder.snippets.count
        realm.transaction {
            folder.snippets.append(snippet)
        }
        activeSnippetCategoryIdentifier = folder.identifier
        onRefreshRequested?()
        selectSnippetInCurrentList(identifier: snippet.identifier)
        snippetEditorTitleField?.selectText(nil)
    }

    private func canAddSnippet(in realm: Realm) -> Bool {
        return EntitlementGate.canCreateSnippet(currentSnippetCount: realm.objects(CPYSnippet.self).count)
    }

    private func canAddSnippetFolder(in realm: Realm) -> Bool {
        return EntitlementGate.canCreateSnippetFolder(currentFolderCount: realm.objects(CPYFolder.self).count)
    }

    private func showProLockedAlert(message: String) {
        NSSound.beep()
        let alert = NSAlert()
        alert.messageText = "Pro limit reached"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func editSelectedSnippetFromPanel(_ sender: Any?) {
        guard let item = selectedSnippetItem else {
            NSSound.beep()
            return
        }

        selectSnippetInCurrentList(identifier: item.dataHash)
        refreshSnippetEditor()
        makeFirstResponder(snippetEditorTitleField)
    }

    @objc private func saveSelectedSnippetFromPanel(_ sender: Any?) {
        guard let item = selectedSnippetItem else {
            NSSound.beep()
            return
        }
        let realm = try! Realm()
        guard let snippet = realm.object(ofType: CPYSnippet.self, forPrimaryKey: item.dataHash) else {
            NSSound.beep()
            onRefreshRequested?()
            return
        }
        let content = snippetEditorTextView?.string ?? ""
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showSnippetValidationAlert(message: "Snippet content is required.")
            return
        }
        realm.transaction {
            snippet.title = normalizedSnippetTitle(snippetEditorTitleField?.stringValue ?? "")
            snippet.content = content
            snippet.enable = snippetEnableButton?.state == .on
        }
        onRefreshRequested?()
        selectSnippetInCurrentList(identifier: snippet.identifier)
    }

    @objc private func snippetFolderEnableChanged(_ sender: NSButton) {
        guard let folder = editorFolder() else {
            NSSound.beep()
            sender.state = .off
            return
        }
        let realm = try! Realm()
        guard let savedFolder = realm.object(ofType: CPYFolder.self, forPrimaryKey: folder.identifier) else { return }
        realm.transaction {
            savedFolder.enable = sender.state == .on
        }
        onRefreshRequested?()
    }

    @objc private func snippetEnableChanged(_ sender: NSButton) {
        guard let item = selectedSnippetItem else {
            NSSound.beep()
            sender.state = .off
            return
        }
        let realm = try! Realm()
        guard let snippet = realm.object(ofType: CPYSnippet.self, forPrimaryKey: item.dataHash) else { return }
        realm.transaction {
            snippet.enable = sender.state == .on
        }
        onRefreshRequested?()
        selectSnippetInCurrentList(identifier: snippet.identifier)
    }

    @objc private func deleteSelectedSnippetFromPanel(_ sender: Any?) {
        guard let item = selectedSnippetItem else {
            NSSound.beep()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Delete Snippet"
        alert.informativeText = "Delete \"\(item.primaryTitle)\" from snippets? Clipboard history is not changed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard runSnippetPanelAlert(alert) == .alertFirstButtonReturn else { return }

        let realm = try! Realm()
        guard let snippet = realm.object(ofType: CPYSnippet.self, forPrimaryKey: item.dataHash) else {
            onRefreshRequested?()
            return
        }

        let identifier = snippet.identifier
        realm.transaction {
            if let folder = snippet.folder, let index = folder.snippets.index(of: snippet) {
                folder.snippets.remove(at: index)
                for (snippetIndex, folderSnippet) in folder.snippets.enumerated() {
                    folderSnippet.index = snippetIndex
                }
            }
            realm.delete(snippet)
        }
        PinnedSnippetStore.shared.remove(identifier)
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

    private func promptForSnippet(title: String, initialTitle: String, initialContent: String, initialCategoryIdentifier: String) -> (title: String, content: String, categoryIdentifier: String)? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Enter a title, category, and content."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 224))
        let titleLabel = NSTextField(labelWithString: "Title")
        titleLabel.frame = NSRect(x: 0, y: 202, width: 360, height: 16)
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        accessory.addSubview(titleLabel)

        let titleField = NSTextField(frame: NSRect(x: 0, y: 174, width: 360, height: 24))
        titleField.stringValue = initialTitle
        titleField.font = NSFont.systemFont(ofSize: 12)
        accessory.addSubview(titleField)

        let categoryLabel = NSTextField(labelWithString: "Category")
        categoryLabel.frame = NSRect(x: 0, y: 150, width: 360, height: 16)
        categoryLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        accessory.addSubview(categoryLabel)

        let categoryPopup = NSPopUpButton(frame: NSRect(x: 0, y: 122, width: 360, height: 24), pullsDown: false)
        populateCategoryPopup(categoryPopup, selectedIdentifier: initialCategoryIdentifier)
        categoryPopup.font = NSFont.systemFont(ofSize: 12)
        accessory.addSubview(categoryPopup)

        let contentLabel = NSTextField(labelWithString: "Content")
        contentLabel.frame = NSRect(x: 0, y: 98, width: 360, height: 16)
        contentLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        accessory.addSubview(contentLabel)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 94))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 348, height: 94))
        textView.string = initialContent
        textView.font = NSFont.systemFont(ofSize: 12)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.enabledTextCheckingTypes = 0
        scroll.documentView = textView
        accessory.addSubview(scroll)

        alert.accessoryView = accessory
        guard runSnippetPanelAlert(alert, initialFirstResponder: initialTitle.isEmpty ? titleField : textView) == .alertFirstButtonReturn else { return nil }
        let categoryIdentifier = (categoryPopup.selectedItem?.representedObject as? String) ?? BoardManPanel.allCategoriesIdentifier
        return (titleField.stringValue, textView.string, categoryIdentifier)
    }

    private func normalizedSnippetTitle(_ title: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "untitled snippet" : trimmedTitle
    }

    private func showSnippetValidationAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Snippet Not Saved"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        runSnippetPanelAlert(alert)
    }

    @discardableResult
    private func runSnippetPanelAlert(_ alert: NSAlert, initialFirstResponder: NSView? = nil) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        if isVisible {
            makeKey()
            orderFrontRegardless()
        } else {
            makeKeyAndOrderFront(nil)
        }
        alert.window.initialFirstResponder = initialFirstResponder
        alert.window.level = .modalPanel

        guard isVisible else {
            alert.window.center()
            alert.window.orderFrontRegardless()
            return alert.runModal()
        }

        var response = NSApplication.ModalResponse.abort
        alert.beginSheetModal(for: self) { result in
            response = result
            NSApp.stopModal()
        }
        NSApp.runModal(for: alert.window)
        return response
    }

    private func populateCategoryPopup(_ popup: NSPopUpButton, selectedIdentifier: String) {
        popup.removeAllItems()
        let realm = try! Realm()
        let folders = realm.objects(CPYFolder.self).sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)
        folders.forEach { folder in
            let title = folder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "untitled folder" : folder.title
            addCategoryMenuItem(to: popup, title: title, identifier: folder.identifier)
        }
        addCategoryMenuItem(to: popup, title: "Uncategorized", identifier: BoardManPanel.uncategorizedCategoryIdentifier)
        let effectiveIdentifier = selectedIdentifier == BoardManPanel.allCategoriesIdentifier ? (folders.first?.identifier ?? BoardManPanel.uncategorizedCategoryIdentifier) : selectedIdentifier
        if let item = popup.itemArray.first(where: { ($0.representedObject as? String) == effectiveIdentifier }) {
            popup.select(item)
        }
    }

    private func snippetTargetFolder(in realm: Realm, preferredIdentifier: String) -> CPYFolder {
        if preferredIdentifier == BoardManPanel.uncategorizedCategoryIdentifier {
            return uncategorizedFolder(in: realm)
        }
        if preferredIdentifier != BoardManPanel.allCategoriesIdentifier,
           let folder = realm.object(ofType: CPYFolder.self, forPrimaryKey: preferredIdentifier) {
            return folder
        }
        return defaultSnippetFolder(in: realm)
    }

    private func defaultSnippetFolder(in realm: Realm) -> CPYFolder {
        let folders = realm.objects(CPYFolder.self).sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)
        if let enabledFolder = folders.first(where: { $0.enable }) {
            return enabledFolder
        }
        if let firstFolder = folders.first {
            return firstFolder
        }

        let folder = CPYFolder()
        folder.title = "Board-Man Snippets"
        folder.enable = true
        folder.index = (folders.last?.index ?? -1) + 1
        realm.transaction {
            realm.add(folder)
        }
        return folder
    }

    private func uncategorizedFolder(in realm: Realm, excluding excludedIdentifier: String? = nil) -> CPYFolder {
        let folders = realm.objects(CPYFolder.self).sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)
        if let folder = folders.first(where: { $0.identifier != excludedIdentifier && $0.title == "Uncategorized" }) {
            return folder
        }
        let folder = CPYFolder()
        folder.title = "Uncategorized"
        folder.enable = true
        folder.index = (folders.last?.index ?? -1) + 1
        if realm.isInWriteTransaction {
            realm.add(folder)
        } else {
            realm.transaction {
                realm.add(folder)
            }
        }
        return folder
    }

    private func moveSnippet(_ snippet: CPYSnippet, toCategoryIdentifier categoryIdentifier: String, in realm: Realm) {
        let targetFolder = snippetTargetFolder(in: realm, preferredIdentifier: categoryIdentifier)
        if snippet.folder?.identifier == targetFolder.identifier { return }
        realm.transaction {
            if let currentFolder = snippet.folder, let index = currentFolder.snippets.index(of: snippet) {
                currentFolder.snippets.remove(at: index)
                for (snippetIndex, folderSnippet) in currentFolder.snippets.enumerated() {
                    folderSnippet.index = snippetIndex
                }
            }
            snippet.index = targetFolder.snippets.count
            targetFolder.snippets.append(snippet)
        }
    }

    @objc private func panelHeightChanged(_ sender: NSStepper) {
        let height = BoardManPanel.clampedPanelHeight(sender.integerValue)
        sender.integerValue = height
        heightLabel?.stringValue = "\(height)"
        AppEnvironment.current.defaults.set(height, forKey: Constants.UserDefaults.boardManPanelHeight)
        var frame = self.frame
        frame.origin.y += frame.height - CGFloat(height)
        frame.size.height = CGFloat(height)
        setFrame(frame, display: true, animate: false)
        layoutPanelSubviews()
    }

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        activateTab(BoardManPanelTab(rawValue: sender.selectedSegment) ?? .history)
    }

    private func activateTab(_ tab: BoardManPanelTab) {
        activeTab = tab
        segmentedControl?.selectedSegment = tab.rawValue
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

    @objc private func maxHistorySizeChanged(_ sender: NSStepper) {
        let value = max(1, sender.integerValue)
        sender.integerValue = value
        maxHistorySizeValueLabel?.stringValue = "\(value)"
        AppEnvironment.current.defaults.set(value, forKey: Constants.UserDefaults.maxHistorySize)
        onRefreshRequested?()
    }

    @objc private func statusItemChanged(_ sender: NSPopUpButton) {
        AppEnvironment.current.defaults.set(BoardManPanel.statusItemValue(for: sender.titleOfSelectedItem),
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
        onRefreshRequested?()
    }

    @objc private func clearHistoryRequested(_ sender: NSButton) {
        let alert = NSAlert()
        alert.messageText = "Clear History"
        alert.informativeText = "Clear all clipboard history?"
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        AppEnvironment.current.clipService.clearAll()
        onRefreshRequested?()
    }

    @objc private func openExcludedAppsSettings(_ sender: NSButton) {
        AppEnvironment.current.menuManager.hideBoardManPanelForPreferences()
        NSApp.activate(ignoringOtherApps: true)
        CPYPreferencesWindowController.sharedController.showWindow(self)
    }

    @objc private func openSnippetManager(_ sender: NSButton) {
        openSnippetsManagerMode()
    }

    @objc private func openLicensePurchasePage(_ sender: NSButton) {
        guard let url = URL(string: "https://uniplanck.com") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func activateLicenseRequested(_ sender: NSButton) {
        licenseActivationStatusLabel?.stringValue = "Activation is not connected yet. Free remains the default runtime entitlement."
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
        guard !rules.isEmpty else {
            hideRulesSummaryLabel?.stringValue = "0 hide rules"
            hideRulesExamplesLabel?.stringValue = "Examples: contains invoice, exact draft"
            removeLastHideRuleButton?.isEnabled = false
            clearHideRulesButton?.isEnabled = false
            return
        }
        let sample = rules.prefix(2).map { rule -> String in
            let value = rule.value.replacingOccurrences(of: "\n", with: " ")
            let clipped = value.count > 28 ? String(value.prefix(25)) + "..." : value
            return "\(rule.mode.summaryTitle) \"\(clipped)\""
        }.joined(separator: ", ")
        hideRulesSummaryLabel?.stringValue = "\(rules.count) hide \(rules.count == 1 ? "rule" : "rules") active"
        hideRulesExamplesLabel?.stringValue = "Examples: \(sample)"
        removeLastHideRuleButton?.isEnabled = true
        clearHideRulesButton?.isEnabled = true
    }

    private func refreshLicenseSummary() {
        let snapshot = EntitlementService.shared.currentSnapshot
        let isActive = snapshot.isProEntitled
        licensePlanLabel?.stringValue = licensePlanTitle(snapshot.plan)
        licensePlanLabel?.textColor = isActive ? .systemGreen : .labelColor
        licenseStateLabel?.stringValue = "\(licenseStateTitle(snapshot.state)): \(licenseStateDescription(snapshot))"
        licenseStateLabel?.textColor = licenseStateColor(snapshot.state)
        licenseLimitsLabel?.stringValue = "History \(limitText(snapshot.limits.maxHistoryItems))  •  Pins \(limitText(snapshot.limits.maxPinnedItems))  •  Snippets \(limitText(snapshot.limits.maxSnippets))"
        licenseKeyField?.placeholderString = isActive ? "Verified in Keychain" : "Secure local license"
        licenseActivateButton?.isHidden = isActive
        licenseUpgradeButton?.isHidden = isActive
        licenseActivationStatusLabel?.stringValue = isActive
            ? "Verified locally. This entitlement is bound to this Mac and restored automatically at launch."
            : "Online activation is not connected yet."
        licenseActivationStatusLabel?.textColor = isActive ? .systemGreen : .secondaryLabelColor
        licenseMockNoteLabel?.stringValue = isActive
            ? "The signed license token is stored in Keychain. The signing private key is not embedded in Board-Man."
            : "Verified licenses are stored in Keychain and bound to this Mac. Online purchase activation remains unavailable."
        licenseProLockedControlView?.refresh()
    }

    private func licensePlanTitle(_ plan: EntitlementPlan) -> String {
        switch plan {
        case .free: return "Free"
        case .pro: return "Pro"
        case .ownerLifetime: return "Owner Lifetime"
        }
    }

    private func licenseStateTitle(_ state: LicenseState) -> String {
        switch state {
        case .free: return "Free"
        case .trial: return "Trial"
        case .proActive: return "Pro Active"
        case .ownerLifetime: return "Owner Lifetime"
        case .proExpired: return "Expired"
        case .invalid: return "Invalid"
        case .offlineGrace: return "Offline Grace"
        case .locked: return "Locked"
        }
    }

    private func licenseActivationStatusTitle(_ status: LicenseActivationStatus) -> String {
        switch status {
        case .activated: return "Activated"
        case .notConfigured: return "Not configured"
        case .invalidInput: return "Invalid input"
        case .networkUnavailable: return "Network unavailable"
        case .unsupported: return "Unsupported"
        }
    }

    private func licenseStateDescription(_ snapshot: EntitlementSnapshot) -> String {
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
        return value == Int.max ? "unlimited" : "\(value)"
    }

    private func refreshExcludedAppsSummary() {
        let apps = AppEnvironment.current.excludeAppService.applications
        guard !apps.isEmpty else {
            excludedAppsSummaryLabel?.stringValue = "0 excluded apps"
            return
        }
        let names = apps.prefix(3).map { $0.name }.joined(separator: ", ")
        let suffix = apps.count > 3 ? " +\(apps.count - 3)" : ""
        excludedAppsSummaryLabel?.stringValue = "\(apps.count) excluded: \(names)\(suffix)"
    }

    @objc private func searchTextChanged(_ sender: NSSearchField) {
        selectedIndex = -1
        hoveredRow = -1
        hidePreviewBubble()
        applyCurrentFilter()
    }

    private func applyCurrentFilter() {
        let query = (searchField?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tabbedItems: [BoardManHistoryItem]
        switch activeTab {
        case .history:
            let pinnedItems = allItems.filter { $0.isPinned && $0.isEnabled }
            let regularHistory = allItems.filter { $0.source == .clip && !$0.isPinned }
            tabbedItems = pinnedItems + regularHistory
        case .snippets:
            let snippetItems = allItems.filter { $0.source == .snippet }
            if activeSnippetCategoryIdentifier == BoardManPanel.allCategoriesIdentifier {
                tabbedItems = snippetItems
            } else {
                tabbedItems = snippetItems.filter { $0.categoryIdentifier == activeSnippetCategoryIdentifier }
            }
        case .settings:
            tabbedItems = []
        }

        let hideRules = BoardManHideRuleStore.shared.rules
        let visibleItems = hideRules.isEmpty ? tabbedItems : tabbedItems.filter { item in
            let searchableText = [item.primaryTitle, item.title, item.previewTitle]
                .joined(separator: "\n")
            return !hideRules.contains { $0.matches(searchableText) }
        }
        historyItems = query.isEmpty ? visibleItems : visibleItems.filter {
            $0.title.lowercased().contains(query) || $0.previewTitle.lowercased().contains(query)
        }
        if historyItems.isEmpty {
            selectedIndex = -1
        } else if selectedIndex >= historyItems.count {
            selectedIndex = historyItems.count - 1
        }
        layoutPanelSubviews()
        placeholderList?.reloadData()
        synchronizeListGeometry()
        syncNativeSelection()
        updateSnippetActionButtons()
    }

    // Single-click paste handler (left click on row pastes immediately; spec #1, #4). Uses safe bounds, selects row for feedback, triggers handlePanelPaste via callback (orderOut first, no close(), strong retain via MenuManager var, no terminate).
    @objc private func handleSingleClickPaste(_ gesture: NSClickGestureRecognizer) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        guard let table = placeholderList else { return }
        let location = gesture.location(in: table)
        let row = table.row(at: location)
        guard row >= 0, let item = historyItems[safe: row] else { return }
        setSelectedIndex(row)
        guard item.isEnabled else {
            NSSound.beep()
            return
        }
        hidePreviewBubble()
        onPasteRequested?(item, startedAt)
    }

    // Right click handler for row actions menu (spec #5, #6). Safe MVP: Paste, Pin/Unpin (reuses existing PinnedSnippetStore safely, no Realm migration), disabled placeholders. No destructive delete.
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
        let menu = NSMenu(title: "Row Actions")
        let pasteItem = NSMenuItem(title: "Paste", action: #selector(performPasteFromMenu(_:)), keyEquivalent: "")
        pasteItem.target = self
        pasteItem.representedObject = row
        menu.addItem(pasteItem)

        if let item = historyItems[safe: row] {
            let pinStore = PinnedSnippetStore.shared
            let isPinnedCurrently = pinStore.isPinned(item.dataHash)
            let pinTitle = isPinnedCurrently ? "Unpin" : "Pin"
            let pinItem = NSMenuItem(title: pinTitle, action: #selector(togglePinFromMenu(_:)), keyEquivalent: "")
            pinItem.target = self
            pinItem.representedObject = item.dataHash
            menu.addItem(pinItem)

            if item.source == .snippet {
                let editSnippetItem = NSMenuItem(title: "Edit Snippet", action: #selector(editSnippetFromMenu(_:)), keyEquivalent: "")
                editSnippetItem.target = self
                editSnippetItem.representedObject = item.dataHash
                menu.addItem(editSnippetItem)

                let deleteSnippetItem = NSMenuItem(title: "Delete Snippet", action: #selector(deleteSnippetFromMenu(_:)), keyEquivalent: "")
                deleteSnippetItem.target = self
                deleteSnippetItem.representedObject = item.dataHash
                menu.addItem(deleteSnippetItem)
            }
        } else {
            let disabledPin = NSMenuItem(title: "Pin / Unpin", action: nil, keyEquivalent: "")
            disabledPin.isEnabled = false
            menu.addItem(disabledPin)
        }

        menu.addItem(NSMenuItem.separator())

        if activeTab == .snippets {
            let addSnippetItem = NSMenuItem(title: "Add Snippet", action: #selector(addSnippetFromPanel(_:)), keyEquivalent: "")
            addSnippetItem.target = self
            menu.addItem(addSnippetItem)
        }

        let copyItem = NSMenuItem(title: "Copy Title", action: nil, keyEquivalent: "")
        copyItem.isEnabled = false  // per spec: if safe otherwise skip; placeholder
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
        if PinnedSnippetStore.shared.isPinned(dataHash) {
            PinnedSnippetStore.shared.remove(dataHash)
        } else if !PinnedSnippetStore.shared.add(dataHash) {
            showProLockedAlert(message: "Free plan includes 3 pinned items. Upgrade or activate Founder Lifetime to pin more.")
        }
        onRefreshRequested?()
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

    override func sendEvent(_ event: NSEvent) {
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
        if modifiers.contains(.command), [3, 18, 19, 20, 43].contains(Int(event.keyCode)) {
            return true
        }
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
            moveTab(delta: -1)
            return true
        case 124:
            moveTab(delta: 1)
            return true
        case 125:
            return selectRowByKeyboard(delta: 1)
        case 126:
            return selectRowByKeyboard(delta: -1)
        case 36, 76:
            guard activeTab != .settings else { return false }
            pasteSelectedRow()
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

    private func moveTab(delta: Int) {
        let tabs = BoardManPanelTab.allCases
        guard let currentIndex = tabs.firstIndex(of: activeTab) else { return }
        let nextIndex = min(tabs.count - 1, max(0, currentIndex + delta))
        guard nextIndex != currentIndex else { return }
        activateTab(tabs[nextIndex])
    }

    @discardableResult
    private func selectRowByKeyboard(delta: Int) -> Bool {
        guard activeTab != .settings,
              let table = placeholderList,
              !historyItems.isEmpty else {
            return false
        }
        let rowCount = historyItems.count
        let tableRow = table.selectedRow
        let previous = tableRow >= 0 && tableRow < rowCount ? tableRow : selectedIndex
        let next: Int
        if previous < 0 || previous >= rowCount {
            next = delta < 0 ? rowCount - 1 : 0
        } else {
            next = max(0, min(rowCount - 1, previous + delta))
        }

        if isSearchFieldEditorActive {
            searchField?.abortEditing()
        }
        makeFirstResponder(table)

        hoveredRow = -1
        keyboardPreviewLockUntil = CFAbsoluteTimeGetCurrent() + 0.35
        selectedIndex = next
        let nextIndexSet = IndexSet(integer: next)
        table.selectRowIndexes(nextIndexSet, byExtendingSelection: false)
        table.scrollRowToVisible(next)

        table.rowView(atRow: next, makeIfNecessary: false)?.needsDisplay = true
        if previous >= 0 && previous < rowCount && previous != next {
            table.rowView(atRow: previous, makeIfNecessary: false)?.needsDisplay = true
        }
        table.needsDisplay = true
        updateSnippetActionButtons()
        showPreviewBubble(for: next)

        return true
    }

    private func refreshSelectionRows(oldIndex: Int, newIndex: Int) {
        guard let table = placeholderList else { return }
        var rows = IndexSet()
        [oldIndex, newIndex].forEach { row in
            guard row >= 0, row < historyItems.count else { return }
            rows.insert(row)
            table.rowView(atRow: row, makeIfNecessary: false)?.needsDisplay = true
        }
        guard !rows.isEmpty else { return }
        table.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integer: 0))
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
        return 0
    }

    private func moveSelection(delta: Int) {
        _ = selectRowByKeyboard(delta: delta)
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
        placeholderList?.rowView(atRow: row, makeIfNecessary: false)?.needsDisplay = true
        placeholderList?.reloadData(forRowIndexes: IndexSet(integer: row),
                                    columnIndexes: IndexSet(integer: 0))
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
            placeholderList?.rowView(atRow: row, makeIfNecessary: false)?.needsDisplay = true
            placeholderList?.reloadData(forRowIndexes: IndexSet(integer: row),
                                        columnIndexes: IndexSet(integer: 0))
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

    fileprivate func usedItemAppearance(for row: Int) -> (background: NSColor, border: NSColor, borderWidth: CGFloat)? {
        guard row >= 0, let item = historyItems[safe: row], item.pasteCount >= 1 else { return nil }
        let style = BoardManPanel.allowedUsedItemStyle(AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManUsedItemStyle))
        let alpha: CGFloat = isThemeLightenEnabled ? 0.09 : (isLiquidGlassEnabled ? 0.16 : 0.20)
        let borderAlpha: CGFloat = isThemeLightenEnabled ? 0.24 : 0.42
        switch style {
        case "Subtle Red":
            return (NSColor.systemRed.withAlphaComponent(alpha), NSColor.systemRed.withAlphaComponent(borderAlpha), 1)
        case "Amber":
            return (NSColor.systemOrange.withAlphaComponent(alpha), NSColor.systemOrange.withAlphaComponent(borderAlpha), 1)
        case "Blue":
            return (NSColor.systemBlue.withAlphaComponent(alpha), NSColor.systemBlue.withAlphaComponent(borderAlpha), 1)
        case "Monochrome":
            return (NSColor.labelColor.withAlphaComponent(isLiquidGlassEnabled ? 0.10 : 0.08), NSColor.separatorColor.withAlphaComponent(0.70), 1)
        default:
            return nil
        }
    }

    private func setSelectedIndex(_ row: Int) {
        guard row >= 0, row < historyItems.count else { return }
        let oldIndex = selectedIndex
        selectedIndex = row
        updateSnippetActionButtons()
        syncNativeSelection()
        refreshSelectionRows(oldIndex: oldIndex, newIndex: row)
        refreshSnippetEditor()
        if CFAbsoluteTimeGetCurrent() >= keyboardPreviewLockUntil {
            showPreviewBubble(for: row)
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
        if let image = previewImage(for: item) {
            showImagePreview(image, in: bubble, imageView: imageView, label: label)
            return
        }
        imageView.isHidden = true
        imageView.image = nil
        label.isHidden = false
        label.stringValue = item.previewTitle
        let maxWidth: CGFloat = 340
        let padding: CGFloat = 12
        let maxLabelSize = NSSize(width: maxWidth - (padding * 2), height: 150)
        let textSize = (item.previewTitle as NSString).boundingRect(
            with: maxLabelSize,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: label.font ?? NSFont.systemFont(ofSize: 12)]
        ).size
        let bubbleWidth = min(maxWidth, max(180, ceil(textSize.width) + (padding * 2)))
        let bubbleHeight = min(174, max(48, ceil(textSize.height) + (padding * 2)))
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
        guard item.source == .clip, !item.imageDataPath.isEmpty,
              let data = NSKeyedUnarchiver.unarchiveObject(withFile: item.imageDataPath) as? CPYClipData else {
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
        let maxImageSize = NSSize(width: min(420, max(260, visibleFrame.width * 0.46)),
                                  height: min(320, max(200, visibleFrame.height * 0.50)))
        let imageSize = image.size
        let scale: CGFloat
        if imageSize.width <= 0 || imageSize.height <= 0 {
            scale = 1
        } else {
            scale = min(maxImageSize.width / imageSize.width, maxImageSize.height / imageSize.height, 1)
        }
        let displayWidth = max(180, min(maxImageSize.width, ceil(imageSize.width * scale)))
        let displayHeight = max(120, min(maxImageSize.height, ceil(imageSize.height * scale)))
        let padding: CGFloat = 14
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
        return globalShortcutRows.contains { $0.recordView === recordView }
            || snippetShortcutRows.contains { $0.recordView === recordView }
    }

    func recordView(_ recordView: RecordView, canRecordKeyCombo keyCombo: KeyCombo) -> Bool {
        guard recordViewShouldBeginRecording(recordView) else { return false }
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

// Basic data source for placeholder list (embedded to avoid extra files)
extension BoardManPanel: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        return max(historyItems.count, 1)
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
        cell.toolTip = nil
        cell.configure(item: item,
                       isSelected: selectedIndex == row,
                       usageStyle: BoardManPanel.allowedUsageCountStyle(AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManUsageCountStyle)),
                       useLiquidGlass: isLiquidGlassEnabled,
                       lightenTheme: isThemeLightenEnabled,
                       themePreset: themePreset)
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 58
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let oldIndex = selectedIndex
        if let row = placeholderList?.selectedRow, row >= 0, row < historyItems.count {
            selectedIndex = row
            refreshSelectionRows(oldIndex: oldIndex, newIndex: row)
            showPreviewBubble(for: row)
            refreshSnippetEditor()
        }
        updateSnippetActionButtons()
        synchronizeListGeometry()
    }
}
