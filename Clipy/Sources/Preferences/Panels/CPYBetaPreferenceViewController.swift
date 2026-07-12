//
//  CPYBetaPreferenceViewController.swift
//  Clipy
//

// swiftlint:disable identifier_name function_parameter_count line_length
import Cocoa

final class CPYBetaPreferenceViewController: NSViewController {
    private let licenseField = NSSecureTextField(string: "")
    private let validationLabel = BoardManPreferenceUI.label("Not connected yet", size: 12, color: BoardManPreferenceUI.secondaryText)
    private let planLabel = BoardManPreferenceUI.label("Free Plan", size: 28, weight: .bold)
    private let statusPill = BoardManPreferenceUI.label("Free", size: 12, weight: .semibold)
    private let currentPlanValue = BoardManPreferenceUI.label("Free Plan", size: 12, weight: .semibold)
    private let statusValue = BoardManPreferenceUI.label("Free", size: 12, weight: .semibold)
    private let lastVerifiedValue = BoardManPreferenceUI.label("Not verified / Offline", size: 12, weight: .semibold, color: BoardManPreferenceUI.red)
    private let deviceStatus = BoardManPreferenceUI.label("Not activated", size: 12, color: BoardManPreferenceUI.secondaryText)

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1180, height: 620))
        view.wantsLayer = true
        view.layer?.backgroundColor = BoardManPreferenceUI.base.cgColor
        buildLicenseView()
        refreshPlanState()
    }

    private func buildLicenseView() {
        addHeaderTabsHint()
        let currentPlan = card(x: 30, y: 320, w: 350, h: 250, title: "1. Current Plan", icon: "crown")
        currentPlan.addSubview(planLabel)
        planLabel.frame = NSRect(x: 20, y: 155, width: 190, height: 36)
        statusPill.frame = NSRect(x: 20, y: 118, width: 70, height: 24)
        BoardManPreferenceUI.prepare(statusPill, color: BoardManPreferenceUI.card, radius: 12, border: BoardManPreferenceUI.borderSubtle)
        currentPlan.addSubview(statusPill)
        currentPlan.addSubview(statusRow("tag", "Current Plan:", currentPlanValue, y: 92))
        currentPlan.addSubview(statusRow("checkmark.seal", "Status:", statusValue, y: 66))
        currentPlan.addSubview(statusRow("clock", "Last verified:", lastVerifiedValue, y: 40))
        currentPlan.addSubview(statusRow("laptopcomputer", "Device activated:", deviceStatus, y: 14))
        let upgrade = BoardManPreferenceUI.secondaryButton("Upgrade to Pro  ›")
        upgrade.target = self
        upgrade.action = #selector(openBuyPro)
        upgrade.frame = NSRect(x: 200, y: 150, width: 130, height: 38)
        upgrade.layer?.borderColor = BoardManPreferenceUI.red.withAlphaComponent(0.8).cgColor
        currentPlan.addSubview(upgrade)
        view.addSubview(currentPlan)

        let activation = card(x: 395, y: 320, w: 405, h: 250, title: "2. License Key Activation", icon: "key")
        licenseField.placeholderString = "License activation is not connected yet"
        licenseField.font = NSFont.systemFont(ofSize: 14)
        licenseField.textColor = BoardManPreferenceUI.primaryText
        licenseField.backgroundColor = BoardManPreferenceUI.field
        licenseField.isEnabled = false
        licenseField.toolTip = "License activation is a disabled preview in this build."
        licenseField.frame = NSRect(x: 20, y: 165, width: 365, height: 38)
        activation.addSubview(licenseField)
        let activate = BoardManPreferenceUI.primaryButton("Activate License")
        activate.target = self
        activate.action = #selector(activateLicense)
        activate.isEnabled = false
        activate.toolTip = "Activation is not connected yet."
        activate.frame = NSRect(x: 20, y: 115, width: 165, height: 38)
        activation.addSubview(activate)
        let paste = BoardManPreferenceUI.secondaryButton("Paste from Clipboard")
        paste.target = self
        paste.action = #selector(pasteLicense)
        paste.isEnabled = false
        paste.toolTip = "License input is disabled until activation is implemented."
        paste.frame = NSRect(x: 195, y: 115, width: 190, height: 38)
        activation.addSubview(paste)
        activation.addSubview(BoardManPreferenceUI.label("Validation status:", size: 13, color: BoardManPreferenceUI.secondaryText).positioned(x: 20, y: 78, w: 130, h: 20))
        validationLabel.frame = NSRect(x: 150, y: 78, width: 220, height: 20)
        activation.addSubview(validationLabel)
        let empty = BoardManPreferenceUI.label("No license has been activated. Activation is not connected in this build.", size: 13, color: BoardManPreferenceUI.secondaryText)
        empty.alignment = .center
        empty.frame = NSRect(x: 20, y: 18, width: 365, height: 44)
        BoardManPreferenceUI.prepare(empty, color: BoardManPreferenceUI.field, radius: BoardManPreferenceUI.Radius.control, border: BoardManPreferenceUI.borderSubtle)
        activation.addSubview(empty)
        view.addSubview(activation)

        let device = card(x: 820, y: 320, w: 330, h: 250, title: "3. Device Binding", icon: "laptopcomputer")
        device.addSubview(row("Device name:", Host.current().localizedName ?? "This Mac", y: 165))
        device.addSubview(row("Masked Device ID:", "Not activated", y: 132))
        device.addSubview(row("Activated at:", "—", y: 99))
        device.addSubview(BoardManPreferenceUI.label("1 license = 1 PC. Device binding is not connected in this build.", size: 13, color: BoardManPreferenceUI.secondaryText).positioned(x: 20, y: 58, w: 285, h: 38))
        let deactivate = BoardManPreferenceUI.secondaryButton("Deactivate this device")
        deactivate.isEnabled = false
        deactivate.frame = NSRect(x: 20, y: 20, width: 290, height: 30)
        device.addSubview(deactivate)
        view.addSubview(device)

        let features = card(x: 30, y: 40, w: 770, h: 250, title: "4. Pro Features", icon: "diamond")
        let names = [("infinity", "Unlimited History", "Keep every clipboard item forever."), ("doc.text", "Unlimited Snippets", "Create and save unlimited snippets."), ("paintbrush", "Advanced Appearance", "Themes, accents, and fine-tuned styling."), ("arrow.up.arrow.down", "Export / Import", "Backup, migrate, and sync your data."), ("chart.bar", "Paste Analytics", "Insights into clipboard usage."), ("icloud", "Future Sync", "Sync across devices later.")]
        for (i, item) in names.enumerated() {
            let x = 20 + (i % 3) * 250
            let y = i < 3 ? 105 : 20
            features.addSubview(featureCard(symbol: item.0, title: item.1, body: item.2, x: CGFloat(x), y: CGFloat(y)))
        }
        view.addSubview(features)

        let cta = card(x: 820, y: 40, w: 330, h: 250, title: "", icon: "diamond")
        cta.layer?.borderColor = BoardManPreferenceUI.red.withAlphaComponent(0.9).cgColor
        cta.addSubview(BoardManPreferenceUI.icon("diamond.fill", size: 34).positioned(x: 143, y: 190, w: 44, h: 36))
        cta.addSubview(BoardManPreferenceUI.label("Unlock the full power of Board-Man", size: 17, weight: .bold).positioned(x: 45, y: 150, w: 250, h: 26))
        cta.addSubview(BoardManPreferenceUI.label("1 license = 1 PC\nPro unlocks advanced controls", size: 14, color: BoardManPreferenceUI.primaryText).positioned(x: 60, y: 95, w: 220, h: 46))
        let buy = BoardManPreferenceUI.primaryButton("Buy Board-Man Pro  ›")
        buy.target = self
        buy.action = #selector(openBuyPro)
        buy.frame = NSRect(x: 25, y: 64, width: 280, height: 36)
        cta.addSubview(buy)
        let manage = BoardManPreferenceUI.secondaryButton("Manage License  ›")
        manage.target = self
        manage.action = #selector(openManageLicense)
        manage.frame = NSRect(x: 25, y: 25, width: 280, height: 30)
        cta.addSubview(manage)
        view.addSubview(cta)
    }

    private func refreshPlanState() {
        let snapshot = EntitlementGate.currentSnapshot()
        let active = snapshot.isProEntitled
        let isOwnerLifetime = snapshot.licenseState == .ownerLifetime && snapshot.plan == .ownerLifetime
        let planName = isOwnerLifetime ? "Owner Lifetime" : (active ? "Board-Man Pro" : "Free Plan")
        let statusName = isOwnerLifetime ? "Lifetime" : (active ? "Active" : "Free")
        planLabel.stringValue = planName
        statusPill.stringValue = statusName
        statusPill.layer?.backgroundColor = (active ? BoardManPreferenceUI.redSoft : BoardManPreferenceUI.card).cgColor
        currentPlanValue.stringValue = planName
        statusValue.stringValue = statusName
        lastVerifiedValue.stringValue = active ? "Verified" : "Not verified / Offline"
        lastVerifiedValue.textColor = active ? .systemGreen : BoardManPreferenceUI.red
        deviceStatus.stringValue = active ? "Activated" : "Not activated"
        deviceStatus.textColor = active ? .systemGreen : BoardManPreferenceUI.secondaryText
        validationLabel.stringValue = isOwnerLifetime ? "Signed owner token required" : (active ? "Activated" : "Not connected yet")
        validationLabel.textColor = active ? .systemGreen : BoardManPreferenceUI.secondaryText
    }

    private func card(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, title: String, icon: String) -> NSView {
        let card = NSView(frame: NSRect(x: x, y: y, width: w, height: h))
        BoardManPreferenceUI.prepare(card, color: BoardManPreferenceUI.panel, radius: BoardManPreferenceUI.Radius.panel, border: BoardManPreferenceUI.borderNormal)
        if !title.isEmpty {
            card.addSubview(BoardManPreferenceUI.icon(icon, size: 16).positioned(x: 18, y: h - 42, w: 24, h: 24))
            card.addSubview(BoardManPreferenceUI.label(title, size: 15, weight: .semibold).positioned(x: 50, y: h - 42, w: w - 70, h: 24))
        }
        return card
    }

    private func row(_ left: String, _ right: String, y: CGFloat) -> NSView {
        let row = NSView(frame: NSRect(x: 20, y: y, width: 290, height: 20))
        row.addSubview(BoardManPreferenceUI.label(left, size: 13, color: BoardManPreferenceUI.secondaryText).positioned(x: 0, y: 0, w: 145, h: 20))
        row.addSubview(BoardManPreferenceUI.label(right, size: 13, weight: .semibold).positioned(x: 150, y: 0, w: 140, h: 20))
        return row
    }

    private func statusRow(_ symbol: String, _ left: String, _ value: NSTextField, y: CGFloat) -> NSView {
        let row = NSView(frame: NSRect(x: 20, y: y, width: 310, height: 20))
        row.addSubview(BoardManPreferenceUI.icon(symbol, size: 13, color: BoardManPreferenceUI.secondaryText).positioned(x: 0, y: 0, w: 18, h: 18))
        row.addSubview(BoardManPreferenceUI.label(left, size: 12, color: BoardManPreferenceUI.secondaryText).positioned(x: 28, y: 0, w: 115, h: 20))
        value.frame = NSRect(x: 145, y: 0, width: 160, height: 20)
        row.addSubview(value)
        return row
    }

    private func featureCard(symbol: String, title: String, body: String, x: CGFloat, y: CGFloat) -> NSView {
        let card = NSView(frame: NSRect(x: x, y: y, width: 225, height: 70))
        BoardManPreferenceUI.prepare(card, color: BoardManPreferenceUI.card, radius: BoardManPreferenceUI.Radius.card, border: BoardManPreferenceUI.borderSubtle)
        card.addSubview(BoardManPreferenceUI.icon(symbol, size: 21).positioned(x: 14, y: 20, w: 32, h: 32))
        card.addSubview(BoardManPreferenceUI.label(title, size: 13, weight: .semibold).positioned(x: 58, y: 38, w: 130, h: 18))
        card.addSubview(BoardManPreferenceUI.label(body, size: 11, color: BoardManPreferenceUI.secondaryText).positioned(x: 58, y: 12, w: 135, h: 26))
        card.addSubview(BoardManPreferenceUI.lockedBadge().positioned(x: 193, y: 39, w: 22, h: 22))
        return card
    }

    private func addHeaderTabsHint() {
        view.addSubview(BoardManPreferenceUI.label("License", size: 22, weight: .bold).positioned(x: 30, y: 585, w: 160, h: 26))
        view.addSubview(BoardManPreferenceUI.label("Free is useful. Pro removes daily limits and unlocks advanced customization.", size: 13, color: BoardManPreferenceUI.secondaryText).positioned(x: 30, y: 562, w: 520, h: 18))
    }

    @objc private func pasteLicense() {
        validationLabel.stringValue = "Activation is not connected yet."
        validationLabel.textColor = BoardManPreferenceUI.secondaryText
    }

    @objc private func activateLicense() {
        validationLabel.stringValue = "Activation is not connected yet."
        validationLabel.textColor = BoardManPreferenceUI.secondaryText
    }

    @objc private func openBuyPro() {
        BoardManUpgradeRoute.openProPage()
    }

    @objc private func openManageLicense() {
        NSWorkspace.shared.open(URL(string: "https://uniplanck.com/board-man/license")!)
    }
}

private extension NSView {
    func positioned(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> Self {
        frame = NSRect(x: x, y: y, width: w, height: h)
        return self
    }
}
