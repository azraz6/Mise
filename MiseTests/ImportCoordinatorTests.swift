import SwiftData
import UIKit
import XCTest
@testable import Mise

private struct StubPageFetcher: PageFetching {
    var html: String?
    var error: ImportFailure?

    func fetch(_ url: URL) async throws -> FetchedPage {
        if let error { throw error }
        return FetchedPage(
            requestedURL: url,
            finalURL: url,
            html: html ?? "",
            contentType: "text/html; charset=utf-8"
        )
    }
}

@MainActor
final class ImportCoordinatorTests: XCTestCase {
    private var temporaryDirectories: [URL] = []
    private var retainedContainers: [ModelContainer] = []
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "MiseImportTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        retainedContainers.removeAll()
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    private func makeCoordinator(
        premium: Bool = false,
        fetcher: PageFetching = StubPageFetcher(html: "<html></html>")
    ) throws -> (ImportCoordinator, RecipeStore, UsageTracker, SubscriptionManager, ModelContainer) {
        let container = try ModelContainerFactory.make(inMemory: true)
        retainedContainers.append(container)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiseImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        let images = ImageStore(baseDirectory: directory)
        let store = RecipeStore(context: container.mainContext, images: images)
        let usage = UsageTracker(defaults: defaults)
        if premium {
            let cache = PremiumEntitlementCache(
                productID: SubscriptionProductID.yearly,
                expirationDate: Date().addingTimeInterval(86_400),
                verifiedAt: Date()
            )
            defaults.set(try JSONEncoder().encode(cache), forKey: "com.mise.premiumEntitlementCache.v1")
        }
        let subscriptions = SubscriptionManager(defaults: defaults)
        let coordinator = ImportCoordinator(
            store: store,
            images: images,
            usage: usage,
            subscriptions: subscriptions,
            fetcher: fetcher,
            sharedStore: nil
        )
        return (coordinator, store, usage, subscriptions, container)
    }

