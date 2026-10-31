import Foundation

enum RecipeSourceType: String, Codable, CaseIterable, Sendable {
    case website
    case instagram
    case tiktok
    case youtube
    case facebook
    case pinterest
    case text
    case screenshot
    case photo
    case manual
    case sharedText

    var displayName: String {
        switch self {
        case .website: return "Website"
        case .instagram: return "Instagram"
        case .tiktok: return "TikTok"
        case .youtube: return "YouTube"
        case .facebook: return "Facebook"
        case .pinterest: return "Pinterest"
        case .text: return "Pasted text"
        case .screenshot: return "Screenshot"
        case .photo: return "Photo"
        case .manual: return "Written by you"
        case .sharedText: return "Shared text"
        }
    }

    var symbolName: String {
        switch self {
        case .website: return "safari"
        case .instagram: return "camera"
        case .tiktok: return "music.note"
        case .youtube: return "play.rectangle"
        case .facebook: return "person.2"
        case .pinterest: return "pin"
        case .text, .sharedText: return "text.alignleft"
        case .screenshot, .photo: return "photo"
        case .manual: return "square.and.pencil"
        }
    }

    var isSocial: Bool {
        switch self {
        case .instagram, .tiktok, .youtube, .facebook, .pinterest: return true
        default: return false
        }
    }
}

enum ExtractionMethod: String, Codable, Sendable {
    case jsonLD
    case pageHeuristics
    case oEmbed
    case textHeuristics
    case ocrHeuristics
    case manual
    case linkOnly

    var displayName: String {
        switch self {
        case .jsonLD: return "Structured recipe data"
        case .pageHeuristics: return "Page text (reviewed)"
        case .oEmbed: return "Public page metadata"
        case .textHeuristics: return "Text heuristics"
        case .ocrHeuristics: return "On-device text recognition"
        case .manual: return "Manual entry"
        case .linkOnly: return "Link saved"
        }
    }
}

enum ExtractionConfidence: String, Codable, Sendable {
    case structured
    case partial
    case heuristic
    case unverified

    var displayName: String {
        switch self {
        case .structured: return "Structured data"
        case .partial: return "Partial data"
        case .heuristic: return "Needs review"
        case .unverified: return "Unverified"
        }
    }
}

enum ImportStatus: String, Codable, CaseIterable, Sendable {
    case queued
    case processing
    case needsReview
    case extracted
    case linkSaved
    case failed
    case completed

    var isTerminal: Bool {
        switch self {
        case .linkSaved, .failed, .completed: return true
        default: return false
        }
    }

    var displayName: String {
        switch self {
        case .queued: return "Waiting"
        case .processing: return "Importing"
        case .needsReview: return "Ready to review"
        case .extracted: return "Extracted"
        case .linkSaved: return "Link saved"
        case .failed: return "Couldn’t import"
        case .completed: return "Saved"
        }
    }
}

struct Ingredient: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var originalText: String
    var quantity: Double?
    var quantityUpper: Double?
    var unit: String?
    var name: String
    var preparation: String?
    var group: String?
    var order: Int
    var scaling: IngredientScalingBehavior

    init(
        id: UUID = UUID(),
        text: String,
        group: String? = nil,
        order: Int = 0
    ) {
        let parsed = IngredientParser.parse(text)
        self.id = id
        self.originalText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.quantity = parsed.quantity
        self.quantityUpper = parsed.quantityUpper
        self.unit = parsed.unit
        self.name = parsed.name
        self.preparation = parsed.preparation
        self.group = group
        self.order = order
        self.scaling = parsed.scaling
    }

    init(
        id: UUID = UUID(),
        originalText: String,
        quantity: Double?,
        quantityUpper: Double?,
        unit: String?,
        name: String,
        preparation: String?,
        group: String?,
        order: Int,
        scaling: IngredientScalingBehavior
    ) {
        self.id = id
        self.originalText = originalText
        self.quantity = quantity
        self.quantityUpper = quantityUpper
        self.unit = unit
        self.name = name
        self.preparation = preparation
        self.group = group
        self.order = order
        self.scaling = scaling
    }

    var isScalable: Bool {
        scaling == .linear && quantity != nil
    }

    var hasPreparation: Bool {
        preparation?.isEmpty == false
    }

    mutating func updateText(_ newText: String) {
        let parsed = IngredientParser.parse(newText)
        originalText = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        quantity = parsed.quantity
        quantityUpper = parsed.quantityUpper
        unit = parsed.unit
        name = parsed.name
        preparation = parsed.preparation
        scaling = parsed.scaling
    }
}

enum IngredientScalingBehavior: String, Codable, Sendable {
    case linear
    case fixed

    var displayName: String {
        switch self {
        case .linear: return "Scales with servings"
        case .fixed: return "Kept as written"
        }
    }
}

struct Instruction: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var text: String
    var order: Int
    var group: String?
    var durationSeconds: Int?

    init(id: UUID = UUID(), text: String, order: Int = 0, group: String? = nil) {
        self.id = id
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.order = order
        self.group = group
        self.durationSeconds = InstructionDurationDetector.firstExplicitDuration(in: text)
    }
}

enum RecipeValidator {
    static func missingFields(for draft: RecipeDraft) -> [String] {
        var missing: [String] = []
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append("Title")
        }
        if draft.ingredients.filter({ !$0.originalText.isEmpty }).isEmpty {
            missing.append("Ingredients")
        }
        if draft.instructions.filter({ !$0.text.isEmpty }).isEmpty {
            missing.append("Instructions")
        }
        return missing
    }

    static func warnings(for draft: RecipeDraft) -> [String] {
        var warnings = draft.warnings
        let ingredients = draft.ingredients.filter { !$0.originalText.isEmpty }
        let instructions = draft.instructions.filter { !$0.text.isEmpty }

        if (draft.servings ?? 0) <= 0 {
            warnings.append("Servings are unknown. Scaling is unavailable until you add them.")
        }
        if ingredients.contains(where: { !$0.isScalable }) {
            warnings.append("Some ingredients are kept exactly as written and will not scale.")
        }
        if instructions.isEmpty {
            warnings.append("No cooking steps were found. Add them before you cook.")
        }
        if draft.sourceURLString == nil, draft.sourceType.isSocial {
            warnings.append("The original source link is missing.")
        }
        return Array(NSOrderedSet(array: warnings).compactMap { $0 as? String })
    }
}

enum InstructionDurationDetector {
    static let pattern = #"(?i)\b(\d{1,3})(?:\s*(?:-|–|—|to)\s*(\d{1,3}))?\s*(seconds?|secs?|minutes?|mins?|hours?|hrs?)\b"#

    static func explicitDurations(in text: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges >= 4 else { return nil }
            let lower = ns.substring(with: match.range(at: 1))
            let upper = match.range(at: 2).location == NSNotFound ? nil : ns.substring(with: match.range(at: 2))
            let unit = ns.substring(with: match.range(at: 3)).lowercased()
            guard var value = Int(upper ?? lower) else { return nil }
            if unit.hasPrefix("hour") || unit.hasPrefix("hr") {
                value *= 3600
            } else if unit.hasPrefix("min") {
                value *= 60
            }
            return value > 0 && value <= 24 * 3600 ? value : nil
        }
    }

    static func firstExplicitDuration(in text: String) -> Int? {
        explicitDurations(in: text).first
    }

    static func display(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return minutes > 0 ? "\(hours) hr \(minutes) min" : "\(hours) hr"
        }
        if minutes > 0 {
            return secs > 0 ? "\(minutes) min \(secs) sec" : "\(minutes) min"
        }
        return "\(secs) sec"
    }
}
