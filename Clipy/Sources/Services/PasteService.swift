//
//  PasteService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/11/23.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import Cocoa
import Magnet
import Sauce

final class PasteService {

    // MARK: - Properties
    fileprivate static let legacyStringPasteboardType = NSPasteboard.PasteboardType(rawValue: "NSStringPboardType")

    fileprivate let lock = NSRecursiveLock(name: "com.uniplanck.BoardMan.Pastable")
    fileprivate var isPastePlainText: Bool {
        guard AppEnvironment.current.defaults.bool(forKey: Constants.Beta.pastePlainText) else { return false }

        let modifierSetting = AppEnvironment.current.defaults.integer(forKey: Constants.Beta.pastePlainTextModifier)
        return isPressedModifier(modifierSetting)
    }
    fileprivate var isDeleteHistory: Bool {
        guard AppEnvironment.current.defaults.bool(forKey: Constants.Beta.deleteHistory) else { return false }

        let modifierSetting = AppEnvironment.current.defaults.integer(forKey: Constants.Beta.deleteHistoryModifier)
        return isPressedModifier(modifierSetting)
    }
    fileprivate var isPasteAndDeleteHistory: Bool {
        guard AppEnvironment.current.defaults.bool(forKey: Constants.Beta.pasteAndDeleteHistory) else { return false }

        let modifierSetting = AppEnvironment.current.defaults.integer(forKey: Constants.Beta.pasteAndDeleteHistoryModifier)
        return isPressedModifier(modifierSetting)
    }

    // MARK: - Modifiers
    private func isPressedModifier(_ flag: Int) -> Bool {
        let flags = NSEvent.modifierFlags
        if flag == 0 && flags.contains(.command) {
            return true
        } else if flag == 1 && flags.contains(.shift) {
            return true
        } else if flag == 2 && flags.contains(.control) {
            return true
        } else if flag == 3 && flags.contains(.option) {
            return true
        }
        return false
    }
}

// MARK: - Copy
extension PasteService {
    @discardableResult
    func paste(with clip: CPYClip, shortcut: KeyCombo) -> Bool {
        guard !clip.isInvalidated,
              NSKeyedUnarchiver.unarchiveObject(withFile: clip.dataPath) is CPYClipData else { return false }
        copyToPasteboard(with: clip)
        return sendShortcut(shortcut)
    }

    @discardableResult
    func paste(with clip: CPYClip) -> Bool {
        guard !clip.isInvalidated else { return false }
        guard let data = NSKeyedUnarchiver.unarchiveObject(withFile: clip.dataPath) as? CPYClipData else { return false }

        // Handling modifier actions
        let isPastePlainText = self.isPastePlainText
        let isPasteAndDeleteHistory = self.isPasteAndDeleteHistory
        let isDeleteHistory = self.isDeleteHistory
        guard isPastePlainText || isPasteAndDeleteHistory || isDeleteHistory else {
            copyToPasteboard(with: clip)
            return paste()
        }

        var didPaste = false
        // Increment change count for don't copy paste item
        if isPasteAndDeleteHistory {
            AppEnvironment.current.clipService.incrementChangeCount()
        }
        // Paste history
        if isPastePlainText {
            copyToPasteboard(with: data.boardManTextValue)
            didPaste = paste()
        } else if isPasteAndDeleteHistory {
            copyToPasteboard(with: clip)
            didPaste = paste()
        }
        // Delete clip
        if isDeleteHistory || isPasteAndDeleteHistory {
            AppEnvironment.current.clipService.delete(with: clip)
        }
        return didPaste
    }

    func copyToPasteboard(with string: String) {
        lock.lock(); defer { lock.unlock() }

        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(string, forType: .string)
        AppEnvironment.current.clipService.markCurrentPasteboardChangeAsHandled()
    }

