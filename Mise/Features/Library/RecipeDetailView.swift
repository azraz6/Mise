import SwiftData
import SwiftUI

private struct RecipeDetailScrollKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct RecipeDetailView: View {
    @Environment(AppDependencies.self) private var app
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    let recipe: Recipe
    @Query(sort: \RecipeCollection.sortOrder) private var collections: [RecipeCollection]
    @Query(sort: \ShoppingList.updatedAt, order: .reverse) private var shoppingLists: [ShoppingList]

    @State private var servings: Int
    @State private var showEditor = false
    @State private var showCollectionPicker = false
    @State private var showShoppingPicker = false
    @State private var showDeleteConfirmation = false
    @State private var showCookingMode = false
    @State private var didAddToList = false
    @State private var isScrolled = false

    init(recipe: Recipe) {
        self.recipe = recipe
        _servings = State(initialValue: max(1, recipe.originalServings ?? 2))
    }

    private var originalServings: Int? {
        guard let value = recipe.originalServings, value > 0 else { return nil }
        return value
    }

    private var multiplier: Double {
        guard let originalServings else { return 1 }
        return IngredientScaler.multiplier(originalServings: originalServings, desiredServings: servings)
    }

    private var sortedIngredients: [Ingredient] {
        recipe.ingredients.sorted { $0.order < $1.order }
    }

    private var sortedInstructions: [Instruction] {
        recipe.instructions.sorted { $0.order < $1.order }
    }

    private var collectionsContaining: [RecipeCollection] {
        collections.filter { $0.contains(recipe.id) }
    }

