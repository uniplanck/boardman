//
//  PasteCountInputService.swift
//  Board-Man
//

import AppKit
import Carbon
import RealmSwift

struct PasteTargetSnapshot {
    let processIdentifier: pid_t
    let role: String
    let valueFingerprint: Int?
    let selectedTextFingerprint: Int?
    let selectedRange: CFRange?
    let numberOfCharacters: Int?
    let childrenCount: Int?
}

enum PasteTargetVerifier {
    private static let verificationDelays: [TimeInterval] = [0.16, 0.38, 0.70]

    static func snapshot(for application: NSRunningApplication?) -> PasteTargetSnapshot? {
        guard AXIsProcessTrusted(), let application else { return nil }
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        var focusedObject: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedObject
        ) == .success,
        let focusedObject else {
            return nil
        }

        let focusedElement = focusedObject as! AXUIElement // swiftlint:disable:this force_cast
        guard isEditable(element: focusedElement) else { return nil }
        return snapshot(of: focusedElement, processIdentifier: application.processIdentifier)
    }

    static func confirmChange(from snapshot: PasteTargetSnapshot,
                              delayIndex: Int = 0,
                              completion: @escaping (Bool) -> Void) {
        guard delayIndex < verificationDelays.count else {
            completion(false)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + verificationDelays[delayIndex]) {
            let application = NSRunningApplication(processIdentifier: snapshot.processIdentifier)
            if let current = self.snapshot(for: application), changed(from: snapshot, to: current) {
                completion(true)
                return
            }
            confirmChange(from: snapshot, delayIndex: delayIndex + 1, completion: completion)
        }
    }

    static func changed(from before: PasteTargetSnapshot, to after: PasteTargetSnapshot) -> Bool {
        guard before.processIdentifier == after.processIdentifier else { return false }
        if let lhs = before.valueFingerprint, let rhs = after.valueFingerprint, lhs != rhs { return true }
        if let lhs = before.selectedTextFingerprint, let rhs = after.selectedTextFingerprint, lhs != rhs { return true }
        if let lhs = before.selectedRange, let rhs = after.selectedRange,
           lhs.location != rhs.location || lhs.length != rhs.length { return true }
        if let lhs = before.numberOfCharacters, let rhs = after.numberOfCharacters, lhs != rhs { return true }
        if let lhs = before.childrenCount, let rhs = after.childrenCount, lhs != rhs { return true }
        return false
    }

    private static func isEditable(element: AXUIElement) -> Bool {
        let role = stringAttribute(kAXRoleAttribute, from: element) ?? ""
        let subrole = stringAttribute(kAXSubroleAttribute, from: element) ?? ""
        if boolAttribute("AXEditable", from: element) == true { return true }
        let editableRoles: Set<String> = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String,
            "AXEditableText"
        ]
        if editableRoles.contains(role) { return true }
        return role == "AXWebArea" && subrole == "AXEditableWebArea"
    }

    private static func snapshot(of element: AXUIElement, processIdentifier: pid_t) -> PasteTargetSnapshot {
        return PasteTargetSnapshot(
            processIdentifier: processIdentifier,
            role: stringAttribute(kAXRoleAttribute, from: element) ?? "",
            valueFingerprint: attributeFingerprint(kAXValueAttribute, from: element),
            selectedTextFingerprint: attributeFingerprint(kAXSelectedTextAttribute, from: element),
            selectedRange: rangeAttribute(kAXSelectedTextRangeAttribute, from: element),
            numberOfCharacters: numberAttribute("AXNumberOfCharacters", from: element),
            childrenCount: arrayCountAttribute(kAXChildrenAttribute, from: element)
        )
    }

    private static func attributeFingerprint(_ attribute: String, from element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
        return String(describing: value).hashValue
    }

    private static func rangeAttribute(_ attribute: String, from element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue // swiftlint:disable:this force_cast
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        return AXValueGetValue(axValue, .cfRange, &range) ? range : nil
    }

    private static func numberAttribute(_ attribute: String, from element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.intValue
    }

    private static func arrayCountAttribute(_ attribute: String, from element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? [Any])?.count
    }

    private static func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func boolAttribute(_ attribute: String, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }
}

enum PasteCountEventTapMode: Equatable {
    case listenOnly
    case accessibilityFallback

    var options: CGEventTapOptions {
        switch self {
        case .listenOnly: return .listenOnly
        case .accessibilityFallback: return .defaultTap
        }
    }
}

final class PasteCountInputService {
    static let shared = PasteCountInputService()

