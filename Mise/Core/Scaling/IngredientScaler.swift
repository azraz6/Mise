import Foundation

enum IngredientScaler {
    static func multiplier(originalServings: Int, desiredServings: Int) -> Double {
        guard originalServings > 0, desiredServings > 0 else { return 1 }
        return Double(desiredServings) / Double(originalServings)
    }

    static func displayText(for ingredient: Ingredient, multiplier: Double) -> String {
        guard multiplier > 0, abs(multiplier - 1) > 0.0001 else {
            return ingredient.originalText
        }
        guard ingredient.isScalable, let quantity = ingredient.quantity else {
            return ingredient.originalText
        }

        let lowerQuantity = quantity * multiplier
        let upperQuantity = ingredient.quantityUpper.map { $0 * multiplier }
        let quantityText: String
        if let upperQuantity {
            quantityText = "\(format(lowerQuantity, unit: ingredient.unit))–\(format(upperQuantity, unit: ingredient.unit))"
        } else {
            quantityText = format(lowerQuantity, unit: ingredient.unit)
        }

        var result = quantityText
        if let unit = ingredient.unit, !unit.isEmpty {
            result += " \(displayUnit(unit, quantity: upperQuantity ?? lowerQuantity))"
        }
        if !ingredient.name.isEmpty {
            result += " \(ingredient.name)"
        }
        if let preparation = ingredient.preparation, !preparation.isEmpty {
            result += ", \(preparation)"
        }
        return result
    }

    static func displayUnit(_ unit: String?, quantity: Double) -> String {
        let normalized = IngredientParser.normalizeUnit(unit)
        guard quantity > 1.0001 else { return normalized }
        switch normalized {
        case "cup": return "cups"
        case "clove": return "cloves"
        case "can": return "cans"
        case "package": return "packages"
        case "bunch": return "bunches"
        case "handful": return "handfuls"
        case "pinch": return "pinches"
        case "slice": return "slices"
        case "sprig": return "sprigs"
        case "stick": return "sticks"
        case "head": return "heads"
        case "fillet": return "fillets"
        case "sheet": return "sheets"
        case "quart": return "quarts"
        case "pint": return "pints"
        default: return normalized
        }
    }

    static func format(_ value: Double, unit: String?) -> String {
        guard value > 0 else { return "0" }
        let normalizedUnit = IngredientParser.normalizeUnit(unit)
        if ["g", "ml", "kg", "l", "oz", "lb"].contains(normalizedUnit) {
            if value >= 100 {
                let rounded = (value / 5).rounded() * 5
                return String(format: "%.0f", rounded)
            }
            if value >= 10 {
                return String(format: "%.0f", value.rounded())
            }
            return trimTrailingZeros(String(format: "%.1f", value))
        }

        let whole = floor(value)
        let fraction = value - whole
        let fractionMap: [(Double, String)] = [
            (0.125, "⅛"), (0.25, "¼"), (1.0 / 3.0, "⅓"), (0.375, "⅜"),
            (0.5, "½"), (0.625, "⅝"), (2.0 / 3.0, "⅔"), (0.75, "¾"),
            (0.875, "⅞")
        ]
        if let closest = fractionMap.min(by: { abs($0.0 - fraction) < abs($1.0 - fraction) }),
           abs(closest.0 - fraction) < 0.035 {
            if whole < 0.01 { return closest.1 }
            return "\(Int(whole))\(closest.1)"
        }
        if abs(value.rounded() - value) < 0.01 {
            return String(format: "%.0f", value)
        }
        return trimTrailingZeros(String(format: "%.1f", value))
    }

    private static func trimTrailingZeros(_ string: String) -> String {
        string.replacingOccurrences(of: #"\.0$"#, with: "", options: .regularExpression)
    }
}
