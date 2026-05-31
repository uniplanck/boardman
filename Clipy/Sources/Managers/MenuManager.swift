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
        let usePanel = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.boardManUsePanelUI)
        if usePanel && type == .main {
            showBoardManPanel()
            return
        }
        let menu: NSMenu?
        switch type {
        case .main:
            menu = clipMenu
        case .history:
            menu = historyMenu
        case .snippet:
            menu = snippetMenu
        }
        menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    func popUpSnippetFolder(_ folder: CPYFolder) {
        let folderMenu = NSMenu(title: folder.title)
        // Folder title
        let labelItem = NSMenuItem(title: folder.title, action: nil)
        labelItem.isEnabled = false
        folderMenu.addItem(labelItem)
        // Snippets
        var index = firstIndexOfMenuItems()
        folder.snippets
            .sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true)
            .filter { $0.enable }
            .forEach { snippet in
                let subMenuItem = makeSnippetMenuItem(snippet, listNumber: index)
                folderMenu.addItem(subMenuItem)
                index += 1
            }
        folderMenu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
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
            let anchor = anchorPoint ?? NSEvent.mouseLocation
            var originX = anchor.x - (panelSize.width / 2)
            var originY = anchor.y - (panelSize.height / 2)
            if let screen = NSScreen.main {
                let visibleFrame = screen.visibleFrame
                originX = max(visibleFrame.minX + 20, min(originX, visibleFrame.maxX - panelSize.width - 20))
                originY = max(visibleFrame.minY + 20, min(originY, visibleFrame.maxY - panelSize.height - 40))
            }
            panel.setFrame(NSRect(x: originX, y: originY, width: panelSize.width, height: panelSize.height),
                           display: false,
                           animate: false)
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            panel.focusTableForKeyboard()
            PasteCountInputService.shared.logBoardManPerformance("panel_visible_fast", startedAt: startedAt, details: "items=\(panel.itemCount)")

            DispatchQueue.main.async { [weak self, weak panel] in
                guard let self, let panel else { return }
                panel.reloadHistoryItems(self.boardManPanelItems())
                panel.focusTableForKeyboard()
            }
        }
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

            let pasteCountKey = PasteCountStore.shared.key(for: clip)
            let isInputLikeTarget = PasteCountInputService.shared.isFocusedTargetInputLike()
            let didPaste = AppEnvironment.current.pasteService.paste(with: clip)

            if didPaste {
                PasteCountStore.shared.markUsed(clip: clip, in: realm)
                if isInputLikeTarget {
                    PasteCountInputService.shared.suppressNextGlobalPaste()
                    PasteCountStore.shared.increment(forKey: pasteCountKey)
                }
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

            AppEnvironment.current.pasteService.copyToPasteboard(with: snippet.content)
            AppEnvironment.current.pasteService.paste()
            self.previousFrontmostApplication = nil
        }
    }

    fileprivate func boardManPanelItems() -> [BoardManHistoryItem] {
        return boardManHistoryItems() + boardManSnippetItems()
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
        let panelHistoryLimit = min(maxHistory, 120)  // V4B-13: keep panel launch fast; full history remains in Realm/legacy menu.
        let items = Array(clipResults.prefix(panelHistoryLimit)).enumerated().map { index, clip in
            let rawTitle = clip.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = rawTitle.isEmpty ? "(empty clipboard item)" : rawTitle
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
            let countText = showUsageCount ? "\(pasteCount)" : ""
            let displayTitle = (parts + [clipped]).joined(separator: " ")
            return BoardManHistoryItem(title: displayTitle,
                                       primaryTitle: clipped,
                                       metadataText: parts.joined(separator: "   "),
                                       countText: countText,
                                       previewTitle: title,
                                       dataHash: clip.dataHash,
                                       pasteCount: pasteCount,
                                       isPinned: isPinned,
                                       source: .clip)
        }
        let sortedItems = items.filter { $0.isPinned } + items.filter { !$0.isPinned }
        let pinnedCount = sortedItems.filter { $0.isPinned }.count
        PasteCountInputService.shared.logBoardManPerformance("history_reload", startedAt: startedAt, details: "items=\(sortedItems.count) pinned=\(pinnedCount)")
        return sortedItems
    }

    fileprivate func boardManSnippetItems() -> [BoardManHistoryItem] {
        let pinStore = PinnedSnippetStore.shared
        let folderResults = realm.objects(CPYFolder.self).sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)
        return folderResults
            .filter { $0.enable }
            .flatMap { folder -> [BoardManHistoryItem] in
                folder.snippets
                    .sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true)
                    .filter { $0.enable }
                    .map { snippet in
                        let rawTitle = snippet.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let title = rawTitle.isEmpty ? "(untitled snippet)" : rawTitle
                        let folderTitle = folder.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let prefix = folderTitle.isEmpty ? "Snippet" : folderTitle
                        let isPinned = pinStore.isPinned(snippet.identifier)
                        let pin = isPinned ? "[PIN] " : ""
                        return BoardManHistoryItem(title: "\(pin)\(prefix) / \(title)",
                                                   primaryTitle: title,
                                                   metadataText: "\(pin)\(prefix)",
                                                   countText: "",
                                                   previewTitle: snippet.content,
                                                   dataHash: snippet.identifier,
                                                   pasteCount: 0,
                                                   isPinned: isPinned,
                                                   source: .snippet)
                    }
            }
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
                self?.changeStatusItem(StatusType(rawValue: key) ?? .black)
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
        // V4B-14: Panel UI mode does not need legacy history/snippet menu rebuilds.
        // Keeping the status menu lightweight avoids slow rebuilds after Realm/paste-count changes.
        let menu = NSMenu(title: Constants.Application.name)
        menu.addItem(NSMenuItem(title: String(localized: "Open Board-Man Settings"), action: #selector(AppDelegate.showPreferenceWindow)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Quit Board-Man"), action: #selector(AppDelegate.terminate)))

        clipMenu = menu
        historyMenu = NSMenu(title: Constants.Menu.history)
        snippetMenu = NSMenu(title: Constants.Menu.snippet)
        statusItem?.menu = nil
    }

     func createClipMenu() {
        if AppEnvironment.current.defaults.bool(forKey: "BoardManUsePanelUI") {
            createBoardManLiteMenu()
            return
        }

        clipMenu = NSMenu(title: Constants.Application.name)
        historyMenu = NSMenu(title: Constants.Menu.history)
        snippetMenu = NSMenu(title: Constants.Menu.snippet)

        addPinnedSnippetItems(clipMenu!)
        addPinnedSnippetItems(snippetMenu!)
        addHistoryItems(clipMenu!)
        addHistoryItems(historyMenu!)

        addSnippetItems(clipMenu!, separateMenu: true)
        addSnippetItems(snippetMenu!, separateMenu: false)

        clipMenu?.addItem(NSMenuItem.separator())

        if AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.addClearHistoryMenuItem) {
            clipMenu?.addItem(NSMenuItem(title: String(localized: "Clear History"), action: #selector(AppDelegate.clearAllHistory)))
        }

        clipMenu?.addItem(NSMenuItem(title: String(localized: "Edit Snippets"), action: #selector(AppDelegate.showSnippetEditorWindow)))
        clipMenu?.addItem(NSMenuItem(title: String(localized: "Open Board-Man Settings"), action: #selector(AppDelegate.showPreferenceWindow)))
        clipMenu?.addItem(NSMenuItem.separator())
        clipMenu?.addItem(NSMenuItem(title: String(localized: "Quit Board-Man"), action: #selector(AppDelegate.terminate)))

        statusItem?.menu = clipMenu
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
        removeStatusItem()
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

        statusItem = NSStatusBar.system.statusItem(withLength: -1)
        statusItem?.image = image
        statusItem?.highlightMode = true
        statusItem?.toolTip = "\(Constants.Application.name)\(Bundle.main.appVersion ?? "")"
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(statusItemClicked(_:))
        statusItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem?.menu = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.boardManUsePanelUI) ? nil : clipMenu
    }

    @objc func statusItemClicked(_ sender: Any?) {
        guard AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.boardManUsePanelUI) else { return }
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            guard let button = statusItem?.button else { return }
            clipMenu?.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
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
            add(identifier)
        }
    }

    func add(_ identifier: String) {
        var values = identifiers.filter { !$0.isEmpty }
        guard !values.contains(identifier) else { return }
        values.append(identifier)
        save(values)
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
        case .snippets: return "No snippets yet - use Add/Edit to open the snippet editor"
        case .settings: return ""
        }
    }
}

fileprivate enum BoardManInlineSettingsCategory: Int {
    case view, behavior, history, privacy
}

fileprivate enum BoardManPanelItemSource {
    case clip
    case snippet
    case favorite
}

fileprivate struct BoardManHistoryItem {
    let title: String
    let primaryTitle: String
    let metadataText: String
    let countText: String
    let previewTitle: String
    let dataHash: String
    let pasteCount: Int
    let isPinned: Bool
    let source: BoardManPanelItemSource
}

private final class BoardManHistoryTableView: NSTableView {
    override var acceptsFirstResponder: Bool {
        return true
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
        let rowRect = bounds.insetBy(dx: 6, dy: 4)
        let useLiquidGlass = previewOwner?.isLiquidGlassEnabled == true
        let path = NSBezierPath(roundedRect: rowRect, xRadius: useLiquidGlass ? 11 : 8, yRadius: useLiquidGlass ? 11 : 8)
        if previewOwner?.isSelectedRow(row) == true {
            (useLiquidGlass
                ? NSColor.controlAccentColor.withAlphaComponent(0.30)
                : NSColor.selectedContentBackgroundColor.withAlphaComponent(0.82)).setFill()
            path.fill()
        } else if previewOwner?.isHoveredRow(row) == true {
            NSColor.controlAccentColor.withAlphaComponent(useLiquidGlass ? 0.14 : 0.16).setFill()
            path.fill()
        } else if let appearance = previewOwner?.usedItemAppearance(for: row) {
            appearance.background.setFill()
            path.fill()
            appearance.border.setStroke()
            path.lineWidth = appearance.borderWidth
            path.stroke()
        } else if row >= 0 {
            (useLiquidGlass
                ? NSColor.textBackgroundColor.withAlphaComponent(0.12)
                : NSColor.textBackgroundColor.withAlphaComponent(0.36)).setFill()
            path.fill()
            if useLiquidGlass {
                NSColor.white.withAlphaComponent(0.12).setStroke()
                path.lineWidth = 1
                path.stroke()
            }
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
        primaryLabel.font = NSFont.systemFont(ofSize: 13.5, weight: .semibold)

        metadataLabel.lineBreakMode = .byTruncatingTail
        metadataLabel.maximumNumberOfLines = 1
        metadataLabel.backgroundColor = .clear
        metadataLabel.drawsBackground = false
        metadataLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)

        countBadge.alignment = .center
        countBadge.lineBreakMode = .byTruncatingTail
        countBadge.maximumNumberOfLines = 1
        countBadge.isBordered = false
        countBadge.isEditable = false
        countBadge.wantsLayer = true
        countBadge.layer?.cornerRadius = 9
        countBadge.layer?.masksToBounds = true
        countBadge.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)

        addSubview(primaryLabel)
        addSubview(metadataLabel)
        addSubview(countBadge)
    }

    func configure(item: BoardManHistoryItem,
                   isSelected: Bool,
                   usageStyle: String,
                   useLiquidGlass: Bool) {
        primaryLabel.stringValue = item.primaryTitle
        metadataLabel.stringValue = item.metadataText
        let badgePrefix = usageStyle == "compact" ? "used " : "x"
        countBadge.stringValue = item.countText.isEmpty ? "" : "\(badgePrefix)\(item.countText)"
        countBadge.isHidden = item.countText.isEmpty

        if isSelected {
            primaryLabel.textColor = .selectedMenuItemTextColor
            metadataLabel.textColor = NSColor.selectedMenuItemTextColor.withAlphaComponent(0.86)
            countBadge.textColor = .selectedMenuItemTextColor
            countBadge.layer?.backgroundColor = NSColor.selectedMenuItemTextColor.withAlphaComponent(useLiquidGlass ? 0.20 : 0.18).cgColor
        } else {
            primaryLabel.textColor = .labelColor
            metadataLabel.textColor = useLiquidGlass ? NSColor.secondaryLabelColor.withAlphaComponent(0.92) : .secondaryLabelColor
            countBadge.textColor = .labelColor
            countBadge.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(useLiquidGlass ? 0.18 : 0.18).cgColor
        }
        countBadge.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(useLiquidGlass ? 0.30 : 0).cgColor
        countBadge.layer?.borderWidth = useLiquidGlass ? 1 : 0
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let insetX: CGFloat = 18
        let topPadding: CGFloat = 8
        let badgeWidth: CGFloat = countBadge.isHidden ? 0 : min(72, max(34, countBadge.intrinsicContentSize.width + 16))
        let badgeX = bounds.width - insetX - badgeWidth
        let textWidth = max(80, bounds.width - (insetX * 2) - badgeWidth - (badgeWidth > 0 ? 10 : 0))
        primaryLabel.frame = NSRect(x: insetX, y: bounds.height - topPadding - 18, width: textWidth, height: 18)
        metadataLabel.frame = NSRect(x: insetX, y: 8, width: textWidth, height: 15)
        if !countBadge.isHidden {
            countBadge.frame = NSRect(x: badgeX, y: (bounds.height - 20) / 2, width: badgeWidth, height: 20)
        }
    }
}

// MARK: - BoardManPanel MVP Shell (embedded in MenuManager.swift per constraints)
class BoardManPanel: NSPanel {

    private var glassBackgroundView: NSVisualEffectView?
    private var searchGlassView: NSVisualEffectView?
    private var tabsGlassView: NSVisualEffectView?
    private var settingsGlassView: NSVisualEffectView?
    private var listGlassView: NSVisualEffectView?
    private var searchField: NSSearchField?
    private var segmentedControl: NSSegmentedControl?
    private var settingsBackgroundView: NSView?
    private var settingsCategoryControl: NSSegmentedControl?
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
    private var densityLabel: NSTextField?
    private var densityPopup: NSPopUpButton?
    private var clickActionLabel: NSTextField?
    private var clickActionPopup: NSPopUpButton?
    private var enterActionLabel: NSTextField?
    private var enterActionPopup: NSPopUpButton?
    private var autoCloseButton: NSButton?
    private var dedupeButton: NSButton?
    private var reuseTopButton: NSButton?
    private var clearHistoryButton: NSButton?
    private var pauseRecordingButton: NSButton?
    private var excludedAppsButton: NSButton?
    private var viewSectionLabel: NSTextField?
    private var behaviorSectionLabel: NSTextField?
    private var historySectionLabel: NSTextField?
    private var privacySectionLabel: NSTextField?
    private var labsSectionLabel: NSTextField?
    private var labsNoteLabel: NSTextField?
    private var heightControlLabel: NSTextField?
    private var heightStepper: NSStepper?
    private var heightLabel: NSTextField?
    private var footerNote: NSTextField?
    private var snippetEditorButton: NSButton?
    private var previewBubblePanel: NSPanel?
    private var previewBubbleLabel: NSTextField?
    private var allItems: [BoardManHistoryItem] = []
    private var historyItems: [BoardManHistoryItem] = []
    private var selectedIndex: Int = -1
    private var hoveredRow: Int = -1
    private var activeTab: BoardManPanelTab = .history
    private var activeSettingsCategory: BoardManInlineSettingsCategory = .view
    fileprivate var onPasteRequested: ((BoardManHistoryItem, CFAbsoluteTime?) -> Void)?
    var onRefreshRequested: (() -> Void)?
    var itemCount: Int {
        return historyItems.count
    }
    fileprivate var isLiquidGlassEnabled: Bool {
        return AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.boardManLiquidGlass)
    }

    static func preferredPanelHeight() -> CGFloat {
        return CGFloat(clampedPanelHeight(AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.boardManPanelHeight)))
    }

    static func preferredPanelWidth() -> CGFloat {
        return 560
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
        self.minSize = NSSize(width: 460, height: 520)
        self.title = "Board-Man"
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.isFloatingPanel = true
        self.level = .popUpMenu
        self.backgroundColor = NSColor.windowBackgroundColor
        self.hasShadow = true
        setupModernContainer()
        setupUI()
        setupPreviewBubble()
        applyLiquidGlassStyle()
    }

    private func setupModernContainer() {
        if let contentView = contentView {
            contentView.wantsLayer = true
            if #available(macOS 10.15, *) {
                contentView.layer?.cornerRadius = 12  // softer, less aggressive look
                contentView.layer?.masksToBounds = true
            }
            contentView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }

    private func makeGlassSurface(blendingMode: NSVisualEffectView.BlendingMode) -> NSVisualEffectView {
        let glass = NSVisualEffectView(frame: .zero)
        glass.autoresizingMask = []
        glass.blendingMode = blendingMode
        glass.material = .hudWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 12
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 1
        return glass
    }

    private func setupGlassBackgroundIfNeeded() {
        guard glassBackgroundView == nil, let contentView = contentView else { return }
        let glass = NSVisualEffectView(frame: contentView.bounds)
        glass.autoresizingMask = [.width, .height]
        glass.blendingMode = .behindWindow
        glass.material = .hudWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.10).cgColor
        glass.isHidden = true
        contentView.addSubview(glass, positioned: .below, relativeTo: nil)
        glassBackgroundView = glass
    }

    private func setupUI() {
        guard let contentView = contentView else { return }
        setupGlassBackgroundIfNeeded()

        let searchGlass = makeGlassSurface(blendingMode: .withinWindow)
        searchGlass.isHidden = true
        contentView.addSubview(searchGlass)
        searchGlassView = searchGlass

        // Search field at top - clean margins
        let search = NSSearchField(frame: .zero)
        search.placeholderString = "Search history and snippets"
        search.target = self
        search.action = #selector(searchTextChanged(_:))
        search.sendsSearchStringImmediately = true
        search.focusRingType = .none
        contentView.addSubview(search)
        searchField = search

        let tabsGlass = makeGlassSurface(blendingMode: .withinWindow)
        tabsGlass.isHidden = true
        contentView.addSubview(tabsGlass)
        tabsGlassView = tabsGlass

        // Tabs: rounded style avoids harsh black blocks; History tab default and visible
        let tabs = NSSegmentedControl(frame: .zero)
        tabs.segmentCount = 3
        tabs.setLabel("History", forSegment: 0)
        tabs.setLabel("Snippets", forSegment: 1)
        tabs.setLabel("Set", forSegment: 2)
        tabs.selectedSegment = 0
        tabs.target = self
        tabs.action = #selector(tabChanged(_:))
        if #available(macOS 10.10, *) {
            tabs.segmentStyle = .rounded
        }
        contentView.addSubview(tabs)
        segmentedControl = tabs

        let settingsGlass = makeGlassSurface(blendingMode: .withinWindow)
        settingsGlass.isHidden = true
        contentView.addSubview(settingsGlass)
        settingsGlassView = settingsGlass

        let settingsBackground = NSView(frame: .zero)
        settingsBackground.wantsLayer = true
        settingsBackground.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        settingsBackground.layer?.cornerRadius = 6
        contentView.addSubview(settingsBackground)
        settingsBackgroundView = settingsBackground

        let categoryControl = NSSegmentedControl(frame: .zero)
        categoryControl.segmentCount = 4
        categoryControl.setLabel("View", forSegment: 0)
        categoryControl.setLabel("Behavior", forSegment: 1)
        categoryControl.setLabel("History", forSegment: 2)
        categoryControl.setLabel("Privacy", forSegment: 3)
        categoryControl.selectedSegment = 0
        categoryControl.target = self
        categoryControl.action = #selector(settingsCategoryChanged(_:))
        if #available(macOS 10.10, *) {
            categoryControl.segmentStyle = .rounded
        }
        contentView.addSubview(categoryControl)
        settingsCategoryControl = categoryControl

        let viewTitle = BoardManPanel.makeSectionLabel("View")
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

        let densityText = NSTextField(labelWithString: "Density")
        densityText.font = NSFont.systemFont(ofSize: 11)
        densityText.textColor = .labelColor
        contentView.addSubview(densityText)
        densityLabel = densityText

        let densityPopupControl = NSPopUpButton(frame: .zero, pullsDown: false)
        densityPopupControl.addItems(withTitles: ["Comfortable", "Compact"])
        densityPopupControl.selectItem(withTitle: "Comfortable")
        densityPopupControl.font = NSFont.systemFont(ofSize: 11)
        densityPopupControl.isEnabled = false
        densityPopupControl.toolTip = "Planned: row density is kept comfortable for paste safety."
        contentView.addSubview(densityPopupControl)
        densityPopup = densityPopupControl

        let behaviorTitle = BoardManPanel.makeSectionLabel("Behavior")
        contentView.addSubview(behaviorTitle)
        behaviorSectionLabel = behaviorTitle

        let clickText = NSTextField(labelWithString: "Click")
        clickText.font = NSFont.systemFont(ofSize: 11)
        clickText.textColor = .labelColor
        contentView.addSubview(clickText)
        clickActionLabel = clickText

        let clickPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        clickPopup.addItems(withTitles: ["Paste", "Copy only"])
        clickPopup.selectItem(withTitle: "Paste")
        clickPopup.font = NSFont.systemFont(ofSize: 11)
        clickPopup.isEnabled = false
        clickPopup.toolTip = "Planned: click behavior is kept as paste for safety."
        contentView.addSubview(clickPopup)
        clickActionPopup = clickPopup

        let enterText = NSTextField(labelWithString: "Enter")
        enterText.font = NSFont.systemFont(ofSize: 11)
        enterText.textColor = .labelColor
        contentView.addSubview(enterText)
        enterActionLabel = enterText

        let enterPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        enterPopup.addItems(withTitles: ["Paste", "Copy only"])
        enterPopup.selectItem(withTitle: "Paste")
        enterPopup.font = NSFont.systemFont(ofSize: 11)
        enterPopup.isEnabled = false
        enterPopup.toolTip = "Planned: Enter behavior is kept as paste for safety."
        contentView.addSubview(enterPopup)
        enterActionPopup = enterPopup

        let autoClose = NSButton(checkboxWithTitle: "Auto close", target: nil, action: nil)
        autoClose.state = .on
        autoClose.font = NSFont.systemFont(ofSize: 11)
        autoClose.isEnabled = false
        autoClose.toolTip = "Current paste behavior closes the panel."
        if #available(macOS 10.14, *) {
            autoClose.contentTintColor = .labelColor
        }
        contentView.addSubview(autoClose)
        autoCloseButton = autoClose

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

        let pause = NSButton(checkboxWithTitle: "Pause", target: nil, action: nil)
        pause.state = .off
        pause.font = NSFont.systemFont(ofSize: 11)
        pause.isEnabled = false
        pause.toolTip = "Planned: recording pause needs backend support."
        if #available(macOS 10.14, *) {
            pause.contentTintColor = .labelColor
        }
        contentView.addSubview(pause)
        pauseRecordingButton = pause

        let exclude = NSButton(title: "Exclude", target: self, action: #selector(openExcludedAppsSettings(_:)))
        exclude.font = NSFont.systemFont(ofSize: 11)
        exclude.bezelStyle = .rounded
        contentView.addSubview(exclude)
        excludedAppsButton = exclude

        let labsTitle = BoardManPanel.makeSectionLabel("Labs")
        contentView.addSubview(labsTitle)
        labsSectionLabel = labsTitle

        let labsNote = NSTextField(labelWithString: "Glass options stay in Preferences.")
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

        // Scroll list: stable margins and taller rows for readability; paste behavior stays on click/Enter.
        let listGlass = makeGlassSurface(blendingMode: .withinWindow)
        listGlass.isHidden = true
        contentView.addSubview(listGlass)
        listGlassView = listGlass

        let scroll = NSScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.wantsLayer = true
        scroll.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        scroll.layer?.cornerRadius = 8
        scroll.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        scroll.layer?.borderWidth = 1

        let table = BoardManHistoryTableView(frame: .zero)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: "main"))
        column.title = "Items"
        column.width = 360
        table.addTableColumn(column)
        table.headerView = nil  // no oversized header
        table.rowHeight = 50
        table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = .clear
        table.allowsEmptySelection = false
        table.allowsMultipleSelection = false
        table.refusesFirstResponder = false
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

        let note = NSTextField(labelWithString: "Click or press Enter to paste - right-click to pin")
        note.alignment = .center
        note.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.95)
        note.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        note.backgroundColor = .clear
        note.drawsBackground = false
        contentView.addSubview(note)
        footerNote = note

        let snippetsButton = NSButton(title: "Add/Edit", target: self, action: #selector(openSnippetEditor(_:)))
        snippetsButton.font = NSFont.systemFont(ofSize: 11)
        snippetsButton.bezelStyle = .rounded
        snippetsButton.isHidden = true
        snippetsButton.toolTip = "Open the existing snippet editor."
        contentView.addSubview(snippetsButton)
        snippetEditorButton = snippetsButton

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

        // Load initial data
        layoutPanelSubviews()
        table.reloadData()
    }

    private func applyLiquidGlassStyle() {
        let useGlass = isLiquidGlassEnabled
        backgroundColor = useGlass ? .clear : .windowBackgroundColor
        isOpaque = !useGlass
        glassBackgroundView?.isHidden = !useGlass
        glassBackgroundView?.material = .hudWindow
        glassBackgroundView?.layer?.backgroundColor = NSColor.black.withAlphaComponent(useGlass ? 0.10 : 0).cgColor
        contentView?.layer?.backgroundColor = (useGlass
            ? NSColor.clear
            : NSColor.controlBackgroundColor).cgColor
        contentView?.layer?.isOpaque = !useGlass
        [searchGlassView, tabsGlassView, settingsGlassView, listGlassView].forEach { glass in
            glass?.isHidden = !useGlass
            glass?.material = .hudWindow
            glass?.state = .active
            glass?.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.10).cgColor
            glass?.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
            glass?.layer?.borderWidth = useGlass ? 1 : 0
        }
        searchField?.wantsLayer = true
        searchField?.layer?.cornerRadius = useGlass ? 10 : 6
        searchField?.layer?.backgroundColor = (useGlass
            ? NSColor.clear
            : NSColor.clear).cgColor
        segmentedControl?.wantsLayer = true
        segmentedControl?.layer?.cornerRadius = useGlass ? 10 : 6
        segmentedControl?.layer?.backgroundColor = (useGlass
            ? NSColor.clear
            : NSColor.clear).cgColor
        settingsBackgroundView?.layer?.backgroundColor = (useGlass
            ? NSColor.textBackgroundColor.withAlphaComponent(0.08)
            : NSColor.controlBackgroundColor).cgColor
        settingsBackgroundView?.layer?.cornerRadius = useGlass ? 12 : 6
        settingsBackgroundView?.layer?.borderColor = (useGlass ? NSColor.white : NSColor.separatorColor).withAlphaComponent(useGlass ? 0.18 : 0).cgColor
        settingsBackgroundView?.layer?.borderWidth = useGlass ? 1 : 0
        scrollView?.layer?.backgroundColor = (useGlass
            ? NSColor.clear
            : NSColor.controlBackgroundColor).cgColor
        scrollView?.layer?.cornerRadius = useGlass ? 11 : 8
        scrollView?.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(useGlass ? 0.18 : 0.55).cgColor
        scrollView?.drawsBackground = !useGlass
        placeholderList?.backgroundColor = .clear
        footerNote?.textColor = NSColor.secondaryLabelColor.withAlphaComponent(useGlass ? 0.98 : 0.95)
        previewBubblePanel?.contentView?.layer?.cornerRadius = useGlass ? 11 : 8
        placeholderList?.reloadData()
    }

    private func setupPreviewBubble() {
        guard let label = previewBubbleLabel else { return }
        let bubble = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 120),
                             styleMask: [.borderless],
                             backing: .buffered,
                             defer: false)
        bubble.isReleasedWhenClosed = false
        bubble.hidesOnDeactivate = false
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
        bubble.contentView?.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.42).cgColor
        bubble.contentView?.layer?.borderWidth = 1
        bubble.contentView?.layer?.cornerRadius = 8
        bubble.contentView?.addSubview(label)
        previewBubblePanel = bubble
    }

    private func layoutPanelSubviews() {
        guard let contentView = contentView else { return }
        let bounds = contentView.bounds
        let margin: CGFloat = 18
        let width = bounds.width - (margin * 2)
        let top = bounds.height - 52
        let isSettings = activeTab == .settings
        searchGlassView?.isHidden = isSettings || !isLiquidGlassEnabled
        searchField?.isHidden = isSettings
        let showsSnippetEditorButton = activeTab == .snippets && !isSettings
        let snippetButtonWidth: CGFloat = showsSnippetEditorButton ? 82 : 0
        let searchWidth = width - snippetButtonWidth - (showsSnippetEditorButton ? 10 : 0)
        searchGlassView?.frame = NSRect(x: margin, y: top, width: searchWidth, height: 32)
        searchField?.frame = NSRect(x: margin, y: top, width: searchWidth, height: 32)
        snippetEditorButton?.isHidden = !showsSnippetEditorButton
        snippetEditorButton?.frame = NSRect(x: margin + searchWidth + 10, y: top + 3, width: snippetButtonWidth, height: 26)
        tabsGlassView?.frame = NSRect(x: margin, y: top - 42, width: width, height: 30)
        segmentedControl?.frame = NSRect(x: margin, y: top - 42, width: width, height: 30)
        updateTabWidths(totalWidth: width)

        settingsCategoryControl?.isHidden = true
        let contentTop = top - 56
        settingsGlassView?.isHidden = !isSettings || !isLiquidGlassEnabled
        settingsBackgroundView?.isHidden = !isSettings
        settingsGlassView?.frame = NSRect(x: margin, y: 30, width: width, height: max(220, contentTop - 30))
        settingsBackgroundView?.frame = NSRect(x: margin, y: 30, width: width, height: max(220, contentTop - 30))
        layoutInlineSettingsControls(margin: margin, width: width, topY: contentTop, isVisible: isSettings)
        footerNote?.frame = NSRect(x: margin, y: 8, width: width, height: 16)
        footerNote?.isHidden = isSettings
        listGlassView?.isHidden = isSettings || !isLiquidGlassEnabled
        scrollView?.isHidden = isSettings
        listGlassView?.frame = NSRect(x: margin, y: 30, width: width, height: max(220, contentTop - 30))
        scrollView?.frame = NSRect(x: margin, y: 30, width: width, height: max(220, contentTop - 30))
        placeholderList?.frame = NSRect(x: 0, y: 0, width: width, height: max(220, contentTop - 30))
        placeholderList?.tableColumns.first?.width = width
        hidePreviewBubble()
    }

    private func updateTabWidths(totalWidth: CGFloat) {
        guard let segmentedControl else { return }
        let settingsWidth: CGFloat = 54
        let minimumReadableWidth: CGFloat = 74
        let contentWidth = max(minimumReadableWidth, floor((totalWidth - settingsWidth) / 2))
        for segment in 0...1 {
            segmentedControl.setWidth(contentWidth, forSegment: segment)
        }
        segmentedControl.setWidth(settingsWidth, forSegment: 2)
    }

    private func layoutInlineSettingsControls(margin: CGFloat, width: CGFloat, topY: CGFloat, isVisible: Bool) {
        let allControls: [NSView?] = [
            viewSectionLabel, rowNumbersButton, timestampLabel, timestampPopup, usageCountButton, usageStyleLabel, usageStylePopup, usedItemStyleLabel, usedItemStylePopup, densityLabel, densityPopup,
            behaviorSectionLabel, clickActionLabel, clickActionPopup, enterActionLabel, enterActionPopup, autoCloseButton,
            historySectionLabel, dedupeButton, reuseTopButton, clearHistoryButton,
            privacySectionLabel, pauseRecordingButton, excludedAppsButton,
            labsSectionLabel, labsNoteLabel,
            heightControlLabel, heightLabel, heightStepper
        ]
        allControls.forEach { $0?.isHidden = !isVisible }
        guard isVisible else { return }

        let rowH: CGFloat = 24
        let sectionGap: CGFloat = 22
        let rowGap: CGFloat = 32
        let fieldLabelWidth: CGFloat = 58
        let contentX = margin + 18
        let contentWidth = max(240, width - 36)
        let useTwoColumns = width >= 620
        let columnGap: CGFloat = 26
        let columnWidth = useTwoColumns ? floor((contentWidth - columnGap) / 2) : contentWidth
        let leftX = contentX
        let rightX = contentX + columnWidth + columnGap
        let firstY = topY - 34

        [densityLabel, clickActionLabel, enterActionLabel].forEach {
            $0?.textColor = .secondaryLabelColor
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

        func placeViewSection(originX: CGFloat, originY: CGFloat, width: CGFloat) {
            placeHeader(viewSectionLabel, originX: originX, originY: originY, width: width)
            rowNumbersButton?.frame = NSRect(x: originX, y: originY - rowGap, width: 86, height: 18)
            placeLabeledRow(label: timestampLabel, control: timestampPopup, originX: originX, originY: originY - (rowGap * 2) - 4, width: width)
            usageCountButton?.frame = NSRect(x: originX, y: originY - (rowGap * 3) - 2, width: 82, height: 18)
            placeLabeledRow(label: usageStyleLabel, control: usageStylePopup, originX: originX + 104, originY: originY - (rowGap * 3) - 6, width: max(150, width - 104), labelWidth: 38)
            placeLabeledRow(label: usedItemStyleLabel, control: usedItemStylePopup, originX: originX, originY: originY - (rowGap * 4) - 8, width: width)
            placeLabeledRow(label: densityLabel, control: densityPopup, originX: originX, originY: originY - (rowGap * 5) - 10, width: width)
            heightControlLabel?.frame = NSRect(x: originX, y: originY - (rowGap * 6) - 5, width: fieldLabelWidth, height: 14)
            heightStepper?.frame = NSRect(x: originX + fieldLabelWidth + 12, y: originY - (rowGap * 6) - 10, width: 72, height: rowH)
            heightLabel?.frame = NSRect(x: originX + fieldLabelWidth + 92, y: originY - (rowGap * 6) - 5, width: 42, height: 14)
        }

        func placeHistorySection(originX: CGFloat, originY: CGFloat, width: CGFloat) {
            placeHeader(historySectionLabel, originX: originX, originY: originY, width: width)
            dedupeButton?.frame = NSRect(x: originX, y: originY - rowGap, width: 92, height: 18)
            reuseTopButton?.frame = NSRect(x: originX + 106, y: originY - rowGap, width: 118, height: 18)
            clearHistoryButton?.frame = NSRect(x: originX, y: originY - (rowGap * 2) - 6, width: 86, height: rowH)
        }

        func placeBehaviorSection(originX: CGFloat, originY: CGFloat, width: CGFloat) {
            placeHeader(behaviorSectionLabel, originX: originX, originY: originY, width: width)
            placeLabeledRow(label: clickActionLabel, control: clickActionPopup, originX: originX, originY: originY - rowGap - 6, width: width)
            placeLabeledRow(label: enterActionLabel, control: enterActionPopup, originX: originX, originY: originY - (rowGap * 2) - 8, width: width)
            autoCloseButton?.frame = NSRect(x: originX, y: originY - (rowGap * 3) - 4, width: 120, height: 18)
        }

        func placePrivacySection(originX: CGFloat, originY: CGFloat, width: CGFloat) {
            placeHeader(privacySectionLabel, originX: originX, originY: originY, width: width)
            pauseRecordingButton?.frame = NSRect(x: originX, y: originY - rowGap, width: 92, height: 18)
            excludedAppsButton?.frame = NSRect(x: originX, y: originY - (rowGap * 2) - 6, width: 92, height: rowH)
        }

        func placeLabsSection(originX: CGFloat, originY: CGFloat, width: CGFloat) {
            placeHeader(labsSectionLabel, originX: originX, originY: originY, width: width)
            labsNoteLabel?.frame = NSRect(x: originX, y: originY - 30, width: width, height: 18)
        }

        if useTwoColumns {
            placeViewSection(originX: leftX, originY: firstY, width: columnWidth)
            placeHistorySection(originX: leftX, originY: firstY - 232, width: columnWidth)
            placeLabsSection(originX: leftX, originY: firstY - 346, width: columnWidth)
            placeBehaviorSection(originX: rightX, originY: firstY, width: columnWidth)
            placePrivacySection(originX: rightX, originY: firstY - 146, width: columnWidth)
        } else {
            var sectionY = firstY
            placeViewSection(originX: leftX, originY: sectionY, width: columnWidth)
            sectionY -= 216 + sectionGap
            placeHistorySection(originX: leftX, originY: sectionY, width: columnWidth)
            sectionY -= 64 + sectionGap
            placeBehaviorSection(originX: leftX, originY: sectionY, width: columnWidth)
            sectionY -= 100 + sectionGap
            placePrivacySection(originX: leftX, originY: sectionY, width: columnWidth)
            sectionY -= 72 + sectionGap
            placeLabsSection(originX: leftX, originY: sectionY, width: columnWidth)
        }
    }

    fileprivate func reloadHistoryItems(_ items: [BoardManHistoryItem]) {
        allItems = items
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
    }

    @objc private func openSnippetEditor(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.showSnippetEditorWindow()
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
        activeTab = BoardManPanelTab(rawValue: sender.selectedSegment) ?? .history
        selectedIndex = -1
        hoveredRow = -1
        hidePreviewBubble()
        applyCurrentFilter()
        if activeTab == .settings {
            makeFirstResponder(self)
        } else {
            focusTableForKeyboard()
        }
    }

    @objc private func settingsCategoryChanged(_ sender: NSSegmentedControl) {
        activeSettingsCategory = BoardManInlineSettingsCategory(rawValue: sender.selectedSegment) ?? .view
        layoutPanelSubviews()
    }

    @objc private func dedupeChanged(_ sender: NSButton) {
        AppEnvironment.current.defaults.set(sender.state == .off, forKey: Constants.UserDefaults.copySameHistory)
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
        (NSApp.delegate as? AppDelegate)?.showPreferenceWindow()
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
            let pinnedItems = allItems.filter { $0.isPinned }
            let regularHistory = allItems.filter { $0.source == .clip && !$0.isPinned }
            tabbedItems = pinnedItems + regularHistory
        case .snippets:
            tabbedItems = allItems.filter { $0.source == .snippet }
        case .settings:
            tabbedItems = []
        }

        historyItems = query.isEmpty ? tabbedItems : tabbedItems.filter {
            $0.title.lowercased().contains(query) || $0.previewTitle.lowercased().contains(query)
        }
        selectedIndex = historyItems.isEmpty ? -1 : min(max(selectedIndex, 0), historyItems.count - 1)
        layoutPanelSubviews()
        placeholderList?.reloadData()
        syncNativeSelection()
    }

    // Single-click paste handler (left click on row pastes immediately; spec #1, #4). Uses safe bounds, selects row for feedback, triggers handlePanelPaste via callback (orderOut first, no close(), strong retain via MenuManager var, no terminate).
    @objc private func handleSingleClickPaste(_ gesture: NSClickGestureRecognizer) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        guard let table = placeholderList else { return }
        let location = gesture.location(in: table)
        let row = table.row(at: location)
        guard row >= 0, let item = historyItems[safe: row] else { return }
        setSelectedIndex(row)
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
                let editSnippetItem = NSMenuItem(title: "Edit Snippet", action: #selector(openSnippetEditor(_:)), keyEquivalent: "")
                editSnippetItem.target = self
                menu.addItem(editSnippetItem)
            }
        } else {
            let disabledPin = NSMenuItem(title: "Pin / Unpin", action: nil, keyEquivalent: "")
            disabledPin.isEnabled = false
            menu.addItem(disabledPin)
        }

        menu.addItem(NSMenuItem.separator())

        if activeTab == .snippets {
            let addSnippetItem = NSMenuItem(title: "Add Snippet", action: #selector(openSnippetEditor(_:)), keyEquivalent: "")
            addSnippetItem.target = self
            menu.addItem(addSnippetItem)
        }

        let copyItem = NSMenuItem(title: "Copy Title", action: nil, keyEquivalent: "")
        copyItem.isEnabled = false  // per spec: if safe otherwise skip; placeholder
        menu.addItem(copyItem)

        let moreItem = NSMenuItem(title: "More actions (delete etc.) coming soon", action: nil, keyEquivalent: "")
        moreItem.isEnabled = false
        menu.addItem(moreItem)

        return menu
    }

    @objc private func performPasteFromMenu(_ sender: NSMenuItem) {
        guard let row = sender.representedObject as? Int,
              let item = historyItems[safe: row] else { return }
        onPasteRequested?(item, nil)
    }

    @objc private func togglePinFromMenu(_ sender: NSMenuItem) {
        guard let dataHash = sender.representedObject as? String else { return }
        PinnedSnippetStore.shared.toggle(dataHash)
        onRefreshRequested?()
    }

    override func cancelOperation(_ sender: Any?) {
        hidePreviewBubble()
        self.orderOut(nil)  // Esc: hide/orderOut only (avoids V4B-6 crash, no terminate)
    }

    override func orderOut(_ sender: Any?) {
        hidePreviewBubble()
        super.orderOut(sender)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        layoutPanelSubviews()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handlePanelKey(event) {
            return
        }
        super.sendEvent(event)
    }

    private func handlePanelKey(_ event: NSEvent) -> Bool {
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
            guard activeTab != .settings else { return false }
            moveSelection(delta: 1)
            return true
        case 126:
            guard activeTab != .settings else { return false }
            moveSelection(delta: -1)
            return true
        case 36, 76:
            guard activeTab != .settings else { return false }
            pasteSelectedRow()
            return true
        default:
            return false
        }
    }

    private func moveTab(delta: Int) {
        let tabs = BoardManPanelTab.allCases
        guard let currentIndex = tabs.firstIndex(of: activeTab) else { return }
        let nextIndex = min(tabs.count - 1, max(0, currentIndex + delta))
        guard nextIndex != currentIndex else { return }
        activeTab = tabs[nextIndex]
        segmentedControl?.selectedSegment = activeTab.rawValue
        selectedIndex = -1
        hoveredRow = -1
        hidePreviewBubble()
        applyCurrentFilter()
        if activeTab == .settings {
            makeFirstResponder(self)
        } else {
            focusTableForKeyboard()
        }
    }

    private func moveSelection(delta: Int) {
        guard let table = placeholderList, !historyItems.isEmpty else { return }
        let current = selectedIndex >= 0 ? selectedIndex : 0
        let next = min(historyItems.count - 1, max(0, current + delta))
        setSelectedIndex(next)
        table.scrollRowToVisible(next)
    }

    private func pasteSelectedRow() {
        let startedAt = CFAbsoluteTimeGetCurrent()
        guard placeholderList != nil else { return }
        let row = selectedIndex >= 0 ? selectedIndex : 0
        guard let item = historyItems[safe: row] else { return }
        setSelectedIndex(row)
        onPasteRequested?(item, startedAt)
    }

    fileprivate func setHoveredRow(_ row: Int) {
        guard row >= 0, historyItems[safe: row] != nil else { return }
        hoveredRow = row
        placeholderList?.rowView(atRow: row, makeIfNecessary: false)?.needsDisplay = true
        placeholderList?.reloadData(forRowIndexes: IndexSet(integer: row),
                                    columnIndexes: IndexSet(integer: 0))
        showPreviewBubble(for: row)
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

    fileprivate func usedItemAppearance(for row: Int) -> (background: NSColor, border: NSColor, borderWidth: CGFloat)? {
        guard row >= 0, let item = historyItems[safe: row], item.pasteCount >= 1 else { return nil }
        let style = BoardManPanel.allowedUsedItemStyle(AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManUsedItemStyle))
        let alpha: CGFloat = isLiquidGlassEnabled ? 0.16 : 0.20
        switch style {
        case "Subtle Red":
            return (NSColor.systemRed.withAlphaComponent(alpha), NSColor.systemRed.withAlphaComponent(0.42), 1)
        case "Amber":
            return (NSColor.systemOrange.withAlphaComponent(alpha), NSColor.systemOrange.withAlphaComponent(0.42), 1)
        case "Blue":
            return (NSColor.systemBlue.withAlphaComponent(alpha), NSColor.systemBlue.withAlphaComponent(0.42), 1)
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
        syncNativeSelection()
        var rows = IndexSet(integer: row)
        if oldIndex >= 0 {
            rows.insert(oldIndex)
        }
        placeholderList?.reloadData(forRowIndexes: rows,
                                    columnIndexes: IndexSet(integer: 0))
    }

    private func syncNativeSelection() {
        guard let table = placeholderList else { return }
        if selectedIndex >= 0, selectedIndex < historyItems.count {
            table.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        } else {
            table.deselectAll(nil)
        }
    }

    fileprivate func showPreviewBubble(for row: Int) {
        guard row >= 0,
              let item = historyItems[safe: row],
              let bubble = previewBubblePanel,
              let label = previewBubbleLabel else {
            hidePreviewBubble()
            return
        }
        label.stringValue = item.previewTitle
        let maxWidth: CGFloat = 340
        let maxLabelSize = NSSize(width: maxWidth - 20, height: 150)
        let textSize = (item.previewTitle as NSString).boundingRect(
            with: maxLabelSize,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: label.font ?? NSFont.systemFont(ofSize: 12)]
        ).size
        let bubbleWidth = min(maxWidth, max(180, ceil(textSize.width) + 20))
        let bubbleHeight = min(166, max(44, ceil(textSize.height) + 18))
        label.frame = NSRect(x: 10, y: 9, width: bubbleWidth - 20, height: bubbleHeight - 18)
        bubble.contentView?.frame = NSRect(x: 0, y: 0, width: bubbleWidth, height: bubbleHeight)
        let useGlass = isLiquidGlassEnabled
        if let effectView = bubble.contentView as? NSVisualEffectView {
            effectView.material = useGlass ? .hudWindow : .popover
            effectView.blendingMode = useGlass ? .behindWindow : .withinWindow
        }
        bubble.contentView?.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(useGlass ? 0.16 : 0.98).cgColor
        bubble.contentView?.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(useGlass ? 0.38 : 0.42).cgColor
        label.textColor = useGlass ? .labelColor : .labelColor

        let panelFrame = frame
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panelFrame.insetBy(dx: -bubbleWidth, dy: -bubbleHeight)
        let gap: CGFloat = 10
        let rightX = panelFrame.maxX + gap
        let leftX = panelFrame.minX - bubbleWidth - gap
        let bubbleX: CGFloat
        if rightX + bubbleWidth <= visibleFrame.maxX {
            bubbleX = rightX
        } else if leftX >= visibleFrame.minX {
            bubbleX = leftX
        } else {
            bubbleX = min(max(visibleFrame.minX + gap, rightX), visibleFrame.maxX - bubbleWidth - gap)
        }
        let desiredY = panelFrame.maxY - bubbleHeight - 54
        let bubbleY = min(max(visibleFrame.minY + gap, desiredY), visibleFrame.maxY - bubbleHeight - gap)
        bubble.setFrame(NSRect(x: bubbleX, y: bubbleY, width: bubbleWidth, height: bubbleHeight), display: true)
        bubble.orderFront(nil)
    }

    fileprivate func hidePreviewBubble() {
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
                       useLiquidGlass: isLiquidGlassEnabled)
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 50
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // Refresh views after selection change so selected row uses readable .selectedTextColor
        placeholderList?.reloadData()
    }
}
