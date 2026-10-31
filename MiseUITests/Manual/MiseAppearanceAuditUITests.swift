import XCTest

/// Captures dark mode and accessibility Dynamic Type layouts for manual review.
final class MiseAppearanceAuditUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-uitest",
            "-resetState",
            "-AppleInterfaceStyle", "Dark",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["importCard"].waitForExistence(timeout: 20))
    }

    func testCaptureDarkLargeTypeScreens() {
        capture("d01-home-top")
        app.swipeUp()
        app.swipeUp()
        capture("d02-home-lower")

        selectTab("Library")
        XCTAssertTrue(app.textFields["librarySearchField"].waitForExistence(timeout: 10))
        capture("d03-library")

        app.staticTexts["Tomato & Basil Penne"].tap()
        XCTAssertTrue(app.staticTexts["recipeDetailTitle"].waitForExistence(timeout: 10))
        capture("d04-detail-top")
        app.swipeUp()
        capture("d05-detail-scrolled")

        if app.navigationBars.buttons.firstMatch.exists {
            app.navigationBars.buttons.firstMatch.tap()
        }

        selectTab("Shopping")
        capture("d06-shopping")

        selectTab("Meal Plan")
        capture("d07-meal-plan")

        selectTab("Home")
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.buttons["settingsPremiumButton"].waitForExistence(timeout: 10))
        capture("d08-settings-top")
        app.swipeUp()
        capture("d09-settings-middle")
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
}
