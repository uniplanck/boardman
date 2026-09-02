import Cocoa
import Testing
@testable import Board_Man

@Suite
struct BoardManPanelAppearanceTests {
    @Test
    func appearanceAndStyleValidationFallbacksStayDeterministic() {
        #expect(BoardManAppearanceMode.allowed(nil) == .system)
        #expect(BoardManAppearanceMode.allowed("Light") == .light)
        #expect(BoardManAppearanceMode.allowed("invalid") == .system)
        #expect(BoardManAppearanceMode.light.appearance?.name == .aqua)
        #expect(BoardManAppearanceMode.dark.appearance?.name == .darkAqua)

        #expect(BoardManUIStyle.allowed("Simple") == .simple)
        #expect(BoardManUIStyle.allowed("invalid") == .defaultStyle)
    }

    @Test
    func fontAndThemePoliciesRemainFocusedAndBounded() {
        #expect(BoardManFontChoice.allowed(nil) == .system)
        #expect(BoardManFontChoice.allowed("Rounded") == .rounded)
        #expect(BoardManFontChoice.allowed("definitely-not-an-installed-font") == .system)

        #expect(BoardManThemePreset.allowed(nil) == .defaultPreset)
        #expect(BoardManThemePreset.allowed("Ocean") == .ocean)
        #expect(BoardManThemePreset.allowed("invalid") == .defaultPreset)
        #expect(abs(BoardManThemePreset.ocean.panelTintColor(useLiquidGlass: true).alphaComponent - 0.15) < 0.001)
        #expect(abs(BoardManThemePreset.ocean.panelTintColor(useLiquidGlass: true, lighten: true).alphaComponent - 0.08) < 0.001)
    }
}
