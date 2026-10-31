import XCTest
@testable import Mise

final class JSONLDExtractorTests: XCTestCase {
    private let sourceURL = URL(string: "https://recipes.example.org/lemon-pasta")!

    private func html(json: String) -> String {
        """
        <html><head><title>Lemon Pasta | Recipes</title></head>
        <body><script type="application/ld+json">\(json)</script></body></html>
        """
    }

    func testExtractsStructuredRecipe() {
        let json = """
        {
          "@context": "https://schema.org",
          "@type": "Recipe",
          "name": "Lemon Pasta",
          "author": {"@type": "Person", "name": "Ada Cook"},
          "description": "A bright, simple pasta.",
          "recipeIngredient": ["200 g spaghetti", "1 lemon", "2 tbsp olive oil"],
          "recipeInstructions": [
            {"@type": "HowToStep", "text": "Boil the pasta."},
            {"@type": "HowToStep", "text": "Toss with lemon and oil."}
          ],
          "recipeYield": "4 servings",
          "prepTime": "PT10M",
          "cookTime": "PT15M",
          "totalTime": "PT25M",
          "image": "/images/lemon-pasta.jpg",
          "recipeCuisine": "Italian",
          "recipeCategory": "Dinner",
          "keywords": "pasta, easy, weeknight"
        }
        """

        let result = JSONLDExtractor.parse(
            html: html(json: json),
            sourceURL: sourceURL,
            sourceTitle: "Lemon Pasta | Recipes"
        )

        XCTAssertTrue(result.foundRecipeObject)
        XCTAssertEqual(result.drafts.count, 1)
        let draft = try! XCTUnwrap(result.drafts.first)
        XCTAssertEqual(draft.title, "Lemon Pasta")
        XCTAssertEqual(draft.author, "Ada Cook")
        XCTAssertEqual(draft.summary, "A bright, simple pasta.")
        XCTAssertEqual(draft.ingredients.count, 3)
        XCTAssertEqual(draft.ingredients.first?.name, "spaghetti")
        XCTAssertEqual(draft.instructions.count, 2)
        XCTAssertEqual(draft.instructions.first?.text, "Boil the pasta.")
        XCTAssertEqual(draft.servings, 4)
        XCTAssertEqual(draft.prepMinutes, 10)
        XCTAssertEqual(draft.cookMinutes, 15)
        XCTAssertEqual(draft.totalMinutes, 25)
        XCTAssertEqual(draft.coverImageRemoteURL, "https://recipes.example.org/images/lemon-pasta.jpg")
        XCTAssertEqual(draft.cuisine, "Italian")
        XCTAssertEqual(draft.category, "Dinner")
        XCTAssertEqual(draft.tags, ["pasta", "easy", "weeknight"])
        XCTAssertEqual(draft.confidence, .structured)
        XCTAssertEqual(draft.extractionMethod, .jsonLD)
        XCTAssertEqual(draft.sourceURLString, sourceURL.absoluteString)
    }

    func testExtractsRecipeFromGraph() {
        let json = """
        {
          "@context": "https://schema.org",
          "@graph": [
            {"@type": "WebSite", "name": "Recipes"},
            {"@type": "Recipe", "name": "Graph Cake", "recipeIngredient": ["1 cup flour"], "recipeInstructions": "Mix and bake."}
          ]
        }
        """
        let result = JSONLDExtractor.parse(html: html(json: json), sourceURL: sourceURL, sourceTitle: "Graph Cake")
        XCTAssertEqual(result.drafts.count, 1)
        XCTAssertEqual(result.drafts.first?.title, "Graph Cake")
        XCTAssertEqual(result.drafts.first?.instructions.first?.text, "Mix and bake.")
    }

    func testSupportsHowToSectionsAndStripsTags() {
        let json = """
        {
          "@type": "Recipe",
          "name": "Layered Lasagna",
          "recipeIngredient": ["12 sheets pasta"],
          "recipeInstructions": [
            {
              "@type": "HowToSection",
              "name": "Sauce",
              "itemListElement": [
                {"@type": "HowToStep", "text": "<p>1. Simmer the tomatoes.</p>"},
                {"@type": "HowToStep", "text": "Season generously."}
              ]
            },
            {
              "@type": "HowToSection",
              "name": "Assembly",
              "itemListElement": [
                {"@type": "HowToStep", "text": "Layer pasta and sauce."}
              ]
            }
          ]
        }
        """
        let result = JSONLDExtractor.parse(html: html(json: json), sourceURL: sourceURL, sourceTitle: "Lasagna")
        let draft = try! XCTUnwrap(result.drafts.first)
        XCTAssertEqual(draft.instructions.map(\.text), [
            "Simmer the tomatoes.",
            "Season generously.",
            "Layer pasta and sauce."
        ])
        XCTAssertEqual(draft.instructions.map(\.group), ["Sauce", "Sauce", "Assembly"])
    }