    private var hasInstructions: Bool {
        !recipe.instructions.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                cover
                titleBlock
                if recipe.extractionMethod == .linkOnly {
                    InlineNotice(
                        style: .warning,
                        message: "Only the source link was saved. Add ingredients and steps so Mise can scale, shop, and cook this recipe.",
                        title: "This recipe is a link"
                    )
                } else if recipe.isArchived {
                    InlineNotice(
                        style: .info,
                        message: "This recipe is archived. It stays out of your main library but remains available here.",
                        title: "Archived"
                    )
                }
                metadataRow
                ingredientsSection
                instructionsSection
                if let notes = recipe.notes, !notes.isEmpty {
                    notesSection(notes)
                }
                if !collectionsContaining.isEmpty {
                    collectionsSection
                }
                sourceSection
                shareSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 30)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: RecipeDetailScrollKey.self,
                        value: proxy.frame(in: .named("recipeDetailScroll")).minY
                    )
                }
            )
        }
        .coordinateSpace(name: "recipeDetailScroll")
        .onPreferenceChange(RecipeDetailScrollKey.self) { offset in
            let shouldScrim = offset < -24
            if shouldScrim != isScrolled {
                isScrolled = shouldScrim
            }
        }
        .background(PageBackground())
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(isScrolled ? Visibility.visible : Visibility.hidden, for: .navigationBar)
        .toolbarBackground(MiseTheme.background, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    app.store.toggleFavourite(recipe)
                    Haptics.tap()
                } label: {
                    Image(systemName: recipe.isFavourite ? "heart.fill" : "heart")
                        .foregroundStyle(recipe.isFavourite ? MiseTheme.accent : MiseTheme.ink)
                }
                .accessibilityLabel(recipe.isFavourite ? "Remove from favourites" : "Add to favourites")
                .accessibilityIdentifier("favouriteRecipeButton")

                Menu {
                    Button {
                        showEditor = true
                    } label: {
                        Label("Edit recipe", systemImage: "pencil")
                    }
                    Button {
                        showCollectionPicker = true
                    } label: {
                        Label("Add to collection", systemImage: "rectangle.stack.badge.plus")
                    }
                    Button {
                        addToShoppingList()
                    } label: {
                        Label("Add ingredients to shopping list", systemImage: "cart.badge.plus")
                    }
                    if let url = recipe.sourceURL {
                        ShareLink(item: url) {
                            Label("Share source link", systemImage: "link")
                        }
                    }
                    ShareLink(item: shareText) {
                        Label("Share recipe", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button {
                        app.store.setArchived(recipe, archived: !recipe.isArchived)
                        router.showToast(recipe.isArchived ? "Recipe archived" : "Recipe restored", symbol: recipe.isArchived ? "archivebox.fill" : "archivebox")
                    } label: {
                        Label(recipe.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox")
                    }
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete recipe", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(MiseTheme.ink)
                }
                .accessibilityLabel("Recipe options")
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .sheet(isPresented: $showEditor) {
            RecipeEditorView(recipe: recipe) { _ in
                router.showToast("Recipe updated")
            }
            .environment(app)
            .environment(router)
            .modelContainer(app.container)
        }
        .sheet(isPresented: $showCollectionPicker) {
            CollectionPickerView(recipe: recipe)
                .environment(app)
                .modelContainer(app.container)
        }
        .sheet(isPresented: $showShoppingPicker) {
            ShoppingListPickerView(selections: ShoppingListBuilder.selections(from: [recipe]))
                .environment(app)
                .environment(router)
                .modelContainer(app.container)
        }
        .fullScreenCover(isPresented: $showCookingMode) {
            CookingModeView(recipe: recipe)
                .environment(app)
                .modelContainer(app.container)
        }
        .alert("Delete recipe?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                app.store.delete(recipe)
                dismiss()
            }
        } message: {
            Text("“\(recipe.title)” will be removed from your library, collections, and meal plan. This can’t be undone.")
        }
    }

    // MARK: - Cover

    private var cover: some View {
        RecipeCoverImage(
            filename: recipe.coverImageFilename,
            assetName: recipe.coverAssetName,
            cornerRadius: 22,
            symbolSize: 34
        )
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .overlay(alignment: .bottomLeading) {
            if recipe.isFavourite {
                Label("Favourite", systemImage: "heart.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MiseTheme.ink)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(.regularMaterial))
                    .padding(14)
            }
        }
        .accessibilityLabel("Cover photo for \(recipe.title)")
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow)
                .font(.caption.weight(.semibold))
                .tracking(1.0)
                .foregroundStyle(MiseTheme.sage)
            Text(recipe.title)
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(MiseTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("recipeDetailTitle")
            if let summary = recipe.summary, !summary.isEmpty {
                Text(summary)
                    .font(.body)
                    .foregroundStyle(MiseTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            if let author = recipe.author, !author.isEmpty {
                Text("By \(author)")
                    .font(.footnote)
                    .foregroundStyle(MiseTheme.secondaryInk)
            }
        }
    }

    private var eyebrow: String {
        let parts = [recipe.cuisine, recipe.category].compactMap { $0?.isEmpty == false ? $0 : nil }
        let descriptor = parts.isEmpty ? recipe.sourceType.displayName : parts.joined(separator: " · ")
        return descriptor.uppercased()
    }

    private var metadataRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                if let total = recipe.totalMinutes {
                    metaPill("\(total) min total", symbol: "clock")
                } else {
                    if let prep = recipe.prepMinutes { metaPill("\(prep) min prep", symbol: "timer") }
                    if let cook = recipe.cookMinutes { metaPill("\(cook) min cook", symbol: "flame") }
                }
                if let originalServings {
                    metaPill("Serves \(originalServings)", symbol: "person.2")
                } else if let description = recipe.servingsDescription, !description.isEmpty {
                    metaPill(description, symbol: "person.2")
                }
                if let lastCooked = recipe.lastCookedAt {
                    metaPill("Cooked \(lastCooked.formatted(.relative(presentation: .named)))", symbol: "checkmark.seal")
                }
                if recipe.extractionMethod != .manual {
                    metaPill(recipe.extractionMethod.displayName, symbol: "sparkles")
                }
            }
        }
        .scrollClipDisabled()
    }

    private func metaPill(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(MiseTheme.ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(Capsule().fill(MiseTheme.raisedSurface))
    }

    // MARK: - Ingredients

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ingredients")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(MiseTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if originalServings != nil {
                    servingsStepper
                }
            }

            if let originalServings, servings != originalServings {
                Text("Scaled from \(originalServings) to \(servings) servings")
                    .font(.caption)
                    .foregroundStyle(MiseTheme.secondaryInk)
            }

            VStack(spacing: 0) {
                ForEach(Array(sortedIngredients.enumerated()), id: \.element.id) { index, ingredient in
                    HStack(alignment: .firstTextBaseline, spacing: 11) {
                        Circle()
                            .fill(MiseTheme.accent.opacity(0.7))
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)
                            .accessibilityHidden(true)
                        Text(IngredientScaler.displayText(for: ingredient, multiplier: multiplier))
                            .font(.body)
                            .foregroundStyle(MiseTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 9)
                    if index < sortedIngredients.count - 1 {
                        MiseDivider().padding(.leading, 16)
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

            if sortedIngredients.contains(where: { !$0.isScalable }) {
                Text("Some items are kept exactly as written, like “salt to taste” or garnishes.")
                    .font(.caption)
                    .foregroundStyle(MiseTheme.secondaryInk)
            }
        }
    }

    private var servingsStepper: some View {
        HStack(spacing: 2) {
            Button {
                if servings > 1 { servings -= 1; Haptics.tap() }
            } label: {
                Image(systemName: "minus")
                    .font(.caption.weight(.bold))
                    .frame(width: 34, height: 34)
            }
            .disabled(servings <= 1)
            .accessibilityLabel("Decrease servings")

            VStack(spacing: 0) {
                Text("\(servings)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MiseTheme.ink)
                Text("servings")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(MiseTheme.secondaryInk)
            }
            .frame(minWidth: 42)

            Button {
                if servings < 24 { servings += 1; Haptics.tap() }
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .frame(width: 34, height: 34)
            }
            .disabled(servings >= 24)
            .accessibilityLabel("Increase servings")
        }
        .foregroundStyle(MiseTheme.ink)
        .background(Capsule().fill(MiseTheme.raisedSurface))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Servings, \(servings)")
    }

    // MARK: - Instructions

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Method")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(MiseTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("^[\(sortedInstructions.count) step](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(MiseTheme.secondaryInk)
            }

            if sortedInstructions.isEmpty {
                InlineNotice(
                    style: .warning,
                    message: "No cooking steps were saved. Add them before you start cooking.",
                    title: "Method missing"
                )
                Button {
                    showEditor = true
                } label: {
                    Label("Add steps", systemImage: "plus")
                }
                .buttonStyle(SecondaryButtonStyle())
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(sortedInstructions.enumerated()), id: \.element.id) { index, instruction in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(MiseTheme.surface)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(MiseTheme.sage))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(instruction.text)
                                    .font(.body)
                                    .foregroundStyle(MiseTheme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let duration = instruction.durationSeconds, duration > 0 {
                                    Label(InstructionDurationDetector.display(seconds: duration), systemImage: "timer")
                                        .font(.caption)
                                        .foregroundStyle(MiseTheme.secondaryInk)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Step \(index + 1). \(instruction.text)")
                    }
                }
            }
        }
    }

    // MARK: - Notes & source

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes", systemImage: "note.text")
                .font(.system(.headline, design: .serif, weight: .semibold))
                .foregroundStyle(MiseTheme.ink)
            Text(notes)
                .font(.body)
                .foregroundStyle(MiseTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MiseTheme.sage.opacity(0.07))
        )
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("In collections")
                .font(.system(.headline, design: .serif, weight: .semibold))
                .foregroundStyle(MiseTheme.ink)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(collectionsContaining) { collection in
                        TagChip(text: collection.name, highlighted: true)
                    }
                    Button {
                        showCollectionPicker = true
                    } label: {
                        Label("Edit", systemImage: "plus")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(MiseTheme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(MiseTheme.accent.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollClipDisabled()
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Source")
                .font(.system(.headline, design: .serif, weight: .semibold))
                .foregroundStyle(MiseTheme.ink)
            VStack(alignment: .leading, spacing: 7) {
                Label(recipe.sourceType.displayName, systemImage: recipe.sourceType.symbolName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(MiseTheme.ink)
                if let sourceTitle = recipe.sourceTitle, !sourceTitle.isEmpty, sourceTitle != recipe.title {
                    Text(sourceTitle)
                        .font(.subheadline)
                        .foregroundStyle(MiseTheme.secondaryInk)
                        .lineLimit(2)
                }
                if let attribution = recipe.attribution, !attribution.isEmpty {
                    Text(attribution)
                        .font(.caption)
                        .foregroundStyle(MiseTheme.secondaryInk)
                }
                if let url = recipe.sourceURL {
                    Link(destination: url) {
                        HStack(spacing: 5) {
                            Text(url.host ?? url.absoluteString)
                                .lineLimit(1)
                            Image(systemName: "arrow.up.right")
                                .font(.caption2.weight(.bold))
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MiseTheme.accent)
                    }
                    .accessibilityLabel("Open original source")
                } else if recipe.sourceType.isSocial {
                    Text("The original link wasn’t saved with this recipe.")
                        .font(.caption)
                        .foregroundStyle(MiseTheme.secondaryInk)
                }
                Text("Added \(recipe.dateAdded.formatted(date: .abbreviated, time: .omitted)) · \(recipe.extractionMethod.displayName)")
                    .font(.caption2)
                    .foregroundStyle(MiseTheme.secondaryInk)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(MiseTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(MiseTheme.line, lineWidth: 1)
            )
        }
        .accessibilityElement(children: .contain)
    }

    private var shareSection: some View {
        HStack(spacing: 10) {
            ShareLink(item: shareText) {
                Label("Share recipe", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MiseTheme.ink)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(MiseTheme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(MiseTheme.line, lineWidth: 1)
                    )
            }
            Button {
                showEditor = true
            } label: {
                Label("Edit recipe", systemImage: "pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MiseTheme.ink)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(MiseTheme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(MiseTheme.line, lineWidth: 1)
                    )
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            MiseDivider()
            HStack(spacing: 12) {
                Button {
                    if hasInstructions {
                        showCookingMode = true
                    } else {
                        showEditor = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: hasInstructions ? "play.fill" : "plus")
                            .font(.footnote.weight(.bold))
                        Text(cookButtonTitle)
                    }
                }
                .buttonStyle(PrimaryButtonStyle(fill: hasInstructions ? MiseTheme.ink : MiseTheme.accent))
                .accessibilityIdentifier("cookButton")

                Button {
                    addToShoppingList()
                } label: {
                    Image(systemName: didAddToList ? "checkmark" : "cart.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(MiseTheme.ink)
                        .frame(width: 52, height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(MiseTheme.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(MiseTheme.line, lineWidth: 1)
                        )
                }
                .accessibilityLabel("Add ingredients to shopping list")
                .accessibilityIdentifier("addToShoppingButton")
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .frame(maxWidth: 760)
        }
        .background(MiseTheme.background)
    }

    private var cookButtonTitle: String {
        if !hasInstructions { return "Add steps to cook" }
        if recipe.hasCookingProgress {
            return "Resume at step \(recipe.cookingStepIndex + 1)"
        }
        return sortedInstructions.isEmpty ? "Start cooking" : "Start cooking"
    }

    private var shareText: String {
        var lines: [String] = [recipe.title]
        if let summary = recipe.summary, !summary.isEmpty {
            lines.append("")
            lines.append(summary)
        }
        lines.append("")
        lines.append("INGREDIENTS")
        for ingredient in sortedIngredients {
            lines.append("• \(ingredient.originalText)")
        }
        lines.append("")
        lines.append("METHOD")
        for (index, instruction) in sortedInstructions.enumerated() {
            lines.append("\(index + 1). \(instruction.text)")
        }
        if let notes = recipe.notes, !notes.isEmpty {
            lines.append("")
            lines.append("NOTES")
            lines.append(notes)
        }
        if let url = recipe.sourceURL {
            lines.append("")
            lines.append("Source: \(url.absoluteString)")
        }
        lines.append("")
        lines.append("Saved with Mise")
        return lines.joined(separator: "\n")
    }

    private func addToShoppingList() {
        if shoppingLists.isEmpty {
            showShoppingPicker = true
            return
        }
        if shoppingLists.count == 1 {
            let list = shoppingLists[0]
            let count = app.store.addAllIngredients(from: [recipe], to: list)
            Haptics.success()
            didAddToList = true
            router.showToast(count == 1 ? "Added 1 item to \(list.name)" : "Added \(count) items to \(list.name)", symbol: "cart.badge.plus")
        } else {
            showShoppingPicker = true
        }
    }
}
