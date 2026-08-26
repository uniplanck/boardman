import AppKit
import Testing
@testable import Board_Man

@Suite
struct BoardManClipDataColorTests {
    @Test
    func nativeHexParserPreservesSupportedSwiftHEXColorsFormats() throws {
        try assertColor("#D4A", red: 0xDD, green: 0x44, blue: 0xAA, alpha: 0xFF)
        try assertColor("78A2", red: 0x77, green: 0x88, blue: 0xAA, alpha: 0x22)
        try assertColor("#81DAB9", red: 0x81, green: 0xDA, blue: 0xB9, alpha: 0xFF)
        try assertColor("81DAB9CC", red: 0x81, green: 0xDA, blue: 0xB9, alpha: 0xCC)
        try assertColor("490d87", red: 0x49, green: 0x0D, blue: 0x87, alpha: 0xFF)
    }

    @Test
    func nativeHexParserRejectsTheSameMalformedShapes() {
        #expect(BoardManClipData.color(fromHexString: "") == nil)
        #expect(BoardManClipData.color(fromHexString: "#FFFFF") == nil)
        #expect(BoardManClipData.color(fromHexString: "#FFF&FF") == nil)
        #expect(BoardManClipData.color(fromHexString: "GGGGGG") == nil)
        #expect(BoardManClipData.color(fromHexString: " #FFFFFF") == nil)
    }

    private func assertColor(
        _ value: String,
        red: Int,
        green: Int,
        blue: Int,
        alpha: Int
    ) throws {
        let color = try #require(BoardManClipData.color(fromHexString: value))
        let rgb = try #require(color.usingColorSpace(.deviceRGB))
        #expect(abs(rgb.redComponent - CGFloat(red) / 255.0) < 0.001)
        #expect(abs(rgb.greenComponent - CGFloat(green) / 255.0) < 0.001)
        #expect(abs(rgb.blueComponent - CGFloat(blue) / 255.0) < 0.001)
        #expect(abs(rgb.alphaComponent - CGFloat(alpha) / 255.0) < 0.001)
    }
}
