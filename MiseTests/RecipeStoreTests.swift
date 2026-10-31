import SwiftData
import XCTest
@testable import Mise

@MainActor
final class RecipeStoreTests: XCTestCase {
    private var temporaryDirectories: [URL] = []
    private var retainedContainers: [ModelContainer] = []

    override func tearDown() {
        retainedContainers.removeAll()
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    private func makeStore(inMemory: Bool = true) throws -> (RecipeStore, ModelContainer) {
        let container = try ModelContainerFactory.make(inMemory: inMemory)
        retainedContainers.append(container)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        let images = ImageStore(baseDirectory: directory)
        return (RecipeStore(context: container.mainContext, images: images), container)
    }

    private func draft(
        title: String = "Test Soup",
        ingredients: [String] = ["2 cups stock", "1 onion"],
        instructions: [String] = ["Simmer everything."],
        servings: Int? = 4
    ) -> RecipeDraft {
        RecipeDraft(
            title: title,
            sourceType: .manual,
            extractionMethod: .manual,
            ingredients: ingredients.enumerated().map { Ingredient(text: $0.element, order: $0.offset) },
            instructions: instructions.enumerated().map { Instruction(text: $0.element, order: $0.offset) },
            servings: servings
        )
    }

    func testSavesAndFetchesRecipe() async throws {
        let (store, _) = try makeStore()
        let recipe = try await store.save(draft: draft())
        XCTAssertEqual(store.allRecipes().count, 1)
        XCTAssertEqual(recipe.title, "Test Soup")
        XCTAssertEqual(recipe.originalServings, 4)
        XCTAssertEqual(recipe.ingredients.count, 2)
        XCTAssertTrue(recipe.searchText.contains("onion"))
    }

    func testUpdateMutatesExistingRecipe() async throws {
        let (store, _) = try makeStore()
        let recipe = try await store.save(draft: draft())
        var updated = recipe.toDraft()
        updated.title = "Updated Soup"
        updated.ingredients = [Ingredient(text: "3 cups stock")]
        updated.instructions = [Instruction(text: "Stir gently.")]
        try await store.update(recipe: recipe, from: updated)
        XCTAssertEqual(store.allRecipes().count, 1)
        XCTAssertEqual(recipe.title, "Updated Soup")
        XCTAssertEqual(recipe.ingredients.map(\.originalText), ["3 cups stock"])
        XCTAssertEqual(recipe.instructions.map(\.text), ["Stir gently."])
        XCTAssertTrue(recipe.searchText.contains("stock"))
    }

    func testDeleteRemovesCollectionMembershipAndMealPlan() async throws {
        let (store, _) = try makeStore()
        let recipe = try await store.save(draft: draft())
        let collection = try store.createCollection(name: "Weeknight")
        store.setRecipe(recipe, in: collection, included: true)
        let day = MealPlanCalendar.dayKey(for: Date())
        store.setMeal(recipeID: recipe.id, dayKey: day, slot: .dinner)

        store.delete(recipe)

        XCTAssertTrue(store.allRecipes().isEmpty)
        XCTAssertFalse(collection.contains(recipe.id))
        XCTAssertTrue(store.allMealPlanEntries().isEmpty)
    }

    func testCollectionsCRUD() async throws {
        let (store, _) = try makeStore()
        let recipe = try await store.save(draft: draft())
        let collection = try store.createCollection(name: "  Favourites  ", summary: "Good ones")
        XCTAssertEqual(collection.name, "Favourites")
        XCTAssertEqual(store.allCollections().count, 1)

        store.setRecipe(recipe, in: collection, included: true)
        XCTAssertTrue(collection.contains(recipe.id))
        XCTAssertEqual(store.recipes(in: collection).map(\.id), [recipe.id])
        store.setRecipe(recipe, in: collection, included: false)
        XCTAssertFalse(collection.contains(recipe.id))

        try store.updateCollection(collection, name: "Best", summary: "")
        XCTAssertEqual(collection.name, "Best")
        XCTAssertNil(collection.summary)

        store.deleteCollection(collection)
        XCTAssertTrue(store.allCollections().isEmpty)
    }

    func testCreateCollectionRejectsBlankName() throws {
        let (store, _) = try makeStore()
        XCTAssertThrowsError(try store.createCollection(name: "   "))
    }

    func testShoppingListMergesAndClearsCheckedItems() async throws {
        let (store, _) = try makeStore()
        let first = try await store.save(draft: draft(title: "Soup", ingredients: ["2 cups stock", "1 onion"]))
        let second = try await store.save(draft: draft(title: "Stew", ingredients: ["1 cup stock", "2 carrots"]))
        let list = store.createShoppingList(name: "Shop")

        let added = store.addAllIngredients(from: [first, second], to: list)
        XCTAssertEqual(added, 3)
        let items = store.items(in: list)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.first { $0.name == "Stock" }?.quantity, 3)

        let stock = try XCTUnwrap(items.first { $0.name == "Stock" })
        store.toggleChecked(stock)
        XCTAssertTrue(stock.isChecked)
        XCTAssertEqual(store.items(in: list).first?.isChecked, false, "Unchecked items must sort first")

        store.clearCompleted(in: list)
        XCTAssertEqual(store.items(in: list).count, 2)
        XCTAssertFalse(store.items(in: list).contains { $0.id == stock.id })
    }