    static func eventTapMode(accessibilityTrusted: Bool, listenEventAccess: Bool) -> PasteCountEventTapMode? {
        if listenEventAccess { return .listenOnly }
        if accessibilityTrusted { return .accessibilityFallback }
        return nil
    }

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var eventTapRunLoop: CFRunLoop?
    private var appDidBecomeActiveObserver: NSObjectProtocol?
    private var isMonitoringStarted = false
    private var isStartingEventTap = false
    private var suppressUntil = Date.distantPast
    private var lastCountedIdentity: String?
    private var lastCountedAt = Date.distantPast
    private var lastDetectedAt = Date.distantPast
    private let sequentialPasteLock = NSLock()
    private var pendingSequentialHashes = Set<String>()
    private let debounceInterval: TimeInterval = 0.45
    private let duplicateDetectionInterval: TimeInterval = 0.12
    private let boardManPasteSuppressionInterval: TimeInterval = 0.35
    private let pasteboardMatchDelay: TimeInterval = 0.15
    private let monitorInstallDelay: TimeInterval = 0.30
    private let eventTapStartDelay: TimeInterval = 1.75
    private let maxLogSize: UInt64 = 128 * 1024
    private let logQueue = DispatchQueue(label: "com.uniplanck.BoardMan.PasteCountInputService.log", qos: .utility)
    private let logURL: URL

    private init() {
        let logDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Board-Man", isDirectory: true)
        self.logURL = logDirectory.appendingPathComponent("paste-count-input.log")
        log("service initialized logFile=\(logURL.path)")
    }

    func startMonitoring() {
        guard !isMonitoringStarted else {
            log("startMonitoring skipped reason=already_started")
            return
        }
        isMonitoringStarted = true
        log("startMonitoring attempted")

        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.logPermissionStatus(context: "startMonitoring")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + monitorInstallDelay) { [weak self] in
            guard let self else { return }
            self.installAppDidBecomeActiveRetryIfNeeded()

            if self.globalMonitor == nil {
                self.globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    self?.handleNSEventKeyDown(event, source: "global")
                }
                self.log(self.globalMonitor == nil ? "nsevent global monitor unavailable" : "nsevent global monitor active")
            } else {
                self.log("nsevent global monitor already_active")
            }

