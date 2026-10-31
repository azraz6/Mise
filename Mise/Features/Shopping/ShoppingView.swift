import SwiftData
import SwiftUI

struct ShoppingView: View {
    @Environment(AppDependencies.self) private var app
    @Environment(AppRouter.self) private var router

    @Query(sort: \ShoppingList.updatedAt, order: .reverse) private var lists: [ShoppingList]
    @Query(sort: \ShoppingItem.createdAt) private var allItems: [ShoppingItem]
    @Query(sort: \Recipe.dateAdded, order: .reverse) private var recipes: [Recipe]

    @State private var selectedListID: UUID?
    @State private var newItemName = ""
    @State private var showAddRecipes = false
    @State private var showNewList = false
    @State private var newListName = ""
    @State private var showRenameList = false
    @State private var renameText = ""
    @State private var showDeleteList = false
    @State private var editingItem: ShoppingItem?
    @FocusState private var newItemFocused: Bool

    private var currentList: ShoppingList? {
        if let selectedListID, let match = lists.first(where: { $0.id == selectedListID }) {
            return match
        }
        return lists.first
    }

    private var currentItems: [ShoppingItem] {
        guard let currentList else { return [] }
        return allItems.filter { $0.listID == currentList.id }
    }

    private var uncheckedItems: [ShoppingItem] {
        currentItems.filter { !$0.isChecked }
    }

    private var checkedItems: [ShoppingItem] {
        currentItems.filter(\.isChecked)
    }

    private var groupedItems: [(ShoppingCategory, [ShoppingItem])] {
        let grouped = Dictionary(grouping: uncheckedItems, by: \.category)
        return grouped
            .map { ($0.key, $0.value.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) }
            .sorted { $0.0.sortIndex < $1.0.sortIndex }
    }

