import Foundation

struct RecipeDraft: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var summary: String
    var author: String
    var sourceTitle: String
    var sourceURLString: String?
    var sourceType: RecipeSourceType
    var extractionMethod: ExtractionMethod
    var confidence: ExtractionConfidence
    var coverImageRemoteURL: String?
    var coverImageFilename: String?
    var coverAssetName: String?
    var ingredients: [Ingredient]
    var instructions: [Instruction]
    var prepMinutes: Int?
    var cookMinutes: Int?
    var totalMinutes: Int?
    var servings: Int?
    var servingsDescription: String?
    var cuisine: String
    var category: String
    var tags: [String]
    var notes: String
    var attribution: String
    var warnings: [String]
    var originalText: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String = "",
        summary: String = "",
        author: String = "",
        sourceTitle: String = "",
        sourceURLString: String? = nil,
        sourceType: RecipeSourceType = .manual,
        extractionMethod: ExtractionMethod = .manual,
        confidence: ExtractionConfidence = .structured,
        coverImageRemoteURL: String? = nil,
        coverImageFilename: String? = nil,
        coverAssetName: String? = nil,
        ingredients: [Ingredient] = [],
        instructions: [Instruction] = [],
        prepMinutes: Int? = nil,
        cookMinutes: Int? = nil,
        totalMinutes: Int? = nil,
        servings: Int? = nil,
        servingsDescription: String? = nil,
        cuisine: String = "",
        category: String = "",
        tags: [String] = [],
        notes: String = "",
        attribution: String = "",
        warnings: [String] = [],
        originalText: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.author = author
        self.sourceTitle = sourceTitle
        self.sourceURLString = sourceURLString
        self.sourceType = sourceType
        self.extractionMethod = extractionMethod
        self.confidence = confidence
        self.coverImageRemoteURL = coverImageRemoteURL
        self.coverImageFilename = coverImageFilename
        self.coverAssetName = coverAssetName
        self.ingredients = ingredients
        self.instructions = instructions
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.totalMinutes = totalMinutes
        self.servings = servings
        self.servingsDescription = servingsDescription
        self.cuisine = cuisine
        self.category = category
        self.tags = tags
        self.notes = notes
        self.attribution = attribution
        self.warnings = warnings
        self.originalText = originalText
        self.createdAt = createdAt
    }

    static func manual() -> RecipeDraft {
        RecipeDraft(
            sourceType: .manual,
            extractionMethod: .manual,
            confidence: .structured,
            ingredients: [Ingredient(text: "", order: 0)],
            instructions: [Instruction(text: "", order: 0)]
        )
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if !sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return sourceTitle }
        return "Untitled recipe"
    }

    var missingFields: [String] {
        RecipeValidator.missingFields(for: self)
    }

    var allWarnings: [String] {
        RecipeValidator.warnings(for: self)
    }

    var hasCoreContent: Bool {
        missingFields.isEmpty
    }

    mutating func normalizeOrdering() {
        ingredients = ingredients.enumerated().map { index, ingredient in
            var copy = ingredient
            copy.order = index
            return copy
        }
        instructions = instructions.enumerated().map { index, instruction in
            var copy = instruction
            copy.order = index
            return copy
        }
    }

    mutating func trimEmptyTrailingRows() {
        while ingredients.count > 1, ingredients.last?.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            ingredients.removeLast()
        }
        while instructions.count > 1, instructions.last?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            instructions.removeLast()
        }
    }
}

enum ModelCoding {
    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