    func testSortsMultipleCandidatesByCompleteness() {
        let json = """
        [
          {"@type": "Recipe", "name": "Thin Draft", "recipeIngredient": ["1 egg"]},
          {
            "@type": "Recipe",
            "name": "Complete Omelette",
            "recipeIngredient": ["3 eggs", "1 tbsp butter"],
            "recipeInstructions": [{"@type": "HowToStep", "text": "Cook the eggs."}],
            "recipeYield": 2
          }
        ]
        """
        let result = JSONLDExtractor.parse(html: html(json: json), sourceURL: sourceURL, sourceTitle: "Eggs")
        XCTAssertEqual(result.drafts.count, 2)
        XCTAssertEqual(result.drafts.first?.title, "Complete Omelette")
        XCTAssertTrue(result.warnings.contains { $0.contains("2 recipe candidates") })
    }

    func testSkipsMalformedBlockButKeepsValidOne() {
        let raw = """
        <html><body>
        <script type="application/ld+json">{ this is not json }</script>
        <script type="application/ld+json">
        {"@type":"Recipe","name":"Good Toast","recipeIngredient":["2 slices bread"],"recipeInstructions":["Toast the bread."]}
        </script>
        </body></html>
        """
        let result = JSONLDExtractor.parse(html: raw, sourceURL: sourceURL, sourceTitle: "Toast")
        XCTAssertEqual(result.drafts.count, 1)
        XCTAssertEqual(result.drafts.first?.title, "Good Toast")
        XCTAssertTrue(result.warnings.contains { $0.contains("malformed") })
    }

    func testRepairsTrailingCommasAndSmartQuotes() {
        let json = """
        {“@type”: “Recipe”, “name”: “Repaired Cookies”, “recipeIngredient”: [“2 cups flour”,], “recipeInstructions”: [“Bake.”,],}
        """
        let result = JSONLDExtractor.parse(html: html(json: json), sourceURL: sourceURL, sourceTitle: "Cookies")
        XCTAssertEqual(result.drafts.first?.title, "Repaired Cookies")
        XCTAssertEqual(result.drafts.first?.ingredients.count, 1)
    }

    func testParsesNumericYieldAndDurationVariants() {
        let json = """
        {
          "@type": "Recipe",
          "name": "Long Braise",
          "recipeIngredient": ["1 kg beef"],
          "recipeInstructions": ["Braise."],
          "recipeYield": 6,
          "prepTime": "PT1H30M",
          "cookTime": "PT2H"
        }
        """
        let result = JSONLDExtractor.parse(html: html(json: json), sourceURL: sourceURL, sourceTitle: "Braise")
        let draft = try! XCTUnwrap(result.drafts.first)
        XCTAssertEqual(draft.servings, 6)
        XCTAssertEqual(draft.prepMinutes, 90)
        XCTAssertEqual(draft.cookMinutes, 120)
    }

    func testFallsBackToPageImageAndTitle() {
        let json = """
        {"@type":"Recipe","recipeIngredient":["1 apple"],"recipeInstructions":["Slice."]}
        """
        let result = JSONLDExtractor.parse(
            html: html(json: json),
            sourceURL: sourceURL,
            sourceTitle: "Page Fallback",
            pageImageURL: "https://recipes.example.org/og.jpg"
        )
        let draft = try! XCTUnwrap(result.drafts.first)
        XCTAssertEqual(draft.title, "Page Fallback")
        XCTAssertEqual(draft.coverImageRemoteURL, "https://recipes.example.org/og.jpg")
        XCTAssertEqual(draft.confidence, .structured)
        XCTAssertTrue(result.warnings.contains { $0.contains("Servings") })
    }

    func testReturnsEmptyWhenNoStructuredData() {
        let result = JSONLDExtractor.parse(
            html: "<html><body><p>No schema here.</p></body></html>",
            sourceURL: sourceURL,
            sourceTitle: "Nothing"
        )
        XCTAssertTrue(result.drafts.isEmpty)
        XCTAssertFalse(result.foundRecipeObject)
        XCTAssertTrue(result.warnings.isEmpty)
    }
}
