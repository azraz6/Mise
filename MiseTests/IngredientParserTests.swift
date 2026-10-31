import XCTest
@testable import Mise

final class IngredientParserTests: XCTestCase {
    func testParsesSimpleQuantityUnitAndName() {
        let parsed = IngredientParser.parse("2 cups all-purpose flour")
        XCTAssertEqual(parsed.quantity, 2)
        XCTAssertNil(parsed.quantityUpper)
        XCTAssertEqual(parsed.unit, "cup")
        XCTAssertEqual(parsed.name, "all-purpose flour")
        XCTAssertNil(parsed.preparation)
        XCTAssertEqual(parsed.scaling, .linear)
    }

    func testParsesUnicodeFractions() {
        let parsed = IngredientParser.parse("1½ cups whole milk")
        XCTAssertEqual(parsed.quantity, 1.5)
        XCTAssertEqual(parsed.unit, "cup")
        XCTAssertEqual(parsed.name, "whole milk")
    }

    func testParsesMixedNumber() {
        let parsed = IngredientParser.parse("1 1/2 tbsp olive oil")
        XCTAssertEqual(parsed.quantity, 1.5)
        XCTAssertEqual(parsed.unit, "tbsp")
        XCTAssertEqual(parsed.name, "olive oil")
    }

    func testParsesRange() {
        let parsed = IngredientParser.parse("2-3 tablespoons granulated sugar")
        XCTAssertEqual(parsed.quantity, 2)
        XCTAssertEqual(parsed.quantityUpper, 3)
        XCTAssertEqual(parsed.unit, "tbsp")
        XCTAssertEqual(parsed.name, "granulated sugar")
    }

    func testParsesPreparationAfterComma() {
        let parsed = IngredientParser.parse("3 cloves garlic, thinly sliced")
        XCTAssertEqual(parsed.quantity, 3)
        XCTAssertEqual(parsed.unit, "clove")
        XCTAssertEqual(parsed.name, "garlic")
        XCTAssertEqual(parsed.preparation, "thinly sliced")
    }

    func testParsesPreparationAfterDash() {
        let parsed = IngredientParser.parse("1 lemon - cut into wedges")
        XCTAssertEqual(parsed.quantity, 1)
        XCTAssertNil(parsed.unit)
        XCTAssertEqual(parsed.name, "lemon")
        XCTAssertEqual(parsed.preparation, "cut into wedges")
    }

    func testKeepsQualitativeAmountsFixed() {
        for text in ["Salt to taste", "A pinch of saffron", "Some parsley for garnish", "Olive oil, as needed"] {
            let parsed = IngredientParser.parse(text)
            XCTAssertNil(parsed.quantity, "Quantity should stay unset for \(text)")
            XCTAssertEqual(parsed.scaling, .fixed, "\(text) should not scale")
        }
    }

    func testLargeIsNotTreatedAsLiter() {
        let parsed = IngredientParser.parse("1 large onion, diced")
        XCTAssertEqual(parsed.quantity, 1)
        XCTAssertNil(parsed.unit)
        XCTAssertEqual(parsed.name, "large onion")
        XCTAssertEqual(parsed.preparation, "diced")
    }

    func testStripsListMarkers() {
        XCTAssertEqual(IngredientParser.parse("• 200 g dark chocolate").quantity, 200)
        XCTAssertEqual(IngredientParser.parse("- 2 tbsp butter").unit, "tbsp")
        XCTAssertEqual(IngredientParser.parse("3. 1 cup stock").quantity, 1)
    }

    func testParsesCommaDecimal() {
        let parsed = IngredientParser.parse("1,5 kg potatoes")
        XCTAssertEqual(parsed.quantity, 1.5)
        XCTAssertEqual(parsed.unit, "kg")
        XCTAssertEqual(parsed.name, "potatoes")
    }

    func testEmptyIngredientDoesNotCrash() {
        let parsed = IngredientParser.parse("   ")
        XCTAssertNil(parsed.quantity)
        XCTAssertEqual(parsed.scaling, .fixed)
        XCTAssertEqual(parsed.name, "")
    }

    func testUnitNormalization() {
        XCTAssertEqual(IngredientParser.normalizeUnit("Tablespoons"), "tbsp")
        XCTAssertEqual(IngredientParser.normalizeUnit("grams"), "g")
        XCTAssertEqual(IngredientParser.normalizeUnit("LBS"), "lb")
        XCTAssertEqual(IngredientParser.normalizeUnit(nil), "")
    }

    func testNameNormalizationFoldsAccentsAndPunctuation() {
        XCTAssertEqual(IngredientParser.normalizedName("Crème Fraîche, 30%"), "creme fraiche 30")
        XCTAssertEqual(IngredientParser.normalizedName("  Extra   Virgin  "), "extra virgin")
    }
}
