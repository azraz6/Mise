import XCTest

/// Manual visual audit capture. Run only this test explicitly.
final class MiseVisualAuditUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest", "-resetState"]
        app.launch()
        XCTAssertTrue(app.buttons["importCard"].waitForExistence(timeout: 20))
    }

    func testDismissDictationPrompt() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.635)).tap()
        sleep(1)
    }

    func testCapturePaywallReview() {
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.buttons["settingsPremiumButton"].waitForExistence(timeout: 10))
        app.buttons["settingsPremiumButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["paywallView"].waitForExistence(timeout: 10))
        capture("paywall-review")
    }

    func testCaptureAuditScreens() {
        capture("01-home-top")

        app.swipeUp()
        app.swipeUp()
        capture("02-home-lower")

        selectTab("Library")
        XCTAssertTrue(app.textFields["librarySearchField"].waitForExistence(timeout: 10))
        capture("03-library-list")

        app.staticTexts["Tomato & Basil Penne"].tap()
        XCTAssertTrue(app.staticTexts["recipeDetailTitle"].waitForExistence(timeout: 10))
        capture("04-detail-top")

        app.swipeUp()
        capture("05-detail-ingredients")
        app.swipeUp()
        capture("06-detail-method")
        app.swipeUp()
        capture("07-detail-source")

        app.buttons["cookButton"].tap()
        XCTAssertTrue(app.staticTexts["cookingStepText"].waitForExistence(timeout: 10))
        capture("08-cooking-step")
        app.buttons["Exit cooking mode"].tap()

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["addRecipeButton"].waitForExistence(timeout: 10))

        app.buttons["libraryMenu"].tap()
        app.buttons["Manage collections"].tap()
        XCTAssertTrue(app.navigationBars["Collections"].waitForExistence(timeout: 10))
        capture("09-collections")
        app.buttons["Done"].tap()

        app.buttons["addRecipeButton"].tap()
        XCTAssertTrue(app.buttons["manualRecipeButton"].waitForExistence(timeout: 10))
        capture("10-import-link")
        app.segmentedControls["importModePicker"].buttons["Text"].tap()
        capture("11-import-text")
        app.buttons["manualRecipeButton"].tap()
        XCTAssertTrue(app.textFields["recipeTitleField"].waitForExistence(timeout: 10))
        capture("12-manual-editor")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["manualRecipeButton"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()

        selectTab("Shopping")
        XCTAssertTrue(app.textFields["shoppingItemField"].waitForExistence(timeout: 10))
        let itemField = app.textFields["shoppingItemField"]
        itemField.tap()
        itemField.typeText("Milk")
        app.buttons["addShoppingItemButton"].tap()

        let doneButtons = app.buttons.matching(NSPredicate(format: "label == 'Done'"))
        for index in 0..<doneButtons.count {
            let button = doneButtons.element(boundBy: index)
            if button.isHittable {
                button.tap()
                break
            }
        }

        app.buttons["addRecipeIngredientsButton"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 10))
        capture("14-shopping-recipe-picker")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.textFields["shoppingItemField"].waitForExistence(timeout: 10))
        capture("13-shopping-with-item")

        selectTab("Meal Plan")
        capture("15-meal-plan-empty")
        let addBreakfast = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add breakfast for '")).firstMatch
        XCTAssertTrue(addBreakfast.waitForExistence(timeout: 10))
        if !addBreakfast.isHittable { app.swipeUp() }
        addBreakfast.tap()
        XCTAssertTrue(app.buttons["mealRecipeOption"].firstMatch.waitForExistence(timeout: 10))
        capture("16-meal-plan-picker")
        app.buttons["mealRecipeOption"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["1 of 21 meals planned"].waitForExistence(timeout: 10))
        capture("17-meal-plan-assigned")

        selectTab("Home")
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.buttons["settingsPremiumButton"].waitForExistence(timeout: 10))
        capture("18-settings-top")
        app.swipeUp()
        capture("19-settings-middle")

        let historyRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Import history'")).firstMatch
        if historyRow.exists {
            historyRow.tap()
            XCTAssertTrue(app.navigationBars["Import history"].waitForExistence(timeout: 10))
            capture("19b-import-history")
            app.navigationBars["Import history"].buttons["Done"].tap()
        }

        app.swipeUp()
        capture("20-settings-bottom")

        app.swipeDown()
        app.swipeDown()
        app.buttons["settingsPremiumButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["paywallView"].waitForExistence(timeout: 10))
        capture("21-paywall-top")
        app.swipeUp()
        capture("22-paywall-plans")

        app.buttons["closePaywall"].tap()
        XCTAssertTrue(app.buttons["settingsPremiumButton"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func selectTab(_ label: String) {
        dismissKeyboardTipIfNeeded()
        let button = app.tabBars.buttons[label].exists ? app.tabBars.buttons[label] : app.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()

        let screenTitle: String
        switch label {
        case "Home": screenTitle = "Mise"
        case "Meal Plan": screenTitle = "Meal plan"
        default: screenTitle = label
        }
        if !app.staticTexts[screenTitle].waitForExistence(timeout: 2) {
            dismissKeyboardTipIfNeeded()
            button.tap()
            XCTAssertTrue(app.staticTexts[screenTitle].waitForExistence(timeout: 10))
        }
    }

    private func dismissKeyboardTipIfNeeded() {
        let tip = app.staticTexts["Speed up your typing by sliding your finger across the letters to compose a word."]
        var attempts = 0
        while (tip.exists || app.buttons["Continue"].exists) && attempts < 3 {
            let continueButton = app.buttons["Continue"]
            guard continueButton.exists else { break }
            continueButton.tap()
            attempts += 1
            _ = tip.waitForExistence(timeout: 1)
        }
    }
}
