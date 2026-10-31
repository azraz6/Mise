import SwiftData
import SwiftUI

private enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case favourites
    case website
    case social
    case linkOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .favourites: return "Favourites"
        case .website: return "Websites"
        case .social: return "Social"
        case .linkOnly: return "Link only"
        }
    }
}

private enum LibraryLayout: String {
    case list
    case grid
}

struct LibraryView: View {
    @Environment(AppDependencies.self) private var app
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Query(sort: \Recipe.dateAdded, order: .reverse) private var recipes: [Recipe]
    @Query(sort: \RecipeCollection.sortOrder) private var collections: [RecipeCollection]
    @Query(sort: \ShoppingList.updatedAt, order: .reverse) private var shoppingLists: [ShoppingList]

    @AppStorage("com.mise.libraryLayout") private var layoutRaw = LibraryLayout.list.rawValue
    @State private var searchText = ""
    @State private var filter: LibraryFilter = .all
    @State private var sort: RecipeSortOrder = .recentlyAdded
    @State private var showArchived = false
    @State private var showManageCollections = false
    @State private var showNewCollection = false
    @State private var recipeToDelete: Recipe?
    @State private var showDeleteAlert = false
    @State private var collectionPickerRecipe: Recipe?
    @State private var archivedCount = 0

    private var layout: LibraryLayout {
        LibraryLayout(rawValue: layoutRaw) ?? .list
    }

    private var visibleRecipes: [Recipe] {
        var filterValue = RecipeFilter(
            query: searchText,
            favouritesOnly: filter == .favourites,
            includeArchived: showArchived
        )
        if filter == .website {
            filterValue.sourceType = .website
        }
        var result = RecipeSearch.apply(recipes, filter: filterValue, sort: sort)
        switch filter {
        case .social:
            result = result.filter { $0.sourceType.isSocial }
        case .linkOnly:
            result = result.filter { $0.extractionMethod == .linkOnly }
        default:
            break
        }
        return result
    }

