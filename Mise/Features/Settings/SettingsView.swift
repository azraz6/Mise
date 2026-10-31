import SwiftData
import SwiftUI

enum MiseLinks {
    static let privacy = URL(string: "https://azraz6.github.io/Mise/privacy.html")!
    static let support = URL(string: "https://azraz6.github.io/Mise/support.html")!
    static let terms = URL(string: "https://azraz6.github.io/Mise/terms.html")!
    static let appleEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let manageSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!
}

struct SettingsView: View {
    @Environment(AppDependencies.self) private var app
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Query(sort: \Recipe.dateAdded, order: .reverse) private var recipes: [Recipe]
    @Query(sort: \RecipeCollection.sortOrder) private var collections: [RecipeCollection]
    @Query(sort: \ShoppingList.updatedAt, order: .reverse) private var shoppingLists: [ShoppingList]

    @State private var showPaywall = false
    @State private var paywallReason: PaywallReason = .general
    @State private var showEraseConfirmation = false
    @State private var isRestoring = false
    @State private var showStarterExplanation = false
    @State private var showImportHistory = false

    private var activeRecipes: [Recipe] {
        recipes.filter { !$0.isArchived }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    premiumCard
                    allowanceSection
                    librarySection
                    privacySection
                    dataSection
                    aboutSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 36)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(PageBackground())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MiseTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .tint(MiseTheme.ink)
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(reason: paywallReason)
                .environment(app)
                .environment(router)
                .modelContainer(app.container)
        }
        .sheet(isPresented: $showImportHistory) {
            ImportHistoryView()
                .environment(app)
                .modelContainer(app.container)
        }
        .alert("Erase all Mise data?", isPresented: $showEraseConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Erase everything", role: .destructive) {
                app.store.resetAllData()
                Haptics.warning()
                router.showToast("Your library has been erased")
            }
        } message: {
            Text("This removes every recipe, collection, shopping list, meal plan entry, and import history from this iPhone. Starter recipes can be restored afterwards. This can’t be undone.")
        }
        .alert("Starter recipes", isPresented: $showStarterExplanation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Starter recipes can be restored when your library is empty. Erase your data first if you want a clean start with the three included recipes.")
        }
        .task {
            app.usage.refreshForCurrentMonth()
        }
    }

    // MARK: - Premium

    private var premiumCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.subscriptions.isPremium ? "MISE PREMIUM" : "MISE FREE")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.1)
                        .foregroundStyle(MiseTheme.sage)
                    Text(app.subscriptions.isPremium ? app.subscriptions.activePlanLabel : "Your cookbook, your rules")
                        .font(.system(.title2, design: .serif, weight: .semibold))
                        .foregroundStyle(MiseTheme.ink)
                }
                Spacer()
                Image(systemName: app.subscriptions.isPremium ? "checkmark.seal.fill" : "leaf")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(app.subscriptions.isPremium ? MiseTheme.positive : MiseTheme.sage)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill((app.subscriptions.isPremium ? MiseTheme.positive : MiseTheme.sage).opacity(0.1)))
            }

            if app.subscriptions.isPremium {
                Text("Unlimited automatic imports and collections. Manual recipes, cooking mode, shopping, and meal planning stay free for everyone.")
                    .font(.subheadline)
                    .foregroundStyle(MiseTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                if let expiration = app.subscriptions.activeExpirationDate {
                    Text("Renews or expires \(expiration.formatted(date: .abbreviated, time: .omitted)).")
                        .font(.caption)
                        .foregroundStyle(MiseTheme.secondaryInk)
                }
                HStack(spacing: 10) {
                    Link(destination: MiseLinks.manageSubscriptions) {
                        Label("Manage subscription", systemImage: "arrow.up.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MiseTheme.ink)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(MiseTheme.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(MiseTheme.line, lineWidth: 1)
                            )
                    }
                    Button {
                        restorePurchases()
                    } label: {
                        if isRestoring {
                            ProgressView()
                                .frame(width: 44, height: 44)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MiseTheme.ink)
                                .frame(width: 44, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(MiseTheme.surface)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(MiseTheme.line, lineWidth: 1)
                                )
                        }
                    }
                    .disabled(isRestoring)
                    .accessibilityLabel("Restore purchases")
                }
            } else {
                Text("Premium adds")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.0)
                    .foregroundStyle(MiseTheme.secondaryInk)
                VStack(alignment: .leading, spacing: 7) {
                    premiumFeature("Unlimited automatic imports", symbol: "arrow.down.to.line.compact")
                    premiumFeature("Unlimited collections", symbol: "rectangle.stack")
                    premiumFeature("On-device screenshot imports, without the monthly cap", symbol: "text.viewfinder")
                }
                Button {
                    paywallReason = .general
                    showPaywall = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("See Mise Premium")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(fill: MiseTheme.ink))
                .accessibilityIdentifier("settingsPremiumButton")

                Text("Free forever: manual recipes, cooking mode, shopping lists, and meal planning.")
                    .font(.caption2)
                    .foregroundStyle(MiseTheme.secondaryInk)
            }
        }
        .padding(17)
        .background(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(MiseTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(MiseTheme.line, lineWidth: 1)
        )
    }

    private func premiumFeature(_ text: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MiseTheme.sage)
                .frame(width: 18)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(MiseTheme.ink)
        }
    }

    // MARK: - Allowance

    private var allowanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("IMPORT ALLOWANCE")
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text(app.subscriptions.isPremium ? "Unlimited" : "\(app.usage.remainingFreeImports) left this month")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MiseTheme.ink)
                    Spacer()
                    if !app.subscriptions.isPremium {
                        Text("\(app.usage.automaticImportsThisMonth) of \(FreeTier.automaticImportsPerMonth) used")
                            .font(.caption)
                            .foregroundStyle(MiseTheme.secondaryInk)
                    }
                }
                if !app.subscriptions.isPremium {
                    ProgressView(
                        value: Double(app.usage.automaticImportsThisMonth),
                        total: Double(FreeTier.automaticImportsPerMonth)
                    )
                    .tint(app.usage.remainingFreeImports == 0 ? MiseTheme.accent : MiseTheme.sage)
                    .accessibilityHidden(true)
                    Text("Automatic imports include links, pasted text, and screenshot text reading. The allowance resets each calendar month. Manual recipes are always unlimited.")
                        .font(.caption)
                        .foregroundStyle(MiseTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(15)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(MiseTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(MiseTheme.line, lineWidth: 1)
            )
        }
    }

    // MARK: - Library

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("YOUR COOKBOOK")
            LazyVGrid(
                columns: dynamicTypeSize.isAccessibilitySize
                    ? [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
                    : [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                statCard(value: "\(activeRecipes.count)", label: "recipes", symbol: "book.closed")
                statCard(value: "\(recipes.filter { $0.lastCookedAt != nil }.count)", label: "cooked", symbol: "flame")
                statCard(value: "\(collections.count)", label: "collections", symbol: "rectangle.stack")
            }
            VStack(spacing: 0) {
                settingsRow(
                    title: "Restore starter recipes",
                    subtitle: recipes.isEmpty ? "Add the three recipes included with Mise." : "Available when your library is empty.",
                    symbol: "sparkles",
                    disabled: !recipes.isEmpty
                ) {
                    if recipes.isEmpty {
                        app.store.restoreStarterRecipes()
                        Haptics.success()
                        router.showToast("Starter recipes restored")
                    } else {
                        showStarterExplanation = true
                    }
                }
                MiseDivider().padding(.leading, 46)
                settingsRow(
                    title: "Import history",
                    subtitle: "\(app.store.allImportJobs().count) attempts saved",
                    symbol: "clock.arrow.circlepath",
                    disabled: false
                ) {
                    showImportHistory = true
                }
            }
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(MiseTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(MiseTheme.line, lineWidth: 1)
            )
        }
    }

    private func statCard(value: String, label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MiseTheme.sage)
            Text(value)
                .font(.system(.title, design: .serif, weight: .semibold))
                .foregroundStyle(MiseTheme.ink)
            Text(label)
                .font(.caption2)
                .foregroundStyle(MiseTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MiseTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MiseTheme.line, lineWidth: 1)
        )
    }

    // MARK: - Privacy

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("PRIVACY & HELP")
            VStack(spacing: 0) {
                settingsLink(
                    title: "Privacy policy",
                    subtitle: "What Mise stores and what it never collects.",
                    symbol: "hand.raised",
                    url: MiseLinks.privacy
                )
                MiseDivider().padding(.leading, 46)
                settingsLink(
                    title: "How imports work",
                    subtitle: "Limits, source types, and the review step.",
                    symbol: "questionmark.circle",
                    url: MiseLinks.support
                )
                MiseDivider().padding(.leading, 46)
                settingsLink(
                    title: "Support",
                    subtitle: "Get help or report a problem.",
                    symbol: "envelope",
                    url: MiseLinks.support
                )
                MiseDivider().padding(.leading, 46)
                settingsLink(
                    title: "Terms of use",
                    subtitle: "Subscription terms and Apple’s standard EULA.",
                    symbol: "doc.text",
                    url: MiseLinks.terms
                )
            }
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(MiseTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(MiseTheme.line, lineWidth: 1)
            )

            InlineNotice(
                style: .info,
                message: "No account and no analytics. Recipes, notes, and photos stay in Mise’s on-device storage. Network access happens only when you ask Mise to read a public recipe page or download a cover photo."
            )
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("DATA")
            VStack(spacing: 0) {
                settingsLink(
                    title: "Manage App Store subscription",
                    subtitle: "Open Apple’s subscription settings.",
                    symbol: "creditcard",
                    url: MiseLinks.manageSubscriptions
                )
                MiseDivider().padding(.leading, 46)
                Button {
                    restorePurchases()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MiseTheme.sage)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Restore purchases")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(MiseTheme.ink)
                            Text("Check your Apple Account for Mise Premium.")
                                .font(.caption)
                                .foregroundStyle(MiseTheme.secondaryInk)
                        }
                        Spacer()
                        if isRestoring {
                            ProgressView()
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(MiseTheme.secondaryInk.opacity(0.6))
                        }
                    }
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isRestoring)
                MiseDivider().padding(.leading, 46)
                Button(role: .destructive) {
                    showEraseConfirmation = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "trash")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MiseTheme.accent)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Erase all data")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(MiseTheme.accent)
                            Text("Remove every recipe and list from this iPhone.")
                                .font(.caption)
                                .foregroundStyle(MiseTheme.secondaryInk)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(MiseTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(MiseTheme.line, lineWidth: 1)
            )
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("ABOUT")
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Mise")
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(MiseTheme.ink)
                    Spacer()
                    Text("Version \(app.appVersion)")
                        .font(.caption)
                        .foregroundStyle(MiseTheme.secondaryInk)
                }
                Text("A quiet recipe box for the way you actually cook.")
                    .font(.subheadline)
                    .foregroundStyle(MiseTheme.secondaryInk)
                MiseDivider()
                Text("Starter photography from Unsplash, used under the Unsplash License. The three starter recipes are original content written for Mise.")
                    .font(.caption)
                    .foregroundStyle(MiseTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Mise is built with SwiftUI and SwiftData. No third-party analytics SDKs.")
                    .font(.caption)
                    .foregroundStyle(MiseTheme.secondaryInk)
            }
            .padding(15)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(MiseTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(MiseTheme.line, lineWidth: 1)
            )
        }
    }

    // MARK: - Components

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .tracking(1.1)
            .foregroundStyle(MiseTheme.secondaryInk)
    }

    private func settingsRow(
        title: String,
        subtitle: String,
        symbol: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(disabled ? MiseTheme.secondaryInk.opacity(0.5) : MiseTheme.sage)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(disabled ? MiseTheme.secondaryInk : MiseTheme.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(MiseTheme.secondaryInk)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MiseTheme.secondaryInk.opacity(0.5))
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func settingsLink(title: String, subtitle: String, symbol: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MiseTheme.sage)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MiseTheme.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(MiseTheme.secondaryInk)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MiseTheme.secondaryInk.opacity(0.6))
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func restorePurchases() {
        guard !isRestoring else { return }
        isRestoring = true
        Task {
            await app.subscriptions.restorePurchases()
            isRestoring = false
            if let message = app.subscriptions.statusMessage {
                router.showToast(message, symbol: "checkmark.circle.fill")
            } else if let error = app.subscriptions.errorMessage {
                router.showToast(error, symbol: "exclamationmark.circle.fill")
            }
        }
    }
}

