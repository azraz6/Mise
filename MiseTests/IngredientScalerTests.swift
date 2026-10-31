import XCTest
@testable import Mise

final class IngredientScalerTests: XCTestCase {
    func testMultiplier() {
        XCTAssertEqual(IngredientScaler.multiplier(originalServings: 4, desiredServings: 6), 1.5, accuracy: 0.0001)
        XCTAssertEqual(IngredientScaler.multiplier(originalServings: 2, desiredServings: 1), 0.5, accuracy: 0.0001)
        XCTAssertEqual(IngredientScaler.multiplier(originalServings: 0, desiredServings: 4), 1)
        XCTAssertEqual(IngredientScaler.multiplier(originalServings: 4, desiredServings: 0), 1)
    }

    func testScaledTextKeepsOriginalAtOne() {
        let ingredient = Ingredient(text: "2 cups flour")
        XCTAssertEqual(IngredientScaler.displayText(for: ingredient, multiplier: 1), "2 cups flour")
    }

    func testScaledTextUsesPluralUnits() {
        let ingredient = Ingredient(text: "2 cups all-purpose flour")
        XCTAssertEqual(IngredientScaler.displayText(for: ingredient, multiplier: 2), "4 cups all-purpose flour")
    }

    func testScaledTextFormatsFractions() {
        let ingredient = Ingredient(text: "1 cup milk")
        XCTAssertEqual(IngredientScaler.displayText(for: ingredient, multiplier: 1.5), "1½ cups milk")
    }

    func testScaledTextPreservesPreparation() {
        let ingredient = Ingredient(text: "2 cloves garlic, minced")
        let scaled = IngredientScaler.displayText(for: ingredient, multiplier: 0.5)
        XCTAssertEqual(scaled, "1 clove garlic, minced")
    }

    func testFixedIngredientsAreNotScaled() {
        let ingredient = Ingredient(text: "Salt to taste")
        XCTAssertEqual(IngredientScaler.displayText(for: ingredient, multiplier: 3), "Salt to taste")
    }

    func testScaledRanges() {
        let ingredient = Ingredient(text: "2-3 tbsp sugar")
        XCTAssertEqual(IngredientScaler.displayText(for: ingredient, multiplier: 2), "4–6 tbsp sugar")
    }

    func testMetricRounding() {
        XCTAssertEqual(IngredientScaler.format(104, unit: "g"), "105")
        XCTAssertEqual(IngredientScaler.format(12.4, unit: "g"), "12")
        XCTAssertEqual(IngredientScaler.format(2.26, unit: "kg"), "2.3")
        XCTAssertEqual(IngredientScaler.format(0, unit: "g"), "0")
    }

    func testUnicodeFractionFormatting() {
        XCTAssertEqual(IngredientScaler.format(0.25, unit: "cup"), "¼")
        XCTAssertEqual(IngredientScaler.format(2.5, unit: "cup"), "2½")
        XCTAssertEqual(IngredientScaler.format(0.333, unit: "cup"), "⅓")
    }

    func testDisplayUnitPluralization() {
        XCTAssertEqual(IngredientScaler.displayUnit("cup", quantity: 2), "cups")
        XCTAssertEqual(IngredientScaler.displayUnit("cup", quantity: 1), "cup")
        XCTAssertEqual(IngredientScaler.displayUnit("clove", quantity: 3), "cloves")
        XCTAssertEqual(IngredientScaler.displayUnit("tbsp", quantity: 3), "tbsp")
        XCTAssertEqual(IngredientScaler.displayUnit("g", quantity: 300), "g")
    }

    func testShoppingQuantityTextUsesPluralUnit() {
        let item = ShoppingItem(listID: UUID(), name: "Flour", quantity: 3, unit: "cup")
        XCTAssertEqual(item.quantityText, "3 cups")
        XCTAssertEqual(item.mergedDisplayText, "3 cups Flour")
    }
}
