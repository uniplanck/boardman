// 
//  AccessibilityService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
// 
//  Created by Econa77 on 2018/10/03.
// 
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import Cocoa

final class AccessibilityService {
    private var hasShownBoardManPermissionAlertThisLaunch = false
}

// MARK: - Permission
extension AccessibilityService {
    @discardableResult
    func isAccessibilityEnabled(isPrompt: Bool) -> Bool {
        // Accessibility permission is required for paste command from macOS 10.14 Mojave.
        // For macOS 10.14 and later only, check accessibility permission at startup and paste
        guard #available(macOS 10.14, *) else { return true }

        guard isPrompt else {
            return AXIsProcessTrusted()
        }

        let checkOptionPromptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [checkOptionPromptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    func isListenEventAccessEnabled() -> Bool {
        return CGPreflightListenEventAccess()
    }

    func logPermissionStatus(context: String) {
        NSLog(
            "Board-Man permission status context=%@ accessibilityTrusted=%@ listenEventAccess=%@",
            context,
            isAccessibilityEnabled(isPrompt: false).description,
            isListenEventAccessEnabled().description
        )
    }

    func showAccessibilityAuthenticationAlert() {
        guard !BoardManRuntimeEnvironment.isRunningTests() else {
            NSLog("Board-Man permission alert suppressed reason=test_process")
            return
        }
        logPermissionStatus(context: "permission-alert-check")
        guard !isAccessibilityEnabled(isPrompt: false) || !isListenEventAccessEnabled() else { return }
        guard !hasShownBoardManPermissionAlertThisLaunch else {
            NSLog("Board-Man permission alert suppressed reason=already_shown_this_launch")
            return
        }
        hasShownBoardManPermissionAlertThisLaunch = true

        let alert = NSAlert()
        alert.messageText = "Board-Manに権限が必要です"
        alert.informativeText = "/Applications/Board-Man.app をアクセシビリティと入力監視に追加してONにしてください。ONに見えても効かない場合は、一度削除してから追加し直してください。"
        alert.icon = NSApplication.shared.applicationIconImage
        alert.addButton(withTitle: String(localized: "システム設定を開く"))
        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn {
            if !isAccessibilityEnabled(isPrompt: false) {
                // Register this exact signed app with TCC first, then open the matching settings pane.
                _ = isAccessibilityEnabled(isPrompt: true)
                _ = openAccessibilitySettingWindow()
                return
            }
            if !isListenEventAccessEnabled() {
                _ = openInputMonitoringSettingWindow()
            }
        }
    }

    func openAccessibilitySettingWindow() -> Bool {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return false }
        return NSWorkspace.shared.open(url)
    }

    func openInputMonitoringSettingWindow() -> Bool {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return false }
        return NSWorkspace.shared.open(url)
    }
}

// MARK: - Permission onboarding

enum BoardManPermissionKind: String, CaseIterable, Equatable {
    case accessibility
    case inputMonitoring

    var isRequired: Bool {
        self == .accessibility
    }

    var stepNumber: Int {
        self == .accessibility ? 1 : 2
    }

    var title: String {
        switch self {
        case .accessibility:
            return boardManPermissionText("Accessibility", ja: "アクセシビリティ")
        case .inputMonitoring:
            return boardManPermissionText("Input Monitoring", ja: "入力監視")
        }
    }

    var detail: String {
        switch self {
        case .accessibility:
            return boardManPermissionText(
                "Required for direct paste, focus restoration, and Selection Clipboard access.",
                ja: "直接貼り付け、貼り付け先の復元、選択コピーの読み取りに必要です。"
            )
        case .inputMonitoring:
            return boardManPermissionText(
                "Optional. Improves fallback global shortcut and paste-event monitoring reliability.",
                ja: "任意です。グローバルショートカットの予備経路と貼り付け監視の安定性を高めます。"
            )
        }
    }
}

enum BoardManPermissionState: Equatable {
    case notDetermined
    case denied
    case granted
}

struct BoardManPermissionSnapshot: Equatable {
    let accessibility: BoardManPermissionState
    let inputMonitoring: BoardManPermissionState

    func state(for kind: BoardManPermissionKind) -> BoardManPermissionState {
        switch kind {
        case .accessibility: return accessibility
        case .inputMonitoring: return inputMonitoring
        }
    }

