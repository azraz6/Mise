import Foundation
import SwiftData

@Model
final class Recipe {
    @Attribute(.unique) var id: UUID
    var title: String
    var summary: String?
    var coverImageFilename: String?
    var coverAssetName: String?
    var sourceTypeRaw: String
    var sourceURLString: String?
    var sourceTitle: String?
    var author: String?
    var dateAdded: Date
    var dateModified: Date
    var lastCookedAt: Date?
    var cookingStepIndex: Int
    var cookingStepCount: Int
    var cookingUpdatedAt: Date?
    var prepMinutes: Int?
    var cookMinutes: Int?
    var totalMinutes: Int?
    var originalServings: Int?
    var servingsDescription: String?
    var cuisine: String?
    var category: String?
    var tagsData: Data
    var notes: String?
    var attribution: String?
    var extractionMethodRaw: String
    var validationWarningsData: Data
    var isFavourite: Bool
    var isArchived: Bool
    var ingredientsData: Data
    var instructionsData: Data
    var searchText: String

    init(draft: RecipeDraft) {
        self.id = draft.id
        self.title = draft.displayTitle
        self.summary = draft.summary.isEmpty ? nil : draft.summary
        self.coverImageFilename = draft.coverImageFilename
        self.coverAssetName = draft.coverAssetName
        self.sourceTypeRaw = draft.sourceType.rawValue
        self.sourceURLString = draft.sourceURLString
        self.sourceTitle = draft.sourceTitle.isEmpty ? nil : draft.sourceTitle
        self.author = draft.author.isEmpty ? nil : draft.author
        self.dateAdded = Date()
        self.dateModified = Date()
        self.lastCookedAt = nil
        self.cookingStepIndex = 0
        self.cookingStepCount = draft.instructions.filter { !$0.text.isEmpty }.count
        self.cookingUpdatedAt = nil
        self.prepMinutes = draft.prepMinutes
        self.cookMinutes = draft.cookMinutes
        self.totalMinutes = draft.totalMinutes
        self.originalServings = draft.servings
        self.servingsDescription = draft.servingsDescription
        self.cuisine = draft.cuisine.isEmpty ? nil : draft.cuisine
        self.category = draft.category.isEmpty ? nil : draft.category
        self.tagsData = ModelCoding.encode(draft.tags)
        self.notes = draft.notes.isEmpty ? nil : draft.notes
        self.attribution = draft.attribution.isEmpty ? nil : draft.attribution
        self.extractionMethodRaw = draft.extractionMethod.rawValue
        self.validationWarningsData = ModelCoding.encode(draft.warnings)
        self.isFavourite = false
        self.isArchived = false
        self.ingredientsData = ModelCoding.encode(draft.ingredients)
        self.instructionsData = ModelCoding.encode(draft.instructions)
        self.searchText = ""
        rebuildSearchText()
    }

    var sourceType: RecipeSourceType {
        get { RecipeSourceType(rawValue: sourceTypeRaw) ?? .manual }
        set { sourceTypeRaw = newValue.rawValue }
    }

    var extractionMethod: ExtractionMethod {
        get { ExtractionMethod(rawValue: extractionMethodRaw) ?? .manual }
        set { extractionMethodRaw = newValue.rawValue }
    }

    var ingredients: [Ingredient] {
        get { ModelCoding.decode([Ingredient].self, from: ingredientsData) ?? [] }
        set { ingredientsData = ModelCoding.encode(newValue); rebuildSearchText() }
    }

    var instructions: [Instruction] {
        get { ModelCoding.decode([Instruction].self, from: instructionsData) ?? [] }
        set {
            instructionsData = ModelCoding.encode(newValue)
            cookingStepCount = newValue.filter { !$0.text.isEmpty }.count
            if cookingStepIndex >= cookingStepCount { cookingStepIndex = max(0, cookingStepCount - 1) }
        }
    }

    var tags: [String] {
        get { ModelCoding.decode([String].self, from: tagsData) ?? [] }
        set { tagsData = ModelCoding.encode(newValue); rebuildSearchText() }
    }

