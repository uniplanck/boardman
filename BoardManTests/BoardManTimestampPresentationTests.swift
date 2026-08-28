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
    func freeUsesStandardRelativeStyleWithoutDeletingLifetimePreferences() throws {
        let suiteName = "BoardManRelativeTimestampCommercialGateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(BoardManRelativeNumberStyle.twoDigits.rawValue,
                     forKey: Constants.UserDefaults.boardManRelativeNumberStyle)
        defaults.set(BoardManRelativeUnitStyle.full.rawValue,
                     forKey: Constants.UserDefaults.boardManRelativeUnitStyle)
        defaults.set(BoardManRelativeSuffixStyle.ago.rawValue,
                     forKey: Constants.UserDefaults.boardManRelativeSuffixStyle)
        defaults.set(BoardManRelativeNowStyle.now.rawValue,
                     forKey: Constants.UserDefaults.boardManRelativeNowStyle)

        let freeStyle = BoardManRelativeTimestampStyle.current(
            defaults: defaults,
            entitlementService: EntitlementService(snapshot: .freeDefault)
        )
        #expect(freeStyle.number == .single)
        #expect(freeStyle.unit == .symbol)
        #expect(freeStyle.suffix == .none)
        #expect(freeStyle.now == .localized)

        #expect(defaults.string(forKey: Constants.UserDefaults.boardManRelativeNumberStyle) == "twoDigits")
        #expect(defaults.string(forKey: Constants.UserDefaults.boardManRelativeUnitStyle) == "full")
        #expect(defaults.string(forKey: Constants.UserDefaults.boardManRelativeSuffixStyle) == "ago")
        #expect(defaults.string(forKey: Constants.UserDefaults.boardManRelativeNowStyle) == "now")

        let verifiedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let metadata = LicenseMetadata(
            licenseKeyMasked: "••••-TEST",
            deviceIdMasked: "••••-DEVICE",
            activatedAt: verifiedAt,
            lastVerifiedAt: verifiedAt,
            status: LicenseState.ownerLifetime.rawValue,
            licenseKind: .ownerLifetime,
            issuedTo: "test-owner"
        )
        let lifetimeStyle = BoardManRelativeTimestampStyle.current(
            defaults: defaults,
            entitlementService: EntitlementService(snapshot: .ownerLifetime(metadata: metadata))
        )
        #expect(lifetimeStyle.number == .twoDigits)
        #expect(lifetimeStyle.unit == .full)
        #expect(lifetimeStyle.suffix == .ago)
        #expect(lifetimeStyle.now == .now)
    }

    @Test
    func timestampShortcutDelayIsBounded() {
        #expect(BoardManTimestampPresentation.clampedShortcutDelay(-1) == 0)
        #expect(BoardManTimestampPresentation.clampedShortcutDelay(0.1) == 0.1)
        #expect(BoardManTimestampPresentation.clampedShortcutDelay(120) == 60)
    }
}
