import StoreKitTest
import XCTest
@testable import Mise

@MainActor
final class StoreKitConfigurationTests: XCTestCase {
    private var session: SKTestSession!

    override func setUpWithError() throws {
        let configurationURL = try XCTUnwrap(
            Bundle(for: StoreKitConfigurationTests.self).url(forResource: "Products", withExtension: "storekit")
        )
        session = try SKTestSession(contentsOf: configurationURL)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.timeRate = .realTime
        session.clearTransactions()
    }

    override func tearDownWithError() throws {
        session.clearTransactions()
        session = nil
    }

    func testConfigurationLoadsBothSubscriptionsAtExpectedPrices() async throws {
        let manager = makeManager()
        await manager.refreshProducts()

        XCTAssertNil(manager.errorMessage)
        XCTAssertEqual(manager.products.count, 2)
        XCTAssertEqual(manager.products.first?.id, SubscriptionProductID.yearly)

        let monthly = try XCTUnwrap(manager.monthlyProduct)
        let yearly = try XCTUnwrap(manager.yearlyProduct)
        XCTAssertEqual(monthly.price, Decimal(string: "3.99"))
        XCTAssertEqual(yearly.price, Decimal(string: "19.99"))
        XCTAssertEqual(monthly.subscription?.subscriptionPeriod.unit, .month)
        XCTAssertEqual(yearly.subscription?.subscriptionPeriod.unit, .year)
    }

    func testPurchasingMonthlyUnlocksPremium() async throws {
        let manager = makeManager()
        await manager.refreshProducts()
        let monthly = try XCTUnwrap(manager.monthlyProduct)

        await manager.purchase(monthly)

        XCTAssertTrue(manager.isPremium, manager.errorMessage ?? "Expected a verified entitlement")
        XCTAssertEqual(manager.activeProductID, SubscriptionProductID.monthly)
        XCTAssertNil(manager.errorMessage)
    }

    private func makeManager() -> SubscriptionManager {
        let suite = "MiseStoreKit-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
        }
        return SubscriptionManager(defaults: defaults)
    }
}