    private func waitForCompletion(
        _ job: ImportJob,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if job.status.isTerminal || job.status == .extracted || job.status == .needsReview {
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Import job did not finish. Status: \(job.status.rawValue)", file: file, line: line)
    }

    private func jsonLDHTML() -> String {
        """
        <html><head><title>Page Soup</title></head><body>
        <script type="application/ld+json">
        {"@type":"Recipe","name":"Lemon Orzo Soup","recipeIngredient":["1 cup orzo","4 cups stock"],"recipeInstructions":["Boil the stock.","Add orzo."],"recipeYield":"4"}
        </script></body></html>
        """
    }

    func testTextImportCreatesDraftAndCountsUsage() async throws {
        let (coordinator, store, usage, _, _) = try makeCoordinator()
        let job = try await coordinator.startTextImport(text: """
        Tomato Toast
        Serves 2
        Ingredients
        2 slices sourdough
        1 tomato
        Instructions
        1. Toast the bread.
        2. Rub with tomato.
        """)
        await waitForCompletion(job)

        XCTAssertEqual(job.status, .extracted)
        XCTAssertEqual(job.drafts.count, 1)
        XCTAssertEqual(job.selectedDraft?.title, "Tomato Toast")
        XCTAssertEqual(job.selectedDraft?.servings, 2)
        XCTAssertEqual(job.didCountUsage, true)
        XCTAssertEqual(usage.automaticImportsThisMonth, 1)
        XCTAssertEqual(store.allImportJobs().count, 1)
    }

    func testTextImportCanSkipUsageForNonAutomaticFlows() async throws {
        let (coordinator, _, usage, _, _) = try makeCoordinator()
        let job = try await coordinator.startTextImport(
            text: "Toast\nIngredients\n1 slice bread\nInstructions\n1. Toast.",
            countUsage: false
        )
        await waitForCompletion(job)
        XCTAssertEqual(usage.automaticImportsThisMonth, 0)
    }

    func testEmptyTextImportIsRejected() async throws {
        let (coordinator, store, _, _, _) = try makeCoordinator()
        do {
            _ = try await coordinator.startTextImport(text: "   ")
            XCTFail("Expected empty input failure")
        } catch let failure as ImportFailure {
            XCTAssertEqual(failure, .invalidInput(.empty))
        }
        XCTAssertTrue(store.allImportJobs().isEmpty)
    }

    func testURLImportExtractsJSONLD() async throws {
        let fetcher = StubPageFetcher(html: jsonLDHTML())
        let (coordinator, store, usage, _, _) = try makeCoordinator(fetcher: fetcher)
        let job = try coordinator.startURLImport(rawInput: "https://recipes.example.com/lemon-orzo")
        await waitForCompletion(job)

        XCTAssertEqual(job.status, .extracted)
        XCTAssertEqual(job.method, .jsonLD)
        XCTAssertEqual(job.selectedDraft?.title, "Lemon Orzo Soup")
        XCTAssertEqual(job.selectedDraft?.ingredients.count, 2)
        XCTAssertEqual(job.selectedDraft?.instructions.count, 2)
        XCTAssertEqual(usage.automaticImportsThisMonth, 1)
        XCTAssertEqual(store.allImportJobs().count, 1)
    }

    func testUnsafeURLIsRejectedBeforeCreatingJob() throws {
        let (coordinator, store, _, _, _) = try makeCoordinator()
        XCTAssertThrowsError(try coordinator.startURLImport(rawInput: "http://192.168.1.4/recipe")) { error in
            XCTAssertEqual(error as? ImportFailure, .invalidInput(.unsafeAddress))
        }
        XCTAssertTrue(store.allImportJobs().isEmpty)
    }

    func testFreeImportLimitBlocksNewImports() async throws {
        let (coordinator, store, usage, _, _) = try makeCoordinator()
        for _ in 0..<FreeTier.automaticImportsPerMonth {
            usage.recordAutomaticImport(isPremium: false)
        }
        do {
            _ = try await coordinator.startTextImport(text: "Toast\nIngredients\n1 slice bread\nInstructions\n1. Toast.")
            XCTFail("Expected limit failure")
        } catch let failure as ImportFailure {
            XCTAssertEqual(failure, .importLimitReached)
        }
        XCTAssertTrue(store.allImportJobs().isEmpty)
    }

    func testPremiumImportIgnoresFreeLimit() async throws {
        let (coordinator, _, usage, subscriptions, _) = try makeCoordinator(premium: true)
        XCTAssertTrue(subscriptions.isPremium)
        for _ in 0..<(FreeTier.automaticImportsPerMonth + 5) {
            usage.recordAutomaticImport(isPremium: false)
        }
        let job = try await coordinator.startTextImport(text: "Toast\nIngredients\n1 slice bread\nInstructions\n1. Toast.")
        await waitForCompletion(job)
        XCTAssertEqual(job.status, .extracted)
        XCTAssertEqual(usage.automaticImportsThisMonth, FreeTier.automaticImportsPerMonth + 5)
    }

    func testInstagramImportSavesLinkWithoutCountingUsage() async throws {
        let fetcher = StubPageFetcher(error: .unreadablePage)
        let (coordinator, store, usage, _, _) = try makeCoordinator(fetcher: fetcher)
        let job = try coordinator.startURLImport(rawInput: "https://www.instagram.com/p/abc123/")
        await waitForCompletion(job)

        XCTAssertEqual(job.status, .linkSaved)
        XCTAssertEqual(job.method, .linkOnly)
        XCTAssertEqual(job.sourceType, .instagram)
        XCTAssertEqual(usage.automaticImportsThisMonth, 0)
        XCTAssertTrue(job.drafts.isEmpty)

        let recipe = try await coordinator.saveLinkPlaceholder(for: job)
        XCTAssertEqual(recipe.extractionMethod, .linkOnly)
        XCTAssertEqual(recipe.sourceURLString, "https://www.instagram.com/p/abc123/")
        XCTAssertEqual(job.status, .completed)
        XCTAssertEqual(job.completedRecipeID, recipe.id)
        XCTAssertEqual(store.allRecipes().count, 1)
    }

    func testFailedFetchMapsOfflineAndCanRetry() async throws {
        let fetcher = StubPageFetcher(error: .offline)
        let (coordinator, _, _, _, _) = try makeCoordinator(fetcher: fetcher)
        let job = try coordinator.startURLImport(rawInput: "https://recipes.example.com/offline")
        await waitForCompletion(job)

        XCTAssertEqual(job.status, .failed)
        XCTAssertEqual(job.errorTitle, "You’re offline")
        XCTAssertTrue(job.retryEligible)
    }

    func testRetryIsBlockedWhenAllowanceIsGone() async throws {
        let (coordinator, _, usage, _, _) = try makeCoordinator(fetcher: StubPageFetcher(error: .offline))
        for _ in 0..<(FreeTier.automaticImportsPerMonth - 1) {
            usage.recordAutomaticImport(isPremium: false)
        }
        let job = try coordinator.startURLImport(rawInput: "https://recipes.example.com/retry")
        await waitForCompletion(job)
        XCTAssertEqual(usage.automaticImportsThisMonth, FreeTier.automaticImportsPerMonth - 1)
        XCTAssertTrue(job.retryEligible)

        usage.recordAutomaticImport(isPremium: false)
        XCTAssertEqual(usage.automaticImportsThisMonth, FreeTier.automaticImportsPerMonth)

        coordinator.retry(job)
        XCTAssertEqual(job.status, .failed)
        XCTAssertEqual(job.errorTitle, "This month’s free imports are used")
        XCTAssertFalse(job.retryEligible)
    }

    func testSelectDraftUpdatesSelectionAndStatus() async throws {
        let fetcher = StubPageFetcher(html: """
        <script type="application/ld+json">
        [{"@type":"Recipe","name":"First","recipeIngredient":["1 egg"],"recipeInstructions":["Cook."]},
         {"@type":"Recipe","name":"Second","recipeIngredient":["2 eggs"],"recipeInstructions":["Cook longer."]}]
        </script>
        """)
        let (coordinator, _, _, _, _) = try makeCoordinator(fetcher: fetcher)
        let job = try coordinator.startURLImport(rawInput: "https://recipes.example.com/two")
        await waitForCompletion(job)
        XCTAssertEqual(job.drafts.count, 2)

        coordinator.selectDraft(1, in: job)
        XCTAssertEqual(job.selectedDraftIndex, 1)
        XCTAssertEqual(job.displayTitle, job.drafts[1].displayTitle)
    }

    func testSavingSelectedDraftPersistsRecipe() async throws {
        let (coordinator, store, _, _, _) = try makeCoordinator()
        let job = try await coordinator.startTextImport(text: "Cucumber Salad\nIngredients\n1 cucumber\nInstructions\n1. Slice.")
        await waitForCompletion(job)
        let selected = try XCTUnwrap(job.selectedDraft)
        let recipe = try await store.save(draft: selected)
        coordinator.markCompleted(job, recipe: recipe)

        XCTAssertEqual(store.allRecipes().count, 1)
        XCTAssertEqual(store.allRecipes().first?.title, "Cucumber Salad")
        XCTAssertEqual(job.status, .completed)
    }
}