    func testCustomShoppingItemAndEditing() throws {
        let (store, _) = try makeStore()
        let list = store.createShoppingList()
        let item = try XCTUnwrap(store.addCustomItem(to: list, name: "  Dish soap  ", quantity: 1, unit: "bottle"))
        XCTAssertEqual(item.name, "Dish soap")
        XCTAssertEqual(item.category, .household)

        store.updateItem(item, name: "Lemons", quantityText: "3")
        XCTAssertEqual(item.name, "Lemons")
        XCTAssertEqual(item.quantity, 3)
        XCTAssertEqual(item.category, .produce)

        store.deleteItem(item)
        XCTAssertTrue(store.items(in: list).isEmpty)
        store.deleteShoppingList(list)
        XCTAssertTrue(store.allShoppingLists().isEmpty)
    }

    func testMealPlanSetReplaceMoveAndGenerate() async throws {
        let (store, _) = try makeStore()
        let recipe = try await store.save(draft: draft(title: "Pasta", ingredients: ["2 cups pasta", "1 tbsp oil"]))
        let other = try await store.save(draft: draft(title: "Salad", ingredients: ["1 lettuce"]))
        let week = MealPlanCalendar.startOfWeek(containing: Date())
        let monday = MealPlanCalendar.dayKey(for: week)
        let tuesdayDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: week))
        let tuesday = MealPlanCalendar.dayKey(for: tuesdayDate)

        store.setMeal(recipeID: recipe.id, dayKey: monday, slot: .dinner)
        store.setMeal(recipeID: other.id, dayKey: monday, slot: .dinner)
        XCTAssertEqual(store.mealEntries(weekStarting: week).count, 1)
        XCTAssertEqual(store.mealEntry(dayKey: monday, slot: .dinner)?.recipeID, other.id)

        store.setMeal(recipeID: recipe.id, dayKey: monday, slot: .lunch)
        let lunch = try XCTUnwrap(store.mealEntry(dayKey: monday, slot: .lunch))
        store.moveMeal(lunch, toDayKey: tuesday, slot: .dinner)
        XCTAssertEqual(store.mealEntry(dayKey: tuesday, slot: .dinner)?.recipeID, recipe.id)
        XCTAssertNil(store.mealEntry(dayKey: monday, slot: .lunch))

        store.removeMeal(try XCTUnwrap(store.mealEntry(dayKey: tuesday, slot: .dinner)))
        store.setMeal(recipeID: recipe.id, dayKey: monday, slot: .dinner)
        store.setMeal(recipeID: recipe.id, dayKey: tuesday, slot: .dinner)
        let entries = store.mealEntries(weekStarting: week)
        XCTAssertEqual(entries.count, 2)

        let list = store.generateShoppingList(from: entries)
        let pasta = store.items(in: list).first { $0.name == "Pasta" }
        XCTAssertEqual(pasta?.quantity, 4, "The same recipe planned twice should contribute its ingredients twice")
        XCTAssertEqual(store.items(in: list).first { $0.name == "Oil" }?.quantity, 2)
    }

    func testImportJobLifecycleAndScratchCleanup() throws {
        let (store, _) = try makeStore()
        let filename = try store.images.storeScratchImage(data: Data([0xFF, 0xD8, 0xFF]))
        let job = ImportJob(sourceType: .screenshot, method: .ocrHeuristics, scratchImageFilenames: [filename])
        store.context.insert(job)
        try store.saveContext()
        XCTAssertEqual(store.allImportJobs().count, 1)
        XCTAssertNotNil(store.images.scratchImageData(named: filename))

        store.deleteImportJob(job)
        XCTAssertTrue(store.allImportJobs().isEmpty)
        XCTAssertNil(store.images.scratchImageData(named: filename))
    }

    func testResetAllDataClearsEverything() async throws {
        let (store, _) = try makeStore()
        let defaults = UserDefaults(suiteName: "MiseReset-\(UUID().uuidString)")!
        let recipe = try await store.save(draft: draft())
        let collection = try store.createCollection(name: "C")
        store.setRecipe(recipe, in: collection, included: true)
        let list = store.createShoppingList()
        store.addCustomItem(to: list, name: "Milk")
        store.setMeal(recipeID: recipe.id, dayKey: MealPlanCalendar.dayKey(for: Date()), slot: .dinner)
        let job = ImportJob(sourceType: .text)
        store.context.insert(job)

        store.resetAllData(defaults: defaults)

        XCTAssertTrue(store.allRecipes().isEmpty)
        XCTAssertTrue(store.allCollections().isEmpty)
        XCTAssertTrue(store.allShoppingLists().isEmpty)
        XCTAssertTrue(store.allMealPlanEntries().isEmpty)
        XCTAssertTrue(store.allImportJobs().isEmpty)
        XCTAssertTrue(defaults.bool(forKey: SeedData.seedKey))
    }

    func testRecipesPersistAcrossContainerReopen() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MisePersist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        let storeURL = directory.appendingPathComponent("Mise.store")
        let images = ImageStore(baseDirectory: directory)
        var savedID: UUID?

        do {
            let container = try ModelContainerFactory.make(storeURL: storeURL)
            let store = RecipeStore(context: container.mainContext, images: images)
            let recipe = try await store.save(draft: draft(title: "Persisted Pie"))
            savedID = recipe.id
            try store.saveContext()
        }

        let reopened = try ModelContainerFactory.make(storeURL: storeURL)
        let reopenedStore = RecipeStore(context: reopened.mainContext, images: images)
        XCTAssertEqual(reopenedStore.allRecipes().first?.id, savedID)
        XCTAssertEqual(reopenedStore.allRecipes().first?.title, "Persisted Pie")
    }
}
