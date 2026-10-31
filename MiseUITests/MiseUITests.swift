import XCTest

final class MiseUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest", "-resetState"]
        app.launch()
        XCTAssertTrue(app.buttons["importCard"].waitForExistence(timeout: 20), "Home should finish launching")
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Home

    func testHomeShowsImportEntryPointAndPromise() {
        XCTAssertTrue(app.buttons["importCard"].exists)
        XCTAssertTrue(app.buttons["settingsButton"].exists)
        XCTAssertTrue(app.staticTexts["Save anything. Cook without the clutter."].exists)
        XCTAssertTrue(app.staticTexts["Save a recipe"].exists)
        XCTAssertTrue(tab("Library").exists)
        XCTAssertTrue(tab("Shopping").exists)
        XCTAssertTrue(tab("Meal Plan").exists)
    }

    // MARK: - Library and detail

    func testLibrarySearchOpensStarterRecipeDetail() {
        selectTab("Library")

        let search = app.textFields["librarySearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("salmon")

        let result = app.staticTexts["Miso-Glazed Salmon"]
        XCTAssertTrue(result.waitForExistence(timeout: 10), "Search should find a starter recipe")
        result.tap()

        XCTAssertTrue(app.staticTexts["recipeDetailTitle"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["favouriteRecipeButton"].exists)
        XCTAssertTrue(app.staticTexts["Ingredients"].exists)
        XCTAssertTrue(app.buttons["cookButton"].exists)
    }

    func testCookingModeOpensAndAdvances() {
        selectTab("Library")

        let search = app.textFields["librarySearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("penne")

        let result = app.staticTexts["Tomato & Basil Penne"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        result.tap()

        let cook = app.buttons["cookButton"]
        XCTAssertTrue(cook.waitForExistence(timeout: 10))
        cook.tap()

        let step = app.staticTexts["cookingStepText"]
        XCTAssertTrue(step.waitForExistence(timeout: 10), "Cooking mode should show a step")
        XCTAssertTrue(step.label.contains("1"), "Cooking mode should start at step 1")

        let next = app.buttons["nextCookingStepButton"]
        XCTAssertTrue(next.exists)
        next.tap()
        XCTAssertTrue(step.waitForExistence(timeout: 5))
    }

    // MARK: - Manual creation

    func testManualRecipeCreationAppearsInLibrary() {
        let title = "UI Test Omelette"
        app.buttons["importCard"].tap()

        let manual = app.buttons["manualRecipeButton"]
        XCTAssertTrue(manual.waitForExistence(timeout: 10))
        manual.tap()

        let titleField = app.textFields["recipeTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10))
        titleField.tap()
        titleField.typeText(title)
        dismissKeyboard()

        let ingredient = app.textFields["ingredientField_0"]
        XCTAssertTrue(ingredient.exists)
        ingredient.tap()
        ingredient.typeText("2 eggs")
        dismissKeyboard()

        let instruction = app.textFields["instructionField_0"]
        XCTAssertTrue(instruction.exists)
        instruction.tap()
        instruction.typeText("Whisk the eggs and cook them gently in a buttered pan.")
        dismissKeyboard()

        let save = app.buttons["saveRecipeButton"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        selectTab("Library")
        let search = app.textFields["librarySearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText(title)
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10), "Manually saved recipe should be in the library")
    }

    // MARK: - Text import

    func testTextImportReviewsAndSavesRecipe() {
        let title = "UI Test Tomato Soup"
        app.buttons["importCard"].tap()

        let picker = app.segmentedControls["importModePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.buttons["Text"].tap()

        let editor = app.textViews["importTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText(
            """
            \(title)

            Ingredients
            2 cups tomatoes
            1 teaspoon salt
            1 tablespoon olive oil

            Instructions
            Warm the oil in a pot.
            Add the tomatoes and salt, then simmer for twenty minutes.
            """
        )

        app.buttons["startTextImportButton"].tap()

        let save = app.buttons["saveRecipeButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 25), "Import review should open with an editable draft")
        XCTAssertTrue(app.staticTexts["Review import"].exists)
        save.tap()

        selectTab("Library")
        let search = app.textFields["librarySearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText(title)
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10), "Imported recipe should be saved to the library")
    }

    // MARK: - Settings and paywall

    func testSettingsOpensAndPaywallPresentsHonestly() {
        app.buttons["settingsButton"].tap()

        let premiumButton = app.buttons["settingsPremiumButton"]
        XCTAssertTrue(premiumButton.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["MISE FREE"].exists)

        premiumButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["paywallView"].waitForExistence(timeout: 10), "Paywall should present")
        XCTAssertTrue(app.staticTexts["MISE PREMIUM"].exists)
        XCTAssertTrue(app.buttons["closePaywall"].exists)

        let monthly = app.buttons["planMonthly"]
        let retry = app.buttons["retryProductsButton"]
        XCTAssertTrue(
            monthly.waitForExistence(timeout: 15) || retry.waitForExistence(timeout: 5),
            "Paywall should show live plans or an honest retry state, never invented prices"
        )

        app.buttons["closePaywall"].tap()
        XCTAssertTrue(app.buttons["settingsPremiumButton"].waitForExistence(timeout: 10))
    }

    // MARK: - Shopping

    func testShoppingAddsCustomItem() {
        selectTab("Shopping")

        XCTAssertTrue(app.staticTexts["Shopping"].waitForExistence(timeout: 10))
        let field = app.textFields["shoppingItemField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("UI Test Oats")
        app.buttons["addShoppingItemButton"].tap()

        XCTAssertTrue(app.staticTexts["UI Test Oats"].waitForExistence(timeout: 10), "Custom item should appear on the list")
    }

    // MARK: - Meal plan

    func testMealPlanAssignsRecipeAndCreatesShoppingList() {
        selectTab("Meal Plan")

        let addBreakfast = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Add breakfast for '")
        ).firstMatch
        XCTAssertTrue(addBreakfast.waitForExistence(timeout: 10), "An empty breakfast slot should be available")
        if !addBreakfast.isHittable {
            app.swipeUp()
        }
        addBreakfast.tap()

        let option = app.buttons["mealRecipeOption"].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 10), "Recipe picker should list library recipes")
        option.tap()

        XCTAssertTrue(app.staticTexts["1 of 21 meals planned"].waitForExistence(timeout: 10), "Assigned meal should update the week summary")

        let shop = app.buttons["mealPlanShopButton"]
        XCTAssertTrue(shop.exists)
        shop.tap()

        let viewList = app.buttons["View list"]
        XCTAssertTrue(viewList.waitForExistence(timeout: 10))
        viewList.tap()

        XCTAssertTrue(app.staticTexts["Shopping"].waitForExistence(timeout: 10), "View list should switch to Shopping")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Meal plan ·'")).firstMatch.waitForExistence(timeout: 10),
            "Generated shopping list should be selected"
        )
    }

    // MARK: - Helpers

    private func tab(_ label: String) -> XCUIElement {
        let tabBarButton = app.tabBars.buttons[label]
        if tabBarButton.exists {
            return tabBarButton
        }
        return app.buttons[label]
    }

    private func selectTab(_ label: String) {
        dismissKeyboardTipIfNeeded()
        let button = tab(label)
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Tab \(label) should exist")
        button.tap()
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

    private func dismissKeyboard() {
        let toolbarDone = app.toolbars.buttons["Done"]
        if toolbarDone.waitForExistence(timeout: 2), toolbarDone.isHittable {
            toolbarDone.tap()
            return
        }
        let done = app.buttons["Done"]
        if done.exists, done.isHittable {
            done.tap()
            return
        }
        app.swipeDown()
    }
}
