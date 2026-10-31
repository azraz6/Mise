import XCTest

final class MiseScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest", "-resetState"]
        app.launch()
        XCTAssertTrue(app.buttons["importCard"].waitForExistence(timeout: 20))
    }

    func testCaptureStoreScreenshots() {
        // Plan Monday dinner and tonight's dinner so the week looks lived-in.
        selectTab("Meal Plan")
        let mondayDinner = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Add dinner for Monday'")
        ).firstMatch
        XCTAssertTrue(mondayDinner.waitForExistence(timeout: 10))
        mondayDinner.tap()

        let option = app.buttons["mealRecipeOption"].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 10))
        option.tap()
        XCTAssertTrue(app.staticTexts["1 of 21 meals planned"].waitForExistence(timeout: 10))

        let todayDinner = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Add dinner for Saturday'")
        ).firstMatch
        XCTAssertTrue(scrollUntilHittable(todayDinner), "Today's dinner slot should be reachable")
        todayDinner.tap()
        XCTAssertTrue(app.buttons["mealRecipeOption"].firstMatch.waitForExistence(timeout: 10))
        app.staticTexts["Tomato & Basil Penne"].tap()
        XCTAssertTrue(app.staticTexts["2 of 21 meals planned"].waitForExistence(timeout: 10))

        // Fill the shopping list from a real recipe.
        selectTab("Shopping")
        let addIngredients = app.buttons["addRecipeIngredientsButton"]
        XCTAssertTrue(addIngredients.waitForExistence(timeout: 10))
        addIngredients.tap()
        XCTAssertTrue(app.navigationBars["Add ingredients"].waitForExistence(timeout: 10))
        app.staticTexts["Miso-Glazed Salmon"].tap()
        let add = app.navigationBars["Add ingredients"].buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Add'")
        ).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.textFields["shoppingItemField"].waitForExistence(timeout: 10))

        selectTab("Home")
        sleep(1)
        capture("1-home")

        selectTab("Library")
        XCTAssertTrue(app.textFields["librarySearchField"].waitForExistence(timeout: 10))
        sleep(1)
        capture("2-library")

        app.staticTexts["Tomato & Basil Penne"].tap()
        XCTAssertTrue(app.staticTexts["recipeDetailTitle"].waitForExistence(timeout: 10))
        sleep(1)
        capture("3-recipe")

        app.buttons["cookButton"].tap()
        XCTAssertTrue(app.staticTexts["cookingStepText"].waitForExistence(timeout: 10))
        app.buttons["nextCookingStepButton"].tap()
        app.buttons["nextCookingStepButton"].tap()
        sleep(1)
        capture("4-cooking")
        app.buttons["Exit cooking mode"].tap()

        if app.navigationBars.buttons.firstMatch.exists {
            app.navigationBars.buttons.firstMatch.tap()
        }
        selectTab("Shopping")
        sleep(1)
        capture("5-shopping")

        selectTab("Meal Plan")
        for _ in 0..<8 {
            app.swipeDown()
        }
        XCTAssertTrue(app.staticTexts["Meal plan"].waitForExistence(timeout: 5))
        sleep(1)
        capture("6-meal-plan")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func selectTab(_ label: String) {
        let button = app.tabBars.buttons[label].exists ? app.tabBars.buttons[label] : app.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
    }

    private func scrollUntilHittable(_ element: XCUIElement) -> Bool {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }
}
