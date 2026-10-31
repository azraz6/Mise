import Foundation
import Observation
import SwiftData
import UIKit

/// Owns the app-wide services and the single main SwiftData context used by the UI.
@MainActor
@Observable
final class AppDependencies {
    let container: ModelContainer
    let store: RecipeStore
    let subscriptions: SubscriptionManager
    let usage: UsageTracker
    let imports: ImportCoordinator
    let sharedImports: SharedImportStore?
    let isUITesting: Bool
    private(set) var startupWarning: String?
    private(set) var sharedImportLimitReached = false

    private var hasStarted = false
    private var isConsumingSharedImports = false

    init(
        container: ModelContainer,
        defaults: UserDefaults = .standard,
        sharedImports: SharedImportStore? = SharedImportStore(),
        isUITesting: Bool = false,
        startupWarning: String? = nil
    ) {
        self.container = container
        self.sharedImports = sharedImports
        self.isUITesting = isUITesting
        self.startupWarning = startupWarning

        let mainContext = container.mainContext
        mainContext.autosaveEnabled = true
        let store = RecipeStore(context: mainContext)
        self.store = store

        let subscriptions = SubscriptionManager(defaults: defaults)
        let usage = UsageTracker(defaults: defaults)
        self.subscriptions = subscriptions
        self.usage = usage
        self.imports = ImportCoordinator(
            store: store,
            usage: usage,
            subscriptions: subscriptions,
            sharedStore: sharedImports
        )

        SeedData.seedIfNeeded(context: mainContext, defaults: defaults)
    }

    static func make() -> AppDependencies {
        let arguments = ProcessInfo.processInfo.arguments
        let isUITesting = arguments.contains("-uitest")
        let useInMemory = isUITesting || arguments.contains("-inMemoryStore")
        let resetState = arguments.contains("-resetState") || arguments.contains("-uitest")

        let defaults = UserDefaults.standard
        if resetState {
            if let bundleID = Bundle.main.bundleIdentifier {
                defaults.removePersistentDomain(forName: bundleID)
            }
        }

        var warning: String?
        let container: ModelContainer
        do {
            container = try ModelContainerFactory.make(inMemory: useInMemory)
        } catch {
            warning = "Mise couldn’t open its on-device library. This session is temporary, so changes won’t be kept after you close the app."
            do {
                container = try ModelContainerFactory.make(inMemory: true)
            } catch {
                fatalError("Mise could not create a working data store: \(error.localizedDescription)")
            }
        }

        return AppDependencies(
            container: container,
            defaults: defaults,
            sharedImports: SharedImportStore(),
            isUITesting: isUITesting,
            startupWarning: warning
        )
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        usage.refreshForCurrentMonth()
        ImageStore.shared.cleanScratchFiles()
        if !isUITesting {
            await subscriptions.start()
        } else {
            await subscriptions.refreshProducts()
        }
    }

    @discardableResult
    func consumeSharedImports() async -> Int {
        guard !isConsumingSharedImports, !isUITesting else { return 0 }
        guard let sharedImports else { return 0 }
        isConsumingSharedImports = true
        sharedImportLimitReached = false
        defer { isConsumingSharedImports = false }

        let requests = sharedImports.pendingRequests()
        guard !requests.isEmpty else { return 0 }
        var accepted = 0
        for request in requests {
            do {
                if (try await imports.startSharedRequest(request)) != nil {
                    accepted += 1
                }
                sharedImports.remove(request)
            } catch {
                if let failure = error as? ImportFailure, failure == .importLimitReached {
                    sharedImportLimitReached = true
                    break
                }
                sharedImports.remove(request)
            }
        }
        if accepted > 0 {
            Haptics.success()
        }
        return accepted
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "mise" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item -> (String, String)? in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })
        if let raw = values["url"] {
            _ = try? imports.startURLImport(rawInput: raw)
        } else if let text = values["text"], !text.isEmpty {
            Task {
                _ = try? await imports.startTextImport(text: text, sourceType: .sharedText)
            }
        }
    }

    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