    var allRequiredGranted: Bool {
        accessibility == .granted
    }
}

enum BoardManPermissionLaunchDisposition: Equatable {
    case onboarding
    case repair
    case continueNormally
}

enum BoardManPermissionLaunchPolicy {
    static func disposition(
        onboardingComplete: Bool,
        isExistingUser: Bool,
        snapshot: BoardManPermissionSnapshot
    ) -> BoardManPermissionLaunchDisposition {
        if onboardingComplete {
            return snapshot.allRequiredGranted ? .continueNormally : .repair
        }
        if isExistingUser {
            return snapshot.allRequiredGranted ? .continueNormally : .repair
        }
        return .onboarding
    }
}

struct BoardManPermissionOnboardingStore {
    static let currentVersion = 1

    let defaults: UserDefaults

    var isComplete: Bool {
        defaults.integer(forKey: Constants.UserDefaults.boardManPermissionOnboardingVersion) >= Self.currentVersion
    }

    func markComplete() {
        defaults.set(Self.currentVersion, forKey: Constants.UserDefaults.boardManPermissionOnboardingVersion)
    }

    func state(for kind: BoardManPermissionKind, granted: Bool) -> BoardManPermissionState {
        if granted { return .granted }
        let attemptedKey = kind == .accessibility
            ? Constants.UserDefaults.boardManAccessibilityPermissionRequested
            : Constants.UserDefaults.boardManInputMonitoringRequestFlag
        return defaults.bool(forKey: attemptedKey) ? .denied : .notDetermined
    }

    func markRequestAttempted(for kind: BoardManPermissionKind) {
        let attemptedKey = kind == .accessibility
            ? Constants.UserDefaults.boardManAccessibilityPermissionRequested
            : Constants.UserDefaults.boardManInputMonitoringRequestFlag
        defaults.set(true, forKey: attemptedKey)
    }
}

@MainActor
final class BoardManPermissionOnboardingCoordinator {
    static let shared = BoardManPermissionOnboardingCoordinator()

    private let defaults: UserDefaults
    private let accessibilityService: AccessibilityService
    private var setupWindowController: BoardManPermissionSetupWindowController?

    init(
        defaults: UserDefaults? = nil,
        accessibilityService: AccessibilityService? = nil
    ) {
        self.defaults = defaults ?? AppEnvironment.current.defaults
        self.accessibilityService = accessibilityService ?? AppEnvironment.current.accessibilityService
    }

    var store: BoardManPermissionOnboardingStore {
        BoardManPermissionOnboardingStore(defaults: defaults)
    }

    func currentSnapshot() -> BoardManPermissionSnapshot {
        BoardManPermissionSnapshot(
            accessibility: store.state(
                for: .accessibility,
                granted: accessibilityService.isAccessibilityEnabled(isPrompt: false)
            ),
            inputMonitoring: store.state(
                for: .inputMonitoring,
                granted: accessibilityService.isListenEventAccessEnabled()
            )
        )
    }

    func launchDisposition(isExistingUser: Bool) -> BoardManPermissionLaunchDisposition {
        let snapshot = currentSnapshot()
        let disposition = BoardManPermissionLaunchPolicy.disposition(
            onboardingComplete: store.isComplete,
            isExistingUser: isExistingUser,
            snapshot: snapshot
        )
        if disposition == .continueNormally, isExistingUser, !store.isComplete {
            // Existing users with the required permission already granted are migrated silently.
            store.markComplete()
        }
        return disposition
    }