    private var activeCount: Int {
        recipes.filter { !$0.isArchived }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    searchField
                    filterRow
                    if !collections.isEmpty {
                        collectionsStrip
                    }
                    recipesSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 36)
                .frame(maxWidth: 780, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(PageBackground())
            .statusBarScrim()
            .toolbar(.hidden, for: .navigationBar)
            .scrollDismissesKeyboard(.interactively)
        }
        .sheet(isPresented: $showManageCollections) {
            CollectionsManageView()
                .environment(app)
                .environment(router)
                .modelContainer(app.container)
        }
        .sheet(isPresented: $showNewCollection) {
            CollectionEditorView(collection: nil)
                .environment(app)
                .environment(router)
                .modelContainer(app.container)
        }
        .sheet(item: $collectionPickerRecipe) { recipe in
            CollectionPickerView(recipe: recipe)
                .environment(app)
                .modelContainer(app.container)
        }
        .alert("Delete recipe?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { recipeToDelete = nil }
            Button("Delete", role: .destructive) {
                if let recipe = recipeToDelete {
                    app.store.delete(recipe)
                    router.showToast("Recipe deleted", symbol: "trash.circle.fill")
                }
                recipeToDelete = nil
            }
        } message: {
            Text("“\(recipeToDelete?.title ?? "This recipe")” will be removed from your library, collections, and meal plan. This can’t be undone.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Library")
                        .font(.system(.largeTitle, design: .serif, weight: .semibold))
                        .foregroundStyle(MiseTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(activeCount == 1 ? "1 recipe, saved on this iPhone" : "\(activeCount) recipes, saved on this iPhone")
                        .font(.subheadline)
                        .foregroundStyle(MiseTheme.secondaryInk)
                }
                Spacer()
                Menu {
                    Button {
                        showManageCollections = true
                    } label: {
                        Label("Manage collections", systemImage: "rectangle.stack")
                    }
                    Button {
                        showArchived.toggle()
                        archivedCount = recipes.filter(\.isArchived).count
                    } label: {
                        Label(showArchived ? "Hide archived" : "Show archived", systemImage: showArchived ? "archivebox.fill" : "archivebox")
                    }
                    Divider()
                    Button {
                        router.showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(MiseTheme.ink)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(MiseTheme.surface))
                        .overlay(Circle().stroke(MiseTheme.line, lineWidth: 1))
                }
                .accessibilityLabel("Library options")
                .accessibilityIdentifier("libraryMenu")

                Button {
                    router.openImport()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(MiseTheme.background)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(MiseTheme.ink))
                }
                .accessibilityLabel("Add recipe")
                .accessibilityIdentifier("addRecipeButton")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(MiseTheme.secondaryInk)
            TextField(dynamicTypeSize.isAccessibilitySize ? "Search recipes" : "Search recipes, ingredients, notes", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(MiseTheme.ink)
                .accessibilityIdentifier("librarySearchField")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MiseTheme.secondaryInk)
                }
                .accessibilityLabel("Clear search")
            }
            Menu {
                ForEach(RecipeSortOrder.allCases) { order in
                    Button {
                        sort = order
                    } label: {
                        if sort == order {
                            Label(order.displayName, systemImage: "checkmark")
                        } else {
                            Text(order.displayName)
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MiseTheme.ink)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(MiseTheme.raisedSurface))
            }
            .accessibilityLabel("Sort recipes")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MiseTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MiseTheme.line, lineWidth: 1)
        )
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryFilter.allCases) { option in
                    Button {
                        filter = option
                        Haptics.tap()
                    } label: {
                        TagChip(text: option.title, highlighted: filter == option)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(filter == option ? [.isSelected] : [])
                }
                if showArchived {
                    TagChip(text: "Archived shown", highlighted: true)
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        layoutRaw = layout == .list ? LibraryLayout.grid.rawValue : LibraryLayout.list.rawValue
                    }
                } label: {
                    Image(systemName: layout == .list ? "square.grid.2x2" : "list.bullet")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MiseTheme.secondaryInk)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(MiseTheme.raisedSurface))
                }
                .accessibilityLabel(layout == .list ? "Show recipe grid" : "Show recipe list")
            }
        }
        .scrollClipDisabled()
    }

    // MARK: - Collections

    private var collectionsStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Collections")
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(MiseTheme.ink)
                Spacer()
                Button("Manage") {
                    showManageCollections = true
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MiseTheme.accent)
                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                .contentShape(Rectangle())
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(collections) { collection in
                        NavigationLink {
                            CollectionDetailView(collection: collection)
                        } label: {
                            collectionCard(collection)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        attemptNewCollection()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .semibold))
                            Text("New")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(MiseTheme.secondaryInk)
                        .frame(width: 92, height: 92)
                        .background(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(MiseTheme.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .foregroundStyle(MiseTheme.line)
                        )
                    }
                    .accessibilityLabel("New collection")
                }
            }
            .scrollClipDisabled()
        }
        .padding(.top, 2)
    }

    private func collectionCard(_ collection: RecipeCollection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "rectangle.stack")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MiseTheme.sage)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MiseTheme.secondaryInk.opacity(0.6))
            }
            Spacer(minLength: 0)
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
            height: dynamicTypeSize.isAccessibilitySize ? 170 : 104,
            alignment: .leading
        )
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(MiseTheme.raisedSurface)
        )
    }

    // MARK: - Recipes

    private var recipesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(searchText.isEmpty ? "All recipes" : "Results")
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(MiseTheme.ink)
                Text("\(visibleRecipes.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MiseTheme.secondaryInk)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(MiseTheme.raisedSurface))
                Spacer()
            }

            if recipes.isEmpty {
                EmptyStateView(
                    symbol: "book.closed",
                    title: "Your library is waiting",
                    message: "Save a recipe from a link, a screenshot, or write one yourself. A few starter recipes are included if you’d like company.",
                    buttonTitle: "Add your first recipe"
                ) {
                    router.openImport()
                }
                .padding(.top, 12)
            } else if visibleRecipes.isEmpty {
                EmptyStateView(
                    symbol: searchText.isEmpty ? "line.3.horizontal.decrease.circle" : "magnifyingglass",
                    title: searchText.isEmpty ? "Nothing here yet" : "No recipes found",
                    message: searchText.isEmpty ? "Try a different filter, or add a recipe to this part of your library." : "Try a different word, or clear the search to see everything.",
                    buttonTitle: "Clear search"
                ) {
                    searchText = ""
                    filter = .all
                }
                .padding(.top, 12)
            } else if layout == .list {
                LazyVStack(spacing: 0) {
                    ForEach(Array(visibleRecipes.enumerated()), id: \.element.id) { index, recipe in
                        NavigationLink {
                            RecipeDetailView(recipe: recipe)
                        } label: {
                            RecipeRow(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            recipeContextMenu(recipe)
                        }
                        if index < visibleRecipes.count - 1 {
                            MiseDivider().padding(.leading, 92)
                        }
                    }
                }
            } else {
                LazyVGrid(
                    columns: dynamicTypeSize.isAccessibilitySize
                        ? [GridItem(.flexible())]
                        : [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                    alignment: .leading,
                    spacing: 20
                ) {
                    ForEach(visibleRecipes) { recipe in
                        NavigationLink {
                            RecipeDetailView(recipe: recipe)
                        } label: {
                            RecipeCard(
                                recipe: recipe,
                                width: gridCardWidth,
                                titleLineLimit: dynamicTypeSize.isAccessibilitySize ? 3 : 2
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            recipeContextMenu(recipe)
                        }
                    }
                }
            }
        }
    }

    private var gridCardWidth: CGFloat {
        let available = min(UIScreen.main.bounds.width, 780) - 40
        if dynamicTypeSize.isAccessibilitySize { return available }
        return (available - 14) / 2
    }

    @ViewBuilder
    private func recipeContextMenu(_ recipe: Recipe) -> some View {
        Button {
            app.store.toggleFavourite(recipe)
            Haptics.tap()
        } label: {
            Label(recipe.isFavourite ? "Remove from favourites" : "Add to favourites", systemImage: recipe.isFavourite ? "heart.slash" : "heart")
        }
        Button {
            collectionPickerRecipe = recipe
        } label: {
            Label("Add to collection", systemImage: "rectangle.stack.badge.plus")
        }
        Button {
            app.store.setArchived(recipe, archived: !recipe.isArchived)
        } label: {
            Label(recipe.isArchived ? "Unarchive" : "Archive", systemImage: recipe.isArchived ? "archivebox" : "archivebox")
        }
        if let list = shoppingLists.first {
            Button {
                let count = app.store.addAllIngredients(from: [recipe], to: list)
                router.showToast(count == 1 ? "Added 1 item to \(list.name)" : "Added \(count) items to \(list.name)", symbol: "cart.badge.plus")
            } label: {
                Label("Add ingredients to \(list.name)", systemImage: "cart.badge.plus")
            }
        }
        if let url = recipe.sourceURL {
            ShareLink(item: url) {
                Label("Share source link", systemImage: "square.and.arrow.up")
            }
        }
        Divider()
        Button(role: .destructive) {
            recipeToDelete = recipe
            showDeleteAlert = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func attemptNewCollection() {
        if app.usage.canCreateCollection(existingCount: collections.count, isPremium: app.subscriptions.isPremium) {
            showNewCollection = true
        } else {
            Haptics.warning()
            router.paywallReason = .collectionLimit
        }
    }
}
