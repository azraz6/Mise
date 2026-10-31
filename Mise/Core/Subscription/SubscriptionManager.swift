import Foundation
import StoreKit
import Observation

enum SubscriptionProductID {
    static let monthly = "com.elahitech.mise.premium.monthly"
    static let yearly = "com.elahitech.mise.premium.yearly"
    static let all = [monthly, yearly]
}

struct PremiumEntitlementCache: Codable, Equatable {
    var productID: String
    var expirationDate: Date?
    var verifiedAt: Date
}

enum EntitlementEvaluator {
    static func isActive(expirationDate: Date?, revocationDate: Date?, now: Date = Date()) -> Bool {
        if revocationDate != nil { return false }
        guard let expirationDate else { return true }
        return expirationDate > now
    }

    static func cachedIsActive(_ cache: PremiumEntitlementCache?, now: Date = Date()) -> Bool {
        guard let cache else { return false }
        if let expiration = cache.expirationDate {
            return expiration > now
        }
        return false
    }
}

@MainActor
@Observable
final class SubscriptionManager {
    private(set) var products: [Product] = []
    private(set) var isPremium = false
    private(set) var isLoadingProducts = false
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    private(set) var errorMessage: String?
    private(set) var statusMessage: String?
    private(set) var hasLoadedProducts = false
    private(set) var activeProductID: String?
    private(set) var activeExpirationDate: Date?

    private let defaults: UserDefaults
    private let cacheKey = "com.mise.premiumEntitlementCache.v1"
    private var updatesTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var hasStarted = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: cacheKey),
           let cache = try? JSONDecoder().decode(PremiumEntitlementCache.self, from: data),
           EntitlementEvaluator.cachedIsActive(cache) {
            isPremium = true
            activeProductID = cache.productID
            activeExpirationDate = cache.expirationDate
        }
    }

    var monthlyProduct: Product? {
        products.first { $0.id == SubscriptionProductID.monthly }
    }

    var yearlyProduct: Product? {
        products.first { $0.id == SubscriptionProductID.yearly }
    }

    var productsById: [String: Product] {
        Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
    }

    var activePlanLabel: String {
        guard let activeProductID else { return isPremium ? "Mise Premium" : "Free" }
        if activeProductID == SubscriptionProductID.yearly { return "Mise Premium · Annual" }
        if activeProductID == SubscriptionProductID.monthly { return "Mise Premium · Monthly" }
        return "Mise Premium"
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        listenForTransactions()
        await refreshProducts()
        await refreshEntitlements()
    }

    func refreshProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        errorMessage = nil
        do {
            let fetched = try await Product.products(for: Set(SubscriptionProductID.all))
            products = fetched.sorted { lhs, rhs in
                let order = [SubscriptionProductID.yearly, SubscriptionProductID.monthly]
                let left = order.firstIndex(of: lhs.id) ?? 99
                let right = order.firstIndex(of: rhs.id) ?? 99
                return left < right
            }
            hasLoadedProducts = true
            if products.isEmpty {
                errorMessage = "Subscriptions aren’t available right now. Check your connection and try again."
            }
        } catch {
            errorMessage = "Mise couldn’t load subscriptions. Check your connection and try again."
        }
        isLoadingProducts = false
    }

    func refreshEntitlements() async {
        var newestExpiration: Date?
        var activeID: String?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard SubscriptionProductID.all.contains(transaction.productID) else { continue }
            guard EntitlementEvaluator.isActive(
                expirationDate: transaction.expirationDate,
                revocationDate: transaction.revocationDate
            ) else { continue }
            activeID = transaction.productID
            if let expiration = transaction.expirationDate,
               expiration > (newestExpiration ?? .distantPast) {
                newestExpiration = expiration
            }
        }

        if let activeID {
            isPremium = true
            activeProductID = activeID
            activeExpirationDate = newestExpiration
            let cache = PremiumEntitlementCache(
                productID: activeID,
                expirationDate: newestExpiration,
                verifiedAt: Date()
            )
            if let data = try? JSONEncoder().encode(cache) {
                defaults.set(data, forKey: cacheKey)
            }
            scheduleExpiryCheck(at: newestExpiration)
        } else {
            isPremium = false
            activeProductID = nil
            activeExpirationDate = nil
            defaults.removeObject(forKey: cacheKey)
            expiryTask?.cancel()
        }
    }

    func purchase(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        errorMessage = nil
        statusMessage = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    errorMessage = "The App Store couldn’t verify that purchase. Nothing was unlocked."
                    return
                }
                await transaction.finish()
                await refreshEntitlements()
                if isPremium {
                    statusMessage = "Mise Premium is active."
                } else {
                    errorMessage = "The purchase completed, but no active entitlement was found. Use Restore Purchases."
                }
            case .pending:
                statusMessage = "The purchase is pending approval. Mise will unlock Premium when the App Store confirms it."
            case .userCancelled:
                break
            @unknown default:
                errorMessage = "The App Store returned an unexpected purchase state. No changes were made."
            }
        } catch {
            errorMessage = "The purchase couldn’t be completed. Nothing was unlocked. You can try again."
        }
    }

    func restorePurchases() async {
        guard !isRestoring else { return }
        isRestoring = true
        errorMessage = nil
        statusMessage = nil
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if isPremium {
                statusMessage = "Purchases restored. Mise Premium is active."
            } else {
                statusMessage = "No active Mise Premium subscription was found for this Apple Account."
            }
        } catch {
            errorMessage = "Purchases couldn’t be restored. Check your connection and try again."
        }
    }

    func clearMessages() {
        errorMessage = nil
        statusMessage = nil
    }

    private func listenForTransactions() {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self.refreshEntitlements()
            }
        }
    }

    private func scheduleExpiryCheck(at date: Date?) {
        expiryTask?.cancel()
        guard let date else { return }
        let interval = date.timeIntervalSinceNow
        guard interval > 0, interval < 60 * 60 * 24 * 400 else { return }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(min(interval, 60 * 60 * 24 * 7)) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.refreshEntitlements()
        }
    }
}