    func request(_ kind: BoardManPermissionKind) {
        store.markRequestAttempted(for: kind)
        switch kind {
        case .accessibility:
            // AXIsProcessTrustedWithOptions is Apple's public mechanism for creating/prompting
            // the Accessibility TCC entry for this exact signed app.
            _ = accessibilityService.isAccessibilityEnabled(isPrompt: true)
            _ = accessibilityService.openAccessibilitySettingWindow()
        case .inputMonitoring:
            if #available(macOS 10.15, *) {
                // Apple's public request API creates the Input Monitoring TCC entry when needed.
                _ = CGRequestListenEventAccess()
            }
            _ = accessibilityService.openInputMonitoringSettingWindow()
        }
    }

    func openSettings(for kind: BoardManPermissionKind) {
        switch kind {
        case .accessibility:
            _ = accessibilityService.openAccessibilitySettingWindow()
        case .inputMonitoring:
            _ = accessibilityService.openInputMonitoringSettingWindow()
        }
    }

    func permissionSummaryText() -> String {
        let snapshot = currentSnapshot()
        func stateText(_ state: BoardManPermissionState) -> String {
            state == .granted
                ? boardManPermissionText("Allowed", ja: "許可済み")
                : boardManPermissionText("Not allowed", ja: "未許可")
        }
        return "\(BoardManPermissionKind.accessibility.title): \(stateText(snapshot.accessibility))  ·  "
            + "\(BoardManPermissionKind.inputMonitoring.title): \(stateText(snapshot.inputMonitoring))"
    }

    func presentRequiredOnboarding(onComplete: @escaping () -> Void) {
        present(mode: .firstRun, onComplete: onComplete)
    }

    func presentSettings() {
        present(mode: .settings, onComplete: nil)
    }

    func presentRepair() {
        present(mode: .repair, onComplete: nil)
    }

    private func present(
        mode: BoardManPermissionSetupWindowController.Mode,
        onComplete: (() -> Void)?
    ) {
        if let existing = setupWindowController {
            existing.updateMode(mode, onComplete: onComplete)
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = BoardManPermissionSetupWindowController(
            coordinator: self,
            mode: mode,
            onComplete: onComplete
        )
        setupWindowController = controller
        controller.onDismiss = { [weak self] in
            self?.setupWindowController = nil
        }
        controller.showWindow(nil)
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class BoardManPermissionSetupRowView: NSView {
    let kind: BoardManPermissionKind
    var actionHandler: ((BoardManPermissionKind) -> Void)?

    private let iconView = NSImageView(frame: .zero)
    private let stepLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let stateLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton(title: "", target: nil, action: nil)

    init(kind: BoardManPermissionKind) {
        self.kind = kind
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        if #available(macOS 11.0, *) {
            let symbol = kind == .accessibility ? "hand.raised.fill" : "keyboard.badge.ellipsis"
            iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: kind.title)
            iconView.contentTintColor = .controlAccentColor
        }
        addSubview(iconView)

        stepLabel.translatesAutoresizingMaskIntoConstraints = false
        stepLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        stepLabel.textColor = .secondaryLabelColor
        stepLabel.stringValue = boardManPermissionText(
            "STEP \(kind.stepNumber) · \(kind.isRequired ? "REQUIRED" : "OPTIONAL")",
            ja: "STEP \(kind.stepNumber) · \(kind.isRequired ? "必須" : "任意")"
        )
        addSubview(stepLabel)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.stringValue = kind.title
        addSubview(titleLabel)

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = NSFont.systemFont(ofSize: 11.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2
        detailLabel.stringValue = kind.detail
        addSubview(detailLabel)

        stateLabel.translatesAutoresizingMaskIntoConstraints = false
        stateLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        stateLabel.alignment = .center
        stateLabel.wantsLayer = true
        stateLabel.layer?.cornerRadius = 8
        stateLabel.layer?.masksToBounds = true
        stateLabel.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(stateLabel)

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.target = self
        actionButton.action = #selector(actionPressed(_:))
        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .small
        actionButton.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(actionButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 84),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 30),
            iconView.heightAnchor.constraint(equalToConstant: 30),

            stepLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            stepLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            titleLabel.leadingAnchor.constraint(equalTo: stepLabel.leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: stepLabel.bottomAnchor, constant: 3),
            detailLabel.leadingAnchor.constraint(equalTo: stepLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: stateLabel.leadingAnchor, constant: -14),
            detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6),

            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            actionButton.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 15),
            actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 84),
            stateLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            stateLabel.bottomAnchor.constraint(equalTo: actionButton.topAnchor, constant: -6),
            stateLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 68),
            stateLabel.heightAnchor.constraint(equalToConstant: 19)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(state: BoardManPermissionState) {
        switch state {
        case .granted:
            stateLabel.stringValue = boardManPermissionText("✓ Allowed", ja: "✓ 許可済み")
            stateLabel.textColor = .systemGreen
            stateLabel.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.10).cgColor
            actionButton.title = boardManPermissionText("Open Settings", ja: "設定を開く")
        case .notDetermined:
            stateLabel.stringValue = boardManPermissionText("Not set", ja: "未設定")
            stateLabel.textColor = .secondaryLabelColor
            stateLabel.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.08).cgColor
            actionButton.title = boardManPermissionText("Allow", ja: "許可する")
        case .denied:
            stateLabel.stringValue = boardManPermissionText("Not allowed", ja: "未許可")
            stateLabel.textColor = .systemOrange
            stateLabel.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.10).cgColor
            actionButton.title = boardManPermissionText("Open Settings", ja: "設定を開く")
        }
    }

    @objc private func actionPressed(_ sender: NSButton) {
        actionHandler?(kind)
    }
}

