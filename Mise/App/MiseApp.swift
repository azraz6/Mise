import SwiftUI

@main
struct MiseApp: App {
    @State private var dependencies: AppDependencies

    init() {
        _dependencies = State(initialValue: AppDependencies.make())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
                .modelContainer(dependencies.container)
                .tint(MiseTheme.accent)
        }
    }
}
