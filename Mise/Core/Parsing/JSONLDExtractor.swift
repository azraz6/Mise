import Foundation

struct JSONLDParseResult: Sendable {
    var drafts: [RecipeDraft]
    var warnings: [String]
    var foundRecipeObject: Bool
}

enum JSONLDExtractor {
    static func parse(
        html: String,
        sourceURL: URL,
        sourceTitle: String,
        sourceType: RecipeSourceType = .website,
        pageImageURL: String? = nil
    ) -> JSONLDParseResult {
        var warnings: [String] = []
        var objects: [Any] = []
        let scripts = HTMLText.jsonLDScripts(in: html)
        if scripts.isEmpty {
            return JSONLDParseResult(drafts: [], warnings: [], foundRecipeObject: false)
        }
        for (index, script) in scripts.enumerated() {
            if let object = parseJSON(script) {
                objects.append(object)
            } else {
                warnings.append("Structured data block \(index + 1) was malformed and was skipped.")
            }
        }
        let recipes = recipeDictionaries(in: objects)
        guard !recipes.isEmpty else {
            return JSONLDParseResult(drafts: [], warnings: warnings, foundRecipeObject: false)
        }

        var drafts: [RecipeDraft] = []
        var seenSignatures = Set<String>()
        for recipe in recipes {
            guard let draft = makeDraft(
                from: recipe,
                sourceURL: sourceURL,
                sourceTitle: sourceTitle,
                sourceType: sourceType,
                fallbackImage: pageImageURL
            ) else { continue }
            let signature = draft.title.lowercased() + "|" + draft.ingredients.map(\.originalText).joined(separator: "|")
            guard !seenSignatures.contains(signature) else { continue }
            seenSignatures.insert(signature)
            drafts.append(draft)
        }
        drafts.sort { completenessScore($0) > completenessScore($1) }
        for draft in drafts {
            warnings.append(contentsOf: draft.warnings)
        }
        warnings = Array(NSOrderedSet(array: warnings).compactMap { $0 as? String })
        if drafts.count > 1 {
            warnings.append("This page contains \(drafts.count) recipe candidates. Choose the one you meant before saving.")
        }
        return JSONLDParseResult(drafts: drafts, warnings: warnings, foundRecipeObject: true)
    }

    static func recipeDictionaries(in objects: [Any]) -> [[String: Any]] {
        var results: [[String: Any]] = []
        var seen = Set<String>()

        func visit(_ object: Any) {
            if let dictionary = object as? [String: Any] {
                if isRecipeType(dictionary["@type"]) {
                    let name = stringValue(dictionary["name"]) ?? ""
                    let ingredients = stringArray(dictionary["recipeIngredient"]).joined(separator: "|")
                    let signature = name + "|" + ingredients + "|" + String(dictionary.count)
                    if !seen.contains(signature) {
                        seen.insert(signature)
                        results.append(dictionary)
                    }
                }
                for (key, value) in dictionary where !key.hasPrefix("@") || key == "@graph" {
                    visit(value)
                }
            } else if let array = object as? [Any] {
                for value in array { visit(value) }
            }
        }
        for object in objects { visit(object) }
        return results
    }

    private static func isRecipeType(_ value: Any?) -> Bool {
        if let string = value as? String {
            let lower = string.lowercased()
            return lower == "recipe" || lower.hasSuffix("/recipe") || lower.hasSuffix(":recipe")
        }
        if let array = value as? [Any] {
            return array.contains { isRecipeType($0) }
        }
        return false
    }

