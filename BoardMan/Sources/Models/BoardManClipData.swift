//
//  BoardManClipData.swift
//
//  Board-Man
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2015/06/21.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import SwiftHEXColors

final class BoardManClipData: NSObject {

    // MARK: - Properties
    fileprivate let kTypesKey       = "types"
    fileprivate let kStringValueKey = "stringValue"
    fileprivate let kRTFDataKey     = "RTFData"
    fileprivate let kPDFKey         = "PDF"
    fileprivate let kFileNamesKey   = "filenames"
    fileprivate let kURLsKey        = "URL"
    fileprivate let kImageKey       = "image"

    var types          = [NSPasteboard.PasteboardType]()
    var fileNames      = [String]()
    var URLs           = [String]()
    var stringValue    = ""
    var RTFData: Data?
    var PDF: Data?
    var image: NSImage?

    override var hash: Int {
        var hash = types.map { $0.rawValue }.joined().hash
        if let image = self.image, let imageData = image.tiffRepresentation {
            hash ^= imageData.count
        } else if let image = self.image {
            hash ^= image.hash
        }
        if !fileNames.isEmpty {
            fileNames.forEach { hash ^= $0.hash }
        } else if !self.URLs.isEmpty {
            URLs.forEach { hash ^= $0.hash }
        } else if let pdf = PDF {
            hash ^= pdf.count
        } else if !stringValue.isEmpty {
            hash ^= stringValue.hash
        }
        if let data = RTFData {
            hash ^= data.count
        }
        return hash
    }
    var primaryType: NSPasteboard.PasteboardType? {
        return types.first
    }
    var isImageOnly: Bool {
        return image != nil && stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && fileNames.isEmpty && URLs.isEmpty && PDF == nil
    }
    var imageDisplayTitle: String? {
        guard isImageOnly else { return nil }
        if types.contains(.png) {
            return "PNG image"
        }
        if types.contains(.tiff) || types.contains(.deprecatedTIFF) {
            return "TIFF image"
        }
        return "Image"
    }
    var isOnlyStringType: Bool {
        return types == [.deprecatedString] || types == [.string]
    }
    var thumbnailImage: NSImage? {
        let defaults = UserDefaults.standard
        let width = defaults.integer(forKey: Constants.UserDefaults.thumbnailWidth)
        let height = defaults.integer(forKey: Constants.UserDefaults.thumbnailHeight)

        if let image = image, fileNames.isEmpty {
            // Image only data
            return image.resizeImage(CGFloat(width), CGFloat(height))
        } else if let fileName = fileNames.first, let path = fileName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), let url = URL(string: path) {
             // In the case of the local file correct data is not included in the image variable
             // Judge the image from the path and create a thumbnail
            switch url.pathExtension.lowercased() {
            case "jpg", "jpeg", "png", "bmp", "tiff":
                return NSImage(contentsOfFile: fileName)?.resizeImage(CGFloat(width), CGFloat(height))
            default: break
            }
        }
        return nil
    }
    var colorCodeImage: NSImage? {
        guard let color = NSColor(hexString: stringValue) else { return nil }
        return NSImage.create(with: color, size: NSSize(width: 20, height: 20))
    }

    var boardManTextValue: String {
        return Self.preferredTextValue(
            plainText: stringValue,
            richText: Self.richTextString(from: RTFData, types: types)
        )
    }

    static func preferredTextValue(plainText: String, richText: String?) -> String {
        let plain = canonicalLineEndings(plainText)
        guard let richText else { return plain }
        var rich = canonicalLineEndings(richText)
        guard !rich.isEmpty else { return plain }

        // HTML -> attributed-string conversion commonly appends one terminal line break that
        // is not present in the plain representation. Ignore only that parser artifact.
        if !plain.hasSuffix("\n"), rich.hasSuffix("\n") {
            rich.removeLast()
        }
        guard plain != rich else { return plain }

        // Chromium can expose a plain-text fallback with extra line breaks that are not
        // always a perfect 2x expansion of the rich representation. Reconcile only when the
        // non-line-break text matches and the surplus is systematic across multiple line-break
        // runs, or when every run is the classic exact 2x expansion. A single extra blank line
        // is not enough evidence because it can be intentional user content.
        let plainWithoutLineBreaks = plain.replacingOccurrences(of: "\n", with: "")
        let richWithoutLineBreaks = rich.replacingOccurrences(of: "\n", with: "")
        let plainRuns = lineBreakRunLengths(in: plain)
        let richRuns = lineBreakRunLengths(in: rich)
        guard plainWithoutLineBreaks == richWithoutLineBreaks,
              plainRuns.count == richRuns.count else {
            return plain
        }

        var surplusRunCount = 0
        var allRunsDoubled = !richRuns.isEmpty
        for (plainRun, richRun) in zip(plainRuns, richRuns) {
            guard plainRun >= richRun else { return plain }
            if plainRun > richRun {
                surplusRunCount += 1
            }
            if plainRun != richRun * 2 {
                allRunsDoubled = false
            }
        }
        return (allRunsDoubled || surplusRunCount >= 2) ? rich : plain
    }

    static func liveSanitizedPlainText(from pasteboard: NSPasteboard) -> String? {
        guard let plain = pasteboard.string(forType: .string)
                ?? pasteboard.string(forType: .deprecatedString),
              let rich = richTextString(from: pasteboard) else {
            return nil
        }
        let canonicalPlain = canonicalLineEndings(plain)
        let preferred = preferredTextValue(plainText: plain, richText: rich)
        return preferred == canonicalPlain ? nil : preferred
    }

    private static func canonicalLineEndings(_ value: String) -> String {
        return value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
    }

    private static func lineBreakRunLengths(in value: String) -> [Int] {
        var runs = [Int]()
        var currentRun = 0
        for character in value {
            if character == "\n" {
                currentRun += 1
            } else if currentRun > 0 {
                runs.append(currentRun)
                currentRun = 0
            }
        }
        if currentRun > 0 {
            runs.append(currentRun)
        }
        return runs
    }

    private static func richTextString(from data: Data?,
                                       types: [NSPasteboard.PasteboardType]) -> String? {
        guard let data else { return nil }
        let documentTypes: [NSAttributedString.DocumentType] = types.contains(.deprecatedRTFD)
            ? [.rtfd, .rtf]
            : [.rtf, .rtfd]
        return richTextString(from: data, documentTypes: documentTypes)
    }

    private static func richTextString(from pasteboard: NSPasteboard) -> String? {
        // Rich representations are consulted transiently even when the user chose not to
        // retain RTF/HTML in history. They are only evidence for correcting a broken plain
        // fallback and are never persisted unless that type was already enabled for storage.
        let candidates: [(NSPasteboard.PasteboardType, NSAttributedString.DocumentType)] = [
            (.deprecatedRTFD, .rtfd),
            (.deprecatedRTF, .rtf),
            (.rtf, .rtf),
            (.html, .html)
        ]
        var checkedTypes = Set<String>()
        for (pasteboardType, documentType) in candidates {
            guard checkedTypes.insert(pasteboardType.rawValue).inserted,
                  let data = pasteboard.data(forType: pasteboardType),
                  let text = richTextString(from: data, documentTypes: [documentType]) else {
                continue
            }
            return text
        }
        return nil
    }

    private static func richTextString(from data: Data,
                                       documentTypes: [NSAttributedString.DocumentType]) -> String? {
        for documentType in documentTypes {
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: documentType
            ]
            if let attributed = try? NSAttributedString(
                data: data,
                options: options,
                documentAttributes: nil
            ) {
                return attributed.string
            }
        }
        return nil
    }

    static var availableTypes: [NSPasteboard.PasteboardType] {
        return [.deprecatedString,
                .deprecatedRTF,
                .deprecatedRTFD,
                .deprecatedPDF,
                .deprecatedFilenames,
                .deprecatedURL,
                .deprecatedTIFF]
    }
    static var availableTypesString: [String] {
        return ["String",
                "RTF",
                "RTFD",
                "PDF",
                "Filenames",
                "URL",
                "TIFF"]
    }
    static var availableTypesDictinary: [NSPasteboard.PasteboardType: String] {
        var availableTypes = [NSPasteboard.PasteboardType: String]()
        zip(Self.availableTypes, Self.availableTypesString).forEach { availableTypes[$0] = $1 }
        return availableTypes
    }

    static func registerLegacyArchiveAliases() {
        let legacyClassName = ["C", "PY", "ClipData"].joined()
        NSKeyedUnarchiver.setClass(Self.self, forClassName: legacyClassName)
        NSKeyedUnarchiver.setClass(Self.self, forClassName: "Board_Man.\(legacyClassName)")
        NSKeyedUnarchiver.setClass(Self.self, forClassName: "Clipy.\(legacyClassName)")
    }

    // MARK: - Init
    init(pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) {
        super.init()
        self.types = types
        types.forEach { type in
            switch type {
            case .deprecatedString:
                guard let string = pasteboard.string(forType: .deprecatedString) ?? pasteboard.string(forType: .string) else { return }
                stringValue = string
            case .string:
                guard let string = pasteboard.string(forType: .string) else { return }
                stringValue = string
            case .deprecatedRTFD:
                RTFData = pasteboard.data(forType: .deprecatedRTFD)
            case .deprecatedRTF where RTFData == nil:
                RTFData = pasteboard.data(forType: .deprecatedRTF)
            case .deprecatedPDF:
                PDF = pasteboard.data(forType: .deprecatedPDF)
            case .deprecatedFilenames:
                guard let filenames = pasteboard.propertyList(forType: .deprecatedFilenames) as? [String] else { return }
                self.fileNames = filenames
            case .deprecatedURL:
                guard let urls = pasteboard.propertyList(forType: .deprecatedURL) as? [String] else { return }
                URLs = urls
            case .deprecatedTIFF:
                image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage
            case .png, .tiff:
                if image == nil {
                    image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage
                }
            default: break
            }
        }
        if !stringValue.isEmpty {
            let transientRichText = Self.richTextString(from: pasteboard)
            let storedRichText = Self.richTextString(from: RTFData, types: types)
            stringValue = Self.preferredTextValue(
                plainText: stringValue,
                richText: transientRichText ?? storedRichText
            )
        }
    }

    init(string: String, type: NSPasteboard.PasteboardType = .deprecatedString) {
        self.types = [type]
        self.stringValue = string
    }

    init(image: NSImage) {
        self.types = [.deprecatedTIFF]
        self.image = image
    }

    deinit {
        self.RTFData = nil
        self.PDF = nil
        self.image = nil
    }

    // MARK: - NSCoding
    @objc func encodeWithCoder(_ aCoder: NSCoder) {
        aCoder.encode(types.map { $0.rawValue }, forKey: kTypesKey)
        aCoder.encode(stringValue, forKey: kStringValueKey)
        aCoder.encode(RTFData, forKey: kRTFDataKey)
        aCoder.encode(PDF, forKey: kPDFKey)
        aCoder.encode(fileNames, forKey: kFileNamesKey)
        aCoder.encode(URLs, forKey: kURLsKey)
        aCoder.encode(image, forKey: kImageKey)
    }

    @objc required init(coder aDecoder: NSCoder) {
        types = (aDecoder.decodeObject(forKey: kTypesKey) as? [String])?.compactMap { NSPasteboard.PasteboardType(rawValue: $0) } ?? []
        fileNames = aDecoder.decodeObject(forKey: kFileNamesKey) as? [String] ?? [String]()
        URLs = aDecoder.decodeObject(forKey: kURLsKey) as? [String] ?? [String]()
        stringValue = aDecoder.decodeObject(forKey: kStringValueKey) as? String ?? ""
        RTFData = aDecoder.decodeObject(forKey: kRTFDataKey) as? Data
        PDF = aDecoder.decodeObject(forKey: kPDFKey) as? Data
        image = aDecoder.decodeObject(forKey: kImageKey) as? NSImage
        super.init()
    }
}

// Archive/source compatibility boundary while callers are migrated to the Board-Man name.