    private var doneCount: Int {
        currentItems.filter(\.isChecked).count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if lists.isEmpty {
                        emptyLibrary
                    } else if let list = currentList {
                        listSwitcher
                        listOverview(list)
                        addBar
                        if currentItems.isEmpty {
                            emptyList
                        } else {
                            itemGroups
                            if !checkedItems.isEmpty {
                                completedSection
                            }
                        }
                        mergingNote
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 36)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(PageBackground())
            .statusBarScrim()
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { newItemFocused = false }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sheet(isPresented: $showAddRecipes) {
            if let currentList {
                RecipeSelectionForShoppingView(list: currentList)
                    .environment(app)
                    .environment(router)
                    .modelContainer(app.container)
            }
        }
        .sheet(item: $editingItem) { item in
            ShoppingItemEditorView(item: item)
                .environment(app)
                .environment(router)
                .modelContainer(app.container)
        }
        .alert("New shopping list", isPresented: $showNewList) {
            TextField("List name", text: $newListName)
            Button("Cancel", role: .cancel) { newListName = "" }
            Button("Create") { createList() }
                .disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Rename list", isPresented: $showRenameList) {
            TextField("List name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let currentList {
                    try? app.store.renameShoppingList(currentList, name: renameText)
                }
            }
        }
        .alert("Delete shopping list?", isPresented: $showDeleteList) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let currentList {
                    app.store.deleteShoppingList(currentList)
                    selectedListID = lists.first(where: { $0.id != currentList.id })?.id
                    router.showToast("Shopping list deleted")
                }
            }
        } message: {
            Text("“\(currentList?.name ?? "This list")” and all of its items will be removed.")
        }
        .onAppear {
            if selectedListID == nil {
                selectedListID = lists.first?.id
            }
        }
        .onChange(of: lists.count) { _, _ in
            if let selectedListID, !lists.contains(where: { $0.id == selectedListID }) {
                self.selectedListID = lists.first?.id
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Shopping")
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    .foregroundStyle(MiseTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(currentList?.name ?? "A calm list for the store")
                    .font(.subheadline)
                    .foregroundStyle(MiseTheme.secondaryInk)
            }
            Spacer()
            if currentList != nil {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(MiseTheme.ink)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(MiseTheme.surface))
                        .overlay(Circle().stroke(MiseTheme.line, lineWidth: 1))
                }
                .accessibilityLabel("Share shopping list")
                .accessibilityIdentifier("shareShoppingList")
            }
            Menu {
                Button {
                    newListName = ""
                    showNewList = true
                } label: {
                    Label("New list", systemImage: "plus")
                }
                if currentList != nil {
                    Button {
                        renameText = currentList?.name ?? ""
                        showRenameList = true
                    } label: {
                        Label("Rename list", systemImage: "pencil")
                    }
                    if !checkedItems.isEmpty {
                        Button {
                            app.store.clearCompleted(in: currentList!)
                            Haptics.tap()
                        } label: {
                            Label("Clear completed", systemImage: "checkmark.circle")
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        showDeleteList = true
                    } label: {
                        Label("Delete list", systemImage: "trash")
                    }
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
            .accessibilityLabel("Shopping list options")
        }
    }

    private var listSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(lists) { list in
                    Button {
                        selectedListID = list.id
                        Haptics.tap()
                    } label: {
                        HStack(spacing: 6) {
                            Text(list.name)
                                .font(.caption.weight(.medium))
                            let count = allItems.filter { $0.listID == list.id && !$0.isChecked }.count
                            if count > 0 {
                                Text("\(count)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(selectedListID == list.id ? MiseTheme.ink : MiseTheme.secondaryInk)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(MiseTheme.surface.opacity(0.7)))
                            }
                        }
                        .foregroundStyle(selectedListID == list.id ? MiseTheme.background : MiseTheme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(selectedListID == list.id ? MiseTheme.ink : MiseTheme.raisedSurface)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedListID == list.id ? [.isSelected] : [])
                }
                Button {
                    newListName = ""
                    showNewList = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MiseTheme.secondaryInk)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(MiseTheme.raisedSurface))
                }
                .accessibilityLabel("New list")
            }
        }
        .scrollClipDisabled()
    }

    private func listOverview(_ list: ShoppingList) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.name)
                        .font(.system(.title2, design: .serif, weight: .semibold))
                        .foregroundStyle(MiseTheme.ink)
                    Text(currentItems.isEmpty ? "Nothing on the list yet" : "\(doneCount) of \(currentItems.count) picked up")
                        .font(.caption)
                        .foregroundStyle(MiseTheme.secondaryInk)
                }
                Spacer()
                if !currentItems.isEmpty {
                    Text("\(currentItems.count - doneCount) left")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MiseTheme.sage)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(MiseTheme.sage.opacity(0.1)))
                }
            }
            ProgressView(value: Double(doneCount), total: Double(max(currentItems.count, 1)))
                .tint(MiseTheme.sage)
                .accessibilityLabel("Shopping progress")
                .accessibilityValue("\(doneCount) of \(currentItems.count) items picked up")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(MiseTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(MiseTheme.line, lineWidth: 1)
        )
    }

    private var addBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus.circle")
                .foregroundStyle(MiseTheme.sage)
            TextField("Add an item", text: $newItemName)
                .focused($newItemFocused)
                .submitLabel(.done)
                .onSubmit(addCustomItem)
                .foregroundStyle(MiseTheme.ink)
                .accessibilityIdentifier("shoppingItemField")
            if !newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Add", action: addCustomItem)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MiseTheme.accent)
                    .accessibilityIdentifier("addShoppingItemButton")
            }
            Button {
                showAddRecipes = true
            } label: {
                Image(systemName: "book.pages")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MiseTheme.ink)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(MiseTheme.raisedSurface))
            }
            .accessibilityLabel("Add ingredients from recipes")
            .accessibilityIdentifier("addRecipeIngredientsButton")
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 50)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MiseTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MiseTheme.line, lineWidth: 1)
        )
    }

    // MARK: - Items

    private var itemGroups: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(groupedItems.enumerated()), id: \.offset) { _, group in
                let category = group.0
                let items = group.1
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Image(systemName: category.symbolName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MiseTheme.sage)
                        Text(category.displayName.uppercased())
                            .font(.caption2.weight(.semibold))
                            .tracking(0.9)
                            .foregroundStyle(MiseTheme.secondaryInk)
                        Text("\(items.count)")
                            .font(.caption2)
                            .foregroundStyle(MiseTheme.secondaryInk.opacity(0.7))
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            itemRow(item)
                            if index < items.count - 1 {
                                MiseDivider().padding(.leading, 42)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
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
        }
    }

    private func itemRow(_ item: ShoppingItem) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Button {
                app.store.toggleChecked(item)
                Haptics.tap()
            } label: {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(item.isChecked ? MiseTheme.sage : MiseTheme.secondaryInk.opacity(0.55))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isChecked ? "Uncheck \(item.name)" : "Check off \(item.name)")

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.name)
                        .font(.body)
                        .foregroundStyle(item.isChecked ? MiseTheme.secondaryInk : MiseTheme.ink)
                        .strikethrough(item.isChecked, color: MiseTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    if item.quantity != nil {
                        Text(item.quantityText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(MiseTheme.secondaryInk)
                    }
                }
                if let title = item.sourceRecipeTitle, !title.isEmpty {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(MiseTheme.secondaryInk.opacity(0.8))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button {
                    editingItem = item
                } label: {
                    Label("Edit item", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    app.store.deleteItem(item)
                } label: {
                    Label("Delete item", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MiseTheme.secondaryInk.opacity(0.65))
                    .frame(width: 24, height: 26)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Options for \(item.name)")
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture {
            app.store.toggleChecked(item)
            Haptics.tap()
        }
    }

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PICKED UP")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.9)
                    .foregroundStyle(MiseTheme.secondaryInk)
                Spacer()
                Button("Clear") {
                    if let currentList {
                        app.store.clearCompleted(in: currentList)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(MiseTheme.secondaryInk)
            }
            VStack(spacing: 0) {
                ForEach(Array(checkedItems.enumerated()), id: \.element.id) { index, item in
                    itemRow(item)
                    if index < checkedItems.count - 1 {
                        MiseDivider().padding(.leading, 42)
                    }
                }
            }
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(MiseTheme.surface.opacity(0.7))
            )
        }
    }

    private var mergingNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.triangle.merge")
                .font(.caption2)
                .foregroundStyle(MiseTheme.secondaryInk)
                .padding(.top, 2)
            Text("Mise merges amounts only when the item and unit match exactly. Everything else stays separate, so nothing disappears at the store.")
                .font(.caption2)
                .foregroundStyle(MiseTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    // MARK: - Empty states

    private var emptyLibrary: some View {
        EmptyStateView(
            symbol: "cart",
            title: "A short list, please",
            message: "Make a shopping list, then add ingredients from one recipe or a whole week of meals.",
            buttonTitle: "Create a list"
        ) {
            newListName = "Shopping list"
            showNewList = true
        }
        .padding(.top, 24)
    }

    private var emptyList: some View {
        VStack(spacing: 14) {
            EmptyStateView(
                symbol: "basket",
                title: "Nothing to pick up",
                message: "Add an item above, or bring in the ingredients from a recipe.",
                buttonTitle: "Add recipe ingredients"
            ) {
                showAddRecipes = true
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Helpers

    private var shareText: String {
        guard let currentList else { return "" }
        var lines = [currentList.name, ""]
        for (category, items) in groupedItems {
            lines.append(category.displayName.uppercased())
            for item in items {
                lines.append("• \(item.name)\(item.quantity != nil ? " — \(item.quantityText)" : "")")
            }
            lines.append("")
        }
        if !checkedItems.isEmpty {
            lines.append("PICKED UP")
            for item in checkedItems {
                lines.append("✓ \(item.name)\(item.quantity != nil ? " — \(item.quantityText)" : "")")
            }
            lines.append("")
        }
        lines.append("Shared from Mise")
        return lines.joined(separator: "\n")
    }

    private func addCustomItem() {
        guard let currentList else { return }
        let trimmed = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        app.store.addCustomItem(to: currentList, name: trimmed)
        newItemName = ""
        newItemFocused = true
        Haptics.tap()
    }

    private func createList() {
        let name = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let list = app.store.createShoppingList(name: name)
        selectedListID = list.id
        newListName = ""
        Haptics.success()
    }
}

// MARK: - Recipe selection for a list

struct RecipeSelectionForShoppingView: View {
    @Environment(AppDependencies.self) private var app
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    let list: ShoppingList
    @Query(sort: \Recipe.dateAdded, order: .reverse) private var recipes: [Recipe]

    @State private var searchText = ""
    @State private var selectedIDs: Set<UUID> = []

    private var visible: [Recipe] {
        RecipeSearch.apply(recipes, filter: RecipeFilter(query: searchText), sort: .title)
    }

    private var selectedRecipes: [Recipe] {
        recipes.filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Choose one or more recipes. Mise adds their ingredients to “\(list.name)” and merges only compatible amounts.")
                        .font(.caption)
                        .foregroundStyle(MiseTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(MiseTheme.secondaryInk)
                        TextField("Search recipes", text: $searchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(MiseTheme.secondaryInk)
                            }
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

                    if visible.isEmpty {
                        EmptyStateView(
                            symbol: "magnifyingglass",
                            title: "No recipes found",
                            message: "Try a different search, or add recipes to your library first."
                        )
                        .padding(.top, 16)
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
                                        .frame(width: 52, height: 52)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(recipe.title)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(MiseTheme.ink)
                                                .lineLimit(2)
                                            Text("^[\(recipe.ingredients.count) ingredient](inflect: true)")
                                                .font(.caption2)
                                                .foregroundStyle(MiseTheme.secondaryInk)
                                        }
                                        Spacer()
                                        Image(systemName: selectedIDs.contains(recipe.id) ? "checkmark.circle.fill" : "circle")
                                            .font(.title3)
                                            .foregroundStyle(selectedIDs.contains(recipe.id) ? MiseTheme.sage : MiseTheme.secondaryInk.opacity(0.35))
                                    }
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if index < visible.count - 1 {
                                    MiseDivider().padding(.leading, 64)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(PageBackground())
            .navigationTitle("Add ingredients")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MiseTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selectedIDs.isEmpty ? "Add" : "Add \(selectedIDs.count)") {
                        addSelected()
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
    }

    private func toggle(_ recipe: Recipe) {
        if selectedIDs.contains(recipe.id) {
            selectedIDs.remove(recipe.id)
        } else {
            selectedIDs.insert(recipe.id)
        }
        Haptics.tap()
    }

    private func addSelected() {
        let count = app.store.addAllIngredients(from: selectedRecipes, to: list)
        Haptics.success()
        router.showToast(count == 1 ? "Added 1 item to \(list.name)" : "Added \(count) items to \(list.name)", symbol: "cart.badge.plus")
        dismiss()
    }
}

// MARK: - Shopping list picker

struct ShoppingListPickerView: View {
    @Environment(AppDependencies.self) private var app
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    let selections: [RecipeIngredientSelection]
    @Query(sort: \ShoppingList.updatedAt, order: .reverse) private var lists: [ShoppingList]
    @Query(sort: \ShoppingItem.createdAt) private var allItems: [ShoppingItem]

    @State private var showNewList = false
    @State private var newListName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if lists.isEmpty {
                        EmptyStateView(
                            symbol: "cart.badge.plus",
                            title: "Make a list first",
                            message: "Create a shopping list for these ingredients.",
                            buttonTitle: "Create a list"
                        ) {
                            newListName = "Shopping list"
                            showNewList = true
                        }
                    } else {
                        Text("Add \(selections.count) ingredient\(selections.count == 1 ? "" : "s") to a list. Compatible amounts merge; everything else stays separate.")
                            .font(.caption)
                            .foregroundStyle(MiseTheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(spacing: 0) {
                            ForEach(Array(lists.enumerated()), id: \.element.id) { index, list in
                                Button {
                                    add(to: list)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "cart")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(MiseTheme.sage)
                                            .frame(width: 34, height: 34)
                                            .background(Circle().fill(MiseTheme.sage.opacity(0.1)))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(list.name)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(MiseTheme.ink)
                                            let unchecked = allItems.filter { $0.listID == list.id && !$0.isChecked }.count
                                            Text(unchecked == 1 ? "1 item to pick up" : "\(unchecked) items to pick up")
                                                .font(.caption2)
                                                .foregroundStyle(MiseTheme.secondaryInk)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(MiseTheme.secondaryInk.opacity(0.6))
                                    }
                                    .padding(.vertical, 11)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if index < lists.count - 1 {
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
                            newListName = "Shopping list"
                            showNewList = true
                        } label: {
                            Label("New list", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MiseTheme.accent)
                        }
                    }
                }
                .padding(20)
            }
            .background(PageBackground())
            .navigationTitle("Add to shopping")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MiseTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .alert("New list", isPresented: $showNewList) {
            TextField("List name", text: $newListName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { createAndAdd() }
                .disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func add(to list: ShoppingList) {
        let count = app.store.add(selections: selections, to: list)
        Haptics.success()
        router.showToast(count == 1 ? "Added 1 item to \(list.name)" : "Added \(count) items to \(list.name)", symbol: "cart.badge.plus")
        dismiss()
    }

    private func createAndAdd() {
        let name = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let list = app.store.createShoppingList(name: name)
        let count = app.store.add(selections: selections, to: list)
        Haptics.success()
        router.showToast(count == 1 ? "Added 1 item to \(name)" : "Added \(count) items to \(name)", symbol: "cart.badge.plus")
        dismiss()
    }
}

// MARK: - Edit an item

struct ShoppingItemEditorView: View {
    @Environment(AppDependencies.self) private var app
    @Environment(\.dismiss) private var dismiss

    let item: ShoppingItem
    @State private var name: String
    @State private var quantityText: String
    @State private var showDeleteConfirmation = false

    init(item: ShoppingItem) {
        self.item = item
        _name = State(initialValue: item.name)
        _quantityText = State(initialValue: item.quantity.map { IngredientScaler.format($0, unit: nil) } ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        FieldLabel(text: "Item")
                        TextField("Item name", text: $name)
                            .padding(13)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(MiseTheme.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(MiseTheme.line, lineWidth: 1)
                            )
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        FieldLabel(text: "Quantity", optional: true)
                        TextField("2", text: $quantityText)
                            .keyboardType(.decimalPad)
                            .padding(13)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(MiseTheme.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(MiseTheme.line, lineWidth: 1)
                            )
                        if let unit = item.unit, !unit.isEmpty {
                            Text("Unit stays as \(unit).")
                                .font(.caption2)
                                .foregroundStyle(MiseTheme.secondaryInk)
                        }
                    }
                    if let title = item.sourceRecipeTitle {
                        InlineNotice(style: .info, message: "This item came from \(title).", title: nil)
                    }
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Remove from list", systemImage: "trash")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MiseTheme.accent)
                    }
                }
                .padding(20)
            }
            .background(PageBackground())
            .navigationTitle("Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MiseTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        app.store.updateItem(item, name: name, quantityText: quantityText)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .alert("Remove item?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                app.store.deleteItem(item)
                dismiss()
            }
        }
    }
}
