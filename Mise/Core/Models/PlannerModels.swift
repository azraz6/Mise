import Foundation
import SwiftData

enum ShoppingCategory: String, Codable, CaseIterable, Sendable {
    case produce
    case dairy
    case meatSeafood
    case bakery
    case pantry
    case frozen
    case drinks
    case household
    case other

    var displayName: String {
        switch self {
        case .produce: return "Produce"
        case .dairy: return "Dairy & eggs"
        case .meatSeafood: return "Meat & seafood"
        case .bakery: return "Bakery"
        case .pantry: return "Pantry"
        case .frozen: return "Frozen"
        case .drinks: return "Drinks"
        case .household: return "Household"
        case .other: return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .produce: return "carrot"
        case .dairy: return "drop"
        case .meatSeafood: return "fish"
        case .bakery: return "birthday.cake"
        case .pantry: return "shippingbox"
        case .frozen: return "snowflake"
        case .drinks: return "cup.and.saucer"
        case .household: return "house"
        case .other: return "basket"
        }
    }

    var sortIndex: Int {
        switch self {
        case .produce: return 0
        case .meatSeafood: return 1
        case .dairy: return 2
        case .bakery: return 3
        case .frozen: return 4
        case .pantry: return 5
        case .drinks: return 6
        case .household: return 7
        case .other: return 8
        }
    }
}

@Model
final class ShoppingList {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class ShoppingItem {
    @Attribute(.unique) var id: UUID
    var listID: UUID
    var name: String
    var quantity: Double?
    var quantityUpper: Double?
    var unit: String?
    var displayText: String
    var categoryRaw: String
    var isChecked: Bool
    var sourceRecipeID: UUID?
    var sourceRecipeTitle: String?
    var createdAt: Date
    var sortOrder: Int

    init(
        listID: UUID,
        name: String,
        quantity: Double? = nil,
        quantityUpper: Double? = nil,
        unit: String? = nil,
        displayText: String = "",
        category: ShoppingCategory = .other,
        sourceRecipeID: UUID? = nil,
        sourceRecipeTitle: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.listID = listID
        self.name = name
        self.quantity = quantity
        self.quantityUpper = quantityUpper
        self.unit = unit
        self.displayText = displayText
        self.categoryRaw = category.rawValue
        self.isChecked = false
        self.sourceRecipeID = sourceRecipeID
        self.sourceRecipeTitle = sourceRecipeTitle
        self.createdAt = Date()
        self.sortOrder = sortOrder
    }

    var category: ShoppingCategory {
        get { ShoppingCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var quantityText: String {
        guard let quantity else { return displayText.isEmpty ? name : displayText }
        let lower = IngredientScaler.format(quantity, unit: unit)
        if let quantityUpper {
            let upper = IngredientScaler.format(quantityUpper, unit: unit)
            let displayUnit = IngredientScaler.displayUnit(unit, quantity: quantityUpper)
            return "\(lower)–\(upper) \(displayUnit)".trimmingCharacters(in: .whitespaces)
        }
        if let unit, !unit.isEmpty {
            return "\(lower) \(IngredientScaler.displayUnit(unit, quantity: quantity))"
        }
        return lower
    }

    var mergedDisplayText: String {
        let amount = quantityText
        if amount.isEmpty || amount == name { return name }
        return "\(amount) \(name)"
    }
}

@Model
final class MealPlanEntry {
    @Attribute(.unique) var id: UUID
    var dayKey: String
    var slotRaw: String
    var recipeID: UUID
    var createdAt: Date

    init(dayKey: String, slot: MealSlot, recipeID: UUID) {
        self.id = UUID()
        self.dayKey = dayKey
        self.slotRaw = slot.rawValue
        self.recipeID = recipeID
        self.createdAt = Date()
    }

    var slot: MealSlot {
        get { MealSlot(rawValue: slotRaw) ?? .dinner }
        set { slotRaw = newValue.rawValue }
    }
}

enum MealSlot: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakfast
    case lunch
    case dinner

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        }
    }

    var symbolName: String {
        switch self {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .dinner: return "moon.stars"
        }
    }

    var sortIndex: Int {
        switch self {
        case .breakfast: return 0
        case .lunch: return 1
        case .dinner: return 2
        }
    }
}

@Model
final class ImportJob {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var sourceURLString: String?
    var sourceTypeRaw: String
    var methodRaw: String
    var statusRaw: String
    var draftsData: Data?
    var selectedDraftIndex: Int
    var displayTitle: String
    var sourceText: String?
    var scratchImageFilenamesData: Data
    var errorTitle: String?
    var errorMessage: String?
    var retryEligible: Bool
    var completedRecipeID: UUID?
    var didCountUsage: Bool

    init(
        sourceType: RecipeSourceType,
        sourceURLString: String? = nil,
        method: ExtractionMethod = .linkOnly,
        sourceText: String? = nil,
        scratchImageFilenames: [String] = []
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.sourceURLString = sourceURLString
        self.sourceTypeRaw = sourceType.rawValue
        self.methodRaw = method.rawValue
        self.statusRaw = ImportStatus.queued.rawValue
        self.draftsData = nil
        self.selectedDraftIndex = 0
        self.displayTitle = sourceURLString ?? "New import"
        self.sourceText = sourceText
        self.scratchImageFilenamesData = ModelCoding.encode(scratchImageFilenames)
        self.errorTitle = nil
        self.errorMessage = nil
        self.retryEligible = false
        self.completedRecipeID = nil
        self.didCountUsage = false
    }

    var scratchImageFilenames: [String] {
        get { ModelCoding.decode([String].self, from: scratchImageFilenamesData) ?? [] }
        set { scratchImageFilenamesData = ModelCoding.encode(newValue) }
    }

    var sourceType: RecipeSourceType {
        get { RecipeSourceType(rawValue: sourceTypeRaw) ?? .text }
        set { sourceTypeRaw = newValue.rawValue }
    }

    var method: ExtractionMethod {
        get { ExtractionMethod(rawValue: methodRaw) ?? .linkOnly }
        set { methodRaw = newValue.rawValue }
    }

    var status: ImportStatus {
        get { ImportStatus(rawValue: statusRaw) ?? .queued }
        set { statusRaw = newValue.rawValue }
    }

    var drafts: [RecipeDraft] {
        get { ModelCoding.decode([RecipeDraft].self, from: draftsData) ?? [] }
        set { draftsData = ModelCoding.encode(newValue) }
    }

    var selectedDraft: RecipeDraft? {
        guard drafts.indices.contains(selectedDraftIndex) else { return drafts.first }
        return drafts[selectedDraftIndex]
    }

    func markUpdated() {
        updatedAt = Date()
    }
}
