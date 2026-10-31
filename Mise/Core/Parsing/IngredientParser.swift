import Foundation

struct ParsedIngredient: Equatable, Sendable {
    var quantity: Double?
    var quantityUpper: Double?
    var unit: String?
    var name: String
    var preparation: String?
    var scaling: IngredientScalingBehavior
}

enum IngredientParser {
    private static let unitMap: [String: String] = [
        "cup": "cup", "cups": "cup", "c": "cup",
        "tablespoon": "tbsp", "tablespoons": "tbsp", "tbsp": "tbsp", "tbs": "tbsp",
        "teaspoon": "tsp", "teaspoons": "tsp", "tsp": "tsp",
        "gram": "g", "grams": "g", "g": "g",
        "kilogram": "kg", "kilograms": "kg", "kg": "kg",
        "ounce": "oz", "ounces": "oz", "oz": "oz",
        "pound": "lb", "pounds": "lb", "lb": "lb", "lbs": "lb",
        "milliliter": "ml", "milliliters": "ml", "ml": "ml",
        "millilitre": "ml", "millilitres": "ml",
        "liter": "l", "liters": "l", "litre": "l", "litres": "l", "l": "l",
        "clove": "clove", "cloves": "clove",
        "can": "can", "cans": "can",
        "tin": "can", "tins": "can",
        "package": "package", "packages": "package", "pkg": "package", "packet": "package", "packets": "package",
        "bunch": "bunch", "bunches": "bunch",
        "handful": "handful", "handfuls": "handful",
        "pinch": "pinch", "pinches": "pinch",
        "slice": "slice", "slices": "slice",
        "sprig": "sprig", "sprigs": "sprig",
        "stick": "stick", "sticks": "stick",
        "head": "head", "heads": "head",
        "fillet": "fillet", "fillets": "fillet",
        "sheet": "sheet", "sheets": "sheet",
        "quart": "quart", "quarts": "quart",
        "pint": "pint", "pints": "pint",
        "liter can": "can"
    ]

    private static let sortedUnits = unitMap.keys.sorted { $0.count > $1.count }
    private static let unicodeFractions: [Character: String] = [
        "¼": "1/4", "½": "1/2", "¾": "3/4", "⅓": "1/3", "⅔": "2/3",
        "⅛": "1/8", "⅜": "3/8", "⅝": "5/8", "⅞": "7/8",
        "⅕": "1/5", "⅖": "2/5", "⅗": "3/5", "⅘": "4/5", "⅙": "1/6", "⅚": "5/6"
    ]

    static func parse(_ raw: String) -> ParsedIngredient {
        let original = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = stripListMarker(original)
        guard !text.isEmpty else {
            return ParsedIngredient(name: original, scaling: .fixed)
        }

        // Normalize unicode fractions to ASCII while retaining a separating space.
        for (character, value) in unicodeFractions {
            if text.contains(character) {
                text = text.replacingOccurrences(of: String(character), with: " " + value)
            }
        }
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        var quantity: Double?
        var quantityUpper: Double?
        var remainder = text

        if let match = firstQuantity(in: text) {
            quantity = match.lower
            quantityUpper = match.upper
            remainder = String(text.dropFirst(match.length)).trimmingCharacters(in: .whitespaces)
        }

        var unit: String?
        for candidate in sortedUnits {
            let lower = remainder.lowercased()
            guard lower.hasPrefix(candidate) else { continue }
            let after = remainder.dropFirst(candidate.count)
            guard after.isEmpty || after.first == " " || after.first == "." else { continue }
            if candidate == "l" && lower.hasPrefix("large") { continue }
            unit = unitMap[candidate]
            remainder = String(after).trimmingCharacters(in: CharacterSet(charactersIn: " ."))
            break
        }

        if remainder.lowercased().hasPrefix("of ") {
            remainder = String(remainder.dropFirst(3))
        }

        var preparation: String?
        if let comma = remainder.firstIndex(of: ",") {
            preparation = remainder[remainder.index(after: comma)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            remainder = String(remainder[..<comma]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let dashRange = remainder.range(of: " - ") ?? remainder.range(of: " — ") {
            preparation = String(remainder[dashRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            remainder = String(remainder[..<dashRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if remainder.isEmpty {
            remainder = original
        }

        let lowerOriginal = original.lowercased()
        let qualitative = lowerOriginal.contains("to taste")
            || lowerOriginal.contains("as needed")
            || lowerOriginal.contains("for serving")
            || lowerOriginal.contains("for garnish")
            || lowerOriginal.hasPrefix("a ") || lowerOriginal.hasPrefix("an ")
            || lowerOriginal.hasPrefix("some ")

        let scaling: IngredientScalingBehavior = (quantity != nil && !qualitative) ? .linear : .fixed
        if qualitative {
            // Keep a qualitative amount as written, even if a stray number appeared.
            quantity = nil
            quantityUpper = nil
            unit = nil
            remainder = original
            preparation = nil
        }

        if preparation?.isEmpty == true { preparation = nil }
        return ParsedIngredient(
            quantity: quantity,
            quantityUpper: quantityUpper,
            unit: unit,
            name: remainder.isEmpty ? original : remainder,
            preparation: preparation,
            scaling: scaling
        )
    }

    static func normalizeUnit(_ unit: String?) -> String {
        guard let unit = unit?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !unit.isEmpty else {
            return ""
        }
        return unitMap[unit] ?? unit
    }

    static func normalizedName(_ name: String) -> String {
        name.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func stripListMarker(_ text: String) -> String {
        var value = text
        let markers = ["- ", "• ", "* ", "· ", "– "]
        for marker in markers where value.hasPrefix(marker) {
            value = String(value.dropFirst(marker.count))
        }
        if let match = value.range(of: #"^\d{1,2}[\.\)]\s+"#, options: .regularExpression) {
            value = String(value[match.upperBound...])
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstQuantity(in text: String) -> (lower: Double, upper: Double?, length: Int)? {
        let ns = text as NSString
        let number = #"(\d+\s+\d+/\d+|\d+/\d+|\d+(?:[.,]\d+)?)"#
        let pattern = "^" + number + #"(?:\s*(?:-|–|—|to)\s*"# + number + #")?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))
        guard let match, match.numberOfRanges >= 3 else { return nil }
        let lowerString = ns.substring(with: match.range(at: 1))
        guard let lower = numberValue(lowerString) else { return nil }
        let upperRange = match.range(at: 2)
        let upper = upperRange.location == NSNotFound ? nil : numberValue(ns.substring(with: upperRange))
        return (lower, upper, match.range.length)
    }

    private static func numberValue(_ string: String) -> Double? {
        let cleaned = string.trimmingCharacters(in: .whitespaces)
        if cleaned.contains(" ") {
            let parts = cleaned.split(separator: " ")
            guard parts.count == 2, let whole = Double(parts[0]), let fraction = fractionValue(String(parts[1])) else {
                return nil
            }
            return whole + fraction
        }
        if cleaned.contains("/") {
            return fractionValue(cleaned)
        }
        return Double(cleaned.replacingOccurrences(of: ",", with: "."))
    }

    private static func fractionValue(_ string: String) -> Double? {
        let parts = string.split(separator: "/")
        guard parts.count == 2, let numerator = Double(parts[0]), let denominator = Double(parts[1]), denominator != 0 else {
            return nil
        }
        return numerator / denominator
    }
}
