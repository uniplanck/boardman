import AppKit
import Testing
@testable import Board_Man

@MainActor @Suite(.serialized)
final class BoardManPrivacySettingsLayoutTests {
    @Test
    func storedTypesUseTwoBoundedColumns() {
        let layout = BoardManPrivacySettingsLayoutPolicy.layout(
            BoardManPrivacySettingsLayoutInput(
                originX: 24,
                originY: 680,
                width: 520,
                storedTypeCount: 6
            )
        )

        #expect(layout.storedTypeFrames.count == 6)
        #expect(layout.storedTypeFrames[0].minY == layout.storedTypeFrames[1].minY)
        #expect(layout.storedTypeFrames[2].minY < layout.storedTypeFrames[0].minY)
        #expect(layout.storedTypeFrames.allSatisfy { $0.minX >= 24 && $0.maxX <= 544 })
    }

    @Test
    func filterControlsStayOrderedAndInsideColumn() {
        let layout = BoardManPrivacySettingsLayoutPolicy.layout(
            BoardManPrivacySettingsLayoutInput(
                originX: 18,
                originY: 620,
                width: 420,
                storedTypeCount: 4
            )
        )

        #expect(layout.hideRuleModeFrame.minX == 18)
        #expect(layout.hideRuleTextFrame.minX > layout.hideRuleModeFrame.minX)
        #expect(layout.addHideRuleFrame.minX > layout.hideRuleTextFrame.minX)
        #expect(layout.addHideRuleFrame.maxX <= 438)
        #expect(layout.removeLastHideRuleFrame.minY == layout.clearHideRulesFrame.minY)
        #expect(layout.hideRulesNoteFrame.minY < layout.hideRulesExamplesFrame.minY)
    }

    @Test
    func privacySectionsReserveSpaceForSelectionClipboardControls() {
        let layout = BoardManPrivacySettingsLayoutPolicy.layout(
            BoardManPrivacySettingsLayoutInput(
                originX: 30,
                originY: 700,
                width: 500,
                storedTypeCount: 0
            )
        )

        #expect(layout.permissionsHeaderFrame.minY == 700)
        #expect(layout.permissionsStatusFrame.minY < layout.permissionsHeaderFrame.minY)
        #expect(layout.permissionsManageFrame.maxX <= 530)
        #expect(layout.privacyHeaderFrame.minY == 614)
        #expect(layout.selectionMemoryFrame.minY < layout.privacyHeaderFrame.minY)
        #expect(layout.selectionHarvestFrame.minY < layout.selectionMemoryFrame.minY)
        #expect(layout.selectionSequentialCaptureFrame.minY < layout.selectionHarvestFrame.minY)
        #expect(layout.selectionMemoryStatusFrame.minY < layout.selectionSequentialCaptureFrame.minY)
        #expect(layout.selectionMemoryOpenFrame.maxX < layout.selectionMemoryClearFrame.minX)
        #expect(layout.selectionMemoryClearFrame.maxX <= 530)
        #expect(layout.selectionPreviewEnabledFrame.minY < layout.selectionMemoryStatusFrame.minY)
        #expect(layout.selectionPreviewPositionFrame.minY < layout.selectionPreviewEnabledFrame.minY)
        #expect(layout.selectionPreviewStyleFrame.minY < layout.selectionPreviewPositionFrame.minY)
        #expect(layout.selectionMetadataPositionFrame.minY < layout.selectionPreviewStyleFrame.minY)
        #expect(layout.selectionAutoDeleteUsedFrame.minY < layout.selectionMetadataPositionFrame.minY)
        #expect(layout.hideMaskedPreviewFrame.minY < layout.selectionAutoDeleteUsedFrame.minY)
        #expect(layout.storedTypesHeaderFrame.minY == 92)
        #expect(layout.filterHeaderFrame.minY == 50)
        #expect(layout.excludedAppsButtonFrame.width <= 178)
        #expect(layout.storedTypeFrames.isEmpty)
    }

