import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(AppDependencies.self) private var app
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Query(sort: \Recipe.dateAdded, order: .reverse) private var recipes: [Recipe]
    @Query(sort: \ImportJob.createdAt, order: .reverse) private var jobs: [ImportJob]
    @Query(sort: \RecipeCollection.sortOrder) private var collections: [RecipeCollection]
    @Query private var mealEntries: [MealPlanEntry]

    @State private var cookingRecipe: Recipe?
    @State private var reviewJob: ImportJob?

    private var recentRecipes: [Recipe] {
        Array(recipes.filter { !$0.isArchived }.prefix(8))
    }

    private var resumeCooking: Recipe? {
        recipes.first { $0.hasCookingProgress }
    }

    private var jobsNeedingAttention: [ImportJob] {
        Array(jobs.filter { [.needsReview, .extracted, .linkSaved, .failed].contains($0.status) }.prefix(3))
    }

    private var tonightEntries: [MealPlanEntry] {
        let key = MealPlanCalendar.dayKey(for: Date())
        return mealEntries
            .filter { $0.dayKey == key }
            .sorted { $0.slot.sortIndex < $1.slot.sortIndex }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    header
                    greeting
                    importCard
                    if let resumeCooking {
                        resumeCard(resumeCooking)
                    }
                    if !jobsNeedingAttention.isEmpty {
                        attentionSection
                    }
                    tonightSection
                    if !recentRecipes.isEmpty {
                        librarySection
                    }
                    if !collections.isEmpty {
                        collectionsSection
                    }
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 34)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(PageBackground())
            .statusBarScrim()
            .toolbar(.hidden, for: .navigationBar)
            .scrollIndicators(.hidden)
        }
        .fullScreenCover(item: $cookingRecipe) { recipe in
            CookingModeView(recipe: recipe)
                .environment(app)
                .modelContainer(app.container)
        }
        .sheet(item: $reviewJob) { job in
            ImportReviewView(job: job) { recipe in
                router.showToast("Saved “\(recipe.title)”")
            }
            .environment(app)
            .environment(router)
            .modelContainer(app.container)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Mise")
                    .font(.system(.title, design: .serif, weight: .bold))
                    .foregroundStyle(MiseTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(MiseTheme.secondaryInk)
            }
            Spacer()
            Button {
                router.showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(MiseTheme.ink)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(MiseTheme.surface))
                    .overlay(Circle().stroke(MiseTheme.line, lineWidth: 1))
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settingsButton")
        }
        .padding(.top, 4)
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(greetingText)
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(MiseTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Save anything. Cook without the clutter.")
                .font(.body)
                .foregroundStyle(MiseTheme.secondaryInk)
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning."
        case 12..<17: return "Good afternoon."
        default: return "Good evening."
        }
    }

    // MARK: - Import

    private var importCard: some View {
        Button {
            router.openImport()
        } label: {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(MiseTheme.surface)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(MiseTheme.sage))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Save a recipe")
                            .font(.system(.title3, design: .serif, weight: .semibold))
                            .foregroundStyle(MiseTheme.ink)
                        Text("A link, a caption, a screenshot, or your own words.")
                            .font(.subheadline)
                            .foregroundStyle(MiseTheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                if dynamicTypeSize.isAccessibilitySize {
                    Text("Link · Text · Screenshot · Write")
                        .font(.caption)
                        .foregroundStyle(MiseTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 8) {
                        methodChip("Link", symbol: "link")
                        methodChip("Text", symbol: "text.alignleft")
                        methodChip("Screenshot", symbol: "photo")
                        methodChip("Write", symbol: "square.and.pencil")
                    }
                }

                HStack(spacing: 8) {
                    Text("Start an import")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MiseTheme.accent)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MiseTheme.accent)
                    Spacer()
                    Text(app.subscriptions.isPremium ? "Unlimited imports" : "\(app.usage.remainingFreeImports) free left this month")
                        .font(.caption2)
                        .foregroundStyle(MiseTheme.secondaryInk)
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(MiseTheme.surface)
                    .shadow(color: MiseTheme.ink.opacity(0.05), radius: 16, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(MiseTheme.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Save a recipe")
        .accessibilityHint("Opens import options for a link, text, screenshot, or manual recipe")
        .accessibilityIdentifier("importCard")
    }

    private func methodChip(_ title: String, symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(MiseTheme.secondaryInk)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Capsule().fill(MiseTheme.raisedSurface))
        .fixedSize()
    }

    // MARK: - Resume

    private func resumeCard(_ recipe: Recipe) -> some View {
        Button {
            cookingRecipe = recipe
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("PICK UP WHERE YOU LEFT OFF")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.1)
                        .foregroundStyle(MiseTheme.sage)
                    Spacer()
                    Image(systemName: "play.fill")
                        .font(.caption)
                        .foregroundStyle(MiseTheme.surface)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(MiseTheme.sage))
                }
                HStack(spacing: 14) {
                    RecipeCoverImage(
                        filename: recipe.coverImageFilename,
                        assetName: recipe.coverAssetName,
                        cornerRadius: 12
                    )
                    .frame(width: 68, height: 68)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(recipe.title)
                            .font(.system(.headline, design: .serif, weight: .semibold))
                            .foregroundStyle(MiseTheme.ink)
                            .lineLimit(2)
                        Text("Step \(min(recipe.cookingStepIndex + 1, recipe.cookingStepCount)) of \(recipe.cookingStepCount)")
                            .font(.caption)
                            .foregroundStyle(MiseTheme.secondaryInk)
                    }
                    Spacer(minLength: 0)
                }
                ProgressView(
                    value: Double(recipe.cookingStepIndex),
                    total: Double(max(recipe.cookingStepCount, 1))
                )
                .tint(MiseTheme.sage)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(MiseTheme.sage.opacity(0.09))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(MiseTheme.sage.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Resume cooking \(recipe.title), step \(recipe.cookingStepIndex + 1) of \(recipe.cookingStepCount)")
    }

    // MARK: - Attention

    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Waiting for you", actionTitle: "All imports") {
                router.openImport()
            }
            VStack(spacing: 0) {
                ForEach(Array(jobsNeedingAttention.enumerated()), id: \.element.id) { index, job in
                    Button {
                        handleJob(job)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: job.status == .failed ? "exclamationmark.circle" : "tray.and.arrow.down")
                                .foregroundStyle(job.status == .failed ? MiseTheme.accent : MiseTheme.sage)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(job.displayTitle)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(MiseTheme.ink)
                                    .lineLimit(1)
                                Text(job.status == .linkSaved
                                     ? "Link saved — add the details when you’re ready."
                                     : job.errorMessage ?? "Review this import before it joins your library.")
                                    .font(.caption)
                                    .foregroundStyle(MiseTheme.secondaryInk)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            StatusBadge(status: job.status)
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(MiseTheme.secondaryInk.opacity(0.6))
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < jobsNeedingAttention.count - 1 {
                        MiseDivider()
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(MiseTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(MiseTheme.line, lineWidth: 1)
            )
        }
    }

    // MARK: - Tonight

    private var tonightSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Tonight", actionTitle: "Meal plan") {
                router.selectedTab = .plan
            }
            if tonightEntries.isEmpty {
                Button {
                    router.selectedTab = .plan
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "moon.stars")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(MiseTheme.sage)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(MiseTheme.sage.opacity(0.1)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nothing planned yet")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MiseTheme.ink)
                            Text("Choose something from your library.")
                                .font(.caption)
                                .foregroundStyle(MiseTheme.secondaryInk)
                        }
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MiseTheme.secondaryInk)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(MiseTheme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(MiseTheme.line, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(tonightEntries.enumerated()), id: \.element.id) { index, entry in
                        if let recipe = app.store.recipe(id: entry.recipeID) {
                            NavigationLink {
                                RecipeDetailView(recipe: recipe)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: entry.slot.symbolName)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(MiseTheme.sage)
                                        .frame(width: 34, height: 34)
                                        .background(Circle().fill(MiseTheme.sage.opacity(0.1)))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.slot.displayName.uppercased())
                                            .font(.caption2.weight(.semibold))
                                            .tracking(0.7)
                                            .foregroundStyle(MiseTheme.secondaryInk)
                                        Text(recipe.title)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(MiseTheme.ink)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    RecipeCoverImage(
                                        filename: recipe.coverImageFilename,
                                        assetName: recipe.coverAssetName,
                                        cornerRadius: 10
                                    )
                                    .frame(width: 46, height: 46)
                                }
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if index < tonightEntries.count - 1 {
                                MiseDivider()
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(MiseTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(MiseTheme.line, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Library

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "From your library", actionTitle: "See all") {
                router.selectedTab = .library
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(recentRecipes) { recipe in
                        NavigationLink {
                            RecipeDetailView(recipe: recipe)
                        } label: {
                            RecipeCard(
                                recipe: recipe,
                                width: dynamicTypeSize.isAccessibilitySize ? 240 : 172,
                                titleLineLimit: dynamicTypeSize.isAccessibilitySize ? 3 : 2
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: - Collections

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Collections")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(collections) { collection in
                        NavigationLink {
                            CollectionDetailView(collection: collection)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(collection.name)
                                    .font(.system(.subheadline, design: .serif, weight: .semibold))
                                    .foregroundStyle(MiseTheme.ink)
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                                Text("^[\(collection.recipeIDs.count) recipe](inflect: true)")
                                    .font(.caption2)
                                    .foregroundStyle(MiseTheme.secondaryInk)
                            }
                            .frame(
                                width: dynamicTypeSize.isAccessibilitySize ? 240 : 148,
                                height: dynamicTypeSize.isAccessibilitySize ? 160 : 86,
                                alignment: .leading
                            )
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .fill(MiseTheme.raisedSurface)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock")
                .font(.caption2)
                .foregroundStyle(MiseTheme.secondaryInk)
            Text("Your cookbook lives on this iPhone. No account, no feed, no noise.")
                .font(.caption)
                .foregroundStyle(MiseTheme.secondaryInk)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

    private func handleJob(_ job: ImportJob) {
        if job.status == .needsReview || job.status == .extracted {
            reviewJob = job
        } else {
            router.openImport()
        }
    }
}
