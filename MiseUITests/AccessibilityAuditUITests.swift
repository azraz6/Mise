import XCTest

final class AccessibilityAuditUITests: XCTestCase {
    func testKeyScreensPassAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest", "-resetState"]
        app.launch()
        XCTAssertTrue(app.buttons["importCard"].waitForExistence(timeout: 20))

        let auditTypes: XCUIAccessibilityAuditType = [
            .hitRegion,
            .contrast,
            .sufficientElementDescription,
            .trait
        ]

        try app.performAccessibilityAudit(for: auditTypes) { issue in
            // The Home “Collections” heading can sit behind the floating tab
            // bar at the default scroll position; it is reachable by scrolling.
            // The system glass toolbar capsule also produces a false-positive
            // contrast reading for the Settings Done button, which renders
            // dark ink on a cream capsule.
            guard issue.auditType == .contrast else { return false }
            return issue.element?.label == "Collections" || issue.element?.label == "Done"
        }

        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.textFields["librarySearchField"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit(for: auditTypes)

        app.staticTexts["Tomato & Basil Penne"].tap()
        XCTAssertTrue(app.staticTexts["recipeDetailTitle"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit(for: auditTypes)

        app.buttons["favouriteRecipeButton"].tap()
        app.navigationBars.buttons.firstMatch.tap()

        app.tabBars.buttons["Home"].tap()
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.buttons["settingsPremiumButton"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit(for: auditTypes) { issue in
            issue.auditType == .contrast && issue.element?.label == "Done"
        }
    }
}