            if self.localMonitor == nil {
                self.localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    self?.handleNSEventKeyDown(event, source: "local")
                    return event
                }
                self.log(self.localMonitor == nil ? "nsevent local monitor unavailable" : "nsevent local monitor active")
            } else {
                self.log("nsevent local monitor already_active")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + self.eventTapStartDelay) { [weak self] in
                self?.startCGEventTap(reason: "startMonitoringDeferred")
            }
        }
    }

    func stopMonitoring() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let eventTapSource, let eventTapRunLoop {
            CFRunLoopRemoveSource(eventTapRunLoop, eventTapSource, .commonModes)
            CFRunLoopStop(eventTapRunLoop)
            CFRunLoopWakeUp(eventTapRunLoop)
        }
        globalMonitor = nil
        localMonitor = nil
        eventTap = nil
        eventTapSource = nil
        eventTapRunLoop = nil
        isStartingEventTap = false
        if let appDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(appDidBecomeActiveObserver)
        }
        appDidBecomeActiveObserver = nil
    }

    private func startCGEventTap(reason: String) {
        if let eventTap {
            log("cg event tap already_active enabled=\(CGEvent.tapIsEnabled(tap: eventTap)) reason=\(reason)")
            return
        }
        guard !isStartingEventTap else {
            log("cg event tap start skipped reason=already_starting trigger=\(reason)")
            return
        }
        isStartingEventTap = true
        log("cg event tap start scheduled reason=\(reason)")

        Thread { [weak self] in
            self?.createAndRunCGEventTap(reason: reason)
        }.start()
    }

    private func createAndRunCGEventTap(reason: String) {
        autoreleasepool {
            // Manual paste tracking is intentionally limited to keyboard events.
            // Prefer a listen-only tap when Input Monitoring is granted. When it is not,
            // fall back to an accessibility-authorized pass-through tap and return every
            // event unchanged. This keeps Cmd+V counting functional with the permission
            // Board-Man already requires for paste automation.
            let accessibilityTrusted = AXIsProcessTrusted()
            let listenEventAccess = CGPreflightListenEventAccess()
            guard let mode = Self.eventTapMode(
                accessibilityTrusted: accessibilityTrusted,
                listenEventAccess: listenEventAccess
            ) else {
                DispatchQueue.main.async { [weak self] in
                    self?.isStartingEventTap = false
                    self?.log("cg event tap skipped reason=permission_missing trigger=\(reason)")
                }
                return
            }

            let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)

            let candidateLocations: [CGEventTapLocation] = mode == .listenOnly
                ? [.cgSessionEventTap]
                : [.cgSessionEventTap, .cgAnnotatedSessionEventTap]
            var selectedLocation: CGEventTapLocation?
            var createdTap: CFMachPort?
            for location in candidateLocations {
                if let tap = CGEvent.tapCreate(
                    tap: location,
                    place: .tailAppendEventTap,
                    options: mode.options,
                    eventsOfInterest: mask,
                    callback: Self.eventTapCallback,
                    userInfo: Unmanaged.passUnretained(self).toOpaque()
                ) {
                    selectedLocation = location
                    createdTap = tap
                    break
                }
            }

            guard let tap = createdTap else {
                DispatchQueue.main.async { [weak self] in
                    self?.isStartingEventTap = false
                    self?.log("cg event tap failed accessibilityTrusted=\(AXIsProcessTrusted()) listenEventAccess=\(CGPreflightListenEventAccess())")
                    AppEnvironment.current.accessibilityService.showAccessibilityAuthenticationAlert()
                }
                return
            }

            guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
                CGEvent.tapEnable(tap: tap, enable: false)
                DispatchQueue.main.async { [weak self] in
                    self?.isStartingEventTap = false
                    self?.log("cg event tap source failed")
                }
                return
            }

            let runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)

            DispatchQueue.main.async { [weak self] in
                self?.eventTap = tap
                self?.eventTapSource = source
                self?.eventTapRunLoop = runLoop
                self?.isStartingEventTap = false
                let locationText = selectedLocation.map { String($0.rawValue) } ?? "none"
                self?.log("cg event tap started mode=\(mode) location=\(locationText) enabled=\(CGEvent.tapIsEnabled(tap: tap)) trigger=\(reason)")
            }

            CFRunLoopRun()

            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
    }

    private func installAppDidBecomeActiveRetryIfNeeded() {
        guard appDidBecomeActiveObserver == nil else { return }
        appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.retryEventTapIfNeeded(reason: "appDidBecomeActive")
        }
    }

    private func retryEventTapIfNeeded(reason: String) {
        guard eventTap == nil else {
            log("cg event tap retry skipped reason=already_active trigger=\(reason)")
            return
        }
        startCGEventTap(reason: reason)
    }

    private func logPermissionStatus(context: String) {
        log("permission status context=\(context) accessibilityTrusted=\(AXIsProcessTrusted()) listenEventAccess=\(CGPreflightListenEventAccess())")
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
        log("cg event tap reenabled reason=\(reason) enabled=\(CGEvent.tapIsEnabled(tap: eventTap))")
    }

    private func handleNSEventKeyDown(_ event: NSEvent, source: String) {
        guard isCommandV(event) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.handleDetectedCommandV(source: source)
        }
    }

    private func handleCGEventKeyDown(_ event: CGEvent) {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        guard keyCode == UInt16(kVK_ANSI_V) else { return }
        guard flags.contains(.maskCommand) else { return }
        guard !flags.contains(.maskControl), !flags.contains(.maskAlternate) else { return }

        if prepareSequentialUnusedPasteIfNeeded() {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.handleDetectedCommandV(source: "cgEventTap")
        }
    }

    private func prepareSequentialUnusedPasteIfNeeded() -> Bool {
        let defaults = AppEnvironment.current.defaults
        guard defaults.string(forKey: Constants.UserDefaults.boardManHistoryUsageFilter) == "Unused" else {
            return false
        }
        guard let targetApplication = NSWorkspace.shared.frontmostApplication,
              targetApplication.bundleIdentifier != Bundle.main.bundleIdentifier,
              let targetSnapshot = editableTargetSnapshot(for: targetApplication) else {
            return false
        }

        let realm = try! Realm()
        let counts = PasteCountStore.shared.countsSnapshot()
        sequentialPasteLock.lock()
        let pending = pendingSequentialHashes
        sequentialPasteLock.unlock()
        let clips = realm.objects(CPYClip.self)
            .sorted(byKeyPath: #keyPath(CPYClip.createdTime), ascending: false)
        guard let clip = clips.first(where: {
            !pending.contains($0.dataHash) && PasteCountStore.shared.count(for: $0, in: counts) == 0
        }) else {
            log("unused sequence skipped reason=empty_queue")
            return false
        }

        let dataHash = clip.dataHash
        let pasteCountKey = PasteCountStore.shared.key(for: clip)
        sequentialPasteLock.lock()
        pendingSequentialHashes.insert(dataHash)
        sequentialPasteLock.unlock()

        AppEnvironment.current.pasteService.copyToPasteboard(with: clip)
        suppressUntil = Date().addingTimeInterval(1.0)
        log("unused sequence prepared hash=redacted")

        confirmPasteChange(from: targetSnapshot) { [weak self] confirmed in
            guard let self else { return }
            self.sequentialPasteLock.lock()
            self.pendingSequentialHashes.remove(dataHash)
            self.sequentialPasteLock.unlock()
            guard confirmed else {
                self.log("unused sequence confirmation failed")
                return
            }
            let confirmationRealm = try! Realm()
            if let confirmedClip = confirmationRealm.object(ofType: CPYClip.self, forPrimaryKey: dataHash) {
                PasteCountStore.shared.markUsed(clip: confirmedClip, in: confirmationRealm)
            }
            PasteCountStore.shared.increment(forKey: pasteCountKey)
            self.log("unused sequence confirmation success")
        }
        return true
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

        let focusedTarget = focusedPasteTargetCheck()
        guard focusedTarget.isEditable else {
            log("detected cmd+v source=\(source) editable_target=false reason=\(focusedTarget.reason)")
            return
        }

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

    private func focusedPasteTargetCheck() -> (isEditable: Bool, reason: String) {
        guard AXIsProcessTrusted() else {
            return (false, "accessibility_untrusted")
        }
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return (false, "frontmost_app_unavailable")
        }
        guard editableTargetSnapshot(for: application) != nil else {
            return (false, "focused_element_not_editable")
        }
        return (true, "editable_target")
    }

    private func countCurrentClipboardIfNeeded(source: String) {
        let pasteboard = NSPasteboard.general
        let text = pasteboard.string(forType: .string)
            ?? pasteboard.string(forType: .deprecatedString)
        let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage

        let identity: String
        let lookupKey: () -> String?
        if let text, !text.isEmpty {
            identity = "text:\(text)"
            lookupKey = { PasteCountStore.shared.keyForLatestClip(matching: text) }
        } else if let image,
                  let fingerprint = PasteCountStore.imageFingerprint(for: image) {
            identity = "image:\(fingerprint)"
            lookupKey = { PasteCountStore.shared.keyForLatestImageClip(matching: image) }
        } else {
            log("matched clip key=no reason=unsupported_clipboard source=\(source)")
            return
        }

        let now = Date()
        if identity == lastCountedIdentity,
           now.timeIntervalSince(lastCountedAt) < debounceInterval {
            log("matched clip key=no reason=debounced source=\(source)")
            return
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let key = lookupKey() else {
                self?.log("matched clip key=no source=\(source)")
                return
            }

            DispatchQueue.main.async { [weak self] in
                PasteCountStore.shared.increment(forKey: key)
                self?.lastCountedIdentity = identity
                self?.lastCountedAt = now
                self?.log("count increment success source=\(source) key=\(key)")
            }
        }
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
        logQueue.async { [logURL] in
            try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            self.rotateLogIfNeeded()

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
}

extension PasteCountInputService {
    func editableTargetSnapshot(
        for application: NSRunningApplication? = NSWorkspace.shared.frontmostApplication
    ) -> PasteTargetSnapshot? {
        return PasteTargetVerifier.snapshot(for: application)
    }

    func confirmPasteChange(from snapshot: PasteTargetSnapshot,
                            completion: @escaping (Bool) -> Void) {
        PasteTargetVerifier.confirmChange(from: snapshot, completion: completion)
    }

    static func pasteTargetChanged(from before: PasteTargetSnapshot,
                                   to after: PasteTargetSnapshot) -> Bool {
        return PasteTargetVerifier.changed(from: before, to: after)
    }

    func suppressNextGlobalPaste() {
        suppressUntil = Date().addingTimeInterval(boardManPasteSuppressionInterval)
        log("suppress next global paste")
    }

    func logBoardManPerformance(_ name: String,
                                startedAt: CFAbsoluteTime,
                                details: String = "") {
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        let suffix = details.isEmpty ? "" : " \(details)"
        log(String(format: "perf %@ %.1fms%@", name, elapsedMs, suffix))
    }
}
