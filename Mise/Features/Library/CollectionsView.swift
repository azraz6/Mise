import SwiftData
import SwiftUI

// MARK: - Manage collections

struct CollectionsManageView: View {
    @Environment(AppDependencies.self) private var app
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \RecipeCollection.sortOrder) private var collections: [RecipeCollection]
    @Query(sort: \Recipe.dateAdded, order: .reverse) private var recipes: [Recipe]

    @State private var showEditor = false
    @State private var editingCollection: RecipeCollection?
    @State private var collectionToDelete: RecipeCollection?
    @State private var showDeleteConfirmation = false
    @State private var paywallReason: PaywallReason?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Group recipes for a weeknight rotation, a dinner party, or anything you like. A recipe can live in more than one collection.")
                        .font(.subheadline)
                        .foregroundStyle(MiseTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)

                    if collections.isEmpty {
                        EmptyStateView(
                            symbol: "rectangle.stack",
                            title: "No collections yet",
                            message: "Collections are small shelves inside your library. Make one for the recipes you return to.",
                            buttonTitle: "Create a collection"
                        ) {
                            attemptCreate()
                        }
                        .padding(.top, 16)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(collections.enumerated()), id: \.element.id) { index, collection in
                                NavigationLink {
                                    CollectionDetailView(collection: collection)
                                } label: {
                                    collectionRow(collection)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        editingCollection = collection
                                        showEditor = true
                                    } label: {
                                        Label("Rename collection", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        collectionToDelete = collection
                                        showDeleteConfirmation = true
                                    } label: {
                                        Label("Delete collection", systemImage: "trash")
                                    }
                                }
                                if index < collections.count - 1 {
                                    MiseDivider().padding(.leading, 54)
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

                        if !app.subscriptions.isPremium {
                            Text("Free plan includes \(FreeTier.collections) collections. Yours: \(collections.count).")
                                .font(.caption)
                                .foregroundStyle(MiseTheme.secondaryInk)
                        }
                    }

                    Button {
                        attemptCreate()
                    } label: {
                        Label("New collection", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MiseTheme.accent)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(MiseTheme.accent.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .background(PageBackground())
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MiseTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showEditor, onDismiss: { editingCollection = nil }) {
            CollectionEditorView(collection: editingCollection)
                .environment(app)
                .environment(router)
                .modelContainer(app.container)
        }
        .sheet(item: $paywallReason) { reason in
            PaywallView(reason: reason)
                .environment(app)
                .environment(router)
                .modelContainer(app.container)
        }
        .alert("Delete collection?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { collectionToDelete = nil }
            Button("Delete", role: .destructive) {
                if let collectionToDelete {
                    app.store.deleteCollection(collectionToDelete)
                    router.showToast("Collection deleted")
                }
                collectionToDelete = nil
            }
        } message: {
            Text("“\(collectionToDelete?.name ?? "This collection")” will be removed. The recipes inside stay in your library.")
        }
    }

    private func collectionRow(_ collection: RecipeCollection) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MiseTheme.sage)
                .frame(width: 34, height: 34)
                .background(Circle().fill(MiseTheme.sage.opacity(0.1)))
            VStack(alignment: .leading, spacing: 2) {
                Text(collection.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MiseTheme.ink)
                Text("^[\(collection.recipeIDs.count) recipe](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(MiseTheme.secondaryInk)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(MiseTheme.secondaryInk.opacity(0.55))
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func attemptCreate() {
        if app.usage.canCreateCollection(existingCount: collections.count, isPremium: app.subscriptions.isPremium) {
            editingCollection = nil
            showEditor = true
        } else {
            Haptics.warning()
            paywallReason = .collectionLimit
        }
    }
}

// MARK: - Create / rename

struct CollectionEditorView: View {
    @Environment(AppDependencies.self) private var app
    @Environment(\.dismiss) private var dismiss

    let collection: RecipeCollection?

    @State private var name: String
    @State private var summary: String
    @State private var errorMessage: String?

    init(collection: RecipeCollection?) {
        self.collection = collection
        _name = State(initialValue: collection?.name ?? "")
        _summary = State(initialValue: collection?.summary ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        FieldLabel(text: "Name")
                        TextField("Weeknight dinners", text: $name)
                            .font(.system(.title3, design: .serif, weight: .semibold))
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(MiseTheme.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(MiseTheme.line, lineWidth: 1)
                            )
                            .accessibilityIdentifier("collectionNameField")
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        FieldLabel(text: "Note", optional: true)
                        ZStack(alignment: .topLeading) {
                            if summary.isEmpty {
                                Text("What belongs on this shelf?")
                                    .foregroundStyle(MiseTheme.secondaryInk.opacity(0.6))
                                    .padding(.top, 13)
                                    .padding(.leading, 17)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $summary)
                                .font(.body)
                                .frame(minHeight: 100)
                                .scrollContentBackground(.hidden)
                                .padding(8)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(MiseTheme.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(MiseTheme.line, lineWidth: 1)
                        )
                    }

                    Text("You can add recipes from any recipe’s menu, or from inside the collection.")
                        .font(.caption)
                        .foregroundStyle(MiseTheme.secondaryInk)

                    if let errorMessage {
                        InlineNotice(style: .error, message: errorMessage)
                    }
                }
                .padding(20)
            }
            .background(PageBackground())
            .navigationTitle(collection == nil ? "New collection" : "Edit collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MiseTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        do {
            if let collection {
                try app.store.updateCollection(collection, name: name, summary: summary)
            } else {
                try app.store.createCollection(name: name, summary: summary)
            }
            Haptics.success()
            dismiss()
        } catch {
            errorMessage = "Mise couldn’t save this collection. Check the name and try again."
        }
    }
}

