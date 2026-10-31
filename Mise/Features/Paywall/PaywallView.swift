import StoreKit
import SwiftUI

struct PaywallView: View {
    let reason: PaywallReason

    @Environment(AppDependencies.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProductID = SubscriptionProductID.yearly
    @State private var didAttemptAutoSelection = false

    var body: some View {
        NavigationStack {
            Group {
                if app.subscriptions.isPremium {
                    premiumActiveView
                } else {
                    paywallContent
                }
            }
            .background(PageBackground())
            .navigationTitle("Mise Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MiseTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("closePaywall")
                }
            }
        }
        .task {
            app.usage.refreshForCurrentMonth()
            app.subscriptions.clearMessages()
            await app.subscriptions.refreshProducts()
            await app.subscriptions.refreshEntitlements()
            selectDefaultPlanIfNeeded()
        }
        .onChange(of: app.subscriptions.products.count) { _, _ in
            selectDefaultPlanIfNeeded()
        }
    }

    // MARK: - Paywall

    private var paywallContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                benefitList
                planSection
                messageSection
                purchaseSection
                restoreSection
                legalSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 40)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("paywallView")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                Text("MISE PREMIUM")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.4)
            }
            .foregroundStyle(MiseTheme.sage)

            Text(headerTitle)
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(MiseTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(headerMessage)
                .font(.body)
                .foregroundStyle(MiseTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 2)
    }

    private var headerTitle: String {
        switch reason {
        case .importLimit:
            return "Keep importing without the monthly cap"
        case .collectionLimit:
            return "Make room for every collection"
        case .general:
            return "A little more room for your recipes"
        }
    }

    private var headerMessage: String {
        switch reason {
        case .importLimit:
            return "You’ve used this month’s automatic imports. Premium lifts the cap so links, pasted text, and screenshots keep flowing into your library."
        case .collectionLimit:
            return "The free plan includes \(FreeTier.collections) collections. Premium lets you build as many shelves as your cooking needs."
        case .general:
            return "Mise stays free for the everyday essentials. Premium is for cooks who save recipes often and want no limits on the way they organize them."
        }
    }

    private var benefitList: some View {
        VStack(alignment: .leading, spacing: 13) {
            benefit(
                symbol: "arrow.down.to.line.compact",
                title: "Unlimited automatic imports",
                detail: "Links, shared text, and on-device screenshot imports without a monthly cap."
            )
            benefit(
                symbol: "rectangle.stack",
                title: "Unlimited collections",
                detail: "Keep as many curated shelves as you like, alongside search and favourites."
            )
            benefit(
                symbol: "lock.open",
                title: "Everything essential stays free",
                detail: "Manual recipes, cooking mode, shopping lists, and meal planning are free for everyone."
            )
        }
        .padding(17)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(MiseTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MiseTheme.line, lineWidth: 1)
        )
    }

    private func benefit(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MiseTheme.sage)
                .frame(width: 30, height: 30)
                .background(Circle().fill(MiseTheme.sage.opacity(0.1)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MiseTheme.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(MiseTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Plans

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CHOOSE A PLAN")
                .font(.caption2.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(MiseTheme.secondaryInk)

            if app.subscriptions.isLoadingProducts && !app.subscriptions.hasLoadedProducts {
                planLoadingCard
            } else if app.subscriptions.products.isEmpty {
                planUnavailableCard
            } else {
                VStack(spacing: 10) {
                    ForEach(app.subscriptions.products, id: \.id) { product in
                        planCard(for: product)
                    }
                }
            }
        }
    }

    private var planLoadingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Checking App Store availability…")
                .font(.subheadline)
                .foregroundStyle(MiseTheme.secondaryInk)
            Spacer(minLength: 0)
        }
        .padding(17)
        .frame(maxWidth: .infinity, minHeight: 76)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(MiseTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(MiseTheme.line, lineWidth: 1)
        )
        .accessibilityLabel("Loading subscription plans")
    }

    private var planUnavailableCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            InlineNotice(
                style: .warning,
                message: app.subscriptions.errorMessage ?? "Subscriptions aren’t available right now. Check your connection and try again."
            )
            Button {
                Task { await app.subscriptions.refreshProducts() }
            } label: {
                Label("Try again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(app.subscriptions.isLoadingProducts)
            .accessibilityIdentifier("retryProductsButton")
        }
    }

    private func planCard(for product: Product) -> some View {
        let isSelected = selectedProductID == product.id
        let isYearly = product.id == SubscriptionProductID.yearly

        return Button {
            selectedProductID = product.id
            Haptics.tap()
        } label: {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(isSelected ? MiseTheme.accent : MiseTheme.secondaryInk.opacity(0.55))
                    .padding(.top, 2)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(isYearly ? "Annual" : "Monthly")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MiseTheme.ink)
                        if isYearly, let savings = savingsPercent {
                            Text("SAVE \(savings)%")
                                .font(.caption2.weight(.bold))
                                .tracking(0.4)
                                .foregroundStyle(MiseTheme.positive)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(MiseTheme.positive.opacity(0.12)))
                        }
                    }
                    Text(planDetail(for: product))
                        .font(.caption)
                        .foregroundStyle(MiseTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(product.displayPrice)
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(MiseTheme.ink)
                    Text(periodLabel(for: product))
                        .font(.caption2)
                        .foregroundStyle(MiseTheme.secondaryInk)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(isSelected ? MiseTheme.accent.opacity(0.07) : MiseTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(isSelected ? MiseTheme.accent : MiseTheme.line, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isYearly ? "Annual" : "Monthly") plan, \(product.displayPrice) \(periodLabel(for: product))")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier(isYearly ? "planYearly" : "planMonthly")
    }

    private func planDetail(for product: Product) -> String {
        if product.id == SubscriptionProductID.yearly {
            if let savings = savingsPercent {
                return "One payment a year. About \(savings)% less than paying monthly."
            }
            return "One payment a year."
        }
        return "Billed every month. Cancel anytime."
    }

    private func periodLabel(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "" }
        switch period.unit {
        case .day:
            return period.value == 1 ? "per day" : "every \(period.value) days"
        case .week:
            return period.value == 1 ? "per week" : "every \(period.value) weeks"
        case .month:
            return period.value == 1 ? "per month" : "every \(period.value) months"
        case .year:
            return period.value == 1 ? "per year" : "every \(period.value) years"
        @unknown default:
            return ""
        }
    }

    private var savingsPercent: Int? {
        guard let monthly = app.subscriptions.monthlyProduct,
              let yearly = app.subscriptions.yearlyProduct else { return nil }
        let monthlyPrice = NSDecimalNumber(decimal: monthly.price).doubleValue
        let yearlyPrice = NSDecimalNumber(decimal: yearly.price).doubleValue
        let monthlyAnnual = monthlyPrice * 12
        guard monthlyPrice > 0, yearlyPrice > 0, yearlyPrice < monthlyAnnual else { return nil }
        return Int((((monthlyAnnual - yearlyPrice) / monthlyAnnual) * 100).rounded())
    }

    // MARK: - Status and purchase

    @ViewBuilder
    private var messageSection: some View {
        // When no plans are available, the plan card already presents the
        // product-loading error and its retry action. Avoid repeating it here.
        if app.subscriptions.products.isEmpty {
            EmptyView()
        } else if let error = app.subscriptions.errorMessage {
            InlineNotice(style: .error, message: error)
        } else if let status = app.subscriptions.statusMessage {
            InlineNotice(style: .info, message: status)
        }
    }

    private var purchaseSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let selectedProduct = selectedProduct {
                Button {
                    purchase(selectedProduct)
                } label: {
                    HStack(spacing: 9) {
                        if app.subscriptions.isPurchasing {
                            ProgressView()
                                .tint(MiseTheme.background)
                        }
                        Text(app.subscriptions.isPurchasing
                             ? "Contacting the App Store…"
                             : "Continue · \(selectedProduct.displayPrice) \(periodLabel(for: selectedProduct))")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(fill: MiseTheme.ink))
                .disabled(app.subscriptions.isPurchasing || app.subscriptions.isRestoring)
                .accessibilityIdentifier("purchasePremiumButton")

                Text("Auto-renews until cancelled. Cancel at least 24 hours before the current period ends to avoid the next charge.")
                    .font(.caption2)
                    .foregroundStyle(MiseTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var selectedProduct: Product? {
        app.subscriptions.products.first { $0.id == selectedProductID }
            ?? app.subscriptions.yearlyProduct
            ?? app.subscriptions.monthlyProduct
    }

    private var restoreSection: some View {
        Button {
            restore()
        } label: {
            HStack(spacing: 8) {
                if app.subscriptions.isRestoring {
                    ProgressView()
                }
                Text(app.subscriptions.isRestoring ? "Restoring purchases…" : "Restore Purchases")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MiseTheme.ink)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
        }
        .buttonStyle(.plain)
        .disabled(app.subscriptions.isRestoring || app.subscriptions.isPurchasing)
        .accessibilityIdentifier("restorePurchasesButton")
    }

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            MiseDivider()
            Text("Payment is charged to your Apple Account when you confirm. Subscriptions renew automatically unless cancelled at least 24 hours before the current period ends. Manage or cancel anytime in your Apple Account settings.")
                .font(.caption2)
                .foregroundStyle(MiseTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                Link("Terms of Use", destination: MiseLinks.terms)
                Link("Privacy Policy", destination: MiseLinks.privacy)
                Link("Apple EULA", destination: MiseLinks.appleEULA)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(MiseTheme.accent)
        }
    }

    // MARK: - Premium active

    private var premiumActiveView: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(MiseTheme.positive)
                    .padding(.top, 28)
                    .accessibilityHidden(true)

                Text("You’re all set")
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    .foregroundStyle(MiseTheme.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text("Mise Premium is active on this Apple Account. Automatic imports and collections are unlimited.")
                    .font(.body)
                    .foregroundStyle(MiseTheme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 4) {
                    Text(app.subscriptions.activePlanLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MiseTheme.ink)
                    if let expiration = app.subscriptions.activeExpirationDate {
                        Text("Renews or expires \(expiration.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(MiseTheme.secondaryInk)
                    }
                }
                .padding(.vertical, 13)
                .padding(.horizontal, 18)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MiseTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MiseTheme.line, lineWidth: 1)
                )

                Link(destination: MiseLinks.manageSubscriptions) {
                    Label("Manage subscription", systemImage: "arrow.up.right")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    dismiss()
                } label: {
                    Text("Start cooking")
                }
                .buttonStyle(PrimaryButtonStyle(fill: MiseTheme.ink))
                .accessibilityIdentifier("dismissActivePaywallButton")

                Button {
                    restore()
                } label: {
                    Text(app.subscriptions.isRestoring ? "Refreshing…" : "Refresh purchase status")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MiseTheme.secondaryInk)
                }
                .disabled(app.subscriptions.isRestoring)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Actions

    private func purchase(_ product: Product) {
        Task {
            app.subscriptions.clearMessages()
            await app.subscriptions.purchase(product)
            if app.subscriptions.isPremium {
                Haptics.success()
            } else {
                Haptics.warning()
            }
        }
    }

    private func restore() {
        Task {
            app.subscriptions.clearMessages()
            await app.subscriptions.restorePurchases()
            if app.subscriptions.isPremium {
                Haptics.success()
            }
        }
    }

    private func selectDefaultPlanIfNeeded() {
        guard !didAttemptAutoSelection,
              app.subscriptions.yearlyProduct != nil || app.subscriptions.monthlyProduct != nil else { return }
        didAttemptAutoSelection = true
        if let yearly = app.subscriptions.yearlyProduct {
            selectedProductID = yearly.id
        } else if let monthly = app.subscriptions.monthlyProduct {
            selectedProductID = monthly.id
        }
    }
}