    func copyToPasteboard(with clip: CPYClip) {
        lock.lock(); defer { lock.unlock() }

        guard let data = NSKeyedUnarchiver.unarchiveObject(withFile: clip.dataPath) as? CPYClipData else { return }

        if isPastePlainText {
            copyToPasteboard(with: data.stringValue)
            return
        }

        // For text-only history, replay the exact captured plain string instead of RTF/RTFD.
        // Some target apps interpret rich-text paragraph attributes as extra visual blank lines.
        // The captured string preserves intentional newlines (including real blank lines) exactly.
        let textOnlyTypes: Set<NSPasteboard.PasteboardType> = [
            Self.legacyStringPasteboardType,
            .deprecatedString,
            .string,
            .deprecatedRTF,
            .deprecatedRTFD
        ]
        let hasTextRepresentation = data.types.contains(Self.legacyStringPasteboardType)
            || data.types.contains(.deprecatedString)
            || data.types.contains(.string)
        let hasNonTextRepresentation = data.types.contains { !textOnlyTypes.contains($0) }
        if hasTextRepresentation && !hasNonTextRepresentation {
            copyToPasteboard(with: data.boardManTextValue)
            return
        }

        let pasteboard = NSPasteboard.general
        let types = data.types
        let declaredTypes = types.map { $0 == Self.legacyStringPasteboardType ? NSPasteboard.PasteboardType.string : $0 }
        pasteboard.declareTypes(declaredTypes, owner: nil)
        types.forEach { type in
            switch type {
            case Self.legacyStringPasteboardType:
                pasteboard.setString(data.boardManTextValue, forType: .string)
            case .deprecatedRTFD:
                guard let rtfData = data.RTFData else { return }
                pasteboard.setData(rtfData, forType: .deprecatedRTFD)
            case .deprecatedRTF:
                guard let rtfData = data.RTFData else { return }
                pasteboard.setData(rtfData, forType: .deprecatedRTF)
            case .deprecatedPDF:
                guard let pdfData = data.PDF, let pdfRep = NSPDFImageRep(data: pdfData) else { return }
                pasteboard.setData(pdfRep.pdfRepresentation, forType: .deprecatedPDF)
            case .deprecatedFilenames:
                let fileNames = data.fileNames
                pasteboard.setPropertyList(fileNames, forType: .deprecatedFilenames)
            case .deprecatedURL:
                let url = data.URLs
                pasteboard.setPropertyList(url, forType: .deprecatedURL)
            case .deprecatedTIFF:
                guard let image = data.image, let imageData = image.tiffRepresentation else { return }
                pasteboard.setData(imageData, forType: .deprecatedTIFF)
            case .tiff:
                guard let image = data.image, let imageData = image.tiffRepresentation else { return }
                pasteboard.setData(imageData, forType: .tiff)
            case .png:
                guard let image = data.image,
                      let tiffData = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData),
                      let imageData = bitmap.representation(using: .png, properties: [:]) else { return }
                pasteboard.setData(imageData, forType: .png)
            default: break
            }
        }
        AppEnvironment.current.clipService.markCurrentPasteboardChangeAsHandled()
    }
}

// MARK: - Paste
extension PasteService {
    @discardableResult
    func paste() -> Bool {
        guard AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.inputPasteCommand) else { return false }
        return sendShortcut(KeyCombo(key: .v, cocoaModifiers: .command))
    }

    @discardableResult
    func sendShortcut(_ keyCombo: KeyCombo) -> Bool {
        guard !keyCombo.doubledModifiers else { return false }
        let accessibilityService = AppEnvironment.current.accessibilityService
        guard accessibilityService.isAccessibilityEnabled(isPrompt: false) else {
            accessibilityService.showAccessibilityAuthenticationAlert()
            return false
        }

        let modifiers = keyCombo.keyEquivalentModifierMask
        if modifiers.contains(.command), keyCombo.keyEquivalent.uppercased() == "V" {
            PasteCountInputService.shared.suppressNextGlobalPaste()
        }
        let keyCode = keyCombo.currentKeyCode
        let eventFlags = Self.eventFlags(from: modifiers)
        DispatchQueue.main.async {
            let source = CGEventSource(stateID: .combinedSessionState)
            source?.setLocalEventsFilterDuringSuppressionState(
                [.permitLocalMouseEvents, .permitSystemDefinedEvents],
                state: .eventSuppressionStateSuppressionInterval
            )
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
            keyDown?.flags = eventFlags
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
            keyUp?.flags = eventFlags
            keyDown?.post(tap: .cgAnnotatedSessionEventTap)
            keyUp?.post(tap: .cgAnnotatedSessionEventTap)
        }
        return true
    }

    private static func eventFlags(from modifiers: NSEvent.ModifierFlags) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.function) { flags.insert(.maskSecondaryFn) }
        if modifiers.contains(.capsLock) { flags.insert(.maskAlphaShift) }
        if modifiers.contains(.numericPad) { flags.insert(.maskNumericPad) }
        if modifiers.contains(.help) { flags.insert(.maskHelp) }
        return flags
    }
}
