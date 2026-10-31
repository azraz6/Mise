import XCTest
@testable import Mise

@MainActor
final class EntitlementTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testActiveEntitlementWithoutExpiration() {
        XCTAssertTrue(EntitlementEvaluator.isActive(expirationDate: nil, revocationDate: nil, now: now))
    }

    func testFutureExpirationIsActive() {
        XCTAssertTrue(EntitlementEvaluator.isActive(
            expirationDate: now.addingTimeInterval(3_600),
            revocationDate: nil,
            now: now
        ))
    }

    func testExpiredEntitlementIsInactive() {
        XCTAssertFalse(EntitlementEvaluator.isActive(
            expirationDate: now.addingTimeInterval(-1),
            revocationDate: nil,
            now: now
        ))
    }

    func testRevokedEntitlementIsInactiveEvenWithFutureExpiration() {
        XCTAssertFalse(EntitlementEvaluator.isActive(
            expirationDate: now.addingTimeInterval(86_400),
            revocationDate: now,
            now: now
        ))
    }

    func testCacheRequiresKnownFutureExpiration() {
        let active = PremiumEntitlementCache(
            productID: SubscriptionProductID.yearly,
            expirationDate: now.addingTimeInterval(86_400),
            verifiedAt: now
        )
        let expired = PremiumEntitlementCache(
            productID: SubscriptionProductID.monthly,
            expirationDate: now.addingTimeInterval(-86_400),
            verifiedAt: now
        )
        let noExpiration = PremiumEntitlementCache(
            productID: SubscriptionProductID.monthly,
            expirationDate: nil,
            verifiedAt: now
        )
        XCTAssertTrue(EntitlementEvaluator.cachedIsActive(active, now: now))
        XCTAssertFalse(EntitlementEvaluator.cachedIsActive(expired, now: now))
        XCTAssertFalse(EntitlementEvaluator.cachedIsActive(noExpiration, now: now))
        XCTAssertFalse(EntitlementEvaluator.cachedIsActive(nil, now: now))
    }

    func testSubscriptionManagerRestoresActiveCachedEntitlement() throws {
        let suite = "MiseEntitlement-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let cache = PremiumEntitlementCache(
            productID: SubscriptionProductID.yearly,
            expirationDate: Date().addingTimeInterval(86_400),
            verifiedAt: Date()
        )
        defaults.set(try JSONEncoder().encode(cache), forKey: "com.mise.premiumEntitlementCache.v1")

        let manager = SubscriptionManager(defaults: defaults)
        XCTAssertTrue(manager.isPremium)
        XCTAssertEqual(manager.activeProductID, SubscriptionProductID.yearly)
        XCTAssertEqual(manager.activePlanLabel, "Mise Premium · Annual")
    }

    func testSubscriptionManagerIgnoresExpiredCache() throws {
        let suite = "MiseEntitlement-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let cache = PremiumEntitlementCache(
            productID: SubscriptionProductID.monthly,
            expirationDate: Date().addingTimeInterval(-86_400),
            verifiedAt: Date().addingTimeInterval(-172_800)
        )
        defaults.set(try JSONEncoder().encode(cache), forKey: "com.mise.premiumEntitlementCache.v1")

        let manager = SubscriptionManager(defaults: defaults)
        XCTAssertFalse(manager.isPremium)
        XCTAssertNil(manager.activeProductID)
        XCTAssertEqual(manager.activePlanLabel, "Free")
    }

    func testProductIdentifiersMatchStoreKitConfiguration() {
        XCTAssertEqual(SubscriptionProductID.monthly, "com.elahitech.mise.premium.monthly")
        XCTAssertEqual(SubscriptionProductID.yearly, "com.elahitech.mise.premium.yearly")
        XCTAssertEqual(SubscriptionProductID.all.count, 2)
    }
}