    private static func makeDraft(
        from recipe: [String: Any],
        sourceURL: URL,
        sourceTitle: String,
        sourceType: RecipeSourceType,
        fallbackImage: String?
    ) -> RecipeDraft? {
        let title = stringValue(recipe["name"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ingredientStrings = stringArray(recipe["recipeIngredient"]).isEmpty
            ? stringArray(recipe["ingredients"])
            : stringArray(recipe["recipeIngredient"])
        let ingredientObjects = recipe["recipeIngredient"] as? [[String: Any]] ?? []
        let ingredients = ingredientStrings.enumerated().map { index, text in
            Ingredient(text: HTMLText.stripTags(text), order: index)
        } + ingredientObjects.compactMap { object -> Ingredient? in
            guard let name = stringValue(object["name"]) ?? stringValue(object["text"]) else { return nil }
            return Ingredient(text: HTMLText.stripTags(name), order: 0)
        }.enumerated().map { index, ingredient in
            var copy = ingredient
            copy.order = ingredientStrings.count + index
            return copy
        }

        let instructionResult = extractInstructions(recipe)
        let totalIngredients = ingredients.filter { !$0.originalText.isEmpty }
        let totalInstructions = instructionResult.instructions.filter { !$0.text.isEmpty }
        guard !title.isEmpty || !totalIngredients.isEmpty || !totalInstructions.isEmpty else { return nil }

        let yields = parseYield(recipe["recipeYield"] ?? recipe["yield"])
        let author = authorName(recipe["author"] ?? recipe["creator"])
        let image = imageURL(from: recipe["image"] ?? recipe["thumbnailUrl"], sourceURL: sourceURL)
            ?? fallbackImage
        let description = stringValue(recipe["description"]).map(HTMLText.stripTags) ?? ""
        let cuisine = firstString(recipe["recipeCuisine"])
        let category = firstString(recipe["recipeCategory"])
        let keywords = parseKeywords(recipe["keywords"])
        let prep = minutes(fromDuration: recipe["prepTime"])
        let cook = minutes(fromDuration: recipe["cookTime"])
        let total = minutes(fromDuration: recipe["totalTime"])

        var warnings: [String] = []
        if totalIngredients.isEmpty {
            warnings.append("The structured data had no ingredient list. Add ingredients during review.")
        }
        if totalInstructions.isEmpty {
            warnings.append("The structured data had no instructions. Add steps during review.")
        }
        if yields.count == nil {
            warnings.append("Servings weren’t stated, so scaling is unavailable until you add them.")
        }
        if author.isEmpty {
            warnings.append("No author was declared. Preserve the source link for attribution.")
        }
        let coreComplete = !(title.isEmpty && sourceTitle.isEmpty) && !totalIngredients.isEmpty && !totalInstructions.isEmpty
        let confidence: ExtractionConfidence = coreComplete ? .structured : .partial

        var draft = RecipeDraft(
            title: title.isEmpty ? sourceTitle : title,
            summary: description,
            author: author,
            sourceTitle: sourceTitle,
            sourceURLString: sourceURL.absoluteString,
            sourceType: sourceType,
            extractionMethod: .jsonLD,
            confidence: confidence,
            coverImageRemoteURL: image,
            ingredients: ingredients,
            instructions: instructionResult.instructions,
            prepMinutes: prep,
            cookMinutes: cook,
            totalMinutes: total,
            servings: yields.count,
            servingsDescription: yields.description,
            cuisine: cuisine,
            category: category,
            tags: keywords,
            attribution: author,
            warnings: warnings + instructionResult.warnings,
            originalText: nil
        )
        draft.normalizeOrdering()
        return draft
    }

    private static func extractInstructions(_ recipe: [String: Any]) -> (instructions: [Instruction], warnings: [String]) {
        let raw = recipe["recipeInstructions"] ?? recipe["instructions"]
        var steps: [Instruction] = []
        var warnings: [String] = []

        func appendText(_ text: String, group: String? = nil) {
            let cleanedLines = HTMLText.stripTags(text)
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for line in cleanedLines {
                let value = line
                    .replacingOccurrences(of: #"^\d{1,2}[\.\)]\s*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"^[-•*]\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                guard !value.isEmpty else { continue }
                steps.append(Instruction(text: value, order: steps.count, group: group))
            }
        }

        func parseNode(_ node: Any, group: String? = nil) {
            if let string = node as? String {
                appendText(string, group: group)
            } else if let array = node as? [Any] {
                for child in array { parseNode(child, group: group) }
            } else if let dictionary = node as? [String: Any] {
                let sectionName = stringValue(dictionary["name"])
                if isHowToSection(dictionary) {
                    if let items = dictionary["itemListElement"] ?? dictionary["steps"] {
                        parseNode(items, group: sectionName ?? group)
                    }
                } else {
                    let text = stringValue(dictionary["text"])
                        ?? stringValue(dictionary["description"])
                        ?? stringValue(dictionary["name"])
                    if let text { appendText(text, group: group) }
                    if let items = dictionary["itemListElement"], !isHowToSection(dictionary) {
                        parseNode(items, group: group)
                    }
                }
            }
        }

        if let raw {
            parseNode(raw)
        }
        if steps.isEmpty {
            warnings.append("Instructions were present but couldn’t be read as steps.")
        }
        let trimmed = steps.filter { !$0.text.isEmpty }
        return (trimmed.enumerated().map { index, step in
            var copy = step
            copy.order = index
            return copy
        }, warnings)
    }

    private static func isHowToSection(_ dictionary: [String: Any]) -> Bool {
        if let type = dictionary["@type"] as? String {
            return type.lowercased().contains("howtosection")
        }
        if let types = dictionary["@type"] as? [String] {
            return types.contains { $0.lowercased().contains("howtosection") }
        }
        return false
    }

    private static func parseYield(_ value: Any?) -> (count: Int?, description: String?) {
        guard let value else { return (nil, nil) }
        let raw: String
        if let string = value as? String {
            raw = string
        } else if let number = value as? NSNumber {
            raw = number.stringValue
        } else if let array = value as? [Any] {
            let strings = array.compactMap { item -> String? in
                if let string = item as? String { return string }
                if let number = item as? NSNumber { return number.stringValue }
                return nil
            }
            raw = strings.first ?? ""
        } else {
            raw = ""
        }
        let cleaned = HTMLText.stripTags(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return (nil, nil) }
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,3})(?:\s*(?:-|–|—|to)\s*(\d{1,3}))?"#),
              let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
              let range = Range(match.range(at: 1), in: cleaned),
              let lower = Int(cleaned[range]), (1...200).contains(lower) else {
            return (nil, cleaned)
        }
        let upperRange = match.numberOfRanges > 2 ? match.range(at: 2) : NSRange(location: NSNotFound, length: 0)
        let upper = upperRange.location == NSNotFound ? nil : Range(upperRange, in: cleaned).flatMap { Int(cleaned[$0]) }
        let description: String
        if let upper, upper != lower {
            description = "\(lower)–\(upper) servings"
        } else if cleaned.lowercased().contains("serving") || cleaned.lowercased().contains("portion") {
            description = cleaned
        } else {
            description = cleaned
        }
        return (lower, description)
    }

    private static func minutes(fromDuration value: Any?) -> Int? {
        guard let raw = stringValue(value), !raw.isEmpty else { return nil }
        if let minutes = RecipeTextSignals.durationMinutes(raw) { return minutes }
        guard let regex = try? NSRegularExpression(pattern: #"^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) else {
            return nil
        }
        func capture(_ index: Int) -> Int? {
            guard match.numberOfRanges > index, match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: raw) else { return nil }
            return Int(Double(raw[range]) ?? 0)
        }
        let days = capture(1) ?? 0
        let hours = capture(2) ?? 0
        let mins = capture(3) ?? 0
        let secs = capture(4) ?? 0
        let total = days * 24 * 60 + hours * 60 + mins + (secs > 30 ? 1 : 0)
        return total > 0 ? total : nil
    }

