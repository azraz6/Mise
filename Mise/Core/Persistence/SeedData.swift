import Foundation
import SwiftData

@MainActor
enum SeedData {
    static let seedKey = "com.mise.starterContentSeeded.v1"

    static func seedIfNeeded(context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: seedKey) else { return }
        let descriptor = FetchDescriptor<Recipe>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else {
            defaults.set(true, forKey: seedKey)
            return
        }

        let pasta = Recipe(draft: pastaDraft())
        let salmon = Recipe(draft: salmonDraft())
        let panna = Recipe(draft: pannaDraft())
        context.insert(pasta)
        context.insert(salmon)
        context.insert(panna)

        let weeknight = RecipeCollection(name: "Weeknight dinners", summary: "Fast, dependable dinners for busy days.", sortOrder: 0)
        weeknight.recipeIDs = [pasta.id, salmon.id]
        let sweet = RecipeCollection(name: "Something sweet", summary: "A small collection for slower weekends.", sortOrder: 1)
        sweet.recipeIDs = [panna.id]
        context.insert(weeknight)
        context.insert(sweet)

        let list = ShoppingList(name: "Weekend shop")
        context.insert(list)
        try? context.save()
        defaults.set(true, forKey: seedKey)
    }

    static func pastaDraft() -> RecipeDraft {
        RecipeDraft(
            title: "Tomato & Basil Penne",
            summary: "A weeknight pasta with a bright tomato sauce, garlic, and a handful of basil. The kind of dinner that comes together while the water boils.",
            author: "Mise test kitchen",
            sourceType: .manual,
            extractionMethod: .manual,
            confidence: .structured,
            coverAssetName: "sample_pasta",
            ingredients: [
                Ingredient(text: "12 oz penne rigate", order: 0),
                Ingredient(text: "2 tbsp extra-virgin olive oil", order: 1),
                Ingredient(text: "3 cloves garlic, thinly sliced", order: 2),
                Ingredient(text: "1/4 tsp red pepper flakes", order: 3),
                Ingredient(text: "28 oz canned crushed tomatoes", order: 4),
                Ingredient(text: "1/2 tsp fine sea salt, plus more for the pasta water", order: 5),
                Ingredient(text: "1/2 cup fresh basil leaves, torn", order: 6),
                Ingredient(text: "1/3 cup finely grated Parmesan, plus more to serve", order: 7),
                Ingredient(text: "Freshly ground black pepper", order: 8)
            ],
            instructions: [
                Instruction(text: "Bring a large pot of well-salted water to a boil. Cook the penne until just shy of al dente, following the package timing. Reserve 1 cup of pasta water before draining.", order: 0),
                Instruction(text: "Warm the olive oil in a wide pan over medium heat. Add the garlic and red pepper flakes and cook for 1 minute, until fragrant but not browned.", order: 1),
                Instruction(text: "Add the crushed tomatoes and 1/2 teaspoon salt. Simmer for 10 minutes, stirring occasionally, until the sauce thickens slightly.", order: 2),
                Instruction(text: "Add the drained pasta to the sauce with a splash of pasta water. Toss over medium heat for 2 minutes so the sauce clings to the penne.", order: 3),
                Instruction(text: "Fold in the basil and Parmesan. Season with black pepper, add more pasta water if needed, and serve with extra Parmesan.", order: 4)
            ],
            prepMinutes: 10,
            cookMinutes: 20,
            totalMinutes: 30,
            servings: 4,
            servingsDescription: "4 servings",
            cuisine: "Italian",
            category: "Pasta",
            tags: ["weeknight", "pasta", "vegetarian"],
            notes: "The sauce freezes well. Keep a little pasta water back even if you think you won’t need it.",
            attribution: "Mise starter recipe",
            warnings: []
        )
    }

    static func salmonDraft() -> RecipeDraft {
        RecipeDraft(
            title: "Miso-Glazed Salmon",
            summary: "A glossy miso and maple glaze under the broiler, finished with scallions and sesame. Serve with rice and something green.",
            author: "Mise test kitchen",
            sourceType: .manual,
            extractionMethod: .manual,
            confidence: .structured,
            coverAssetName: "sample_salmon",
            ingredients: [
                Ingredient(text: "2 tbsp white miso paste", order: 0),
                Ingredient(text: "1 tbsp maple syrup", order: 1),
                Ingredient(text: "1 tbsp rice vinegar", order: 2),
                Ingredient(text: "1 tsp toasted sesame oil", order: 3),
                Ingredient(text: "2 salmon fillets, about 6 oz each", order: 4),
                Ingredient(text: "2 scallions, thinly sliced", order: 5),
                Ingredient(text: "1 tsp sesame seeds", order: 6),
                Ingredient(text: "Steamed rice and broccolini, to serve", order: 7)
            ],
            instructions: [
                Instruction(text: "Heat the broiler to high and line a small baking tray with foil. Whisk the miso, maple syrup, rice vinegar, and sesame oil into a smooth glaze.", order: 0),
                Instruction(text: "Pat the salmon dry and place it on the tray. Brush a generous layer of glaze over the top of each fillet.", order: 1),
                Instruction(text: "Broil 6 inches from the heat for 8 to 10 minutes, until the salmon is just opaque in the center and the glaze is bubbling at the edges. Watch closely toward the end.", order: 2),
                Instruction(text: "Scatter with scallions and sesame seeds. Serve with steamed rice and broccolini.", order: 3)
            ],
            prepMinutes: 10,
            cookMinutes: 10,
            totalMinutes: 20,
            servings: 2,
            servingsDescription: "2 servings",
            cuisine: "Japanese-inspired",
            category: "Main",
            tags: ["dinner", "salmon", "quick"],
            notes: "If the glaze darkens too quickly, move the tray down a rack rather than turning up the heat.",
            attribution: "Mise starter recipe",
            warnings: []
        )
    }

    static func pannaDraft() -> RecipeDraft {
        RecipeDraft(
            title: "Vanilla Panna Cotta with Strawberries",
            summary: "A soft, barely set vanilla panna cotta with macerated strawberries. Make it in the morning and let the fridge do the rest.",
            author: "Mise test kitchen",
            sourceType: .manual,
            extractionMethod: .manual,
            confidence: .structured,
            coverAssetName: "sample_panna",
            ingredients: [
                Ingredient(text: "2 1/2 cups heavy cream", order: 0),
                Ingredient(text: "1/2 cup whole milk", order: 1),
                Ingredient(text: "1/3 cup granulated sugar", order: 2),
                Ingredient(text: "1 vanilla bean, split, or 2 tsp vanilla extract", order: 3),
                Ingredient(text: "2 1/4 tsp powdered gelatin", order: 4),
                Ingredient(text: "3 tbsp cold water", order: 5),
                Ingredient(text: "2 cups strawberries, hulled and sliced", order: 6),
                Ingredient(text: "1 tbsp granulated sugar, for the strawberries", order: 7),
                Ingredient(text: "Small basil leaves, to finish", order: 8)
            ],
            instructions: [
                Instruction(text: "Pour the cold water into a small bowl and sprinkle the gelatin over the surface. Let it bloom for 5 minutes without stirring.", order: 0),
                Instruction(text: "Warm the cream, milk, 1/3 cup sugar, and vanilla in a saucepan over medium-low heat until steaming. Do not let it boil. Stir occasionally so the sugar dissolves.", order: 1),
                Instruction(text: "Take the pan off the heat. Scrape the seeds from the vanilla bean into the cream, if using. Add the bloomed gelatin and stir for 1 minute, until completely dissolved.", order: 2),
                Instruction(text: "Strain the mixture through a fine sieve into a jug. Divide between four small glasses and refrigerate for at least 4 hours, until softly set.", order: 3),
                Instruction(text: "Toss the sliced strawberries with the remaining tablespoon of sugar and leave for 10 minutes. Spoon over the panna cotta and finish with basil leaves.", order: 4)
            ],
            prepMinutes: 20,
            cookMinutes: 8,
            totalMinutes: 268,
            servings: 4,
            servingsDescription: "4 servings",
            cuisine: "Italian",
            category: "Dessert",
            tags: ["dessert", "make ahead", "strawberry"],
            notes: "The panna cotta should wobble like a soft custard, not bounce. If it sets too firmly, serve it in the glass rather than turning it out.",
            attribution: "Mise starter recipe",
            warnings: []
        )
    }
}
