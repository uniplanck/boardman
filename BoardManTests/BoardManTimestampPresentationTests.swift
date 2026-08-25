import Foundation
import Testing
@testable import Board_Man

@Suite
struct BoardManTimestampPresentationTests {
    @Test
    func formatValidationAndMenuMappingAreDeterministic() {
        #expect(BoardManTimestampPresentation.allowedFormat("relative") == "relative")
        #expect(BoardManTimestampPresentation.allowedFormat("HH:mm:ss") == "HH:mm:ss")
        #expect(BoardManTimestampPresentation.allowedFormat("not-a-format") == "none")
        #expect(BoardManTimestampPresentation.allowedFormat(nil) == "none")

        #expect(BoardManTimestampPresentation.menuTitle(for: "relative") == "Relative")
        #expect(BoardManTimestampPresentation.menuTitle(for: "HH:mm") == "24-hour")
        #expect(BoardManTimestampPresentation.menuTitle(for: "none") == "Hidden")
        #expect(BoardManTimestampPresentation.format(forMenuTitle: "Relative") == "relative")
        #expect(BoardManTimestampPresentation.format(forMenuTitle: "12-hour + seconds") == "h:mm:ss a")
        #expect(BoardManTimestampPresentation.format(forMenuTitle: "Unknown") == "none")
    }

    @Test
    func absoluteAndRelativeTextUseTheFocusedTimestampOwner() {
        let timestamp = 1_700_000_000
        let now = Date(timeIntervalSince1970: TimeInterval(timestamp + 3_600))
        let relativeStyle = BoardManRelativeTimestampStyle(
            number: .single,
            unit: .symbol,
            suffix: .none,
            now: .now
        )
        #expect(
            BoardManTimestampPresentation.text(
                for: timestamp,
                format: "relative",
                relativeStyle: relativeStyle,
                now: now
            ) == "1h"
        )

        let utc = Locale(identifier: "en_US_POSIX")
        let rendered = BoardManTimestampPresentation.text(
            for: timestamp,
            format: "yyyy/MM/dd HH:mm",
            now: now,
            locale: utc
        )
        #expect(!rendered.isEmpty)
        #expect(BoardManTimestampPresentation.text(for: timestamp, format: "none", now: now).isEmpty)
    }

    @Test
    func timestampShortcutDelayIsBounded() {
        #expect(BoardManTimestampPresentation.clampedShortcutDelay(-1) == 0)
        #expect(BoardManTimestampPresentation.clampedShortcutDelay(0.1) == 0.1)
        #expect(BoardManTimestampPresentation.clampedShortcutDelay(120) == 60)
    }
}
