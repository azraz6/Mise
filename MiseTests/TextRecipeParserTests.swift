import XCTest
@testable import Mise

final class TextRecipeParserTests: XCTestCase {
    func testParsesHeadingBasedRecipe() {
        let text = """
        # Creamy Tomato Soup

        Serves 4
        Prep time: 10 minutes
        Cook time: 25 minutes

        ## Ingredients
        - 2 tbsp olive oil
        - 1 onion, diced
        - 2 cloves garlic, minced
        - 28 oz crushed tomatoes

        ## Instructions
        1. Warm the oil in a pot.
        2. Add the onion and cook until soft.
        3. Add tomatoes and simmer for 20 minutes.
        """

        let outcome = TextRecipeParser.parse(text, sourceType: .text, method: .textHeuristics)
        let draft = outcome.draft
        XCTAssertEqual(draft.title, "Creamy Tomato Soup")
        XCTAssertEqual(draft.ingredients.count, 4)
        XCTAssertEqual(draft.ingredients[0].quantity, 2)
        XCTAssertEqual(draft.ingredients[1].preparation, "diced")
        XCTAssertEqual(draft.instructions.count, 3)
        XCTAssertEqual(draft.instructions.last?.text, "Add tomatoes and simmer for 20 minutes.")
        XCTAssertEqual(draft.servings, 4)
        XCTAssertEqual(draft.prepMinutes, 10)
        XCTAssertEqual(draft.cookMinutes, 25)
        XCTAssertEqual(draft.sourceType, .text)
        XCTAssertEqual(draft.confidence, .heuristic)
    }

    func testHeuristicSplitWithoutHeadings() {
        let text = """
        Quick Pancakes
        2 cups flour
        1 tbsp sugar
        1. Whisk the batter until smooth.
        2. Cook on a hot griddle.
        """
        let outcome = TextRecipeParser.parse(text, sourceType: .sharedText)
        XCTAssertEqual(outcome.draft.title, "Quick Pancakes")
        XCTAssertEqual(outcome.draft.ingredients.count, 2)
        XCTAssertEqual(outcome.draft.instructions.count, 2)
        XCTAssertTrue(outcome.warnings.contains { $0.contains("separated heuristically") })
    }

    func testSocialCaptionMetadata() {
        let text = """
        Crispy Chili Noodles #recipe #spicy
        Serves 2
        Ingredients
        200 g noodles
        2 tbsp chili crisp
        Method
        1. Boil the noodles.
        2. Toss with chili crisp.
        """
        let outcome = TextRecipeParser.parse(text, sourceType: .instagram, sourceURL: URL(string: "https://instagram.com/p/abc"), sourceTitle: "Crispy Chili Noodles")
        XCTAssertEqual(outcome.draft.servings, 2)
        XCTAssertEqual(Set(outcome.draft.tags), Set(["recipe", "spicy"]))
        XCTAssertEqual(outcome.draft.sourceType, .instagram)
        XCTAssertEqual(outcome.draft.sourceURLString, "https://instagram.com/p/abc")
        XCTAssertEqual(outcome.draft.extractionMethod, .textHeuristics)
    }

    func testOCRAddsHonestWarning() {
        let text = "Ingredients\n1 cup flour\nInstructions\n1. Bake."
        let outcome = TextRecipeParser.parse(text, sourceType: .screenshot, method: .ocrHeuristics)
        XCTAssertTrue(outcome.warnings.contains { $0.localizedCaseInsensitiveContains("Text recognition can misread") })
        XCTAssertEqual(outcome.draft.extractionMethod, .ocrHeuristics)
    }

    func testStopsInstructionsAtNotesSection() {
        let text = """
        Toast
        Ingredients
        2 slices bread
        Instructions
        1. Toast the bread.
        Notes
        Use good bread.
        """
        let outcome = TextRecipeParser.parse(text, sourceType: .text)
        XCTAssertEqual(outcome.draft.instructions.map(\.text), ["Toast the bread."])
    }

    func testEmptyTextReturnsWarning() {
        let outcome = TextRecipeParser.parse("   \n  ", sourceType: .text)
        XCTAssertEqual(outcome.draft.confidence, .unverified)
        XCTAssertTrue(outcome.warnings.contains("There was no text to read."))
    }

    func testMissingSectionsProduceWarnings() {
        let outcome = TextRecipeParser.parse("Just a title and some thoughts.", sourceType: .text)
        XCTAssertTrue(outcome.warnings.contains { $0.contains("No ingredient lines") })
        XCTAssertTrue(outcome.warnings.contains { $0.contains("No cooking steps") })
        XCTAssertTrue(outcome.warnings.contains { $0.contains("Servings weren’t stated") })
    }

    func testServingsAndTimeSignals() {
        let servings = RecipeTextSignals.servings(in: "Makes 12 cookies")
        XCTAssertEqual(servings.count, 12)
        XCTAssertEqual(servings.description, "12 servings")

        let range = RecipeTextSignals.servings(in: "Serves 4 to 6 people")
        XCTAssertEqual(range.count, 4)
        XCTAssertEqual(range.description, "4–6 servings")

        let times = RecipeTextSignals.times(in: "Prep time: 15 minutes. Cook time: 1 hour 5 minutes. Total time: 1 hour 20 minutes.")
        XCTAssertEqual(times.prep, 15)
        XCTAssertEqual(times.cook, 65)
        XCTAssertEqual(times.total, 80)
    }

    func testDurationDetector() {
        XCTAssertEqual(RecipeTextSignals.durationMinutes("1 hour 30 minutes"), 90)
        XCTAssertEqual(RecipeTextSignals.durationMinutes("45 mins"), 45)
        XCTAssertNil(RecipeTextSignals.durationMinutes("until golden"))
    }

    func testInstructionDurationDetection() {
        XCTAssertEqual(InstructionDurationDetector.firstExplicitDuration(in: "Simmer for 20 minutes."), 1_200)
        XCTAssertEqual(InstructionDurationDetector.explicitDurations(in: "Bake 25–30 minutes, then rest 10 minutes."), [1_800, 600])
        XCTAssertNil(InstructionDurationDetector.firstExplicitDuration(in: "Cook until done."))
    }
}
