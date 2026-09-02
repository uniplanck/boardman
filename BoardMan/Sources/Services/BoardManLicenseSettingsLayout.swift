import AppKit

struct BoardManLicenseSettingsLayoutInput: Equatable {
    let originX: CGFloat
    let originY: CGFloat
    let width: CGFloat
    let controlHeight: CGFloat

    init(
        originX: CGFloat,
        originY: CGFloat,
        width: CGFloat,
        controlHeight: CGFloat = BoardManPanelLayoutMetrics.controlHeight
    ) {
        self.originX = originX
        self.originY = originY
        self.width = width
        self.controlHeight = controlHeight
    }
}

struct BoardManLicenseSettingsLayout: Equatable {
    let sectionHeaderFrame: NSRect
    let planFrame: NSRect
    let stateFrame: NSRect
    let limitsFrame: NSRect
    let keyFieldFrame: NSRect
    let activateFrame: NSRect
    let activationStatusFrame: NSRect
    let upgradeFrame: NSRect
    let proLockedFrame: NSRect
    let mockNoteFrame: NSRect
    let stateExamplesFrame: NSRect
}

enum BoardManLicenseSettingsLayoutPolicy {
    static func layout(_ input: BoardManLicenseSettingsLayoutInput) -> BoardManLicenseSettingsLayout {
        let buttonWidth: CGFloat = 106
        let upgradeWidth = min(126, input.width)
        let fieldWidth = max(120, input.width - buttonWidth - 12)
        return BoardManLicenseSettingsLayout(
            sectionHeaderFrame: NSRect(x: input.originX, y: input.originY, width: input.width, height: 18),
            planFrame: NSRect(x: input.originX, y: input.originY - 34, width: input.width, height: 18),
            stateFrame: NSRect(x: input.originX, y: input.originY - 58, width: input.width, height: 18),
            limitsFrame: NSRect(x: input.originX, y: input.originY - 82, width: input.width, height: 18),
            keyFieldFrame: NSRect(
                x: input.originX,
                y: input.originY - 124,
                width: fieldWidth,
                height: input.controlHeight
            ),
            activateFrame: NSRect(
                x: input.originX + fieldWidth + 12,
                y: input.originY - 126,
                width: buttonWidth,
                height: input.controlHeight
            ),
            activationStatusFrame: NSRect(x: input.originX, y: input.originY - 166, width: input.width, height: 34),
            upgradeFrame: NSRect(
                x: input.originX,
                y: input.originY - 208,
                width: upgradeWidth,
                height: input.controlHeight
            ),
            proLockedFrame: NSRect(x: input.originX, y: input.originY - 352, width: input.width, height: 126),
            mockNoteFrame: NSRect(x: input.originX, y: input.originY - 400, width: input.width, height: 42),
            stateExamplesFrame: NSRect(x: input.originX, y: input.originY - 436, width: input.width, height: 28)
        )
    }
}
