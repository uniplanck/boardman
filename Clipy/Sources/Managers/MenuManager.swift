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

    fileprivate func showBoardManPanel() {
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
            let panelSize = NSSize(width: 460, height: BoardManPanel.preferredPanelHeight())
            let mouseLoc = NSEvent.mouseLocation
            var originX = mouseLoc.x - (panelSize.width / 2)
            var originY = mouseLoc.y - (panelSize.height / 2)
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
        let dateFormatter: DateFormatter? = timestampFormat == "none" ? nil : {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = timestampFormat
            return formatter
        }()

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
            if let dateFormatter {
                parts.append(dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(clip.updateTime))))
            }
            if isPinned {
                parts.append("[PIN]")
            }
            let displayTitle = (parts + ["\(PasteCountStore.shared.label(for: clip))\(clipped)"]).joined(separator: " ")
            return BoardManHistoryItem(title: displayTitle,
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
                                                   previewTitle: snippet.content,
                                                   dataHash: snippet.identifier,
                                                   pasteCount: 0,
                                                   isPinned: isPinned,
                                                   source: .snippet)
                    }
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
        menu.addItem(NSMenuItem(title: String(localized: "Board-Man Settings"), action: #selector(AppDelegate.showPreferenceWindow)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Quit Board-Man"), action: #selector(AppDelegate.terminate)))

        clipMenu = menu
        historyMenu = NSMenu(title: Constants.Menu.history)
        snippetMenu = NSMenu(title: Constants.Menu.snippet)
        statusItem?.menu = clipMenu
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
        clipMenu?.addItem(NSMenuItem(title: String(localized: "Board-Man Settings"), action: #selector(AppDelegate.showPreferenceWindow)))
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
        statusItem?.menu = clipMenu
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
fileprivate enum BoardManPanelTab: Int {
    case history = 0
    case pinned
    case snippets
    case favorites

    var title: String {
        switch self {
        case .history: return "History"
        case .pinned: return "Pinned"
        case .snippets: return "Snippets"
        case .favorites: return "Favorites"
        }
    }

    var emptyMessage: String {
        switch self {
        case .history: return "No clipboard history yet"
        case .pinned: return "No pinned items yet - pin rows from the context menu"
        case .snippets: return "No snippets yet - add reusable text in Snippets"
        case .favorites: return "No favorites yet - saved favorites will appear here"
        }
    }
}

fileprivate enum BoardManPanelItemSource {
    case clip
    case snippet
    case favorite
}

fileprivate struct BoardManHistoryItem {
    let title: String
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
        let rowRect = bounds.insetBy(dx: 4, dy: 3)
        let path = NSBezierPath(roundedRect: rowRect, xRadius: 7, yRadius: 7)
        if previewOwner?.isSelectedRow(row) == true {
            NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
            path.fill()
        } else if previewOwner?.isHoveredRow(row) == true {
            NSColor.controlAccentColor.withAlphaComponent(0.10).setFill()
            path.fill()
        } else {
            super.drawBackground(in: dirtyRect)
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        drawBackground(in: dirtyRect)
    }
}

// MARK: - BoardManPanel MVP Shell (embedded in MenuManager.swift per constraints)
class BoardManPanel: NSPanel {

    private var searchField: NSSearchField?
    private var segmentedControl: NSSegmentedControl?
    private var settingsBackgroundView: NSView?
    private var scrollView: NSScrollView?
    private var placeholderList: NSTableView?
    private var rowNumbersButton: NSButton?
    private var timestampLabel: NSTextField?
    private var timestampPopup: NSPopUpButton?
    private var heightControlLabel: NSTextField?
    private var heightStepper: NSStepper?
    private var heightLabel: NSTextField?
    private var footerNote: NSTextField?
    private var previewBubblePanel: NSPanel?
    private var previewBubbleLabel: NSTextField?
    private var allItems: [BoardManHistoryItem] = []
    private var historyItems: [BoardManHistoryItem] = []
    private var selectedIndex: Int = -1
    private var hoveredRow: Int = -1
    private var activeTab: BoardManPanelTab = .history
    fileprivate var onPasteRequested: ((BoardManHistoryItem, CFAbsoluteTime?) -> Void)?
    var onRefreshRequested: (() -> Void)?
    var itemCount: Int {
        return historyItems.count
    }

    static func preferredPanelHeight() -> CGFloat {
        return CGFloat(clampedPanelHeight(AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.boardManPanelHeight)))
    }

    static func clampedPanelHeight(_ value: Int) -> Int {
        return min(900, max(520, value == 0 ? 680 : value))
    }

    static func allowedTimestampFormat(_ value: String?) -> String {
        let allowed = ["yyyy/MM/dd HH:mm", "HH:mm", "none"]
        guard let value, allowed.contains(value) else { return "none" }
        return value
    }

    convenience init() {
        let contentRect = NSRect(x: 0, y: 0, width: 460, height: BoardManPanel.preferredPanelHeight())
        self.init(contentRect: contentRect,
                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView],  // no .hudWindow = no harsh black footer/band
                  backing: .buffered,
                  defer: false)
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

    private func setupUI() {
        guard let contentView = contentView else { return }

        // Search field at top - clean margins
        let search = NSSearchField(frame: .zero)
        search.placeholderString = "Search history, pinned items, and snippets"
        search.target = self
        search.action = #selector(searchTextChanged(_:))
        search.sendsSearchStringImmediately = true
        search.focusRingType = .none
        contentView.addSubview(search)
        searchField = search

        // Tabs: rounded style avoids harsh black blocks; History tab default and visible
        let tabs = NSSegmentedControl(frame: .zero)
        tabs.segmentCount = 4
        tabs.setLabel("History", forSegment: 0)
        tabs.setLabel("Pinned", forSegment: 1)
        tabs.setLabel("Snippets", forSegment: 2)
        tabs.setLabel("Favorites", forSegment: 3)
        tabs.selectedSegment = 0
        tabs.target = self
        tabs.action = #selector(tabChanged(_:))
        if #available(macOS 10.10, *) {
            tabs.segmentStyle = .rounded
        }
        contentView.addSubview(tabs)
        segmentedControl = tabs

        let settingsBackground = NSView(frame: .zero)
        settingsBackground.wantsLayer = true
        settingsBackground.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        settingsBackground.layer?.cornerRadius = 6
        contentView.addSubview(settingsBackground)
        settingsBackgroundView = settingsBackground

        let numbers = NSButton(checkboxWithTitle: "Number", target: self, action: #selector(rowNumbersChanged(_:)))
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
        popup.addItems(withTitles: ["none", "HH:mm", "yyyy/MM/dd HH:mm"])
        popup.selectItem(withTitle: BoardManPanel.allowedTimestampFormat(AppEnvironment.current.defaults.string(forKey: Constants.UserDefaults.boardManTimestampFormat)))
        popup.font = NSFont.systemFont(ofSize: 11)
        popup.target = self
        popup.action = #selector(timestampFormatChanged(_:))
        contentView.addSubview(popup)
        timestampPopup = popup

        let heightTitle = NSTextField(labelWithString: "Height")
        heightTitle.font = NSFont.systemFont(ofSize: 11)
        heightTitle.textColor = .labelColor
        contentView.addSubview(heightTitle)
        heightControlLabel = heightTitle

        let stepper = NSStepper(frame: .zero)
        stepper.minValue = 520
        stepper.maxValue = 900
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
        table.rowHeight = 46
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
        note.textColor = .secondaryLabelColor
        note.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        note.backgroundColor = .clear
        note.drawsBackground = false
        contentView.addSubview(note)
        footerNote = note

        let bubbleLabel = NSTextField(labelWithString: "")
        bubbleLabel.font = NSFont.systemFont(ofSize: 12)
        bubbleLabel.textColor = NSColor(calibratedWhite: 0.08, alpha: 1.0)
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
        bubble.contentView = NSView(frame: bubble.contentRect(forFrameRect: bubble.frame))
        bubble.contentView?.wantsLayer = true
        bubble.contentView?.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.98).cgColor
        bubble.contentView?.layer?.borderColor = NSColor.separatorColor.cgColor
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
        searchField?.frame = NSRect(x: margin, y: top, width: width, height: 32)
        segmentedControl?.frame = NSRect(x: margin, y: top - 42, width: width, height: 30)
        // V4B-13: remove broken inline settings row from the panel. Keep settings in Preferences later.
        settingsBackgroundView?.isHidden = true
        rowNumbersButton?.isHidden = true
        timestampLabel?.isHidden = true
        timestampPopup?.isHidden = true
        heightControlLabel?.isHidden = true
        heightLabel?.isHidden = true
        heightStepper?.isHidden = true
        footerNote?.frame = NSRect(x: margin, y: 8, width: width, height: 16)
        let scrollTop = top - 58
        scrollView?.frame = NSRect(x: margin, y: 30, width: width, height: max(220, scrollTop - 30))
        placeholderList?.frame = NSRect(x: 4, y: 0, width: width - 8, height: max(220, scrollTop - 30))
        placeholderList?.tableColumns.first?.width = width - 24
        hidePreviewBubble()
    }

    fileprivate func reloadHistoryItems(_ items: [BoardManHistoryItem]) {
        allItems = items
        applyCurrentFilter()
        if let table = placeholderList {
            makeFirstResponder(table)
        }
    }

    fileprivate func focusTableForKeyboard() {
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
        let value = BoardManPanel.allowedTimestampFormat(sender.titleOfSelectedItem)
        AppEnvironment.current.defaults.set(value, forKey: Constants.UserDefaults.boardManTimestampFormat)
        onRefreshRequested?()
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
            tabbedItems = allItems.filter { $0.source == .clip }
        case .pinned:
            tabbedItems = allItems.filter { $0.isPinned }
        case .snippets:
            tabbedItems = allItems.filter { $0.source == .snippet }
        case .favorites:
            tabbedItems = allItems.filter { $0.source == .favorite }
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
        let pointInWindow = table.convert(location, to: nil)
        menu.popUp(positioning: nil, at: pointInWindow, in: table)
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
        } else {
            let disabledPin = NSMenuItem(title: "Pin / Unpin", action: nil, keyEquivalent: "")
            disabledPin.isEnabled = false
            menu.addItem(disabledPin)
        }

        menu.addItem(NSMenuItem.separator())

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
        case 125:
            moveSelection(delta: 1)
            return true
        case 126:
            moveSelection(delta: -1)
            return true
        case 36, 76:
            pasteSelectedRow()
            return true
        default:
            return false
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
        bubble.contentView?.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.98).cgColor
        bubble.contentView?.layer?.borderColor = NSColor.separatorColor.cgColor

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
        let identifier = NSUserInterfaceItemIdentifier("cell")
        var cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField

        if cell == nil {
            cell = NSTextField()
            cell?.identifier = identifier
            cell?.isEditable = false
            cell?.isBordered = false
            cell?.backgroundColor = .clear
            cell?.drawsBackground = false
            // Single-line truncated text (no wrapping/messy long text) - per UI requirements
            if let textFieldCell = cell?.cell {
                textFieldCell.wraps = false
                textFieldCell.lineBreakMode = .byTruncatingTail
            }
            cell?.maximumNumberOfLines = 1
        }

        let isSelected = selectedIndex == row
        if historyItems.isEmpty {
            cell?.stringValue = activeTab.emptyMessage
            cell?.toolTip = nil
            cell?.textColor = .secondaryLabelColor
            cell?.backgroundColor = .clear
            cell?.drawsBackground = false
            cell?.alignment = .center
            cell?.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        } else if let item = historyItems[safe: row] {
            cell?.alignment = .left
            cell?.toolTip = nil
            // V4B-10 polish: clearer hover/selection affordance via explicit selected bg, subtle zero-count
            // background/marker using PasteCountStore (safe, no schema/realm changes). Cleaner spacing/text via
            // consistent attributed styling and row height tweak below. Single-click semantics untouched.
            if item.pasteCount == 0 || item.isPinned || isSelected {
                let attributedTitle = NSMutableAttributedString(string: item.title)
                let fullRange = NSRange(location: 0, length: (item.title as NSString).length)
                if item.pasteCount == 0 || item.isPinned {
                    attributedTitle.addAttributes([
                        .foregroundColor: NSColor.labelColor,
                        .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
                    ], range: fullRange)
                    if item.pasteCount == 0 {
                        // V4B-13: no inline background marker; row selection/hover owns background contrast.
                    }
                }
                if isSelected {
                    attributedTitle.addAttributes([
                        .foregroundColor: NSColor.labelColor,
                        .font: NSFont.systemFont(ofSize: 13, weight: .medium)
                    ], range: fullRange)
                }
                cell?.attributedStringValue = attributedTitle
                cell?.backgroundColor = .clear
                cell?.drawsBackground = true
            } else {
                cell?.stringValue = item.title
                cell?.textColor = .labelColor
                cell?.backgroundColor = .clear
                cell?.drawsBackground = false
            }
        }

        // font fallback; attributed zero-count rows keep their explicit attributes.
        if !historyItems.isEmpty {
            cell?.font = NSFont.systemFont(ofSize: 13)
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 46
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // Refresh views after selection change so selected row uses readable .selectedTextColor
        placeholderList?.reloadData()
    }
}