// MARK: - Import history

struct ImportHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ImportJob.createdAt, order: .reverse) private var jobs: [ImportJob]

    var body: some View {
        NavigationStack {
            ZStack {
                PageBackground()
                Group {
                    if jobs.isEmpty {
                        EmptyStateView(
                            symbol: "clock.arrow.circlepath",
                            title: "No imports yet",
                            message: "Every link, pasted caption, and screenshot you try will be listed here on this iPhone."
                        )
                        .padding(.horizontal, 24)
                    } else {
                        ScrollView {
                            VStack(spacing: 10) {
                                ForEach(jobs) { job in
                                    jobRow(job)
                                }
                                Text("Import history stays on this iPhone. Saved recipes are never removed when an attempt is cleared.")
                                    .font(.caption2)
                                    .foregroundStyle(MiseTheme.secondaryInk)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 8)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .frame(maxWidth: 640, alignment: .leading)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle("Import history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MiseTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func jobRow(_ job: ImportJob) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(job.sourceType.displayName, systemImage: job.sourceType.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MiseTheme.secondaryInk)
                Spacer(minLength: 8)
                StatusBadge(status: job.status)
            }
            Text(job.displayTitle)
                .font(.system(.body, design: .serif, weight: .semibold))
                .foregroundStyle(MiseTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(job.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(MiseTheme.secondaryInk)
            if let error = job.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(MiseTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MiseTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MiseTheme.line, lineWidth: 1)
        )
    }
}