    var validationWarnings: [String] {
        get { ModelCoding.decode([String].self, from: validationWarningsData) ?? [] }
        set { validationWarningsData = ModelCoding.encode(newValue) }
    }

    var sourceURL: URL? {
        guard let sourceURLString else { return nil }
        return URL(string: sourceURLString)
    }

    var hasCookingProgress: Bool {
        lastCookedAt != nil && cookingStepIndex > 0 && cookingStepCount > 0 && cookingStepIndex < cookingStepCount
    }

    func rebuildSearchText() {
        var parts: [String] = [title]
        parts.append(contentsOf: ingredients.flatMap { [$0.originalText, $0.name, $0.preparation ?? ""] })
        parts.append(contentsOf: tags)
        if let summary { parts.append(summary) }
        if let notes { parts.append(notes) }
        if let cuisine { parts.append(cuisine) }
        if let category { parts.append(category) }
        if let sourceTitle { parts.append(sourceTitle) }
        if let author { parts.append(author) }
        searchText = parts.joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    func apply(_ draft: RecipeDraft) {
        title = draft.displayTitle
        summary = draft.summary.isEmpty ? nil : draft.summary
        coverImageFilename = draft.coverImageFilename
        coverAssetName = draft.coverAssetName
        sourceTypeRaw = draft.sourceType.rawValue
        sourceURLString = draft.sourceURLString
        sourceTitle = draft.sourceTitle.isEmpty ? nil : draft.sourceTitle
        author = draft.author.isEmpty ? nil : draft.author
        prepMinutes = draft.prepMinutes
        cookMinutes = draft.cookMinutes
        totalMinutes = draft.totalMinutes
        originalServings = draft.servings
        servingsDescription = draft.servingsDescription
        cuisine = draft.cuisine.isEmpty ? nil : draft.cuisine
        category = draft.category.isEmpty ? nil : draft.category
        tags = draft.tags
        notes = draft.notes.isEmpty ? nil : draft.notes
        attribution = draft.attribution.isEmpty ? nil : draft.attribution
        extractionMethodRaw = draft.extractionMethod.rawValue
        validationWarnings = draft.warnings
        ingredients = draft.ingredients
        instructions = draft.instructions
        dateModified = Date()
        rebuildSearchText()
    }

    func toDraft() -> RecipeDraft {
        RecipeDraft(
            id: id,
            title: title,
            summary: summary ?? "",
            author: author ?? "",
            sourceTitle: sourceTitle ?? "",
            sourceURLString: sourceURLString,
            sourceType: sourceType,
            extractionMethod: extractionMethod,
            confidence: .structured,
            coverImageRemoteURL: nil,
            coverImageFilename: coverImageFilename,
            coverAssetName: coverAssetName,
            ingredients: ingredients,
            instructions: instructions,
            prepMinutes: prepMinutes,
            cookMinutes: cookMinutes,
            totalMinutes: totalMinutes,
            servings: originalServings,
            servingsDescription: servingsDescription,
            cuisine: cuisine ?? "",
            category: category ?? "",
            tags: tags,
            notes: notes ?? "",
            attribution: attribution ?? "",
            warnings: validationWarnings,
            originalText: nil,
            createdAt: dateAdded
        )
    }
}

@Model
final class RecipeCollection {
    @Attribute(.unique) var id: UUID
    var name: String
    var summary: String?
    var createdAt: Date
    var sortOrder: Int
    var recipeIDsData: Data

    init(name: String, summary: String = "", sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.summary = summary.isEmpty ? nil : summary
        self.createdAt = Date()
        self.sortOrder = sortOrder
        self.recipeIDsData = Data()
    }

    var recipeIDs: [UUID] {
        get { ModelCoding.decode([UUID].self, from: recipeIDsData) ?? [] }
        set { recipeIDsData = ModelCoding.encode(newValue) }
    }

    func contains(_ recipeID: UUID) -> Bool {
        recipeIDs.contains(recipeID)
    }

    func add(_ recipeID: UUID) {
        guard !recipeIDs.contains(recipeID) else { return }
        recipeIDs.append(recipeID)
    }

    func remove(_ recipeID: UUID) {
        recipeIDs.removeAll { $0 == recipeID }
    }
}