    @Test
    func permissionPolicyCoversFirstRunExistingUsersOptionalAccessAndRevocation() {
        let granted = BoardManPermissionSnapshot(accessibility: .granted, inputMonitoring: .granted)
        let requiredOnly = BoardManPermissionSnapshot(accessibility: .granted, inputMonitoring: .denied)
        let missingRequired = BoardManPermissionSnapshot(accessibility: .denied, inputMonitoring: .granted)

        #expect(BoardManPermissionKind.accessibility.isRequired)
        #expect(!BoardManPermissionKind.inputMonitoring.isRequired)
        #expect(BoardManPermissionLaunchPolicy.disposition(
            onboardingComplete: false,
            isExistingUser: false,
            snapshot: missingRequired
        ) == .onboarding)
        #expect(BoardManPermissionLaunchPolicy.disposition(
            onboardingComplete: false,
            isExistingUser: true,
            snapshot: granted
        ) == .continueNormally)
        #expect(BoardManPermissionLaunchPolicy.disposition(
            onboardingComplete: false,
            isExistingUser: true,
            snapshot: missingRequired
        ) == .repair)
        #expect(BoardManPermissionLaunchPolicy.disposition(
            onboardingComplete: true,
            isExistingUser: false,
            snapshot: requiredOnly
        ) == .continueNormally,
        "Optional Input Monitoring must not block Board-Man startup.")
        #expect(BoardManPermissionLaunchPolicy.disposition(
            onboardingComplete: true,
            isExistingUser: false,
            snapshot: missingRequired
        ) == .repair,
        "Revoking required Accessibility after onboarding must enter repair state.")
    }

    @Test
    func permissionStoreModelsNotDeterminedDeniedGrantedAndPersistenceWithoutTouchingTCC() throws {
        let suiteName = "BoardManPermissionOnboardingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BoardManPermissionOnboardingStore(defaults: defaults)

        #expect(store.state(for: .accessibility, granted: false) == .notDetermined)
        store.markRequestAttempted(for: .accessibility)
        #expect(store.state(for: .accessibility, granted: false) == .denied)
        #expect(store.state(for: .accessibility, granted: true) == .granted)
        #expect(store.state(for: .inputMonitoring, granted: false) == .notDetermined)
        #expect(!store.isComplete)

        store.markComplete()
        let reloaded = BoardManPermissionOnboardingStore(defaults: defaults)
        #expect(reloaded.isComplete)
        #expect(defaults.integer(forKey: Constants.UserDefaults.boardManPermissionOnboardingVersion)
                == BoardManPermissionOnboardingStore.currentVersion)
    }

    @Test
    func privacyLayoutKeepsAllControlsAboveBottomSafeArea() {
        let layout = BoardManPrivacySettingsLayoutPolicy.layout(
            BoardManPrivacySettingsLayoutInput(
                originX: 24,
                originY: 980,
                width: 520,
                storedTypeCount: 6
            )
        )
        let frames = [
            layout.permissionsHeaderFrame,
            layout.permissionsStatusFrame,
            layout.permissionsManageFrame,
            layout.selectionMemoryFrame,
            layout.selectionHarvestFrame,
            layout.selectionSequentialCaptureFrame,
            layout.selectionMemoryStatusFrame,
            layout.selectionMemoryOpenFrame,
            layout.selectionMemoryClearFrame,
            layout.selectionPreviewEnabledFrame,
            layout.selectionPreviewPositionLabelFrame,
            layout.selectionPreviewPositionFrame,
            layout.selectionPreviewStyleLabelFrame,
            layout.selectionPreviewStyleFrame,
            layout.selectionMetadataPositionLabelFrame,
            layout.selectionMetadataPositionFrame,
            layout.selectionAutoDeleteUsedFrame,
            layout.hideMaskedPreviewFrame,
            layout.hideMaskedTitleFrame,
            layout.excludedAppsSummaryFrame,
            layout.excludedAppsButtonFrame,
            layout.storedTypesHeaderFrame,
            layout.filterHeaderFrame,
            layout.hideRuleModeFrame,
            layout.hideRuleTextFrame,
            layout.addHideRuleFrame,
            layout.removeLastHideRuleFrame,
            layout.clearHideRulesFrame,
            layout.hideRulesSummaryFrame,
            layout.hideRulesExamplesFrame,
            layout.hideRulesNoteFrame
        ] + layout.storedTypeFrames

        #expect(frames.allSatisfy { $0.minY >= 80 })
        #expect(layout.selectionMemoryStatusFrame.maxX < layout.selectionMemoryOpenFrame.minX)
        let storedBottom = layout.storedTypeFrames.map(\.minY).min() ?? .greatestFiniteMagnitude
        #expect(layout.filterHeaderFrame.maxY < storedBottom)
    }
}
