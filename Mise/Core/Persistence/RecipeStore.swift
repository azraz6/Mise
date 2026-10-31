import Foundation
import SwiftData
import UIKit

enum RecipeStoreError: LocalizedError {
    case saveFailed
    case recipeNotFound
    case listNotFound

    var errorDescription: String? {
        switch self {
        case .saveFailed: return "Mise couldn’t save that change. Your library is unchanged."
        case .recipeNotFound: return "That recipe is no longer in your library."
        case .listNotFound: return "That shopping list is no longer available."
        }
    }
}

@MainActor
final class RecipeStore {
    let context: ModelContext
    let images: ImageStore

    init(context: ModelContext, images: ImageStore = .shared) {
        self.context = context
        self.images = images
    }

    // MARK: - Recipes

    func allRecipes(includeArchived: Bool = true) -> [Recipe] {
        let descriptor = FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\.dateAdded, order: .reverse)])
        let recipes = (try? context.fetch(descriptor)) ?? []
        return includeArchived ? recipes : recipes.filter { !$0.isArchived }
    }

    func recipe(id: UUID) -> Recipe? {
        allRecipes().first { $0.id == id }
    }

    @discardableResult
    func save(draft: RecipeDraft, image: UIImage? = nil) async throws -> Recipe {
        var draft = draft
        draft.normalizeOrdering()
        draft.trimEmptyTrailingRows()
        if let image {
            let filename = try await images.store(image: image)
            draft.coverImageFilename = filename
            draft.coverAssetName = nil
        } else if draft.coverImageFilename == nil,
                  draft.coverAssetName == nil,
                  let remote = draft.coverImageRemoteURL.flatMap(URL.init(string:)) {
            if let filename = try? await images.downloadAndStoreImage(from: remote) {
                draft.coverImageFilename = filename
            }
        }
        let recipe = Recipe(draft: draft)
        context.insert(recipe)
        try saveContext()
        return recipe
    }

    func update(recipe: Recipe, from draft: RecipeDraft, image: UIImage? = nil) async throws {
        var draft = draft
        draft.normalizeOrdering()
        draft.trimEmptyTrailingRows()
        if let image {
            let old = recipe.coverImageFilename
            let filename = try await images.store(image: image)
            draft.coverImageFilename = filename
            draft.coverAssetName = nil
            images.deleteImage(named: old)
        }
        recipe.apply(draft)
        try saveContext()
    }

    func replaceCover(recipe: Recipe, image: UIImage) async throws {
        let old = recipe.coverImageFilename
        let filename = try await images.store(image: image)
        recipe.coverImageFilename = filename
        recipe.coverAssetName = nil
        recipe.dateModified = Date()
        try saveContext()
        images.deleteImage(named: old)
    }

    func toggleFavourite(_ recipe: Recipe) {
        recipe.isFavourite.toggle()
        recipe.dateModified = Date()
        try? saveContext()
    }

    func setArchived(_ recipe: Recipe, archived: Bool) {
        recipe.isArchived = archived
        recipe.dateModified = Date()
        try? saveContext()
    }

    func delete(_ recipe: Recipe) {
        let imageFilename = recipe.coverImageFilename
        for collection in allCollections() {
            if collection.contains(recipe.id) {
                collection.remove(recipe.id)
            }
        }
        for entry in allMealPlanEntries() where entry.recipeID == recipe.id {
            context.delete(entry)
        }
        context.delete(recipe)
        try? saveContext()
        images.deleteImage(named: imageFilename)
    }

    func recordCookingStep(recipe: Recipe, index: Int, count: Int) {
        recipe.cookingStepIndex = max(0, min(index, max(0, count - 1)))
        recipe.cookingStepCount = count
        recipe.lastCookedAt = Date()
        recipe.cookingUpdatedAt = Date()
        try? saveContext()
    }

    func finishCooking(recipe: Recipe) {
        recipe.cookingStepIndex = 0
        recipe.cookingStepCount = recipe.instructions.count
        recipe.lastCookedAt = Date()
        recipe.cookingUpdatedAt = Date()
        try? saveContext()
    }

    // MARK: - Collections

    func allCollections() -> [RecipeCollection] {
        let descriptor = FetchDescriptor<RecipeCollection>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    func createCollection(name: String, summary: String = "") throws -> RecipeCollection {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RecipeStoreError.saveFailed }
        let collection = RecipeCollection(name: trimmed, summary: summary, sortOrder: allCollections().count)
        context.insert(collection)
        try saveContext()
        return collection
    }

    func updateCollection(_ collection: RecipeCollection, name: String, summary: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RecipeStoreError.saveFailed }
        collection.name = trimmed
        collection.summary = summary.isEmpty ? nil : summary
        try saveContext()
    }

    func deleteCollection(_ collection: RecipeCollection) {
        context.delete(collection)
        try? saveContext()
    }

    func setRecipe(_ recipe: Recipe, in collection: RecipeCollection, included: Bool) {
        if included {
            collection.add(recipe.id)
        } else {
            collection.remove(recipe.id)
        }
        try? saveContext()
    }

    func recipes(in collection: RecipeCollection) -> [Recipe] {
        let ids = Set(collection.recipeIDs)
        return allRecipes().filter { ids.contains($0.id) }
    }

    // MARK: - Shopping

    func allShoppingLists() -> [ShoppingList] {
        let descriptor = FetchDescriptor<ShoppingList>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    func createShoppingList(name: String? = nil) -> ShoppingList {
        let base = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = ShoppingList(name: (base?.isEmpty == false ? base! : "Shopping list"))
        context.insert(list)
        try? saveContext()
        return list
    }

    func renameShoppingList(_ list: ShoppingList, name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        list.name = trimmed
        list.updatedAt = Date()
        try saveContext()
    }

    func deleteShoppingList(_ list: ShoppingList) {
        for item in items(in: list) { context.delete(item) }
        context.delete(list)
        try? saveContext()
    }

    func items(in list: ShoppingList) -> [ShoppingItem] {
        let listID = list.id
        let descriptor = FetchDescriptor<ShoppingItem>(
            predicate: #Predicate { $0.listID == listID },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let items = (try? context.fetch(descriptor)) ?? []
        return items.sorted { lhs, rhs in
            if lhs.isChecked != rhs.isChecked { return !lhs.isChecked }
            if lhs.category.sortIndex != rhs.category.sortIndex { return lhs.category.sortIndex < rhs.category.sortIndex }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    @discardableResult
    func add(selections: [RecipeIngredientSelection], to list: ShoppingList) -> Int {
        let drafts = ShoppingListBuilder.items(from: selections)
        let existing = items(in: list)
        var added = 0

        for draft in drafts {
            let matching = existing.first { item in
                item.quantity != nil
                    && draft.quantity != nil
                    && IngredientParser.normalizedName(item.name) == IngredientParser.normalizedName(draft.name)
                    && IngredientParser.normalizeUnit(item.unit) == IngredientParser.normalizeUnit(draft.unit)
            }
            if let matching {
                matching.quantity = (matching.quantity ?? 0) + (draft.quantity ?? 0)
                matching.isChecked = false
                matching.createdAt = Date()
                added += 1
                continue
            }
            let item = ShoppingItem(
                listID: list.id,
                name: draft.name,
                quantity: draft.quantity,
                quantityUpper: draft.quantityUpper,
                unit: draft.unit,
                displayText: draft.displayText,
                category: draft.category,
                sourceRecipeID: draft.sourceRecipeIDs.first,
                sourceRecipeTitle: Self.sourceTitleText(draft.sourceRecipeTitles),
                sortOrder: existing.count + added
            )
            context.insert(item)
            added += 1
        }
        list.updatedAt = Date()
        try? saveContext()
        return added
    }

    @discardableResult
    func addAllIngredients(from recipes: [Recipe], to list: ShoppingList) -> Int {
        add(selections: ShoppingListBuilder.selections(from: recipes), to: list)
    }

    @discardableResult
    func addCustomItem(to list: ShoppingList, name: String, quantity: Double? = nil, unit: String? = nil) -> ShoppingItem? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let item = ShoppingItem(
            listID: list.id,
            name: trimmed,
            quantity: quantity,
            unit: unit,
            displayText: trimmed,
            category: ShoppingCategoryClassifier.category(for: trimmed),
            sortOrder: items(in: list).count
        )
        context.insert(item)
        list.updatedAt = Date()
        try? saveContext()
        return item
    }

    func updateItem(_ item: ShoppingItem, name: String, quantityText: String?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        item.name = trimmed
        if let quantityText, let quantity = Double(quantityText.replacingOccurrences(of: ",", with: ".")) {
            item.quantity = quantity
        } else if quantityText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            item.quantity = nil
        }
        item.category = ShoppingCategoryClassifier.category(for: trimmed)
        if let list = allShoppingLists().first(where: { $0.id == item.listID }) {
            list.updatedAt = Date()
        }
        try? saveContext()
    }

    func toggleChecked(_ item: ShoppingItem) {
        item.isChecked.toggle()
        if let list = allShoppingLists().first(where: { $0.id == item.listID }) {
            list.updatedAt = Date()
        }
        try? saveContext()
    }

    func deleteItem(_ item: ShoppingItem) {
        context.delete(item)
        try? saveContext()
    }

    func clearCompleted(in list: ShoppingList) {
        for item in items(in: list) where item.isChecked {
            context.delete(item)
        }
        list.updatedAt = Date()
        try? saveContext()
    }

    // MARK: - Meal plan

    func allMealPlanEntries() -> [MealPlanEntry] {
        (try? context.fetch(FetchDescriptor<MealPlanEntry>())) ?? []
    }

    func mealEntries(weekStarting start: Date) -> [MealPlanEntry] {
        let keys = Set(MealPlanCalendar.days(inWeekStarting: start).map { MealPlanCalendar.dayKey(for: $0) })
        return allMealPlanEntries()
            .filter { keys.contains($0.dayKey) }
            .sorted { lhs, rhs in
                if lhs.dayKey != rhs.dayKey { return lhs.dayKey < rhs.dayKey }
                return lhs.slot.sortIndex < rhs.slot.sortIndex
            }
    }

    func mealEntry(dayKey: String, slot: MealSlot) -> MealPlanEntry? {
        allMealPlanEntries().first { $0.dayKey == dayKey && $0.slot == slot }
    }

    func setMeal(recipeID: UUID, dayKey: String, slot: MealSlot) {
        if let existing = mealEntry(dayKey: dayKey, slot: slot) {
            existing.recipeID = recipeID
        } else {
            context.insert(MealPlanEntry(dayKey: dayKey, slot: slot, recipeID: recipeID))
        }
        try? saveContext()
    }

    func removeMeal(_ entry: MealPlanEntry) {
        context.delete(entry)
        try? saveContext()
    }

    func moveMeal(_ entry: MealPlanEntry, toDayKey: String, slot: MealSlot) {
        if let conflict = mealEntry(dayKey: toDayKey, slot: slot), conflict.id != entry.id {
            context.delete(conflict)
        }
        entry.dayKey = toDayKey
        entry.slot = slot
        try? saveContext()
    }

    @discardableResult
    func generateShoppingList(from entries: [MealPlanEntry], name: String = "Meal plan shop") -> ShoppingList {
        let list = createShoppingList(name: name)
        let recipes = entries.compactMap { recipe(id: $0.recipeID) }
        _ = addAllIngredients(from: recipes, to: list)
        return list
    }

    // MARK: - Import jobs

    func allImportJobs() -> [ImportJob] {
        let descriptor = FetchDescriptor<ImportJob>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func importJob(id: UUID) -> ImportJob? {
        allImportJobs().first { $0.id == id }
    }

    func deleteImportJob(_ job: ImportJob) {
        for filename in job.scratchImageFilenames {
            images.deleteScratchImage(named: filename)
        }
        context.delete(job)
        try? saveContext()
    }

    func recentImportJobs(limit: Int = 4) -> [ImportJob] {
        Array(allImportJobs().prefix(limit))
    }

    // MARK: - Maintenance

    func saveContext() throws {
        do {
            try context.save()
        } catch {
            throw RecipeStoreError.saveFailed
        }
    }

    func resetAllData(defaults: UserDefaults = .standard) {
        for item in (try? context.fetch(FetchDescriptor<ShoppingItem>())) ?? [] { context.delete(item) }
        for list in (try? context.fetch(FetchDescriptor<ShoppingList>())) ?? [] { context.delete(list) }
        for entry in allMealPlanEntries() { context.delete(entry) }
        for collection in allCollections() { context.delete(collection) }
        for job in allImportJobs() {
            for filename in job.scratchImageFilenames {
                images.deleteScratchImage(named: filename)
            }
            context.delete(job)
        }
        for recipe in allRecipes() {
            images.deleteImage(named: recipe.coverImageFilename)
            context.delete(recipe)
        }
        try? context.save()
        defaults.set(true, forKey: SeedData.seedKey)
    }

    func restoreStarterRecipes(defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: SeedData.seedKey)
        SeedData.seedIfNeeded(context: context, defaults: defaults)
    }

    private static func sourceTitleText(_ titles: [String]) -> String? {
        let unique = Array(NSOrderedSet(array: titles).compactMap { $0 as? String })
        guard let first = unique.first else { return nil }
        if unique.count == 1 { return first }
        return "\(first) + \(unique.count - 1) more"
    }
}
