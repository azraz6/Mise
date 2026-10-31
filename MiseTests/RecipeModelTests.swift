import XCTest
@testable import Mise

final class RecipeModelTests: XCTestCase {
    func testDraftDisplayTitleFallbacks() {
        XCTAssertEqual(RecipeDraft.manual().displayTitle, "Untitled recipe")
        var draft = RecipeDraft.manual()
        draft.sourceTitle = "Source title"
        XCTAssertEqual(draft.displayTitle, "Source title")
        draft.title = "  Real title  "
        XCTAssertEqual(draft.displayTitle, "Real title")
    }

    func testValidatorReportsMissingCoreFields() {
        let draft = RecipeDraft.manual()
        XCTAssertEqual(RecipeValidator.missingFields(for: draft), ["Title", "Ingredients", "Instructions"])
        XCTAssertFalse(draft.hasCoreContent)
    }

    func testValidatorWarnsAboutUnknownServingsAndFixedIngredients() {
        let draft = RecipeDraft(
            title: "Toast",
            extractionMethod: .manual,
            ingredients: [Ingredient(text: "Salt to taste"), Ingredient(text: "2 slices bread")],
            instructions: [Instruction(text: "Toast the bread.")],
            servings: nil
        )
        let warnings = RecipeValidator.warnings(for: draft)
        XCTAssertTrue(warnings.contains { $0.contains("Servings are unknown") })
        XCTAssertTrue(warnings.contains { $0.contains("kept exactly as written") })
        XCTAssertFalse(warnings.contains { $0.contains("No cooking steps") })
    }

    func testNormalizeOrderingAndTrimTrailingRows() {
        var draft = RecipeDraft(
            title: "Order",
            ingredients: [
                Ingredient(text: "1 cup rice", order: 8),
                Ingredient(text: "", order: 2),
                Ingredient(text: "   ", order: 3)
            ],
            instructions: [
                Instruction(text: "Cook.", order: 9),
                Instruction(text: "  ", order: 4)
            ]
        )
        draft.normalizeOrdering()
        XCTAssertEqual(draft.ingredients.map(\.order), [0, 1, 2])
        XCTAssertEqual(draft.instructions.map(\.order), [0, 1])
        draft.trimEmptyTrailingRows()
        XCTAssertEqual(draft.ingredients.count, 1)
        XCTAssertEqual(draft.instructions.count, 1)
    }

    func testRecipeAppliesDraftFieldsAndSearchText() {
        let draft = RecipeDraft(
            title: "Miso Soup",
            summary: "Savory and quick.",
            author: "Mise",
            sourceType: .website,
            extractionMethod: .jsonLD,
            ingredients: [Ingredient(text: "2 tbsp miso paste")],
            instructions: [Instruction(text: "Warm the broth.")],
            servings: 2,
            cuisine: "Japanese",
            category: "Soup",
            tags: ["quick"]
        )
        let recipe = Recipe(draft: draft)
        XCTAssertEqual(recipe.title, "Miso Soup")
        XCTAssertEqual(recipe.originalServings, 2)
        XCTAssertEqual(recipe.ingredients.map(\.originalText), ["2 tbsp miso paste"])
        XCTAssertEqual(recipe.instructions.map(\.text), ["Warm the broth."])
        XCTAssertTrue(recipe.searchText.contains("miso"))
        XCTAssertTrue(recipe.searchText.contains("japanese"))
        XCTAssertTrue(recipe.searchText.contains("quick"))

        var changed = recipe.toDraft()
        changed.title = "Better Miso Soup"
        changed.tags = ["winter"]
        recipe.apply(changed)
        XCTAssertEqual(recipe.title, "Better Miso Soup")
        XCTAssertEqual(recipe.tags, ["winter"])
        XCTAssertTrue(recipe.searchText.contains("winter"))
    }

    func testInstructionClampsCookingProgress() {
        let recipe = Recipe(draft: RecipeDraft(
            title: "Steps",
            ingredients: [Ingredient(text: "1 thing")],
            instructions: [Instruction(text: "One."), Instruction(text: "Two."), Instruction(text: "Three.")]
        ))
        recipe.cookingStepIndex = 2
        recipe.instructions = [Instruction(text: "Only one.")]
        XCTAssertEqual(recipe.instructions.count, 1)
        XCTAssertEqual(recipe.cookingStepCount, 1)
        XCTAssertEqual(recipe.cookingStepIndex, 0)
    }

    func testCollectionMutationDoesNotDuplicate() {
        let collection = RecipeCollection(name: "Test")
        let id = UUID()
        collection.add(id)
        collection.add(id)
        XCTAssertEqual(collection.recipeIDs, [id])
        collection.remove(id)
        XCTAssertTrue(collection.recipeIDs.isEmpty)
    }
}
