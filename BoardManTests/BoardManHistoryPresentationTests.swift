import Testing
@testable import Board_Man

@Suite
struct BoardManHistoryPresentationTests {
    @Test
    func usageFilterPresentationPreservesDefaults() {
        #expect(BoardManHistoryUsageFilter.allowed(nil) == .all)
        #expect(BoardManHistoryUsageFilter.allowed("Unused") == .unused)
        #expect(BoardManHistoryUsageFilter.allowed("invalid") == .all)
        #expect(BoardManHistoryUsageFilter.used.symbolName == "checkmark.circle.fill")
        #expect(BoardManHistoryUsageFilter.unused.toolTip.contains("Command+V"))
    }

    @Test
    func pinAndInlineImagePresentationStayCompatible() {
        #expect(BoardManPinLabelStyle.allowed("p") == .compact)
        #expect(BoardManPinLabelStyle.off.badgeTitle.isEmpty)
        #expect(BoardManPinLabelStyle.full.badgeTitle == "PIN")
        #expect(BoardManPinLabelStyle.allowed("invalid") == .full)

        #expect(BoardManInlineImagePosition.allowed("left") == .left)
        #expect(BoardManInlineImagePosition.allowed("RIGHT") == .right)
        #expect(BoardManInlineImagePosition.allowed(nil) == .right)
    }
}
