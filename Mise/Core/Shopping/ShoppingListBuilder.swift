import Foundation

struct ShoppingDraftItem: Equatable, Sendable {
    var name: String
    var quantity: Double?
    var quantityUpper: Double?
    var unit: String?
    var displayText: String
    var category: ShoppingCategory
    var sourceRecipeIDs: [UUID]
    var sourceRecipeTitles: [String]
    var sortOrder: Int
}

struct RecipeIngredientSelection: Sendable {
    var recipeID: UUID
    var recipeTitle: String
    var ingredient: Ingredient
}

enum ShoppingListBuilder {
    static func selections(from recipes: [Recipe]) -> [RecipeIngredientSelection] {
        recipes.flatMap { recipe in
            recipe.ingredients
                .filter { !$0.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map {
                    RecipeIngredientSelection(recipeID: recipe.id, recipeTitle: recipe.title, ingredient: $0)
                }
        }
    }

    static func items(from selections: [RecipeIngredientSelection]) -> [ShoppingDraftItem] {
        var merged: [ShoppingDraftItem] = []

        for selection in selections {
            let ingredient = selection.ingredient
            let name = shoppingName(for: ingredient)
            let unit = IngredientParser.normalizeUnit(ingredient.unit)
            let canMerge = ingredient.quantity != nil && ingredient.quantityUpper == nil
            let existingIndex = canMerge ? merged.firstIndex(where: { item in
                item.quantity != nil
                    && item.quantityUpper == nil
                    && IngredientParser.normalizedName(item.name) == IngredientParser.normalizedName(name)
                    && IngredientParser.normalizeUnit(item.unit) == unit
            }) : nil

            if let existingIndex {
                merged[existingIndex].quantity = (merged[existingIndex].quantity ?? 0) + (ingredient.quantity ?? 0)
                if !merged[existingIndex].sourceRecipeIDs.contains(selection.recipeID) {
                    merged[existingIndex].sourceRecipeIDs.append(selection.recipeID)
                    merged[existingIndex].sourceRecipeTitles.append(selection.recipeTitle)
                }
                continue
            }

            let category = ShoppingCategoryClassifier.category(for: ingredient.name.isEmpty ? ingredient.originalText : ingredient.name)
            merged.append(
                ShoppingDraftItem(
                    name: name,
                    quantity: ingredient.quantity,
                    quantityUpper: ingredient.quantityUpper,
                    unit: ingredient.unit,
                    displayText: ingredient.originalText,
                    category: category,
                    sourceRecipeIDs: [selection.recipeID],
                    sourceRecipeTitles: [selection.recipeTitle],
                    sortOrder: merged.count
                )
            )
        }

        return merged.sorted { lhs, rhs in
            if lhs.category.sortIndex != rhs.category.sortIndex {
                return lhs.category.sortIndex < rhs.category.sortIndex
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func shoppingName(for ingredient: Ingredient) -> String {
        let candidates = [ingredient.name, ingredient.originalText]
        for candidate in candidates {
            let cleaned = candidate
                .replacingOccurrences(of: #"\s*,\s*.*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
            }
        }
        return "Item"
    }
}

enum ShoppingCategoryClassifier {
    private static let produce = [
        "apple", "avocado", "banana", "basil", "berry", "blackberry", "blueberry", "broccoli",
        "broccolini", "cabbage", "carrot", "celery", "cilantro", "coriander", "corn", "cucumber",
        "eggplant", "garlic", "ginger", "grape", "herb", "kale", "leek", "lemon", "lettuce", "lime",
        "mango", "mushroom", "onion", "orange", "parsley", "peach", "pear", "pepper", "potato",
        "raspberry", "scallion", "shallot", "spinach", "squash", "strawberr", "thyme", "tomato", "zucchini"
    ]
    private static let dairy = [
        "butter", "cheese", "cream", "creme", "egg", "milk", "parmesan", "ricotta", "yogurt", "yoghurt"
    ]
    private static let meat = [
        "beef", "chicken", "duck", "fish", "ham", "lamb", "mince", "pork", "prawn", "salmon", "sausage",
        "shrimp", "steak", "tuna", "turkey"
    ]
    private static let bakery = ["bagel", "bread", "brioche", "bun", "cake", "croissant", "pastry", "pita", "roll", "tortilla"]
    private static let frozen = ["frozen", "ice cream", "puff pastry"]
    private static let drinks = ["coffee", "juice", "soda", "tea", "wine", "beer", "water"]
    private static let household = ["baking paper", "foil", "paper towel", "cling film", "soap", "trash bag"]

    static func category(for name: String) -> ShoppingCategory {
        let lower = name.lowercased()
        if household.contains(where: { lower.contains($0) }) { return .household }
        if frozen.contains(where: { lower.contains($0) }) { return .frozen }
        if meat.contains(where: { lower.contains($0) }) { return .meatSeafood }
        if dairy.contains(where: { lower.contains($0) }) { return .dairy }
        if bakery.contains(where: { lower.contains($0) }) { return .bakery }
        if produce.contains(where: { lower.contains($0) }) { return .produce }
        if drinks.contains(where: { lower.contains($0) }) { return .drinks }
        return .pantry
    }
}

enum MealPlanCalendar {
    static func startOfWeek(containing date: Date = Date(), calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: start) ?? start
    }

    static func days(inWeekStarting start: Date, calendar: Calendar = .current) -> [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func date(fromDayKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        return calendar.date(from: components)
    }

    static func weekTitle(for start: Date, calendar: Calendar = .current) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        let endFormatter = DateFormatter()
        endFormatter.locale = Locale.current
        endFormatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
        if calendar.component(.month, from: start) == calendar.component(.month, from: end) {
            return "\(formatter.string(from: start))–\(endFormatter.string(from: end))"
        }
        return "\(formatter.string(from: start)) – \(endFormatter.string(from: end))"
    }

    static func isToday(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDateInToday(date)
    }
}