@MainActor
private final class BoardManPermissionSetupWindowController: NSWindowController, NSWindowDelegate {
    enum Mode: Equatable {
        case firstRun
        case repair
        case settings
    }

    private let coordinator: BoardManPermissionOnboardingCoordinator
    private var mode: Mode
    private var completionHandler: (() -> Void)?
    private var rows: [BoardManPermissionKind: BoardManPermissionSetupRowView] = [:]
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    private let readinessLabel = NSTextField(labelWithString: "")
    private let finishButton = NSButton(title: "", target: nil, action: nil)
    private var appActivationObserver: NSObjectProtocol?
    private var pollTimer: Timer?
    private var pollDeadline: Date?
    var onDismiss: (() -> Void)?

    init(
        coordinator: BoardManPermissionOnboardingCoordinator,
        mode: Mode,
        onComplete: (() -> Void)?
    ) {
        self.coordinator = coordinator
        self.mode = mode
        self.completionHandler = onComplete
        super.init(window: nil)
        window = buildWindow()
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let appActivationObserver {
            NotificationCenter.default.removeObserver(appActivationObserver)
        }
        pollTimer?.invalidate()
    }

    func updateMode(_ mode: Mode, onComplete: (() -> Void)?) {
        self.mode = mode
        self.completionHandler = onComplete
        configureMode()
        refresh()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        configureMode()
        refresh()
        startBoundedPolling()
    }

    func windowWillClose(_ notification: Notification) {
        pollTimer?.invalidate()
        pollTimer = nil
        onDismiss?()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        mode != .firstRun || coordinator.currentSnapshot().allRequiredGranted
    }