// MARK: - Collection detail

struct CollectionDetailView: View {
    @Environment(AppDependencies.self) private var app
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    let collection: RecipeCollection
    @Query(sort: \Recipe.dateAdded, order: .reverse) private var recipes: [Recipe]

    @State private var showAddRecipes = false
    @State private var showEdit = false
    @State private var showDeleteConfirmation = false
    @State private var recipeToRemove: Recipe?

    private var collectionRecipes: [Recipe] {
        let ids = Set(collection.recipeIDs)
        return recipes
            .filter { ids.contains($0.id) }
            .sorted { $0.dateAdded > $1.dateAdded }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if !collectionRecipes.isEmpty {
                    coverStrip
                }
                if let summary = collection.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(MiseTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if collectionRecipes.isEmpty {
                    EmptyStateView(
                        symbol: "rectangle.stack.badge.plus",
                        title: "This shelf is empty",
                        message: "Add recipes from your library to make this collection useful.",
                        buttonTitle: "Add recipes"
                    ) {
                        showAddRecipes = true
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recipes")
                            .font(.system(.title3, design: .serif, weight: .semibold))
                            .foregroundStyle(MiseTheme.ink)
                        LazyVStack(spacing: 0) {
                            ForEach(Array(collectionRecipes.enumerated()), id: \.element.id) { index, recipe in
                                NavigationLink {
                                    RecipeDetailView(recipe: recipe)
                                } label: {
                                    RecipeRow(recipe: recipe)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        app.store.setRecipe(recipe, in: collection, included: false)
                                        router.showToast("Removed from \(collection.name)")
                                    } label: {
                                        Label("Remove from collection", systemImage: "rectangle.stack.badge.minus")
                                    }
                                    Button(role: .destructive) {
                                        recipeToRemove = recipe
                                    } label: {
                                        Label("Delete recipe", systemImage: "trash")
                                    }
                                }
                                if index < collectionRecipes.count - 1 {
                                    MiseDivider().padding(.leading, 92)
                                }
                            }
                        }
                    }

                    Button {
                        showAddRecipes = true
                    } label: {
                        Label("Add more recipes", systemImage: "plus.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MiseTheme.accent)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 34)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(PageBackground())
        .toolbar(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showEdit = true
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Edit collection")

                Menu {
                    Button {
                        showAddRecipes = true
                    } label: {
                        Label("Add recipes", systemImage: "plus")
                    }
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete collection", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Collection options")
            }
        }
        .sheet(isPresented: $showAddRecipes) {
            AddRecipesToCollectionView(collection: collection)
                .environment(app)
                .modelContainer(app.container)
        }
        .sheet(isPresented: $showEdit) {
            CollectionEditorView(collection: collection)
                .environment(app)
                .environment(router)
                .modelContainer(app.container)
        }
        .alert("Delete collection?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                app.store.deleteCollection(collection)
                dismiss()
            }
        } message: {
            Text("“\(collection.name)” will be removed. The recipes inside stay in your library.")
        }
        .alert("Delete recipe?", isPresented: Binding(
            get: { recipeToRemove != nil },
            set: { if !$0 { recipeToRemove = nil } }
        )) {
            Button("Cancel", role: .cancel) { recipeToRemove = nil }
            Button("Delete", role: .destructive) {
                if let recipeToRemove {
                    app.store.delete(recipeToRemove)
                }
                recipeToRemove = nil
            }
        } message: {
            Text("This removes the recipe from your whole library, not just this collection.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("COLLECTION")
                .font(.caption.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(MiseTheme.sage)
            Text(collection.name)
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(MiseTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("^[\(collectionRecipes.count) recipe](inflect: true)")
                .font(.subheadline)
                .foregroundStyle(MiseTheme.secondaryInk)
        }
    }

    private var coverStrip: some View {
        HStack(spacing: 8) {
            ForEach(Array(collectionRecipes.prefix(3))) { recipe in
                RecipeCoverImage(
                    filename: recipe.coverImageFilename,
                    assetName: recipe.coverAssetName,
                    cornerRadius: 12
                )
                .frame(maxWidth: .infinity)
                .frame(height: 108)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Add recipes to a collection

struct AddRecipesToCollectionView: View {
    @Environment(AppDependencies.self) private var app
    @Environment(\.dismiss) private var dismiss

    let collection: RecipeCollection
    @Query(sort: \Recipe.dateAdded, order: .reverse) private var recipes: [Recipe]

    @State private var searchText = ""
    @State private var selectedIDs: Set<UUID> = []
    @State private var didLoad = false

    private var visible: [Recipe] {
        RecipeSearch.apply(recipes, filter: RecipeFilter(query: searchText), sort: .title)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    searchField
                    if visible.isEmpty {
                        EmptyStateView(
                            symbol: "magnifyingglass",
                            title: "No recipes found",
                            message: "Try a different search, or add a recipe to your library first."
                        )
                        .padding(.top, 20)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(visible.enumerated()), id: \.element.id) { index, recipe in
                                Button {
                                    toggle(recipe)
                                } label: {
                                    HStack(spacing: 12) {
                                        RecipeCoverImage(
                                            filename: recipe.coverImageFilename,
                                            assetName: recipe.coverAssetName,
                                            cornerRadius: 10
                                        )
                                        .frame(width: 54, height: 54)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(recipe.title)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(MiseTheme.ink)
                                                .lineLimit(2)
                                            if let total = recipe.totalMinutes {
                                                Text("\(total) min")
                                                    .font(.caption)
                                                    .foregroundStyle(MiseTheme.secondaryInk)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: selectedIDs.contains(recipe.id) ? "checkmark.circle.fill" : "circle")
                                            .font(.title3)
                                            .foregroundStyle(selectedIDs.contains(recipe.id) ? MiseTheme.sage : MiseTheme.secondaryInk.opacity(0.4))
                                    }
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if index < visible.count - 1 {
                                    MiseDivider().padding(.leading, 66)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(PageBackground())
            .navigationTitle("Add to \(collection.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MiseTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { saveSelection() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                guard !didLoad else { return }
                selectedIDs = Set(collection.recipeIDs)
                didLoad = true
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(MiseTheme.secondaryInk)
            TextField("Search your library", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MiseTheme.secondaryInk)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 46)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(MiseTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(MiseTheme.line, lineWidth: 1)
        )
    }

    private func toggle(_ recipe: Recipe) {
        if selectedIDs.contains(recipe.id) {
            selectedIDs.remove(recipe.id)
        } else {
            selectedIDs.insert(recipe.id)
        }
        Haptics.tap()
    }

    private func saveSelection() {
        let existing = Set(collection.recipeIDs)
        for recipe in recipes {
            let shouldInclude = selectedIDs.contains(recipe.id)
            if shouldInclude != existing.contains(recipe.id) {
                app.store.setRecipe(recipe, in: collection, included: shouldInclude)
            }
        }
        Haptics.success()
        dismiss()
    }
}

// MARK: - Add to collection from a recipe

struct CollectionPickerView: View {
    @Environment(AppDependencies.self) private var app
    @Environment(\.dismiss) private var dismiss

    let recipe: Recipe
    @Query(sort: \RecipeCollection.sortOrder) private var collections: [RecipeCollection]

    @State private var showNewCollection = false
    @State private var newName = ""
    @State private var showLimitNotice = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if collections.isEmpty {
                        EmptyStateView(
                            symbol: "rectangle.stack.badge.plus",
                            title: "No collections yet",
                            message: "Make a collection, then add this recipe to it.",
                            buttonTitle: "Create a collection"
                        ) {
                            attemptCreate()
                        }
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(collections.enumerated()), id: \.element.id) { index, collection in
                                Button {
                                    toggle(collection)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "rectangle.stack")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(MiseTheme.sage)
                                            .frame(width: 32, height: 32)
                                            .background(Circle().fill(MiseTheme.sage.opacity(0.1)))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(collection.name)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(MiseTheme.ink)
                                            Text("^[\(collection.recipeIDs.count) recipe](inflect: true)")
                                                .font(.caption2)
                                                .foregroundStyle(MiseTheme.secondaryInk)
                                        }
                                        Spacer()
                                        Image(systemName: collection.contains(recipe.id) ? "checkmark.circle.fill" : "circle")
                                            .font(.title3)
                                            .foregroundStyle(collection.contains(recipe.id) ? MiseTheme.sage : MiseTheme.secondaryInk.opacity(0.35))
                                    }
                                    .padding(.vertical, 11)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if index < collections.count - 1 {
                                    MiseDivider().padding(.leading, 46)
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

                        Button {
                            attemptCreate()
                        } label: {
                            Label("New collection", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MiseTheme.accent)
                        }
                    }
                }
                .padding(20)
            }
            .background(PageBackground())
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MiseTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .alert("New collection", isPresented: $showNewCollection) {
            TextField("Collection name", text: $newName)
            Button("Cancel", role: .cancel) { newName = "" }
            Button("Create") { createCollection() }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("This recipe will be added to the new collection.")
        }
        .alert("Collection limit reached", isPresented: $showLimitNotice) {
            Button("Not now", role: .cancel) {}
            Button("See Mise Premium") {
                dismiss()
            }
        } message: {
            Text("The free plan includes \(FreeTier.collections) collections and \(FreeTier.automaticImportsPerMonth) automatic imports each month. Mise Premium removes those limits. You can upgrade from Settings.")
        }
    }

    private func toggle(_ collection: RecipeCollection) {
        let included = collection.contains(recipe.id)
        app.store.setRecipe(recipe, in: collection, included: !included)
        Haptics.tap()
    }

    private func attemptCreate() {
        guard app.usage.canCreateCollection(existingCount: collections.count, isPremium: app.subscriptions.isPremium) else {
            Haptics.warning()
            showLimitNotice = true
            return
        }
        newName = ""
        showNewCollection = true
    }

    private func createCollection() {
        do {
            let collection = try app.store.createCollection(name: newName)
            app.store.setRecipe(recipe, in: collection, included: true)
            newName = ""
            Haptics.success()
        } catch {
            Haptics.warning()
        }
    }
}
