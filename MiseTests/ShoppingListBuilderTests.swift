import XCTest
@testable import Mise

final class ShoppingListBuilderTests: XCTestCase {
    private func recipe(id: UUID = UUID(), title: String, ingredients: [String]) -> Recipe {
        Recipe(draft: RecipeDraft(
            id: id,
            title: title,
            sourceType: .manual,
            extractionMethod: .manual,
            ingredients: ingredients.enumerated().map { Ingredient(text: $0.element, order: $0.offset) },
            instructions: [Instruction(text: "Cook.")]
        ))
    }

    func testMergesSameIngredientAndUnit() {
        let first = recipe(title: "Soup", ingredients: ["2 cups flour", "1 tsp salt"])
        let second = recipe(title: "Bread", ingredients: ["1 cup flour", "2 tsp salt"])
        let items = ShoppingListBuilder.items(from: ShoppingListBuilder.selections(from: [first, second]))
        let flour = items.first { $0.name == "Flour" }
        let salt = items.first { $0.name == "Salt" }
        XCTAssertEqual(flour?.quantity, 3)
        XCTAssertEqual(flour?.unit, "cup")
        XCTAssertEqual(salt?.quantity, 3)
        XCTAssertEqual(salt?.unit, "tsp")
        XCTAssertEqual(items.count, 2)
    }

    func testDoesNotMergeDifferentUnits() {
        let recipe = recipe(title: "Mixed", ingredients: ["1 cup flour", "100 g flour"])
        let items = ShoppingListBuilder.items(from: ShoppingListBuilder.selections(from: [recipe]))
        XCTAssertEqual(items.count, 2)
    }

    func testDoesNotMergeRanges() {
        let recipe = recipe(title: "Range", ingredients: ["2-3 tbsp sugar", "1 tbsp sugar"])
        let items = ShoppingListBuilder.items(from: ShoppingListBuilder.selections(from: [recipe]))
        XCTAssertEqual(items.count, 2)
    }

    func testMergesWithPreparationAndPluralUnits() {
        let first = recipe(title: "One", ingredients: ["2 cloves garlic, minced"])
        let second = recipe(title: "Two", ingredients: ["1 clove garlic"])
        let items = ShoppingListBuilder.items(from: ShoppingListBuilder.selections(from: [first, second]))
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.name, "Garlic")
        XCTAssertEqual(items.first?.quantity, 3)
        XCTAssertEqual(items.first?.unit, "clove")
    }

    func testTracksUniqueSourceRecipes() {
        let sharedID = UUID()
        let first = recipe(id: sharedID, title: "Soup", ingredients: ["1 onion"])
        let second = recipe(id: sharedID, title: "Soup", ingredients: ["2 onion"])
        let items = ShoppingListBuilder.items(from: ShoppingListBuilder.selections(from: [first, second]))
        XCTAssertEqual(items.first?.sourceRecipeIDs, [sharedID])
        XCTAssertEqual(items.first?.sourceRecipeTitles, ["Soup"])
    }

    func testSkipsBlankIngredients() {
        let recipe = recipe(title: "Blank", ingredients: ["1 cup rice", "   "])
        let items = ShoppingListBuilder.items(from: ShoppingListBuilder.selections(from: [recipe]))
        XCTAssertEqual(items.count, 1)
    }

    func testCategorizesCommonIngredients() {
        XCTAssertEqual(ShoppingCategoryClassifier.category(for: "Roma tomatoes"), .produce)
        XCTAssertEqual(ShoppingCategoryClassifier.category(for: "Parmesan"), .dairy)
        XCTAssertEqual(ShoppingCategoryClassifier.category(for: "Chicken thighs"), .meatSeafood)
        XCTAssertEqual(ShoppingCategoryClassifier.category(for: "Sourdough loaf"), .pantry)
        XCTAssertEqual(ShoppingCategoryClassifier.category(for: "Frozen peas"), .frozen)
        XCTAssertEqual(ShoppingCategoryClassifier.category(for: "Paper towel"), .household)
    }

    func testSortsByCategoryThenName() {
        let recipe = recipe(title: "Sorted", ingredients: ["1 cup flour", "2 tomatoes", "1 chicken breast"])
        let items = ShoppingListBuilder.items(from: ShoppingListBuilder.selections(from: [recipe]))
        XCTAssertEqual(items.map(\.category), [.produce, .meatSeafood, .pantry])
    }

    func testShoppingNameFallsBackAndCapitalizes() {
        let ingredient = Ingredient(text: "2 tbsp olive oil")
        XCTAssertEqual(ShoppingListBuilder.shoppingName(for: ingredient), "Olive oil")
        let blank = Ingredient(text: "")
        XCTAssertEqual(ShoppingListBuilder.shoppingName(for: blank), "Item")
    }
}