    private static func authorName(_ value: Any?) -> String {
        guard let value else { return "" }
        if let string = value as? String { return HTMLText.stripTags(string).trimmingCharacters(in: .whitespaces) }
        if let dictionary = value as? [String: Any] {
            return stringValue(dictionary["name"])?.trimmingCharacters(in: .whitespaces) ?? ""
        }
        if let array = value as? [Any] {
            let names = array.map { authorName($0) }.filter { !$0.isEmpty }
            return Array(NSOrderedSet(array: names).compactMap { $0 as? String }).joined(separator: ", ")
        }
        return ""
    }

    private static func imageURL(from value: Any?, sourceURL: URL) -> String? {
        guard let value else { return nil }
        if let string = value as? String {
            return PageMetadataParser.resolveURL(HTMLText.decodeEntities(string), baseURL: sourceURL)
        }
        if let dictionary = value as? [String: Any] {
            if let url = stringValue(dictionary["url"]) {
                return PageMetadataParser.resolveURL(url, baseURL: sourceURL)
            }
            if let content = stringValue(dictionary["contentUrl"]) {
                return PageMetadataParser.resolveURL(content, baseURL: sourceURL)
            }
        }
        if let array = value as? [Any] {
            for item in array {
                if let result = imageURL(from: item, sourceURL: sourceURL) { return result }
            }
        }
        return nil
    }

    private static func parseKeywords(_ value: Any?) -> [String] {
        guard let value else { return [] }
        let strings: [String]
        if let string = value as? String {
            strings = string.components(separatedBy: ",")
        } else if let array = value as? [String] {
            strings = array
        } else if let array = value as? [Any] {
            strings = array.compactMap { $0 as? String }
        } else {
            strings = []
        }
        let cleaned = strings.map {
            HTMLText.stripTags($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty && $0.count <= 40 }
        return Array(NSOrderedSet(array: cleaned).compactMap { $0 as? String }).prefix(12).map { $0 }
    }

    private static func firstString(_ value: Any?) -> String {
        guard let value else { return "" }
        if let string = value as? String { return HTMLText.stripTags(string).trimmingCharacters(in: .whitespaces) }
        if let array = value as? [Any] {
            return array.compactMap { firstString($0) }.first(where: { !$0.isEmpty }) ?? ""
        }
        return ""
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func stringArray(_ value: Any?) -> [String] {
        guard let value else { return [] }
        if let string = value as? String {
            return string.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        if let array = value as? [String] { return array }
        if let array = value as? [Any] { return array.compactMap { $0 as? String } }
        return []
    }

    private static func completenessScore(_ draft: RecipeDraft) -> Int {
        var score = 0
        if !draft.title.isEmpty { score += 4 }
        if !draft.ingredients.isEmpty { score += 4 }
        if !draft.instructions.isEmpty { score += 4 }
        if draft.servings != nil { score += 1 }
        if draft.prepMinutes != nil { score += 1 }
        if draft.cookMinutes != nil { score += 1 }
        if draft.coverImageRemoteURL != nil { score += 1 }
        if !draft.author.isEmpty { score += 1 }
        return score
    }

    private static func parseJSON(_ raw: String) -> Any? {
        guard let data = raw.data(using: .utf8) else { return nil }
        if let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return object
        }
        // A pragmatic repair for the most common invalid JSON-LD: trailing commas.
        var repaired = raw.replacingOccurrences(of: #",\s*([}\]])"#, with: "$1", options: .regularExpression)
        repaired = repaired.replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
        guard let repairedData = repaired.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: repairedData, options: [.fragmentsAllowed])
    }
}
