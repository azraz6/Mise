import XCTest
@testable import Mise

final class RecipeSearchAndDuplicateTests: XCTestCase {
    private func recipe(
        title: String,
        ingredients: [String] = ["1 cup flour"],
        tags: [String] = [],
        favourite: Bool = false,
        archived: Bool = false,
        sourceType: RecipeSourceType = .manual,
        sourceURL: String? = nil,
        daysAgo: Int = 0
    ) -> Recipe {
        let recipe = Recipe(draft: RecipeDraft(
            title: title,
            sourceURLString: sourceURL,
            sourceType: sourceType,
            extractionMethod: .manual,
            ingredients: ingredients.enumerated().map { Ingredient(text: $0.element, order: $0.offset) },
            instructions: [Instruction(text: "Cook.")],
            tags: tags,
            createdAt: Date().addingTimeInterval(-Double(daysAgo) * 86_400)
        ))
        recipe.isFavourite = favourite
        recipe.isArchived = archived
        recipe.dateAdded = Date().addingTimeInterval(-Double(daysAgo) * 86_400)
        return recipe
    }

    func testSearchMatchesIngredientsAndTags() {
        let recipes = [
            recipe(title: "Tomato Pasta", ingredients: ["2 tomatoes", "200 g spaghetti"], tags: ["weeknight"]),
            recipe(title: "Roast Salmon", ingredients: ["1 salmon fillet", "1 lemon"])
        ]
        XCTAssertEqual(RecipeSearch.apply(recipes, filter: RecipeFilter(query: "spaghetti")).map(\.title), ["Tomato Pasta"])
        XCTAssertEqual(RecipeSearch.apply(recipes, filter: RecipeFilter(query: "lemon")).map(\.title), ["Roast Salmon"])
        XCTAssertEqual(RecipeSearch.apply(recipes, filter: RecipeFilter(query: "weeknight")).map(\.title), ["Tomato Pasta"])
    }

    func testSearchRequiresAllTokens() {
        let recipes = [recipe(title: "Lemon Herb Chicken", ingredients: ["1 chicken", "1 lemon", "1 bunch herbs"])]
        XCTAssertEqual(RecipeSearch.apply(recipes, filter: RecipeFilter(query: "lemon chicken")).count, 1)
        XCTAssertTrue(RecipeSearch.apply(recipes, filter: RecipeFilter(query: "lemon beef")).isEmpty)
    }

    func testFavouriteAndArchiveFilters() {
        let recipes = [
            recipe(title: "Favourite", favourite: true),
            recipe(title: "Archived", archived: true),
            recipe(title: "Plain")
        ]
        XCTAssertEqual(RecipeSearch.apply(recipes, filter: RecipeFilter(favouritesOnly: true)).map(\.title), ["Favourite"])
        XCTAssertEqual(RecipeSearch.apply(recipes, filter: RecipeFilter()).map(\.title).sorted(), ["Favourite", "Plain"])
        XCTAssertEqual(RecipeSearch.apply(recipes, filter: RecipeFilter(includeArchived: true)).count, 3)
    }

    func testCollectionAndSourceFilters() {
        let website = recipe(title: "Web", sourceType: .website)
        let instagram = recipe(title: "Social", sourceType: .instagram)
        let filter = RecipeFilter(collectionRecipeIDs: [instagram.id], sourceType: .instagram)
        XCTAssertEqual(RecipeSearch.apply([website, instagram], filter: filter).map(\.title), ["Social"])
    }

    func testSortOrders() {
        let newest = recipe(title: "Zebra", daysAgo: 0)
        let oldest = recipe(title: "Apple", daysAgo: 5)
        XCTAssertEqual(RecipeSearch.apply([oldest, newest], filter: RecipeFilter(), sort: .recentlyAdded).map(\.title), ["Zebra", "Apple"])
        XCTAssertEqual(RecipeSearch.apply([newest, oldest], filter: RecipeFilter(), sort: .title).map(\.title), ["Apple", "Zebra"])
    }

    func testDuplicateDetectorFindsSameNormalizedSource() {
        let existing = recipe(
            title: "Lemon Pasta",
            sourceURL: "https://www.example.com/recipe/?utm_source=newsletter"
        )
        let draft = RecipeDraft(
            title: "Lemon Pasta",
            sourceURLString: "https://example.com/recipe",
            sourceType: .website
        )
        let candidates = DuplicateDetector.candidates(for: draft, in: [existing])
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.reason, .sameSource)
    }

    func testDuplicateDetectorFindsSimilarTitles() {
        let existing = recipe(title: "Best Banana Bread")
        let draft = RecipeDraft(title: "Best Banana Bread Recipe")
        let candidates = DuplicateDetector.candidates(for: draft, in: [existing])
        XCTAssertEqual(candidates.first?.reason, .similarTitle)
    }

    func testDuplicateDetectorSkipsArchivedAndEditedRecipe() {
        let archived = recipe(title: "Same", archived: true)
        let edited = recipe(title: "Same")
        let draft = RecipeDraft(title: "Same")
        XCTAssertTrue(DuplicateDetector.candidates(for: draft, in: [archived]).isEmpty)
        XCTAssertTrue(DuplicateDetector.candidates(for: draft, excluding: edited.id, in: [edited]).isEmpty)
    }

    func testTitleSimilarityHandlesPunctuationAndAccents() {
        XCTAssertEqual(DuplicateDetector.titleSimilarity("Crème Brûlée", "Creme Brulee"), 1, accuracy: 0.0001)
        XCTAssertGreaterThan(DuplicateDetector.titleSimilarity("Roast Chicken", "Roasted Chicken"), 0.8)
        XCTAssertLessThan(DuplicateDetector.titleSimilarity("Roast Chicken", "Chocolate Cake"), 0.4)
    }
}
