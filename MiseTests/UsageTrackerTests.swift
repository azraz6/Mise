import XCTest
@testable import Mise

@MainActor
final class UsageTrackerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "MiseUsage-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    func testFreeImportAllowance() {
        let now = date(year: 2026, month: 10, day: 15)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let tracker = UsageTracker(defaults: defaults, calendar: calendar, now: { now })

        XCTAssertEqual(tracker.remainingFreeImports, FreeTier.automaticImportsPerMonth)
        for index in 1...FreeTier.automaticImportsPerMonth {
            tracker.recordAutomaticImport(isPremium: false)
            XCTAssertEqual(tracker.remainingFreeImports, FreeTier.automaticImportsPerMonth - index)
        }
        XCTAssertFalse(tracker.canStartAutomaticImport(isPremium: false))
        XCTAssertTrue(tracker.canStartAutomaticImport(isPremium: true))
    }

    func testPremiumImportsAreNotRecorded() {
        let fixed = date(year: 2026, month: 10, day: 15)
        let tracker = UsageTracker(defaults: defaults, now: { fixed })
        tracker.recordAutomaticImport(isPremium: true)
        XCTAssertEqual(tracker.automaticImportsThisMonth, 0)
        XCTAssertEqual(tracker.remainingFreeImports, FreeTier.automaticImportsPerMonth)
    }

    func testAllowanceResetsInNewMonth() {
        var now = date(year: 2026, month: 10, day: 31)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let tracker = UsageTracker(defaults: defaults, calendar: calendar, now: { now })

        for _ in 0..<FreeTier.automaticImportsPerMonth {
            tracker.recordAutomaticImport(isPremium: false)
        }
        XCTAssertFalse(tracker.canStartAutomaticImport(isPremium: false))

        now = date(year: 2026, month: 11, day: 1)
        XCTAssertEqual(tracker.currentMonthKey, "2026-11")
        XCTAssertTrue(tracker.canStartAutomaticImport(isPremium: false))
        XCTAssertEqual(tracker.remainingFreeImports, FreeTier.automaticImportsPerMonth)
    }

    func testCollectionLimit() {
        let tracker = UsageTracker(defaults: defaults)
        XCTAssertTrue(tracker.canCreateCollection(existingCount: 0, isPremium: false))
        XCTAssertTrue(tracker.canCreateCollection(existingCount: FreeTier.collections - 1, isPremium: false))
        XCTAssertFalse(tracker.canCreateCollection(existingCount: FreeTier.collections, isPremium: false))
        XCTAssertTrue(tracker.canCreateCollection(existingCount: 99, isPremium: true))
    }

    func testMonthKeyFormatting() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(UsageTracker.monthKey(for: date(year: 2026, month: 1, day: 4), calendar: calendar), "2026-01")
        XCTAssertEqual(UsageTracker.monthKey(for: date(year: 2026, month: 12, day: 31), calendar: calendar), "2026-12")
    }
}
