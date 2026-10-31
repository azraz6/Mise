import Foundation

enum RecipeTextSignals {
    static func servings(in text: String) -> (count: Int?, description: String?) {
        let patterns = [
            #"(?i)\b(?:serves|servings?|yield|makes)\s*[:\-–]?\s*(\d{1,3})(?:\s*(?:-|–|—|to)\s*(\d{1,3}))?"#,
            #"(?i)\b(\d{1,3})(?:\s*(?:-|–|—|to)\s*(\d{1,3}))?\s*(?:servings?|portions?)\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  match.numberOfRanges >= 2,
                  let range = Range(match.range(at: 1), in: text),
                  let lower = Int(text[range]) else { continue }
            let upperRange = match.numberOfRanges >= 3 ? match.range(at: 2) : NSRange(location: NSNotFound, length: 0)
            let upper = upperRange.location == NSNotFound ? nil : Range(upperRange, in: text).flatMap { Int(text[$0]) }
            let description: String
            if let upper, upper != lower {
                description = "\(lower)–\(upper) servings"
            } else {
                description = "\(lower) servings"
            }
            return (lower, description)
        }
        return (nil, nil)
    }

    static func times(in text: String) -> (prep: Int?, cook: Int?, total: Int?) {
        (minutesNear(labelPattern: #"(?i)\bprep(?:aration)?(?:\s*time)?"#, in: text),
         minutesNear(labelPattern: #"(?i)\b(?:cook(?:ing)?|bake|baking)(?:\s*time)?"#, in: text),
         minutesNear(labelPattern: #"(?i)\b(?:total(?:\s*time)?|ready\s*in)"#, in: text))
    }

    static func hashtags(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"(?<!\w)#([\p{L}\p{N}_]{2,30})"#) else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        let tags = matches.compactMap { match -> String? in
            guard match.numberOfRanges >= 2 else { return nil }
            return ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
        }
        return Array(NSOrderedSet(array: tags.map { $0.lowercased() }).compactMap { $0 as? String }).prefix(8).map { $0 }
    }

    static func durationMinutes(_ value: String) -> Int? {
        let lower = value.lowercased()
        var total = 0
        var found = false
        if let hours = firstInt(pattern: #"(\d+)\s*(?:hours?|hrs?|h)(?=\d|\b)"#, in: lower) {
            total += hours * 60
            found = true
        }
        if let minutes = firstInt(pattern: #"(\d+)\s*(?:minutes?|mins?|m)\b"#, in: lower) {
            total += minutes
            found = true
        }
        return found ? total : nil
    }

    private static func minutesNear(labelPattern: String, in text: String) -> Int? {
        let pattern = labelPattern + #"\s*[:\-–]?\s*((?:\d+\s*(?:hours?|hrs?|h))?(?:\s*\d+\s*(?:minutes?|mins?|m))?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        let value = String(text[range]).trimmingCharacters(in: .whitespaces)
        return durationMinutes(value)
    }

    private static func firstInt(pattern: String, in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[range])
    }
}

enum TextRecipeParser {
    private enum SectionKind {
        case ingredients
        case instructions
        case excluded
    }

    static func parse(
        _ rawText: String,
        sourceType: RecipeSourceType,
        sourceURL: URL? = nil,
        sourceTitle: String = "",
        method: ExtractionMethod = .textHeuristics
    ) -> TextParseOutcome {
        let original = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        var warnings: [String] = []
        guard !original.isEmpty else {
            return TextParseOutcome(
                draft: RecipeDraft(
                    title: "",
                    sourceURLString: sourceURL?.absoluteString,
                    sourceType: sourceType,
                    extractionMethod: method,
                    confidence: .unverified,
                    warnings: ["There was no text to read."],
                    originalText: original
                ),
                warnings: ["There was no text to read."]
            )
        }

        let lines = original
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let nonEmpty = lines.filter { !$0.isEmpty }
        let signal = RecipeTextSignals.servings(in: original)
        let times = RecipeTextSignals.times(in: original)
        let tags = RecipeTextSignals.hashtags(in: original)

        var title = ""
        var ingredients: [Ingredient] = []
        var instructions: [Instruction] = []
        let headings = lines.enumerated().compactMap { index, line -> (Int, SectionKind)? in
            guard let kind = headingKind(line) else { return nil }
            return (index, kind)
        }
        let ingredientHeading = headings.first(where: { $0.1 == .ingredients })
        let instructionHeading = headings.first(where: { $0.1 == .instructions })

        if let ingredientHeading {
            let start = ingredientHeading.0 + 1
            let end = instructionHeading?.0 ?? lines.count
            ingredients = parseIngredientLines(Array(lines[start..<max(start, min(end, lines.count))]))
            if let instructionHeading {
                instructions = parseInstructionLines(Array(lines[(instructionHeading.0 + 1)...]))
            }
            let titleLines = lines[..<ingredientHeading.0].filter { !$0.isEmpty && headingKind($0) == nil }
            title = cleanTitle(titleLines.first ?? "")
        } else if let instructionHeading {
            instructions = parseInstructionLines(Array(lines[(instructionHeading.0 + 1)...]))
            let titleLines = lines[..<instructionHeading.0].filter { !$0.isEmpty }
            title = cleanTitle(titleLines.first ?? "")
        }

        if ingredients.isEmpty && instructions.isEmpty {
            let heuristic = heuristicSplit(from: lines)
            ingredients = heuristic.ingredients
            instructions = heuristic.instructions
            title = heuristic.title
            if !ingredients.isEmpty && !instructions.isEmpty {
                warnings.append("No section headings were found. Ingredients and steps were separated heuristically.")
            } else {
                warnings.append("This text doesn’t clearly separate ingredients from steps. Everything is preserved, so you can edit it into shape.")
            }
        }

        if title.isEmpty {
            title = cleanTitle(nonEmpty.first ?? "")
        }
        if title.isEmpty, !sourceTitle.isEmpty { title = sourceTitle }
        if title.isEmpty { title = "Imported recipe" }

        if ingredients.isEmpty {
            warnings.append("No ingredient lines were recognized. Add them during review so scaling and shopping lists work.")
        }
        if instructions.isEmpty {
            warnings.append("No cooking steps were recognized. Add them during review before cooking.")
        }
        if signal.count == nil {
            warnings.append("Servings weren’t stated. Add them to enable ingredient scaling.")
        }
        if times.prep == nil && times.cook == nil && times.total == nil {
            warnings.append("No times were stated. Leave them blank unless you know them.")
        }
        if method == .ocrHeuristics {
            warnings.append("Text recognition can misread fractions, units, and small print. Compare with the original screenshot.")
        }
        if method == .textHeuristics || method == .ocrHeuristics {
            warnings.append("This draft came from text heuristics, not a verified recipe schema.")
        }

        var draft = RecipeDraft(
            title: title,
            summary: "",
            sourceTitle: sourceTitle,
            sourceURLString: sourceURL?.absoluteString,
            sourceType: sourceType,
            extractionMethod: method,
            confidence: ingredients.isEmpty || instructions.isEmpty ? .partial : .heuristic,
            ingredients: ingredients,
            instructions: instructions,
            prepMinutes: times.prep,
            cookMinutes: times.cook,
            totalMinutes: times.total,
            servings: signal.count,
            servingsDescription: signal.description,
            tags: tags,
            warnings: [],
            originalText: original
        )
        draft.normalizeOrdering()
        warnings = Array(NSOrderedSet(array: warnings).compactMap { $0 as? String })
        draft.warnings = warnings
        return TextParseOutcome(draft: draft, warnings: warnings)
    }

    private static func headingKind(_ line: String) -> SectionKind? {
        let stripped = line
            .replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[*_]{1,3}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[*_]{1,3}$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":：-–—")))
            .lowercased()
        guard stripped.count <= 48 else { return nil }
        if stripped.range(of: #"^(ingredients?|ingredient list|you'?ll need|you will need|what you need|shopping list|for the .*)"#, options: .regularExpression) != nil {
            return .ingredients
        }
        if stripped.range(of: #"^(instructions?|method|directions?|steps?|how to (make|cook)|preparation|procedure|to make)$"#, options: .regularExpression) != nil {
            return .instructions
        }
        if stripped.range(of: #"^(notes?|tips?|storage|nutrition|equipment|allergens?|serving suggestion|did you make)"#, options: .regularExpression) != nil {
            return .excluded
        }
        return nil
    }

    private static func cleanTitle(_ line: String) -> String {
        var value = line
            .replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[*_]{1,3}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[*_]{1,3}$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if value.count > 100 {
            value = String(value.prefix(100)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return value
    }

    private static func parseIngredientLines(_ lines: [String]) -> [Ingredient] {
        var result: [Ingredient] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if headingKind(trimmed) != nil { continue }
            if let kind = headingKind(trimmed), kind == .excluded { continue }
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { continue }
            if trimmed.range(of: #"^#[\w]+$"#, options: .regularExpression) != nil { continue }
            let cleaned = trimmed
                .replacingOccurrences(of: #"^[-•*·▪◦]\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^\d{1,2}[\.\)]\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            guard cleaned.count >= 2 else { continue }
            result.append(Ingredient(text: cleaned, order: result.count))
        }
        return result
    }

    private static func parseInstructionLines(_ lines: [String]) -> [Instruction] {
        var groups: [String] = []
        var current: [String] = []
        let numbered = lines.filter { !$0.isEmpty }.allSatisfy { line in
            line.range(of: #"^\d{1,2}[\.\)]\s*"#, options: .regularExpression) != nil
                || line.hasPrefix("- ") || line.hasPrefix("• ") || line.hasPrefix("* ")
        }

        func flush() {
            let text = current.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { groups.append(text) }
            current.removeAll()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
                continue
            }
            if let kind = headingKind(trimmed), kind == .excluded { break }
            if headingKind(trimmed) != nil { continue }
            let cleaned = trimmed
                .replacingOccurrences(of: #"^\d{1,2}[\.\)]\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^[-•*·▪◦]\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            guard !cleaned.isEmpty else { continue }
            if numbered {
                flush()
                current.append(cleaned)
                flush()
            } else {
                current.append(cleaned)
            }
        }
        flush()
        return groups.enumerated().map { Instruction(text: $0.element, order: $0.offset) }
    }

    private static func heuristicSplit(from lines: [String]) -> (title: String, ingredients: [Ingredient], instructions: [Instruction]) {
        var ingredientLines: [String] = []
        var instructionLines: [(Int, String)] = []
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if trimmed.range(of: #"^\d{1,2}[\.\)]\s+"#, options: .regularExpression) != nil {
                instructionLines.append((index, trimmed))
            } else if looksLikeIngredient(trimmed) {
                ingredientLines.append(trimmed)
            }
        }
        let firstContentIndex = (ingredientLines.compactMap { lines.firstIndex(of: $0) } + instructionLines.map(\.0)).min() ?? 0
        let title = cleanTitle(lines.prefix(firstContentIndex).first(where: { !$0.isEmpty }) ?? "")

        if ingredientLines.count >= 2 && !instructionLines.isEmpty {
            let ingredients = parseIngredientLines(ingredientLines)
            let instructions = instructionLines.enumerated().map { offset, pair in
                let cleaned = pair.1.replacingOccurrences(of: #"^\d{1,2}[\.\)]\s*"#, with: "", options: .regularExpression)
                return Instruction(text: cleaned, order: offset)
            }
            return (title, ingredients, instructions)
        }
        return (title, [], [])
    }

    private static func looksLikeIngredient(_ line: String) -> Bool {
        let lower = line.lowercased()
        let measurement = #"^(?:\d|¼|½|¾|⅓|⅔|⅛|⅜|⅝|⅞)"#
        if line.range(of: measurement, options: .regularExpression) != nil { return true }
        if line.hasPrefix("- ") || line.hasPrefix("• ") {
            let stripped = String(line.dropFirst(2))
            return stripped.range(of: measurement, options: .regularExpression) != nil
        }
        return ["cup", "tbsp", "tsp", "gram", "g ", "kg", "ounce", "oz", "pound", "ml", "clove", "can "]
            .contains(where: { lower.hasPrefix($0) })
    }
}