    private func buildWindow() -> NSWindow {
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .fullSizeContentView]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 438),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = "Board-Man"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 560, height: 410)

        let root = NSVisualEffectView(frame: window.contentView?.bounds ?? .zero)
        root.translatesAutoresizingMaskIntoConstraints = false
        root.material = .underWindowBackground
        root.blendingMode = .behindWindow
        root.state = .active
        window.contentView = root

        let appIcon = NSImageView(frame: .zero)
        appIcon.translatesAutoresizingMaskIntoConstraints = false
        appIcon.image = NSApplication.shared.applicationIconImage
        appIcon.imageScaling = .scaleProportionallyDown
        root.addSubview(appIcon)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        root.addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = NSFont.systemFont(ofSize: 12.5)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 2
        root.addSubview(subtitleLabel)

        let stack = NSStackView(frame: .zero)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        root.addSubview(stack)

        for kind in BoardManPermissionKind.allCases {
            if !stack.arrangedSubviews.isEmpty {
                let separator = NSBox(frame: .zero)
                separator.boxType = .separator
                separator.translatesAutoresizingMaskIntoConstraints = false
                stack.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            let row = BoardManPermissionSetupRowView(kind: kind)
            row.actionHandler = { [weak self] kind in
                guard let self else { return }
                let state = self.coordinator.currentSnapshot().state(for: kind)
                if state == .granted {
                    self.coordinator.openSettings(for: kind)
                } else {
                    self.coordinator.request(kind)
                }
                self.startBoundedPolling()
                self.refresh()
            }
            rows[kind] = row
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        readinessLabel.translatesAutoresizingMaskIntoConstraints = false
        readinessLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        readinessLabel.textColor = .secondaryLabelColor
        root.addSubview(readinessLabel)

        finishButton.translatesAutoresizingMaskIntoConstraints = false
        finishButton.target = self
        finishButton.action = #selector(finishPressed(_:))
        finishButton.bezelStyle = .rounded
        finishButton.keyEquivalent = "\r"
        root.addSubview(finishButton)

        NSLayoutConstraint.activate([
            appIcon.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            appIcon.topAnchor.constraint(equalTo: root.topAnchor, constant: 44),
            appIcon.widthAnchor.constraint(equalToConstant: 46),
            appIcon.heightAnchor.constraint(equalToConstant: 46),

            titleLabel.leadingAnchor.constraint(equalTo: appIcon.trailingAnchor, constant: 14),
            titleLabel.topAnchor.constraint(equalTo: appIcon.topAnchor, constant: 1),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -30),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),

            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            stack.topAnchor.constraint(equalTo: appIcon.bottomAnchor, constant: 18),

            readinessLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            readinessLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -27),
            readinessLabel.trailingAnchor.constraint(lessThanOrEqualTo: finishButton.leadingAnchor, constant: -18),
            finishButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            finishButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -22),
            finishButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 132)
        ])

        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                self?.startBoundedPolling()
            }
        }
        return window
    }

    private func configureMode() {
        let firstRun = mode == .firstRun
        let repair = mode == .repair
        titleLabel.stringValue = firstRun
            ? boardManPermissionText("Initial Setup", ja: "初期セットアップ")
            : repair
                ? boardManPermissionText("Permission Needs Attention", ja: "権限の修復が必要です")
                : boardManPermissionText("Permissions", ja: "権限")
        subtitleLabel.stringValue = repair
            ? boardManPermissionText(
                "A required macOS permission is no longer available. Board-Man remains open while you restore it.",
                ja: "必須のmacOS権限が解除されています。Board-Manは開いたまま、ここから権限を修復できます。"
            )
            : boardManPermissionText(
                "Board-Man uses macOS permissions only where required. You stay in control of every switch in System Settings.",
                ja: "Board-Manが必要とするmacOS権限を確認します。許可そのものはシステム設定でユーザーが行います。"
            )
        finishButton.title = firstRun
            ? boardManPermissionText("Start Board-Man", ja: "Board-Manを開始")
            : boardManPermissionText("Close", ja: "閉じる")
        window?.standardWindowButton(.closeButton)?.isHidden = firstRun
    }

    private func refresh() {
        let snapshot = coordinator.currentSnapshot()
        for (kind, row) in rows {
            row.update(state: snapshot.state(for: kind))
        }
        if snapshot.allRequiredGranted {
            if snapshot.inputMonitoring == .granted {
                readinessLabel.stringValue = boardManPermissionText(
                    "✓ Board-Man is ready.",
                    ja: "✓ Board-Manの準備ができました"
                )
            } else {
                readinessLabel.stringValue = boardManPermissionText(
                    "✓ Core setup complete. Input Monitoring can be enabled later.",
                    ja: "✓ 基本設定は完了です。入力監視はあとから設定できます。"
                )
            }
        } else {
            readinessLabel.stringValue = boardManPermissionText(
                "Accessibility is required before Board-Man can start.",
                ja: "Board-Manを開始するにはアクセシビリティの許可が必要です。"
            )
        }
        finishButton.isEnabled = mode != .firstRun || snapshot.allRequiredGranted
    }

    private func startBoundedPolling() {
        pollDeadline = Date().addingTimeInterval(30)
        if pollTimer != nil { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else {
                    timer.invalidate()
                    return
                }
                self.refresh()
                guard let deadline = self.pollDeadline, Date() < deadline, self.window?.isVisible == true else {
                    timer.invalidate()
                    self.pollTimer = nil
                    return
                }
            }
        }
    }

    @objc private func finishPressed(_ sender: NSButton) {
        let snapshot = coordinator.currentSnapshot()
        if mode == .firstRun {
            guard snapshot.allRequiredGranted else {
                NSSound.beep()
                return
            }
            coordinator.store.markComplete()
        }
        let completion = completionHandler
        completionHandler = nil
        close()
        completion?()
    }
}

private func boardManPermissionText(_ english: String, ja japanese: String) -> String {
    let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
    return preferred.hasPrefix("ja") ? japanese : english
}
