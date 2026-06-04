//
//  PasteCountInputService.swift
//  Board-Man
//

import AppKit
import Carbon

final class PasteCountInputService {
    static let shared = PasteCountInputService()

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var suppressUntil = Date.distantPast
    private var lastCountedText: String?
    private var lastCountedAt = Date.distantPast
    private var lastDetectedAt = Date.distantPast
    private let debounceInterval: TimeInterval = 0.45
    private let duplicateDetectionInterval: TimeInterval = 0.12
    private let boardManPasteSuppressionInterval: TimeInterval = 0.35
    private let pasteboardMatchDelay: TimeInterval = 0.15
    private let maxLogSize: UInt64 = 128 * 1024
    private let logURL: URL

    private init() {
        let logDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Board-Man", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        self.logURL = logDirectory.appendingPathComponent("paste-count.log")
    }

    func startMonitoring() {
        guard globalMonitor == nil, localMonitor == nil, eventTap == nil else { return }

        log("monitor started accessibilityTrusted=\(AXIsProcessTrusted()) listenEventTrusted=\(CGPreflightListenEventAccess())")

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleNSEventKeyDown(event, source: "global")
        }
        log(globalMonitor == nil ? "nsevent global monitor unavailable" : "nsevent global monitor active")

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleNSEventKeyDown(event, source: "local")
            return event
        }
        log(localMonitor == nil ? "nsevent local monitor unavailable" : "nsevent local monitor active")

        startCGEventTap()
    }

    func stopMonitoring() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        globalMonitor = nil
        localMonitor = nil
        eventTap = nil
        eventTapSource = nil
    }

    func suppressNextGlobalPaste() {
        suppressUntil = Date().addingTimeInterval(boardManPasteSuppressionInterval)
        log("suppress next global paste")
    }

    func isFocusedTargetInputLike() -> Bool {
        guard AXIsProcessTrusted() else { return true }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedObject: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedObject
        )

        guard result == .success, let focusedObject else { return true }

        var roleObject: CFTypeRef?
        AXUIElementCopyAttributeValue(
            // swiftlint:disable:next force_cast
            focusedObject as! AXUIElement,
            kAXRoleAttribute as CFString,
            &roleObject
        )

        let role = roleObject as? String ?? ""
        return [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            "AXComboBox",
            "AXWebArea",
            "AXEditableText"
        ].contains(role)
    }

    func logBoardManPerformance(_ name: String, startedAt: CFAbsoluteTime, details: String = "") {
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        let suffix = details.isEmpty ? "" : " \(details)"
        log(String(format: "perf %@ %.1fms%@", name, elapsedMs, suffix))
    }

    private func startCGEventTap() {
        if !CGPreflightListenEventAccess() {
            let granted = CGRequestListenEventAccess()
            log("listen event access requested granted=\(granted)")
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            log("cg event tap failed listenEventTrusted=\(CGPreflightListenEventAccess())")
            return
        }

        eventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let eventTapSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            log("cg event tap started enabled=\(CGEvent.tapIsEnabled(tap: eventTap))")
        } else {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
            log("cg event tap source failed")
        }
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }

        let service = Unmanaged<PasteCountInputService>
            .fromOpaque(refcon)
            .takeUnretainedValue()

        if type == .tapDisabledByTimeout {
            service.reenableEventTap(reason: "tapDisabledByTimeout")
            return Unmanaged.passUnretained(event)
        }

        if type == .tapDisabledByUserInput {
            service.reenableEventTap(reason: "tapDisabledByUserInput")
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        service.handleCGEventKeyDown(event)

        return Unmanaged.passUnretained(event)
    }

    private func reenableEventTap(reason: String) {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        log("cg event tap reenabled reason=\(reason)")
    }

    private func handleNSEventKeyDown(_ event: NSEvent, source: String) {
        guard isCommandV(event) else { return }
        handleDetectedCommandV(source: source)
    }

    private func handleCGEventKeyDown(_ event: CGEvent) {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        guard keyCode == UInt16(kVK_ANSI_V) else { return }
        guard flags.contains(.maskCommand) else { return }
        guard !flags.contains(.maskControl), !flags.contains(.maskAlternate) else { return }

        handleDetectedCommandV(source: "cgEventTap")
    }

    private func handleDetectedCommandV(source: String) {
        let now = Date()
        guard now >= suppressUntil else {
            log("detected cmd+v source=\(source) suppressed=true")
            return
        }

        if now.timeIntervalSince(lastDetectedAt) < duplicateDetectionInterval {
            log("detected cmd+v source=\(source) duplicate=ignored")
            return
        }
        lastDetectedAt = now

        log("detected cmd+v source=\(source) scheduling_match_delay=\(pasteboardMatchDelay)")

        DispatchQueue.main.asyncAfter(deadline: .now() + pasteboardMatchDelay) { [weak self] in
            self?.countCurrentClipboardIfNeeded(source: source)
        }
    }

    private func isCommandV(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else { return false }
        guard !flags.contains(.option), !flags.contains(.control) else { return false }

        return event.keyCode == UInt16(kVK_ANSI_V)
    }

    private func countCurrentClipboardIfNeeded(source: String) {
        guard let pastedText = NSPasteboard.general.string(forType: .string)
            ?? NSPasteboard.general.string(forType: .deprecatedString),
              !pastedText.isEmpty else {
            log("matched clip key=no reason=empty_clipboard source=\(source)")
            return
        }

        let now = Date()
        if pastedText == lastCountedText,
           now.timeIntervalSince(lastCountedAt) < debounceInterval {
            log("matched clip key=no reason=debounced source=\(source)")
            return
        }

        guard let key = PasteCountStore.shared.keyForLatestClip(matching: pastedText) else {
            log("matched clip key=no source=\(source)")
            return
        }

        PasteCountStore.shared.increment(forKey: key)

        lastCountedText = pastedText
        lastCountedAt = now

        log("count increment success source=\(source) key=\(key)")
    }

    private func rotateLogIfNeeded() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path),
              let sizeNumber = attributes[.size] as? NSNumber,
              sizeNumber.uint64Value > maxLogSize else {
            return
        }

        guard let data = try? Data(contentsOf: logURL) else { return }
        let suffix = data.suffix(Int(maxLogSize / 2))
        try? Data(suffix).write(to: logURL)
    }

    private func log(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        rotateLogIfNeeded()

        if FileManager.default.fileExists(atPath: logURL.path) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            }
        } else {
            try? data.write(to: logURL)
        }
    }
}
